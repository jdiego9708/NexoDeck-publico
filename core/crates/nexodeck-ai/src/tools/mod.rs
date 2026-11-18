//! Herramientas que el modelo puede llamar, y el registro que las despacha.
//!
//! ## Todas devuelven JSON, ninguna devuelve un error de transporte
//!
//! Una herramienta que falla devuelve `{"ok": false, "error": "..."}`. Nunca un
//! `Err`. La diferencia importa: un error **como resultado** es una senal que el
//! modelo sabe leer y con la que corrige el rumbo; un error de protocolo lo
//! descarrila y termina inventando.
//!
//! ## El gate: por que existe [`TurnFacts`]
//!
//! El brief pide que el asistente **converse y repregunte** antes de proponer
//! nada. Un system prompt que lo diga no alcanza en un modelo de 4B: obedece
//! las dos primeras veces y despues se apura. La solucion que si funciona es
//! hacerlo estructural — `propose_action` **rechaza** el borrador si menciona
//! una ruta que ninguna herramienta devolvio, o un ejecutable que nunca se
//! verifico. Un rechazo devuelto como resultado de herramienta es la senal que
//! los modelos chicos obedecen con mucha mas fiabilidad que cualquier
//! instruccion en prosa.

pub mod deck;
pub mod devices;
pub mod emit;
pub mod exec;
pub mod fs;

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use serde_json::{Value, json};

use crate::openai::types::ToolDef;

/// Builtins y palabras de shell que no son programas del PATH: exigir
/// `which_executable` para `cd` seria absurdo y quemaria rondas. Compartido
/// entre `emit.rs` (que los exime de la verificacion obligatoria) y
/// `exec.rs` (que hace que `which_executable` los reconozca en vez de
/// devolver "no esta instalado" para algo que nunca se instala).
pub const SHELL_BUILTINS: &[&str] = &[
    "cd", "echo", "set", "setx", "dir", "type", "cls", "exit", "call", "start", "rem", "if",
    "for", "pushd", "popd", "md", "mkdir", "rd", "copy", "move", "ren", "pause", "timeout",
    "set-location", "write-host", "write-output", "get-childitem", "get-content", "get-location",
    "new-item", "select-object", "where-object", "foreach-object", "sleep", "start-process",
    "start-sleep", "export", "source", "alias", "pwd", "ls", "cat", "true", "false", "then",
    "else", "fi", "do", "done", "&&", "||", "|", ";",
];

/// Los cmdlets de PowerShell siguen la convencion `Verbo-Sustantivo` en
/// PascalCase (`Get-WmiObject`, `Get-CimInstance`, `Test-Path`,
/// `Copy-Item`...) — son parte del motor o de un modulo cargado, nunca un
/// archivo del PATH. Hay cientos, entre los del sistema y los que trae cada
/// modulo instalado: imposible listarlos uno por uno como `SHELL_BUILTINS`
/// (bug real: `Get-WmiObject` no estaba en esa lista, `which_executable` lo
/// dio por "no instalado", y el modelo termino recomendando instalar
/// "Windows Management Framework" para un cmdlet que ya viene con
/// Windows). Se detectan por FORMA, no por nombre.
pub fn looks_like_powershell_cmdlet(name: &str) -> bool {
    let Some(dash) = name.find('-') else { return false };
    let (verb, rest) = name.split_at(dash);
    is_pascal_word(verb) && is_pascal_word(&rest[1..])
}

fn is_pascal_word(word: &str) -> bool {
    let mut chars = word.chars();
    match chars.next() {
        Some(first) if first.is_ascii_uppercase() => {}
        _ => return false,
    }
    chars.all(|c| c.is_ascii_alphanumeric())
}

/// Accion que ya existe en el deck, para que el asistente no proponga
/// duplicados.
#[derive(Debug, Clone)]
pub struct DeckActionRef {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub description: Option<String>,
}

