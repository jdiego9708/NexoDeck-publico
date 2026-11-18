//! El hilo de la ventana de notas: un event loop de tao que vive toda la sesion.
//!
//! tao (como winit) no deja recrear el event loop de un proceso, asi que se crea
//! una vez, en un hilo propio (`with_any_thread`), y cerrar la ventana solo la
//! destruye. El loop nunca sale: en Windows, que `run` termine cierra el proceso
//! entero, y el proceso es NexoDeck. Verificado en la prueba de viabilidad:
//! abierto desde un hilo de flutter_rust_bridge, se escribe con teclas muertas y
//! se cierra y reabre con el mismo loop sin tocar la ventana de Flutter.
//!
//! Aca solo se aplican efectos; que hacer con cada cosa lo decide `session.rs`.

use std::borrow::Cow;
use std::path::PathBuf;
use std::sync::{mpsc, Arc, Mutex};
use std::thread;
use std::time::Instant;

use tao::dpi::{LogicalSize, PhysicalPosition, PhysicalSize};
use tao::event::{Event, WindowEvent};
use tao::event_loop::{ControlFlow, EventLoopBuilder, EventLoopProxy, EventLoopWindowTarget};
use tao::platform::windows::{EventLoopBuilderExtWindows, IconExtWindows};
use tao::window::{Icon, Theme as WindowTheme, Window, WindowBuilder};
use wry::http::{header, Request, Response, StatusCode};
use wry::{
    NewWindowResponse, Theme as WebTheme, WebContext, WebView, WebViewBuilder,
    WebViewBuilderExtWindows,
};

use crate::assets;
use crate::backend::{EditorBackend, EditorEvent, EventSink};
use crate::protocol::{script_for, NoteDto, PageMessage, ThemeDto};
use crate::session::{run_job, Effect, Fetched, Job, Pick, Session};

/// El icono de la app en los recursos del ejecutable (`IDI_APP_ICON` del runner
/// de Flutter, `app/windows/runner/resource.h`).
const APP_ICON_RESOURCE: u16 = 101;

/// Una ventana restaurada tiene que verse al menos este trozo en algun monitor
/// conectado. El mismo criterio que `isWindowRectUsable` en la app: una posicion
/// de un monitor que ya no esta deja la ventana invisible.
const MIN_VISIBLE: (i32, i32) = (160, 80);

enum Command {
    Open {
        note: NoteDto,
        theme: Option<ThemeDto>,
    },
    Show {
        theme: Option<ThemeDto>,
    },
    SetTheme(ThemeDto),
    /// Un mensaje de la pagina, todavia sin parsear.
    Page(String),
    Fetched(Fetched),
    /// Lo elegido en un dialogo nativo; `None` si se cancelo.
    Picked(Pick, Option<String>),
    Changed,
    Close,
}

/// La ventana de notas. Arrancarla crea el hilo y el event loop, sin ventana: la
/// ventana aparece con `show` o al abrir la primera nota.
pub struct Editor {
    // El `Mutex` es para que `Editor` sea `Sync` y la FFI lo pueda guardar en un
    // `static`, sin depender de si el proxy de tao lo es.
    proxy: Mutex<EventLoopProxy<Command>>,
}

impl Editor {
    pub fn start(backend: Arc<dyn EditorBackend>, events: EventSink) -> Result<Editor, String> {
        let (ready_tx, ready_rx) = mpsc::channel();
        thread::Builder::new()
            .name("nexodeck-editor".into())
            .spawn(move || run(ready_tx, backend, events))
            .map_err(|e| format!("no se pudo lanzar el hilo del editor: {e}"))?;
        let proxy = ready_rx
            .recv()
            .map_err(|_| "el hilo del editor murio al arrancar".to_string())?;
        Ok(Editor {
            proxy: Mutex::new(proxy),
        })
    }

    /// Abre la ventana (o la trae al frente) sin abrir ninguna nota.
    pub fn show(&self, theme: Option<ThemeDto>) -> Result<(), String> {
        self.send(Command::Show { theme })
    }

    /// Abre la nota en la ventana. No espera a que se vea: lo que pase llega como
    /// [`EditorEvent`].
    pub fn open(&self, note: NoteDto, theme: Option<ThemeDto>) -> Result<(), String> {
        self.send(Command::Open { note, theme })
    }

