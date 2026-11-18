//! Pegar en la ventana que el usuario tenia enfocada ANTES de tocar NexoDeck.
//!
//! El problema que resuelve es el que hace inutil una accion de portapapeles
//! en un deck: el usuario esta escribiendo en el bloc de notas, hace clic en
//! el boton de NexoDeck y **ese clic le da el foco a NexoDeck**. Copiar el
//! texto al portapapeles no alcanza -- el cursor de escritura ya no esta
//! donde tiene que estar, y no hay nadie que apriete Ctrl+V.
//!
//! Por eso hacen falta las dos mitades:
//!
//! 1. **Saber a que ventana volver.** No se puede averiguar en el momento de
//!    ejecutar (ahi el foco ya es nuestro), asi que hay que ir anotandolo
//!    desde antes: [`start_focus_tracking`] engancha `EVENT_SYSTEM_FOREGROUND`
//!    y guarda la ultima ventana en primer plano **que no sea de este
//!    proceso**.
//! 2. **Devolverle el foco y mandar Ctrl+V.** Ver [`paste_into_active_window`].
//!
//! Es un hook de eventos y no un poll: el foco cambia cuando el usuario lo
//! cambia, y un poll cada N ms se pierde justo el caso rapido (tocar la app y
//! volver). Se registra con `WINEVENT_OUTOFCONTEXT`, asi que Windows no
//! inyecta ningun DLL en los otros procesos -- solo nos manda el evento.
//!
//! Emparentado con `nexodeck-hardware::foreground`, que tambien mira la
//! ventana en primer plano, pero para otra cosa (resolver el nombre del
//! proceso para el auto-cambio de perfil) y con otra cadencia. No se
//! comparten: aquel resuelve nombres una vez por segundo con `sysinfo`, este
//! necesita el `HWND` exacto en el instante justo.

use crate::ActionError;

#[cfg(target_os = "windows")]
mod platform {
    use std::sync::OnceLock;
    use std::sync::atomic::{AtomicIsize, Ordering};
    use std::time::{Duration, Instant};

    use windows::Win32::Foundation::HWND;
    use windows::Win32::System::Threading::{
        AttachThreadInput, GetCurrentProcessId, GetCurrentThreadId,
    };
    use windows::Win32::UI::Accessibility::{HWINEVENTHOOK, SetWinEventHook};
    use windows::Win32::UI::Input::KeyboardAndMouse::{
        INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP, SendInput, VIRTUAL_KEY,
        VK_CONTROL, VK_V,
    };
    use windows::Win32::UI::WindowsAndMessaging::{
        DispatchMessageW, EVENT_SYSTEM_FOREGROUND, GetForegroundWindow, GetMessageW,
        GetWindowThreadProcessId, IsIconic, IsWindow, IsWindowVisible, MSG, OBJID_WINDOW,
        SW_RESTORE, SetForegroundWindow, ShowWindow, WINEVENT_OUTOFCONTEXT,
        WINEVENT_SKIPOWNPROCESS,
    };

    /// Ultima ventana en primer plano ajena a este proceso, como `HWND` crudo.
    /// `0` = todavia no se vio ninguna.
    static LAST_EXTERNAL: AtomicIsize = AtomicIsize::new(0);
    static TRACKER: OnceLock<bool> = OnceLock::new();

    /// Cuanto se espera a que Windows haga efectivo el cambio de foco antes de
    /// mandar las teclas. `SetForegroundWindow` vuelve enseguida pero la
    /// activacion es asincrona: mandar Ctrl+V antes de que el destino este
    /// activo se lo come la ventana equivocada.
    const FOCUS_TIMEOUT: Duration = Duration::from_millis(400);
    const FOCUS_POLL: Duration = Duration::from_millis(10);

    /// Margen entre que el destino queda activo y las teclas. Sin esto, algunas
    /// apps (las de Electron sobre todo) todavia no movieron el foco a su campo
    /// de texto interno y el Ctrl+V se pierde.
    const SETTLE: Duration = Duration::from_millis(40);

    unsafe extern "system" fn on_foreground(
        _hook: HWINEVENTHOOK,
        event: u32,
        hwnd: HWND,
        id_object: i32,
        id_child: i32,
        _thread: u32,
        _time: u32,
    ) {
        // Solo la ventana en si: el mismo evento llega para controles hijos
        // (`id_object != OBJID_WINDOW`), y esos no sirven como destino.
        if event != EVENT_SYSTEM_FOREGROUND || id_object != OBJID_WINDOW.0 || id_child != 0 {
            return;
        }
        if hwnd.is_invalid() {
            return;
        }
        // `WINEVENT_SKIPOWNPROCESS` ya deberia filtrar nuestras ventanas, pero
        // se vuelve a comprobar aca: si alguna vez se registrara el hook sin
        // ese flag, NexoDeck se anotaria a si mismo como destino y la accion
        // terminaria pegando sobre la propia app.
        if is_own_window(hwnd) {
            return;
        }
        LAST_EXTERNAL.store(hwnd.0 as isize, Ordering::Relaxed);
    }

    fn is_own_window(hwnd: HWND) -> bool {
        let mut pid = 0u32;
        unsafe { GetWindowThreadProcessId(hwnd, Some(&mut pid)) };
        pid != 0 && pid == unsafe { GetCurrentProcessId() }
    }