/// Hechos que se fueron verificando **en este turno**. Es la memoria contra la
/// que `propose_action` valida.
#[derive(Debug, Default)]
pub struct TurnFacts {
    /// Rutas absolutas que alguna herramienta devolvio de verdad. Normalizadas
    /// en minusculas y con `/`.
    pub confirmed_paths: BTreeSet<String>,
    pub verified_executables: BTreeSet<String>,
    pub missing_executables: BTreeSet<String>,
    pub listed_android_devices: bool,
    pub android_serials: Vec<String>,
    pub listed_shells: bool,
    /// Cuantas veces se llamo a `propose_action`. Se topea en 1 por turno.
    pub proposals: u32,
}

impl TurnFacts {
    pub fn confirm_path(&mut self, path: &Path) {
        self.confirmed_paths.insert(normalize_path(path));
    }

    pub fn knows_path(&self, candidate: &str) -> bool {
        let normalized = normalize_str(candidate);
        // Alcanza con que la ruta este **debajo** de algo confirmado: si el
        // modelo listo `E:/Proyectos/ExampleApp`, referirse a
        // `E:/Proyectos/ExampleApp/lib` es legitimo y no hace falta obligarlo
        // a listar cada subcarpeta.
        self.confirmed_paths
            .iter()
            .any(|known| normalized == *known || normalized.starts_with(&format!("{known}/")))
    }
}

fn normalize_path(path: &Path) -> String {
    normalize_str(&path.to_string_lossy())
}

fn normalize_str(path: &str) -> String {
    path.trim()
        .replace('\\', "/")
        .trim_end_matches('/')
        .to_lowercase()
}

/// Contexto compartido por todas las herramientas durante una conversacion.
///
/// Las carpetas permitidas y el deck van detras de un `RwLock` porque **cambian
/// mientras la conversacion esta viva**: el usuario puede sacar una carpeta
/// desde el wizard, o crear un boton en otra pantalla. Recrear la sesion para
/// eso perderia el historial; que el cambio no se aplique hasta la proxima
/// conversacion seria una sorpresa silenciosa.
pub struct ToolContext {
    /// Carpetas que el asistente puede leer. **Solo lectura, siempre**:
    /// ninguna herramienta escribe, borra ni ejecuta nada del proyecto del
    /// usuario.
    allowed_roots: std::sync::RwLock<Vec<PathBuf>>,
    pub os: nexodeck_hardware::HostOs,
    deck: std::sync::RwLock<Vec<DeckActionRef>>,
    pub facts: Arc<Mutex<TurnFacts>>,
}

impl ToolContext {
    pub fn new(allowed_roots: Vec<PathBuf>, os: nexodeck_hardware::HostOs) -> Self {
        ToolContext {
            allowed_roots: std::sync::RwLock::new(allowed_roots),
            os,
            deck: std::sync::RwLock::new(Vec::new()),
            facts: Arc::new(Mutex::new(TurnFacts::default())),
        }
    }

    pub fn allowed_roots(&self) -> Vec<PathBuf> {
        self.allowed_roots
            .read()
            .map(|roots| roots.clone())
            .unwrap_or_default()
    }

    pub fn set_allowed_roots(&self, roots: Vec<PathBuf>) {
        if let Ok(mut current) = self.allowed_roots.write() {
            *current = roots;
        }
    }

    pub fn deck(&self) -> Vec<DeckActionRef> {
        self.deck.read().map(|deck| deck.clone()).unwrap_or_default()
    }

    pub fn set_deck(&self, deck: Vec<DeckActionRef>) {
        if let Ok(mut current) = self.deck.write() {
            *current = deck;
        }
    }

    /// Empieza un turno nuevo: los hechos verificados no se arrastran entre
    /// pedidos distintos del usuario.
    pub fn reset_facts(&self) {
        if let Ok(mut facts) = self.facts.lock() {
            *facts = TurnFacts::default();
        }
    }

    pub fn with_facts<R>(&self, f: impl FnOnce(&mut TurnFacts) -> R) -> R {
        let mut facts = self.facts.lock().unwrap_or_else(|poisoned| {
            // Un panic en una herramienta no puede dejar toda la conversacion
            // inutilizable.
            poisoned.into_inner()
        });
        f(&mut facts)
    }