    pub fn set_theme(&self, theme: ThemeDto) -> Result<(), String> {
        self.send(Command::SetTheme(theme))
    }

    /// Algo cambio en la boveda o en el buzon: la ventana vuelve a leer lo que
    /// enseña. Sin ventana abierta no hace nada.
    pub fn changed(&self) -> Result<(), String> {
        self.send(Command::Changed)
    }

    /// Como pulsar la X: si hay cambios, se guardan antes.
    pub fn close(&self) -> Result<(), String> {
        self.send(Command::Close)
    }

    fn send(&self, command: Command) -> Result<(), String> {
        self.proxy
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .send_event(command)
            .map_err(|_| "el hilo del editor ya no esta".to_string())
    }
}

struct OpenWindow {
    window: Window,
    webview: WebView,
    session: Session,
}

/// Donde estaba la ventana al cerrarla, para abrirla igual la proxima vez.
/// Solo en memoria: vale para la sesion, no sobrevive a reiniciar NexoDeck.
#[derive(Clone, Copy)]
struct Bounds {
    position: Option<PhysicalPosition<i32>>,
    size: PhysicalSize<u32>,
    maximized: bool,
}

fn run(ready: mpsc::Sender<EventLoopProxy<Command>>, backend: Arc<dyn EditorBackend>, events: EventSink) {
    let event_loop = EventLoopBuilder::<Command>::with_user_event()
        .with_any_thread(true)
        .build();
    let proxy = event_loop.create_proxy();
    let _ = ready.send(proxy.clone());

    let mut context = WebContext::new(webview_data_dir());
    let mut open: Option<OpenWindow> = None;
    let mut bounds: Option<Bounds> = None;

    event_loop.run(move |event, target, control_flow| {
        *control_flow = ControlFlow::Wait;
        let now = Instant::now();
        let effects = match event {
            Event::UserEvent(Command::Open { note, theme }) => {
                if !ensure_window(&mut open, target, &mut context, &proxy, &backend, &events, theme.as_ref(), bounds) {
                    return;
                }
                with_session(&mut open, |s| s.open(note, theme, now))
            }
            Event::UserEvent(Command::Show { theme }) => {
                if !ensure_window(&mut open, target, &mut context, &proxy, &backend, &events, theme.as_ref(), bounds) {
                    return;
                }
                with_session(&mut open, |s| s.show(theme, now))
            }
            Event::UserEvent(Command::SetTheme(theme)) => with_session(&mut open, |s| s.set_theme(theme)),
            Event::UserEvent(Command::Page(raw)) => match serde_json::from_str::<PageMessage>(&raw) {
                Ok(message) => with_session(&mut open, |s| s.page(message, now)),
                Err(error) => {
                    log::warn!("mensaje de la pagina del editor que no se entiende: {error}");
                    return;
                }
            },
            Event::UserEvent(Command::Fetched(result)) => with_session(&mut open, |s| s.fetched(result, now)),
            Event::UserEvent(Command::Picked(pick, path)) => with_session(&mut open, |s| s.picked(pick, path)),
            Event::UserEvent(Command::Changed) => with_session(&mut open, |s| s.changed(now)),
            Event::UserEvent(Command::Close)
            | Event::WindowEvent {
                event: WindowEvent::CloseRequested,
                ..
            } => with_session(&mut open, |s| s.close_requested(now)),
            Event::WindowEvent {
                event: WindowEvent::Focused(true),
                ..
            } => with_session(&mut open, |s| s.focused(now)),
            _ => return,
        };
        apply(&mut open, &mut bounds, effects, &backend, &proxy, &events);
    });
}

/// Crea la ventana si no esta. `false` si no se pudo (ya se aviso a la app).
#[allow(clippy::too_many_arguments)]
fn ensure_window(
    open: &mut Option<OpenWindow>,
    target: &EventLoopWindowTarget<Command>,
    context: &mut WebContext,
    proxy: &EventLoopProxy<Command>,
    backend: &Arc<dyn EditorBackend>,
    events: &EventSink,
    theme: Option<&ThemeDto>,
    bounds: Option<Bounds>,
) -> bool {
    if open.is_some() {
        return true;
    }
    match build_window(target, context, proxy, theme, bounds, backend) {
        Ok((window, webview)) => {
            *open = Some(OpenWindow {
                window,
                webview,
                session: Session::new(Arc::clone(backend)),
            });
            true
        }
        Err(detail) => {
            events(EditorEvent::Error { detail });
            false
        }
    }
}