    /// Arranca el hook, una sola vez por proceso.
    ///
    /// El callback de un `WinEvent` corre **en el hilo que instalo el hook**, y
    /// solo mientras ese hilo bombee mensajes: de ahi el hilo propio con su
    /// `GetMessageW`. Colgarlo del hilo de UI de Flutter no es opcion, no
    /// tenemos su bomba de mensajes desde Rust.
    pub fn start_tracking() {
        TRACKER.get_or_init(|| {
            std::thread::Builder::new()
                .name("nexodeck-focus".into())
                .spawn(|| unsafe {
                    let hook = SetWinEventHook(
                        EVENT_SYSTEM_FOREGROUND,
                        EVENT_SYSTEM_FOREGROUND,
                        None,
                        Some(on_foreground),
                        0,
                        0,
                        WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS,
                    );
                    if hook.is_invalid() {
                        return;
                    }
                    let mut msg = MSG::default();
                    while GetMessageW(&mut msg, None, 0, 0).as_bool() {
                        DispatchMessageW(&msg);
                    }
                })
                .is_ok()
        });
    }

    /// La ventana a la que hay que devolverle el foco, ya validada.
    fn target() -> Option<HWND> {
        let tracked = LAST_EXTERNAL.load(Ordering::Relaxed);
        let candidate = if tracked != 0 {
            HWND(tracked as *mut core::ffi::c_void)
        } else {
            // Sin tracker (o antes del primer cambio de foco) queda el camino
            // directo, que ademas es el correcto cuando la ejecucion NO vino
            // de un clic en NexoDeck: si la dispara el telefono, la ventana en
            // primer plano ya es la que el usuario esta usando.
            let current = unsafe { GetForegroundWindow() };
            if current.is_invalid() || is_own_window(current) {
                return None;
            }
            current
        };

        let alive = unsafe { IsWindow(Some(candidate)).as_bool() }
            && unsafe { IsWindowVisible(candidate).as_bool() };
        alive.then_some(candidate)
    }

    /// Devuelve el foco al destino y manda Ctrl+V.
    pub fn paste_into_last_window() -> Result<(), String> {
        let target = target().ok_or_else(|| {
            "no hay ninguna ventana a la que pegar (la ultima que se uso ya no existe)".to_string()
        })?;

        unsafe {
            if IsIconic(target).as_bool() {
                let _ = ShowWindow(target, SW_RESTORE);
            }

            // `AttachThreadInput` es lo que hace que `SetForegroundWindow`
            // funcione de verdad: Windows bloquea el robo de foco entre
            // procesos, y compartir la cola de entrada con el destino nos
            // cuenta como "el mismo hilo" para esa comprobacion. NexoDeck es
            // el proceso en primer plano en este momento (el usuario acaba de
            // hacerle clic), asi que tiene derecho a cederlo.
            let our_thread = GetCurrentThreadId();
            let target_thread = GetWindowThreadProcessId(target, None);
            let attached =
                target_thread != 0 && AttachThreadInput(our_thread, target_thread, true).as_bool();

            let activated = SetForegroundWindow(target).as_bool();

            if attached {
                let _ = AttachThreadInput(our_thread, target_thread, false);
            }
            if !activated {
                return Err("Windows no dejo devolverle el foco a la ventana de destino".to_string());
            }

            // Se espera a que el cambio sea efectivo en vez de dormir un rato
            // fijo: una app pesada tarda mas que una liviana, y un sleep largo
            // se siente como un boton que no responde.
            let deadline = Instant::now() + FOCUS_TIMEOUT;
            while GetForegroundWindow() != target && Instant::now() < deadline {
                std::thread::sleep(FOCUS_POLL);
            }
            if GetForegroundWindow() != target {
                return Err("la ventana de destino no llego a tomar el foco".to_string());
            }
            std::thread::sleep(SETTLE);

            send_ctrl_v()
        }
    }

    unsafe fn send_ctrl_v() -> Result<(), String> {
        let inputs = [
            key(VK_CONTROL, false),
            key(VK_V, false),
            key(VK_V, true),
            key(VK_CONTROL, true),
        ];
        let sent = unsafe { SendInput(&inputs, std::mem::size_of::<INPUT>() as i32) };
        if sent as usize != inputs.len() {
            // El caso tipico es UIPI: si la ventana de destino pertenece a un
            // proceso elevado y NexoDeck no lo esta, Windows descarta la
            // entrada sintetica sin mas senal que este conteo.
            return Err(
                "Windows bloqueo el envio de teclas (la ventana de destino corre como \
                 administrador y NexoDeck no)"
                    .to_string(),
            );
        }
        Ok(())
    }

    fn key(vk: VIRTUAL_KEY, up: bool) -> INPUT {
        INPUT {
            r#type: INPUT_KEYBOARD,
            Anonymous: INPUT_0 {
                ki: KEYBDINPUT {
                    wVk: vk,
                    wScan: 0,
                    dwFlags: if up {
                        KEYEVENTF_KEYUP
                    } else {
                        Default::default()
                    },
                    time: 0,
                    dwExtraInfo: 0,
                },
            },
        }
    }
}

#[cfg(not(target_os = "windows"))]
mod platform {
    pub fn start_tracking() {}

    pub fn paste_into_last_window() -> Result<(), String> {
        Err("pegar en la ventana activa solo esta implementado en Windows".to_string())
    }
}

/// Empieza a seguir que ventana tiene el foco. Idempotente y barata: se llama
/// una vez al arrancar la app.
///
/// **Tiene que llamarse antes** de que el usuario toque un boton del deck: en
/// el momento de ejecutar la accion el foco ya es de NexoDeck, y de ahi no se
/// puede deducir cual era la ventana anterior.
pub fn start_focus_tracking() {
    platform::start_tracking();
}

/// Le devuelve el foco a la ultima ventana ajena que lo tuvo y manda Ctrl+V.
///
/// Da por sentado que el texto ya esta en el portapapeles (ver
/// [`crate::paste_to_clipboard`]).
pub fn paste_into_active_window() -> Result<(), ActionError> {
    platform::paste_into_last_window().map_err(ActionError::Focus)
}
