//! El borrador que produce el asistente, y sus invariantes.
//!
//! Es la frontera entre "lo que dijo un modelo de lenguaje" y "algo que se
//! puede guardar en la base". Todo lo de aca asume que **el modelo se
//! equivoca**: inventa iconos que no existen, se olvida de declarar un
//! parametro que uso, propone nombres de 200 caracteres. La validacion no es
//! defensiva por manía; es el motivo por el que la funcion puede existir.
//!
//! La misma validacion se repite del lado Dart (`draft_validation.dart`). No es
//! duplicacion inutil: aca sirve para poder **devolverle el error al modelo** y
//! que lo corrija en la misma conversacion; alla sirve como ultima red antes de
//! escribir en Drift.

use serde::{Deserialize, Serialize};

/// Iconos validos. **Tiene que coincidir exactamente** con `kActionIcons` de
/// `app/lib/features/actions/presentation/widgets/action_icons.dart`: un icono
/// fuera de esta lista cae al de por defecto y el boton generado no se parece
/// a lo que el usuario vio en la vista previa.
pub const ICONS: &[&str] = &[
    "bolt",
    "terminal",
    "content_paste",
    "code",
    "videocam",
    "mic",
    "storage",
    "edit",
    "folder",
    "settings",
];

/// Paleta valida, espejo de `kActionColorPalette` del mismo archivo.
pub const COLORS: &[&str] = &[
    "#6366F1", "#22C55E", "#EF4444", "#F59E0B", "#0EA5E9", "#EC4899",
];

/// Limite de `ActionsTable.name` en Drift (`withLength(min: 1, max: 60)`).
/// Pasarse no da un error legible: falla el insert.
pub const MAX_NAME_LEN: usize = 60;