    /// ¿Se puede leer esta ruta?
    ///
    /// Dos condiciones: estar debajo de alguna raiz permitida **y** no estar en
    /// la lista de exclusion. La exclusion gana siempre.
    pub fn is_readable(&self, path: &Path) -> bool {
        let normalized = normalize_path(path);

        if is_excluded(&normalized) {
            return false;
        }

        self.allowed_roots().iter().any(|root| {
            let root = normalize_path(root);
            normalized == root || normalized.starts_with(&format!("{root}/"))
        })
    }
}

/// Carpetas que nunca se leen aunque caigan dentro de una raiz permitida.
///
/// No es seguridad real (el proceso corre como el usuario y podria leerlas);
/// es higiene: nada de lo que hay ahi ayuda a armar un boton, y el contenido
/// no tiene por que pasar por el contexto de un modelo.
const EXCLUDED_FRAGMENTS: &[&str] = &[
    "/windows/system32",
    "/windows/syswow64",
    "/windows/winsxs",
    "/appdata/local/microsoft",
    "/appdata/roaming/microsoft",
    "/microsoft/credentials",
    "/microsoft/crypto",
    "/microsoft/protect",
    "/.ssh",
    "/.gnupg",
    "/.aws",
    "/$recycle.bin",
    "/system volume information",
    "/etc/shadow",
    "/proc/",
];

fn is_excluded(normalized: &str) -> bool {
    EXCLUDED_FRAGMENTS
        .iter()
        .any(|fragment| normalized.contains(fragment))
}

/// Una herramienta llamable por el modelo.
///
/// `call` es **sincrono** a proposito: todas hacen I/O de disco o lanzan
/// procesos, que bloquean. El agente las corre dentro de `spawn_blocking` en
/// vez de contagiar `async` a todo el arbol para nada.
pub trait Tool: Send + Sync {
    fn name(&self) -> &'static str;
    fn definition(&self) -> ToolDef;
    fn call(&self, args: &Value, ctx: &ToolContext) -> Value;
}

/// Registro con despacho por nombre.
pub struct ToolRegistry {
    tools: Vec<Box<dyn Tool>>,
}

impl ToolRegistry {
    /// Todas las herramientas del Bloque B.
    pub fn standard() -> Self {
        ToolRegistry {
            tools: vec![
                Box::new(fs::ListDirectory),
                Box::new(fs::FindProject),
                Box::new(fs::ReadTextFile),
                Box::new(exec::WhichExecutable),
                Box::new(exec::ListShellCapabilities),
                Box::new(devices::ListAndroidDevices),
                Box::new(deck::ListExistingActions),
                Box::new(emit::ProposeAction),
            ],
        }
    }

    pub fn definitions(&self) -> Vec<ToolDef> {
        self.tools.iter().map(|tool| tool.definition()).collect()
    }

    /// Ejecuta por nombre. Una herramienta desconocida devuelve un resultado de
    /// error, no un panic: los modelos chicos inventan nombres de herramienta a
    /// veces, y hay que dejarlos corregir.
    pub fn dispatch(&self, name: &str, arguments: &str, ctx: &ToolContext) -> Value {
        let Some(tool) = self.tools.iter().find(|tool| tool.name() == name) else {
            return json!({
                "ok": false,
                "error": format!(
                    "no existe una herramienta llamada '{name}'. Las disponibles son: {}",
                    self.tools.iter().map(|t| t.name()).collect::<Vec<_>>().join(", ")
                )
            });
        };

        // Los argumentos vienen como string JSON armado por el modelo y pueden
        // estar mal formados. Se le devuelve el error para que reintente.
        let args: Value = match serde_json::from_str(arguments) {
            Ok(args) => args,
            Err(_) if arguments.trim().is_empty() => json!({}),
            Err(error) => {
                return json!({
                    "ok": false,
                    "error": format!("los argumentos no son JSON valido: {error}")
                });
            }
        };

        tool.call(&args, ctx)
    }