fn with_session(open: &mut Option<OpenWindow>, act: impl FnOnce(&mut Session) -> Vec<Effect>) -> Vec<Effect> {
    open.as_mut().map(|o| act(&mut o.session)).unwrap_or_default()
}

fn apply(
    open: &mut Option<OpenWindow>,
    bounds: &mut Option<Bounds>,
    effects: Vec<Effect>,
    backend: &Arc<dyn EditorBackend>,
    proxy: &EventLoopProxy<Command>,
    events: &EventSink,
) {
    for effect in effects {
        match effect {
            Effect::Emit(event) => events(event),
            Effect::OpenExternal(url) => open_external(&url),
            Effect::Fetch(job) => fetch(Arc::clone(backend), proxy.clone(), job),
            Effect::Pick(pick) => {
                if let Some(o) = open.as_ref() {
                    pick_path(&o.window, proxy.clone(), pick);
                }
            }
            Effect::Destroy => {
                if let Some(OpenWindow { window, webview, .. }) = open.take() {
                    if !window.is_minimized() {
                        *bounds = Some(Bounds {
                            position: window.outer_position().ok(),
                            size: window.inner_size(),
                            maximized: window.is_maximized(),
                        });
                    }
                    // Primero el WebView, despues la ventana que lo contiene.
                    drop(webview);
                    drop(window);
                }
            }
            Effect::Send(message) => {
                if let Some(o) = open.as_ref() {
                    // Nunca el mensaje en el log: lleva el texto de la nota.
                    if let Err(error) = o.webview.evaluate_script(&script_for(&message)) {
                        log::warn!("no se pudo entregar un mensaje a la pagina del editor: {error}");
                    }
                }
            }
            Effect::Title(title) => {
                if let Some(o) = open.as_ref() {
                    o.window.set_title(&title);
                }
            }
            Effect::Focus => {
                if let Some(o) = open.as_ref() {
                    if o.window.is_minimized() {
                        o.window.set_minimized(false);
                    }
                    o.window.set_focus();
                    let _ = o.webview.focus();
                }
            }
            Effect::Theme(theme) => {
                if let Some(o) = open.as_ref() {
                    o.window.set_theme(Some(window_theme(&theme)));
                }
            }
        }
    }
}

fn build_window(
    target: &EventLoopWindowTarget<Command>,
    context: &mut WebContext,
    proxy: &EventLoopProxy<Command>,
    theme: Option<&ThemeDto>,
    bounds: Option<Bounds>,
    backend: &Arc<dyn EditorBackend>,
) -> Result<(Window, WebView), String> {
    let mut window = WindowBuilder::new()
        .with_title("Notas de NexoDeck")
        .with_min_inner_size(LogicalSize::new(720.0, 480.0))
        .with_theme(theme.map(window_theme));
    match bounds {
        Some(previous) => {
            window = window
                .with_inner_size(previous.size)
                .with_maximized(previous.maximized);
            if let Some(position) = previous
                .position
                .filter(|position| is_on_screen(target, *position, previous.size))
            {
                window = window.with_position(position);
            }
        }
        None => window = window.with_inner_size(default_size(target)),
    }
    // Sin el recurso (el ejemplo, que no es el exe de Flutter) queda el de Windows.
    if let Ok(icon) = Icon::from_resource(APP_ICON_RESOURCE, None) {
        window = window.with_window_icon(Some(icon));
    }
    let window = window
        .build(target)
        .map_err(|e| format!("no se pudo crear la ventana del editor: {e}"))?;

    let ipc_proxy = proxy.clone();
    let serve_backend = Arc::clone(backend);
    let mut webview = WebViewBuilder::new_with_web_context(context)
        .with_url(assets::START_URL)
        .with_custom_protocol(assets::PROTOCOL.to_string(), move |_id, request| {
            serve(&request, &serve_backend)
        })
        .with_ipc_handler(move |request: Request<String>| {
            // Solo la pagina propia habla con Rust; la navegacion ya bloquea el
            // resto, esto es la segunda puerta.
            if !assets::is_own_url(&request.uri().to_string()) {
                log::warn!("mensaje al editor desde una pagina ajena: ignorado");
                return;
            }
            let _ = ipc_proxy.send_event(Command::Page(request.into_body()));
        })
        .with_navigation_handler(|url| {
            let own = assets::is_own_url(&url);
            if !own && assets::is_external_url(&url) {
                open_external(&url);
            }
            own
        })
        .with_new_window_req_handler(|url, _features| {
            if assets::is_external_url(&url) {
                open_external(&url);
            }
            NewWindowResponse::Deny
        })
        .with_devtools(cfg!(debug_assertions))
        .with_hotkeys_zoom(true)
        .with_focused(true)
        // Sin los atajos del navegador: Ctrl+P es la paleta y no imprimir, Ctrl+F
        // busca con CodeMirror, y F5 no recarga la pagina a mitad de una nota.
        .with_browser_accelerator_keys(false);
    if let Some(theme) = theme {
        if let Some(color) = theme.background_rgba() {
            webview = webview.with_background_color(color);
        }
        webview = webview.with_theme(web_theme(theme));
    }
    let webview = webview
        .build(&window)
        .map_err(|e| format!("no se pudo crear el WebView2 del editor: {e}"))?;
    Ok((window, webview))
}