/// Tope de pasos de una macro propuesta. No es un limite tecnico: una cadena
/// de mas de esto casi siempre significa que el modelo se fue por las ramas y
/// conviene que vuelva a preguntar.
pub const MAX_STEPS: usize = 12;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DraftActionType {
    Clipboard,
    Terminal,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DraftTerminalType {
    DefaultShell,
    PowerShell,
    Bash,
    Cmd,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DraftParamKind {
    Text,
    Number,
    Select,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DraftParam {
    /// Nombre de la variable, sin llaves: `rama`, no `{{rama}}`.
    pub key: String,
    pub label: String,
    #[serde(default = "default_param_kind")]
    pub kind: DraftParamKind,
    #[serde(default)]
    pub default_value: Option<String>,
    #[serde(default)]
    pub options: Vec<String>,
}

fn default_param_kind() -> DraftParamKind {
    DraftParamKind::Text
}

/// Arranca una suscripcion SignalR en vivo apenas el paso termina bien, leyendo
/// [`json_field`] de su salida (interpretada como JSON) — mismo dato que
/// `AutoSubscribeConfig` del lado Dart (`deck_action.dart`), copiado aca para
/// que el modelo lo pueda proponer. Solo tiene efecto sobre un paso capturado
/// (`show_terminal_window = false`): `validate_step` lo exige.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DraftAutoSubscribe {
    pub base_url: String,
    pub hub_path: String,
    pub invoke_method: String,
    /// Campo de nivel superior de la salida JSON que trae el id del job
    /// (ej. `job_id`). Sin rutas anidadas, mismo limite que el lado Dart.
    pub json_field: String,
    #[serde(default)]
    pub allow_invalid_cert: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DraftStep {
    pub name: String,
    #[serde(default)]
    pub description: Option<String>,
    pub action_type: DraftActionType,
    /// Comando o texto a copiar. Puede llevar `{{variables}}`.
    pub command: String,
    #[serde(default = "default_terminal")]
    pub terminal: DraftTerminalType,
    #[serde(default)]
    pub requires_admin: bool,
    #[serde(default = "default_true")]
    pub show_terminal_window: bool,
    /// Carpeta desde la que hay que ejecutar. Se pliega dentro del comando en
    /// [`fold_working_directory`] porque el esquema de acciones no tiene una
    /// columna para esto.
    #[serde(default)]
    pub working_directory: Option<String>,
    #[serde(default)]
    pub parameters: Vec<DraftParam>,
    /// Pausa despues de este paso, solo en macros.
    #[serde(default)]
    pub delay_ms_after: u32,
    #[serde(default)]
    pub auto_subscribe: Option<DraftAutoSubscribe>,
}

fn default_terminal() -> DraftTerminalType {
    DraftTerminalType::DefaultShell
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActionDraft {
    pub name: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default = "default_icon")]
    pub icon: String,
    #[serde(default = "default_color")]
    pub color_hex: String,
    /// Explicacion en lenguaje natural de por que el comando quedo asi. Se
    /// muestra en la vista previa: es lo que permite que el usuario apruebe con
    /// criterio en vez de a ciegas.
    #[serde(default)]
    pub summary: String,
    /// Un paso = accion simple. Varios = macro con esos pasos como hojas.
    pub steps: Vec<DraftStep>,
}

fn default_icon() -> String {
    "bolt".to_string()
}

fn default_color() -> String {
    COLORS[0].to_string()
}

impl ActionDraft {
    pub fn is_macro(&self) -> bool {
        self.steps.len() > 1
    }
}

// ---------------------------------------------------------------------
// Validacion
// ---------------------------------------------------------------------

/// Un problema concreto del borrador, redactado **para el modelo**: cada
/// mensaje dice que esta mal y como arreglarlo, porque se le devuelve tal cual
/// como resultado de la herramienta para que reintente.
#[derive(Debug, Clone, PartialEq)]
pub struct DraftProblem {
    pub field: String,
    pub detail: String,
}

impl DraftProblem {
    fn new(field: impl Into<String>, detail: impl Into<String>) -> Self {
        DraftProblem {
            field: field.into(),
            detail: detail.into(),
        }
    }
}

pub fn validate(draft: &ActionDraft) -> Vec<DraftProblem> {
    let mut problems = Vec::new();

    let name = draft.name.trim();
    if name.is_empty() {
        problems.push(DraftProblem::new("name", "el nombre no puede estar vacio"));
    } else if name.chars().count() > MAX_NAME_LEN {
        problems.push(DraftProblem::new(
            "name",
            format!(
                "el nombre tiene {} caracteres y el maximo es {MAX_NAME_LEN}",
                name.chars().count()
            ),
        ));
    }

    if !ICONS.contains(&draft.icon.as_str()) {
        problems.push(DraftProblem::new(
            "icon",
            format!(
                "'{}' no es un icono valido. Elegi uno de: {}",
                draft.icon,
                ICONS.join(", ")
            ),
        ));
    }

    if !COLORS.contains(&draft.color_hex.to_uppercase().as_str()) {
        problems.push(DraftProblem::new(
            "color_hex",
            format!(
                "'{}' no es un color valido. Elegi uno de: {}",
                draft.color_hex,
                COLORS.join(", ")
            ),
        ));
    }

    if draft.steps.is_empty() {
        problems.push(DraftProblem::new("steps", "hace falta al menos un paso"));
    } else if draft.steps.len() > MAX_STEPS {
        problems.push(DraftProblem::new(
            "steps",
            format!(
                "{} pasos es demasiado (maximo {MAX_STEPS}). Dividilo o volve a preguntar que necesita el usuario.",
                draft.steps.len()
            ),
        ));
    }

    for (index, step) in draft.steps.iter().enumerate() {
        validate_step(index, step, &mut problems);
    }

    problems
}

fn validate_step(index: usize, step: &DraftStep, problems: &mut Vec<DraftProblem>) {
    let field = |suffix: &str| format!("steps[{index}].{suffix}");

    if step.name.trim().is_empty() {
        problems.push(DraftProblem::new(field("name"), "el paso necesita un nombre"));
    } else if step.name.chars().count() > MAX_NAME_LEN {
        problems.push(DraftProblem::new(
            field("name"),
            format!("el nombre del paso supera los {MAX_NAME_LEN} caracteres"),
        ));
    }

    if step.command.trim().is_empty() {
        problems.push(DraftProblem::new(
            field("command"),
            "el comando no puede estar vacio",
        ));
    }

    // Claves de parametro: unicas, no vacias y usables como `{{clave}}`.
    let mut seen: Vec<&str> = Vec::new();
    for param in &step.parameters {
        let key = param.key.trim();
        if key.is_empty() {
            problems.push(DraftProblem::new(
                field("parameters"),
                "hay un parametro sin `key`",
            ));
            continue;
        }
        if !key
            .chars()
            .all(|c| c.is_alphanumeric() || c == '_' || c == '-')
        {
            problems.push(DraftProblem::new(
                field("parameters"),
                format!(
                    "la clave '{key}' tiene caracteres no permitidos: usa solo letras, numeros, guion y guion bajo"
                ),
            ));
        }
        if seen.contains(&key) {
            problems.push(DraftProblem::new(
                field("parameters"),
                format!("la clave '{key}' esta repetida en el mismo paso"),
            ));
        }
        seen.push(key);

        if param.kind == DraftParamKind::Select && param.options.len() < 2 {
            problems.push(DraftProblem::new(
                field("parameters"),
                format!(
                    "el parametro '{key}' es de tipo select pero tiene {} opciones: una lista necesita al menos 2",
                    param.options.len()
                ),
            ));
        }
    }

    // El invariante que mas se rompe: usar `{{algo}}` sin declararlo. El
    // resultado seria un boton que copia o ejecuta las llaves literales.
    let declared: Vec<String> = step
        .parameters
        .iter()
        .map(|param| param.key.trim().to_string())
        .collect();
    for placeholder in placeholders_in(&step.command) {
        if !declared.contains(&placeholder) {
            problems.push(DraftProblem::new(
                field("parameters"),
                format!(
                    "el comando usa {{{{{placeholder}}}}} pero no lo declaraste en `parameters`. Agregalo o saca la variable del comando."
                ),
            ));
        }
    }

    if step.action_type == DraftActionType::Clipboard && step.requires_admin {
        problems.push(DraftProblem::new(
            field("requires_admin"),
            "copiar al portapapeles nunca necesita permisos de administrador",
        ));
    }

    if let Some(auto_subscribe) = &step.auto_subscribe {
        validate_auto_subscribe(index, step, auto_subscribe, problems);
    }
}

fn validate_auto_subscribe(
    index: usize,
    step: &DraftStep,
    auto_subscribe: &DraftAutoSubscribe,
    problems: &mut Vec<DraftProblem>,
) {
    let field = |suffix: &str| format!("steps[{index}].auto_subscribe.{suffix}");

    if step.action_type == DraftActionType::Clipboard {
        problems.push(DraftProblem::new(
            field("action_type"),
            "el portapapeles no ejecuta nada: no hay salida que leer para suscribirse",
        ));
    }
    // `auto_subscribe` solo puede disparar sobre una corrida CAPTURADA (ver
    // `ActionsRepository._executeCaptured` / `ai_live_runner.dart`): una
    // ventana real no entrega su salida a nadie, la suscripcion nunca
    // arrancaria y el fallo seria mudo.
    if step.show_terminal_window {
        problems.push(DraftProblem::new(
            field("show_terminal_window"),
            "la suscripcion automatica necesita la salida capturada: poné `show_terminal_window: false` en este paso",
        ));
    }

    for (value, suffix, label) in [
        (auto_subscribe.base_url.trim(), "base_url", "la URL base"),
        (auto_subscribe.hub_path.trim(), "hub_path", "la ruta del hub"),
        (auto_subscribe.invoke_method.trim(), "invoke_method", "el metodo a invocar"),
        (auto_subscribe.json_field.trim(), "json_field", "el campo del JSON con el id"),
    ] {
        if value.is_empty() {
            problems.push(DraftProblem::new(
                field(suffix),
                format!("falta {label}: no la inventes, pedisela al usuario si no la dijo"),
            ));
        }
    }
}

/// Extrae los nombres de variable de un `{{...}}`.
///
/// Mismo criterio que `app/lib/features/actions/domain/placeholders.dart`: se
/// admite espacio alrededor del nombre y se ignoran las llaves anidadas.
pub fn placeholders_in(template: &str) -> Vec<String> {
    let mut found = Vec::new();
    let bytes = template.as_bytes();
    let mut i = 0;

    while i + 1 < bytes.len() {
        if bytes[i] == b'{' && bytes[i + 1] == b'{' {
            if let Some(end) = template[i + 2..].find("}}") {
                let inner = template[i + 2..i + 2 + end].trim();
                if !inner.is_empty() && !inner.contains('{') && !found.iter().any(|f| f == inner) {
                    found.push(inner.to_string());
                }
                i = i + 2 + end + 2;
                continue;
            }
        }
        i += 1;
    }

    found
}

/// Mete el `working_directory` dentro del comando.
///
/// El esquema de acciones no tiene columna para "carpeta de trabajo", asi que
/// se resuelve con el prefijo que corresponda a cada shell. Se hace aca (puro y
/// testeado) y no en la UI para que el comando que se muestra en la vista
/// previa sea **exactamente** el que se va a guardar y ejecutar.
pub fn fold_working_directory(step: &DraftStep) -> String {
    let Some(directory) = step
        .working_directory
        .as_deref()
        .map(str::trim)
        .filter(|dir| !dir.is_empty())
    else {
        return step.command.clone();
    };

    // El portapapeles no ejecuta nada: un `cd` ahi solo ensuciaria el texto.
    if step.action_type == DraftActionType::Clipboard {
        return step.command.clone();
    }

    // Los modelos meten el `cd` dentro del comando **y** ademas rellenan
    // `working_directory`. Verificado con Qwen3-4B contra un proyecto real: el
    // resultado era `cd /d "E:\x"` seguido de `cd "E:\x" && flutter analyze`.
    // En cmd funciona de casualidad, pero el segundo `cd` va sin `/d`: si algun
    // dia la consola arranca en otra unidad, no cambia de directorio y el boton
    // "no hace nada" sin ningun error. Se detecta y no se antepone nada.
    if command_already_enters(directory, &step.command) {
        return step.command.clone();
    }

    match step.terminal {
        DraftTerminalType::PowerShell => format!(
            "Set-Location -LiteralPath '{}'\n{}",
            directory.replace('\'', "''"),
            step.command
        ),
        // `/d` es obligatorio: sin el, `cd` no cambia de unidad y un proyecto
        // en E:\ desde una consola parada en C:\ no se abriria nunca.
        DraftTerminalType::Cmd | DraftTerminalType::DefaultShell => {
            format!("cd /d \"{directory}\"\r\n{}", step.command)
        }
        DraftTerminalType::Bash => format!("cd \"{directory}\" && {}", step.command),
    }
}

/// ¿El comando ya empieza entrando a esa misma carpeta?
///
/// Solo mira el **primer** enunciado: un `cd` en el medio de una cadena es otra
/// cosa y no hay que tocarlo.
fn command_already_enters(directory: &str, command: &str) -> bool {
    const PREFIXES: &[&str] = &["cd /d ", "cd ", "set-location -literalpath ", "set-location ", "pushd "];

    let first_statement = command
        .split(['\n', '\r'])
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("")
        // `cd X && cmd` y `cd X; cmd`: el `cd` es el primer enunciado igual.
        .split("&&")
        .next()
        .unwrap_or("")
        .split(';')
        .next()
        .unwrap_or("")
        .trim();

    let lowered = first_statement.to_lowercase();
    let Some(prefix) = PREFIXES.iter().find(|prefix| lowered.starts_with(**prefix)) else {
        return false;
    };

    let target = first_statement[prefix.len()..].trim();
    normalize_dir(target) == normalize_dir(directory)
}

fn normalize_dir(path: &str) -> String {
    path.trim()
        .trim_matches(|c| matches!(c, '"' | '\''))
        .replace('\\', "/")
        .trim_end_matches('/')
        .to_lowercase()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn step(command: &str) -> DraftStep {
        DraftStep {
            name: "Paso".into(),
            description: None,
            action_type: DraftActionType::Terminal,
            command: command.into(),
            terminal: DraftTerminalType::PowerShell,
            requires_admin: false,
            show_terminal_window: true,
            working_directory: None,
            parameters: Vec::new(),
            delay_ms_after: 0,
            auto_subscribe: None,
        }
    }

    fn auto_subscribe() -> DraftAutoSubscribe {
        DraftAutoSubscribe {
            base_url: "https://relay.example.com".into(),
            hub_path: "/jobsHub".into(),
            invoke_method: "SubscribeToJob".into(),
            json_field: "job_id".into(),
            allow_invalid_cert: false,
        }
    }

    fn draft(steps: Vec<DraftStep>) -> ActionDraft {
        ActionDraft {
            name: "Analizar proyecto".into(),
            description: None,
            icon: "code".into(),
            color_hex: "#6366F1".into(),
            summary: "corre flutter analyze".into(),
            steps,
        }
    }

    #[test]
    fn un_borrador_correcto_no_tiene_problemas() {
        assert!(validate(&draft(vec![step("flutter analyze")])).is_empty());
    }

    #[test]
    fn un_icono_inventado_se_rechaza_y_se_listan_los_validos() {
        let mut d = draft(vec![step("echo hola")]);
        d.icon = "rocket".into();

        let problems = validate(&d);
        let problem = problems.iter().find(|p| p.field == "icon").unwrap();
        assert!(problem.detail.contains("rocket"));
        assert!(
            problem.detail.contains("terminal"),
            "el mensaje tiene que listar los validos para que el modelo corrija"
        );
    }

    #[test]
    fn un_color_fuera_de_la_paleta_se_rechaza() {
        let mut d = draft(vec![step("echo hola")]);
        d.color_hex = "#123456".into();
        assert!(validate(&d).iter().any(|p| p.field == "color_hex"));
    }

    #[test]
    fn el_color_se_compara_sin_importar_mayusculas() {
        let mut d = draft(vec![step("echo hola")]);
        d.color_hex = "#6366f1".into();
        assert!(validate(&d).iter().all(|p| p.field != "color_hex"));
    }

    #[test]
    fn el_nombre_no_puede_pasar_el_limite_de_drift() {
        let mut d = draft(vec![step("echo hola")]);
        d.name = "a".repeat(MAX_NAME_LEN + 1);
        assert!(validate(&d).iter().any(|p| p.field == "name"));

        d.name = "a".repeat(MAX_NAME_LEN);
        assert!(validate(&d).iter().all(|p| p.field != "name"));
    }

    /// El error mas comun del modelo: usar una variable sin declararla. El
    /// boton resultante ejecutaria las llaves literales.
    #[test]
    fn una_variable_sin_declarar_se_rechaza_con_instruccion_de_como_arreglarlo() {
        let d = draft(vec![step("git checkout {{rama}}")]);

        let problems = validate(&d);
        let problem = problems
            .iter()
            .find(|p| p.detail.contains("rama"))
            .expect("tiene que detectar la variable sin declarar");
        assert!(problem.detail.contains("Agregalo"));
    }

    #[test]
    fn una_variable_declarada_no_da_problema() {
        let mut s = step("git checkout {{rama}}");
        s.parameters.push(DraftParam {
            key: "rama".into(),
            label: "Rama".into(),
            kind: DraftParamKind::Text,
            default_value: Some("main".into()),
            options: Vec::new(),
        });

        assert!(validate(&draft(vec![s])).is_empty());
    }

    #[test]
    fn las_claves_repetidas_en_un_paso_se_rechazan() {
        let mut s = step("echo {{a}}");
        for _ in 0..2 {
            s.parameters.push(DraftParam {
                key: "a".into(),
                label: "A".into(),
                kind: DraftParamKind::Text,
                default_value: None,
                options: Vec::new(),
            });
        }

        assert!(validate(&draft(vec![s]))
            .iter()
            .any(|p| p.detail.contains("repetida")));
    }

    #[test]
    fn un_select_sin_opciones_no_sirve() {
        let mut s = step("echo {{modo}}");
        s.parameters.push(DraftParam {
            key: "modo".into(),
            label: "Modo".into(),
            kind: DraftParamKind::Select,
            default_value: None,
            options: vec!["debug".into()],
        });

        assert!(validate(&draft(vec![s]))
            .iter()
            .any(|p| p.detail.contains("al menos 2")));
    }

    #[test]
    fn el_portapapeles_nunca_necesita_administrador() {
        let mut s = step("texto");
        s.action_type = DraftActionType::Clipboard;
        s.requires_admin = true;

        assert!(validate(&draft(vec![s]))
            .iter()
            .any(|p| p.field.ends_with("requires_admin")));
    }

    // ---- auto_subscribe ----

    #[test]
    fn un_paso_capturado_con_auto_subscribe_completo_no_tiene_problemas() {
        let mut s = step("curl -X POST https://relay.example.com/jobs/nueva-tanda");
        s.show_terminal_window = false;
        s.auto_subscribe = Some(auto_subscribe());

        assert!(validate(&draft(vec![s])).is_empty());
    }

    #[test]
    fn auto_subscribe_en_el_portapapeles_se_rechaza() {
        let mut s = step("texto");
        s.action_type = DraftActionType::Clipboard;
        s.auto_subscribe = Some(auto_subscribe());

        let problems = validate(&draft(vec![s]));
        assert!(problems.iter().any(|p| p.field.ends_with("action_type")));
    }

    /// El motivo real: una ventana real no entrega su salida a nadie, la
    /// suscripcion nunca arrancaria y el fallo seria mudo.
    #[test]
    fn auto_subscribe_con_ventana_de_terminal_se_rechaza() {
        let mut s = step("curl https://relay.example.com/jobs");
        s.show_terminal_window = true;
        s.auto_subscribe = Some(auto_subscribe());

        let problems = validate(&draft(vec![s]));
        assert!(problems.iter().any(|p| p.field.ends_with("show_terminal_window")));
    }

    #[test]
    fn auto_subscribe_con_campos_vacios_se_rechaza_uno_por_uno() {
        let mut s = step("curl https://relay.example.com/jobs");
        s.show_terminal_window = false;
        s.auto_subscribe = Some(DraftAutoSubscribe {
            base_url: String::new(),
            hub_path: "  ".into(),
            invoke_method: "SubscribeToJob".into(),
            json_field: "job_id".into(),
            allow_invalid_cert: false,
        });

        let problems = validate(&draft(vec![s]));
        assert!(problems.iter().any(|p| p.field.ends_with("base_url")));
        assert!(problems.iter().any(|p| p.field.ends_with("hub_path")));
        assert!(!problems.iter().any(|p| p.field.ends_with("invoke_method")));
    }

    #[test]
    fn placeholders_in_tolera_espacios_y_no_repite() {
        assert_eq!(
            placeholders_in("git checkout {{ rama }} && git pull origin {{rama}}"),
            vec!["rama"]
        );
        assert!(placeholders_in("sin variables").is_empty());
        assert!(placeholders_in("{{}}").is_empty(), "vacio no es una variable");
        assert!(placeholders_in("{{sin cerrar").is_empty());
    }

    // ---- fold_working_directory ----

    #[test]
    fn powershell_usa_set_location_con_literalpath() {
        let mut s = step("flutter analyze");
        s.working_directory = Some(r"E:\Proyectos\ExampleApp".into());

        let folded = fold_working_directory(&s);
        assert!(folded.starts_with("Set-Location -LiteralPath 'E:\\Proyectos\\ExampleApp'"));
        assert!(folded.ends_with("flutter analyze"));
    }

    /// Sin `/d`, `cd` no cambia de unidad: un proyecto en E:\ desde una consola
    /// parada en C:\ no se abriria nunca, y el sintoma seria "el boton no hace
    /// nada".
    #[test]
    fn cmd_usa_cd_con_barra_d_para_poder_cambiar_de_unidad() {
        let mut s = step("flutter analyze");
        s.terminal = DraftTerminalType::Cmd;
        s.working_directory = Some(r"E:\Proyectos\ExampleApp".into());

        assert!(fold_working_directory(&s).starts_with("cd /d \"E:\\Proyectos\\ExampleApp\""));
    }

    #[test]
    fn bash_encadena_con_and() {
        let mut s = step("flutter analyze");
        s.terminal = DraftTerminalType::Bash;
        s.working_directory = Some("/home/user/app".into());

        assert_eq!(
            fold_working_directory(&s),
            "cd \"/home/user/app\" && flutter analyze"
        );
    }

    #[test]
    fn las_comillas_simples_de_la_ruta_se_escapan_en_powershell() {
        let mut s = step("dir");
        s.working_directory = Some("E:/carpeta d'ejemplo".into());

        assert!(fold_working_directory(&s).contains("d''ejemplo"));
    }

    #[test]
    fn sin_working_directory_el_comando_queda_igual() {
        assert_eq!(fold_working_directory(&step("flutter analyze")), "flutter analyze");
    }

    /// Caso real: Qwen3-4B puso el `cd` dentro del comando **y ademas** relleno
    /// `working_directory`. Anteponer otro `cd` dejaba dos, y el de adentro sin
    /// `/d`: en otra unidad no cambiaria de carpeta y el boton "no haria nada".
    #[test]
    fn no_se_antepone_un_cd_si_el_comando_ya_entra_a_esa_carpeta() {
        let mut s = step(r#"cd "E:\RepositoriosFix\ExampleApp" && flutter analyze"#);
        s.terminal = DraftTerminalType::Cmd;
        s.working_directory = Some(r"E:\RepositoriosFix\ExampleApp".into());

        let folded = fold_working_directory(&s);
        assert_eq!(folded, s.command);
        assert_eq!(folded.matches("cd ").count(), 1, "quedaron dos cd: {folded}");
    }

    #[test]
    fn se_detecta_el_cd_en_sus_variantes_y_sin_importar_barras_ni_comillas() {
        for command in [
            r#"cd /d "E:\Proyectos\App""#,
            r#"cd E:/Proyectos/App"#,
            r#"pushd 'E:\Proyectos\App'"#,
            "Set-Location -LiteralPath 'E:/Proyectos/App'\nflutter analyze",
        ] {
            assert!(
                command_already_enters(r"E:\Proyectos\App", command),
                "no detecto el cd en: {command}"
            );
        }
    }

    /// Un `cd` a **otra** carpeta no cuenta: ahi si hace falta el prefijo.
    #[test]
    fn un_cd_a_otra_carpeta_no_evita_el_prefijo() {
        let mut s = step(r#"cd "E:\Otra" && flutter analyze"#);
        s.terminal = DraftTerminalType::Cmd;
        s.working_directory = Some(r"E:\Proyectos\App".into());

        assert!(fold_working_directory(&s).starts_with(r#"cd /d "E:\Proyectos\App""#));
    }

    /// Un `cd` en el medio de la cadena es otra cosa y no hay que interpretarlo
    /// como "ya estamos ahi".
    #[test]
    fn un_cd_que_no_es_el_primer_enunciado_no_cuenta() {
        assert!(!command_already_enters(
            r"E:\Proyectos\App",
            r#"flutter clean && cd "E:\Proyectos\App""#
        ));
    }

    #[test]
    fn el_portapapeles_ignora_el_working_directory() {
        let mut s = step("texto a copiar");
        s.action_type = DraftActionType::Clipboard;
        s.working_directory = Some("E:/x".into());

        assert_eq!(fold_working_directory(&s), "texto a copiar");
    }

    #[test]
    fn un_solo_paso_no_es_macro() {
        assert!(!draft(vec![step("a")]).is_macro());
        assert!(draft(vec![step("a"), step("b")]).is_macro());
    }

    /// El borrador viene del modelo como JSON: los defaults tienen que
    /// aguantar que falte casi todo.
    #[test]
    fn el_json_minimo_del_modelo_deserializa_con_defaults() {
        let json = serde_json::json!({
            "name": "Abrir proyecto",
            "steps": [{
                "name": "Abrir",
                "action_type": "terminal",
                "command": "code ."
            }]
        });

        let draft: ActionDraft = serde_json::from_value(json).unwrap();
        assert_eq!(draft.icon, "bolt");
        assert_eq!(draft.color_hex, COLORS[0]);
        assert!(draft.steps[0].show_terminal_window);
        assert_eq!(draft.steps[0].terminal, DraftTerminalType::DefaultShell);
        assert!(validate(&draft).is_empty());
    }
}