    /// Herramienta que existe. Lo usa el agente para no ejecutar dos veces la
    /// terminal.
    pub fn is_terminal(name: &str) -> bool {
        name == emit::ProposeAction.name()
    }
}

/// Carpetas que el asistente puede leer si el usuario no configuro otra cosa.
///
/// Decision de producto tomada: **home del usuario + raices de unidades
/// fijas**, solo lectura, con la lista de exclusion de arriba encima. La
/// alternativa (arrancar vacio y que el usuario agregue carpetas) da mejor
/// privacidad pero un primer uso malo: `find_project` no encuentra nada y el
/// asistente tiene que pedir rutas absolutas a mano en cada conversacion.
///
/// La lista es visible y editable desde el wizard y se persiste en
/// `app_settings`.
pub fn default_allowed_roots() -> Vec<PathBuf> {
    let mut roots = Vec::new();

    if let Some(dirs) = directories::UserDirs::new() {
        roots.push(dirs.home_dir().to_path_buf());
    }

    #[cfg(target_os = "windows")]
    {
        // Se prueban las letras de unidad en vez de enumerar por API para no
        // arrastrar el crate `windows` a este crate. Las que no existen fallan
        // al instante.
        for letter in b'A'..=b'Z' {
            let root = PathBuf::from(format!("{}:\\", letter as char));
            if root.is_dir() {
                roots.push(root);
            }
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        roots.push(PathBuf::from("/home"));
        roots.push(PathBuf::from("/opt"));
        roots.push(PathBuf::from("/srv"));
    }

    // Una raiz contenida en otra es ruido: `C:\` ya cubre el home del usuario.
    roots.sort_by_key(|root| root.as_os_str().len());
    let mut deduped: Vec<PathBuf> = Vec::new();
    for root in roots {
        let normalized = normalize_path(&root);
        let covered = deduped.iter().any(|kept| {
            let kept = normalize_path(kept);
            normalized == kept || normalized.starts_with(&format!("{kept}/"))
        });
        if !covered {
            deduped.push(root);
        }
    }

    deduped
}

/// Helpers compartidos por las herramientas.
pub(crate) fn arg_str<'a>(args: &'a Value, key: &str) -> Option<&'a str> {
    args.get(key).and_then(Value::as_str).map(str::trim).filter(|s| !s.is_empty())
}