/// La primera vez: casi todo el monitor principal, con tope. La ventana lleva
/// lista, editor y panel lado a lado, y a 1280 px de ancho ya van justos.
fn default_size(target: &EventLoopWindowTarget<Command>) -> LogicalSize<f64> {
    target
        .primary_monitor()
        .map(|monitor| {
            let screen = monitor.size().to_logical::<f64>(monitor.scale_factor());
            LogicalSize::new((screen.width * 0.86).min(1480.0), (screen.height * 0.86).min(940.0))
        })
        .unwrap_or_else(|| LogicalSize::new(1280.0, 820.0))
}

fn is_on_screen(
    target: &EventLoopWindowTarget<Command>,
    position: PhysicalPosition<i32>,
    size: PhysicalSize<u32>,
) -> bool {
    let width = i32::try_from(size.width).unwrap_or(i32::MAX);
    let height = i32::try_from(size.height).unwrap_or(i32::MAX);
    target.available_monitors().any(|monitor| {
        let origin = monitor.position();
        let screen = monitor.size();
        let screen_width = i32::try_from(screen.width).unwrap_or(i32::MAX);
        let screen_height = i32::try_from(screen.height).unwrap_or(i32::MAX);
        let overlap_x = (position.x.saturating_add(width)).min(origin.x.saturating_add(screen_width))
            - position.x.max(origin.x);
        let overlap_y = (position.y.saturating_add(height)).min(origin.y.saturating_add(screen_height))
            - position.y.max(origin.y);
        overlap_x >= MIN_VISIBLE.0 && overlap_y >= MIN_VISIBLE.1
    })
}

fn serve(request: &Request<Vec<u8>>, backend: &Arc<dyn EditorBackend>) -> Response<Cow<'static, [u8]>> {
    let uri = request.uri();
    if uri.path() == "/attachment" {
        return serve_attachment(uri.query().unwrap_or(""), backend);
    }
    let Some(asset) = assets::lookup(uri.path()) else {
        return not_found();
    };
    Response::builder()
        .header(header::CONTENT_TYPE, asset.mime)
        .header(header::CACHE_CONTROL, "no-store")
        .header(header::X_CONTENT_TYPE_OPTIONS, "nosniff")
        .body(Cow::Borrowed(asset.bytes))
        .unwrap_or_else(|_| not_found())
}

/// Sirve una imagen de la boveda pedida como `/attachment?note=..&src=..`. El
/// backend resuelve `src` relativa a la nota, dentro de la boveda: nada de
/// fuera se sirve.
fn serve_attachment(query: &str, backend: &Arc<dyn EditorBackend>) -> Response<Cow<'static, [u8]>> {
    let mut note = String::new();
    let mut src = String::new();
    for pair in query.split('&') {
        let Some((key, value)) = pair.split_once('=') else {
            continue;
        };
        match key {
            "note" => note = percent_decode(value),
            "src" => src = percent_decode(value),
            _ => {}
        }
    }
    if src.is_empty() {
        return not_found();
    }
    match backend.read_attachment(&note, &src) {
        Ok(Some((mime, bytes))) => Response::builder()
            .header(header::CONTENT_TYPE, mime)
            .header(header::CACHE_CONTROL, "no-store")
            .header(header::X_CONTENT_TYPE_OPTIONS, "nosniff")
            .body(Cow::Owned(bytes))
            .unwrap_or_else(|_| not_found()),
        _ => not_found(),
    }
}