pub(crate) fn error(message: impl Into<String>) -> Value {
    json!({ "ok": false, "error": message.into() })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ctx_with_root(root: &str) -> ToolContext {
        ToolContext::new(vec![PathBuf::from(root)], nexodeck_hardware::HostOs::Windows)
    }

    /// Bug real: `Get-WmiObject` no estaba en `SHELL_BUILTINS`,
    /// `which_executable` lo dio por no instalado, y el modelo recomendo
    /// instalar "Windows Management Framework" para un cmdlet que ya viene
    /// con Windows.
    #[test]
    fn reconoce_cmdlets_reales_de_powershell() {
        for cmdlet in [
            "Get-WmiObject",
            "Get-CimInstance",
            "Test-Path",
            "Copy-Item",
            "Remove-Item",
            "ConvertTo-Json",
            "Invoke-WebRequest",
        ] {
            assert!(looks_like_powershell_cmdlet(cmdlet), "{cmdlet} tendria que reconocerse");
        }
    }

    #[test]
    fn no_confunde_programas_reales_con_cmdlets() {
        for name in [
            "git",
            "flutter",
            "docker-compose",
            "node",
            "python3",
            "npm",
            "",
            "-",
            "Get-",
            "-WmiObject",
        ] {
            assert!(
                !looks_like_powershell_cmdlet(name),
                "'{name}' no es un cmdlet, no se tendria que reconocer como uno"
            );
        }
    }

    #[test]
    fn una_ruta_fuera_de_las_raices_no_se_lee() {
        let ctx = ctx_with_root("E:/Proyectos");

        assert!(ctx.is_readable(Path::new("E:/Proyectos/ExampleApp")));
        assert!(ctx.is_readable(Path::new(r"E:\Proyectos\ExampleApp\lib")));
        assert!(!ctx.is_readable(Path::new("C:/Otra")));
    }

    /// Un prefijo de texto no es un prefijo de ruta: `E:/ProyectosViejos` no
    /// esta dentro de `E:/Proyectos`.
    #[test]
    fn el_prefijo_se_compara_por_segmento_de_ruta() {
        let ctx = ctx_with_root("E:/Proyectos");
        assert!(!ctx.is_readable(Path::new("E:/ProyectosViejos/x")));
    }

    #[test]
    fn la_exclusion_gana_sobre_la_raiz_permitida() {
        let ctx = ctx_with_root("C:/");

        assert!(!ctx.is_readable(Path::new(r"C:\Windows\System32\config")));
        assert!(!ctx.is_readable(Path::new(
            r"C:\Users\x\AppData\Local\Microsoft\Credentials"
        )));
        assert!(!ctx.is_readable(Path::new(r"C:\Users\x\.ssh\id_rsa")));
        assert!(ctx.is_readable(Path::new(r"C:\Users\x\Documentos")));
    }

    #[test]
    fn una_ruta_confirmada_habilita_sus_subcarpetas() {
        let mut facts = TurnFacts::default();
        facts.confirm_path(Path::new(r"E:\Proyectos\ExampleApp"));

        assert!(facts.knows_path(r"E:\Proyectos\ExampleApp"));
        assert!(facts.knows_path("E:/Proyectos/ExampleApp/lib"));
        assert!(!facts.knows_path("E:/Proyectos/OtroProyecto"));
        // Y tampoco el hermano con prefijo de texto.
        assert!(!facts.knows_path("E:/Proyectos/ExampleApp2"));
    }

    #[test]
    fn una_herramienta_inexistente_devuelve_error_con_la_lista_de_validas() {
        let registry = ToolRegistry::standard();
        let ctx = ctx_with_root("E:/");

        let result = registry.dispatch("volar", "{}", &ctx);
        assert_eq!(result["ok"], false);
        assert!(result["error"].as_str().unwrap().contains("list_directory"));
    }

    #[test]
    fn los_argumentos_mal_formados_vuelven_como_error_util() {
        let registry = ToolRegistry::standard();
        let ctx = ctx_with_root("E:/");

        let result = registry.dispatch("list_directory", "{no es json", &ctx);
        assert_eq!(result["ok"], false);
        assert!(result["error"].as_str().unwrap().contains("JSON"));
    }

    /// Un modelo que manda `""` en vez de `"{}"` para una herramienta sin
    /// argumentos es comun y no puede costar una ronda.
    #[test]
    fn los_argumentos_vacios_se_tratan_como_objeto_vacio() {
        let registry = ToolRegistry::standard();
        let ctx = ctx_with_root("E:/");

        let result = registry.dispatch("list_shell_capabilities", "", &ctx);
        assert_eq!(result["ok"], true);
    }

    #[test]
    fn el_registro_expone_las_ocho_herramientas() {
        let definitions = ToolRegistry::standard().definitions();
        assert_eq!(definitions.len(), 8);

        let names: Vec<_> = definitions.iter().map(|d| d.function.name.as_str()).collect();
        for expected in [
            "list_directory",
            "find_project",
            "read_text_file",
            "which_executable",
            "list_shell_capabilities",
            "list_android_devices",
            "list_existing_actions",
            "propose_action",
        ] {
            assert!(names.contains(&expected), "falta {expected}");
        }
    }

    #[test]
    fn reset_facts_limpia_lo_verificado_en_el_turno_anterior() {
        let ctx = ctx_with_root("E:/");
        ctx.with_facts(|facts| facts.confirm_path(Path::new("E:/x")));
        assert!(ctx.with_facts(|facts| facts.knows_path("E:/x")));

        ctx.reset_facts();
        assert!(!ctx.with_facts(|facts| facts.knows_path("E:/x")));
    }
}