fn percent_decode(value: &str) -> String {
    percent_encoding::percent_decode_str(value)
        .decode_utf8_lossy()
        .into_owned()
}

fn not_found() -> Response<Cow<'static, [u8]>> {
    let mut response = Response::new(Cow::Borrowed(&b"no existe"[..]));
    *response.status_mut() = StatusCode::NOT_FOUND;
    response
}

/// Abre un dialogo nativo, modal sobre la ventana de notas.
///
/// **En otro hilo**: el dialogo bloquea hasta que el usuario elige, y en el hilo
/// del event loop dejaria de llegar todo lo demas (los avisos del buzon, el
/// resultado de una busqueda). Lo elegido vuelve por el event loop, como un
/// `Fetched`.
fn pick_path(window: &Window, proxy: EventLoopProxy<Command>, pick: Pick) {
    let dialog = rfd::FileDialog::new().set_parent(window);
    let spawned = thread::Builder::new()
        .name("nexodeck-editor-dialog".into())
        .spawn(move || {
            let chosen = match &pick {
                Pick::Vault => dialog
                    .set_title("Espacio de NexoDeck: la carpeta principal de notas")
                    .pick_folder(),
                Pick::LocalFolder => dialog
                    .set_title("Importar notas locales: carpeta con tus .md")
                    .pick_folder(),
                Pick::OneNoteFile => dialog
                    .set_title("Importar desde OneNote: elige el cuaderno (.one)")
                    .add_filter("OneNote", &["one"])
                    .pick_file(),
                Pick::OneNoteFolder { .. } => dialog
                    .set_title("¿Dónde guardar las notas importadas?")
                    .pick_folder(),
                Pick::ExportZip { file_name } => dialog
                    .set_title("Exportar notas")
                    .add_filter("Zip", &["zip"])
                    .set_file_name(file_name)
                    .save_file(),
            };
            let path = chosen.map(|p| p.display().to_string());
            let _ = proxy.send_event(Command::Picked(pick, path));
        });
    if let Err(error) = spawned {
        log::warn!("no se pudo abrir el dialogo de carpetas: {error}");
    }
}

/// Un trabajo lento en su propio hilo; el resultado vuelve por el event loop.
fn fetch(backend: Arc<dyn EditorBackend>, proxy: EventLoopProxy<Command>, job: Job) {
    let spawned = thread::Builder::new()
        .name("nexodeck-editor-fetch".into())
        .spawn(move || {
            let result = run_job(backend.as_ref(), job);
            let _ = proxy.send_event(Command::Fetched(result));
        });
    if let Err(error) = spawned {
        log::warn!("no se pudo lanzar una lectura de la boveda: {error}");
    }
}

/// `explorer.exe` y no `cmd /c start`: con cmd, un `&` del enlace seria otro
/// comando.
fn open_external(url: &str) {
    if let Err(error) = std::process::Command::new("explorer.exe").arg(url).spawn() {
        log::warn!("no se pudo abrir el enlace en el navegador: {error}");
    }
}

/// La carpeta de datos de WebView2. En la local y no en la itinerante: es cache
/// del navegador, cientos de MB que no tienen que viajar con el perfil. Sin
/// indicarla, WebView2 la crea junto al ejecutable, que en una instalacion para
/// todos los usuarios no se puede escribir.
fn webview_data_dir() -> Option<PathBuf> {
    directories::ProjectDirs::from("dev", "nexodeck", "NexoDeck")
        .map(|dirs| dirs.data_local_dir().join("editor_webview2"))
}

fn window_theme(theme: &ThemeDto) -> WindowTheme {
    if theme.dark {
        WindowTheme::Dark
    } else {
        WindowTheme::Light
    }
}

fn web_theme(theme: &ThemeDto) -> WebTheme {
    if theme.dark {
        WebTheme::Dark
    } else {
        WebTheme::Light
    }
}
