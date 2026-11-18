//! `propose_action`: la salida estructurada y el gate que la protege.
//!
//! # Por que esto no es "una herramienta mas"
//!
//! El brief pide que el asistente **converse y aclare toda duda, por minima que
//! sea**, antes de generar el script. Poner eso en el system prompt no alcanza:
//! un modelo de 4B (y a veces uno de 14B) lo cumple las primeras veces y
//! despues se apura, especialmente si el usuario escribe algo que "suena
//! completo".
//!
//! La solucion que si funciona es hacerlo **estructural**. Esta herramienta
//! revisa el borrador contra los hechos que se verificaron realmente en el
//! turno ([`TurnFacts`]) y, si algo no cierra, **rechaza la propuesta y
//! devuelve exactamente que falta y con que herramienta conseguirlo**. Un
//! rechazo devuelto como *resultado de herramienta* es la senal que los modelos
//! chicos obedecen con muchisima mas fiabilidad que cualquier instruccion en
//! prosa: no es una sugerencia, es que su intento no funciono.
//!
//! Las precondiciones que se exigen:
//!
//! 1. Toda ruta absoluta que aparezca en un comando o en `working_directory`
//!    tiene que haber salido de `find_project` / `list_directory` /
//!    `read_text_file`.
//! 2. Todo programa que el comando invoque tiene que haber pasado por
//!    `which_executable` (salvo los builtins del shell).
//! 3. Si el comando menciona `adb` o `-d <serial>`, `list_android_devices`
//!    tiene que haber corrido.
//! 4. El borrador tiene que pasar la validacion estructural de [`crate::draft`].
//! 5. Una sola propuesta por turno.

use serde_json::{Value, json};

use crate::draft::{self, ActionDraft, DraftActionType};
use crate::openai::types::ToolDef;
use crate::tools::{SHELL_BUILTINS, Tool, ToolContext, TurnFacts};

pub struct ProposeAction;

impl Tool for ProposeAction {
    fn name(&self) -> &'static str {
        "propose_action"
    }

    fn definition(&self) -> ToolDef {
        ToolDef::function(
            "propose_action",
            "Emite el borrador FINAL del boton (o de la cadena de botones). \
             Llamala UNA SOLA VEZ por conversacion y SOLO cuando no quede ninguna ambiguedad: \
             la ruta absoluta confirmada con find_project o list_directory, el programa verificado \
             con which_executable, el shell elegido con list_shell_capabilities y, si hay un \
             telefono involucrado, el serial obtenido con list_android_devices. \
             Si te falta algo, NO la llames: preguntale al usuario o usa la herramienta que falte.",
            schema(),
        )
    }

    fn call(&self, args: &Value, ctx: &ToolContext) -> Value {
        let already_proposed = ctx.with_facts(|facts| {
            facts.proposals += 1;
            facts.proposals > 1
        });
        if already_proposed {
            return json!({
                "ok": false,
                "error": "ya emitiste un borrador en este turno. Si necesitas corregirlo, \
                          esperá a que el usuario responda."
            });
        }

        let parsed: ActionDraft = match serde_json::from_value(args.clone()) {
            Ok(parsed) => parsed,
            Err(error) => {
                return json!({
                    "ok": false,
                    "error": format!(
                        "el borrador no tiene la forma esperada: {error}. \
                         Revisá el esquema de la herramienta y volvé a intentar."
                    )
                });
            }
        };

        // Primero la validacion estructural: si el borrador esta mal formado no
        // tiene sentido revisar hechos.
        let problems = draft::validate(&parsed);
        if !problems.is_empty() {
            return json!({
                "ok": false,
                "error": "el borrador tiene problemas que hay que corregir antes de mostrarselo al usuario",
                "problems": problems.iter().map(|problem| json!({
                    "field": problem.field,
                    "detail": problem.detail,
                })).collect::<Vec<_>>()
            });
        }

        let missing = ctx.with_facts(|facts| unverified_facts(&parsed, facts));
        if !missing.is_empty() {
            // Se descuenta el intento: este rechazo es "todavia no", no "ya
            // gastaste tu propuesta".
            ctx.with_facts(|facts| facts.proposals = facts.proposals.saturating_sub(1));

            return json!({
                "ok": false,
                "error": "todavia no verificaste todo lo que el borrador da por hecho. \
                          Usá las herramientas indicadas y volvé a proponer.",
                "missing": missing
            });
        }

        json!({
            "ok": true,
            "accepted": true,
            "message": "Borrador aceptado. Contale al usuario en una frase que hace el boton \
                        y decile que lo revise en el editor."
        })
    }
}

/// Lo que el borrador afirma sin haberlo comprobado.
fn unverified_facts(draft: &ActionDraft, facts: &TurnFacts) -> Vec<Value> {
    let mut missing = Vec::new();

    for step in &draft.steps {
        // El portapapeles solo copia texto: no ejecuta ni abre carpetas, asi
        // que no hay nada que verificar.
        if step.action_type == DraftActionType::Clipboard {
            continue;
        }

        if let Some(directory) = step.working_directory.as_deref().filter(|d| !d.trim().is_empty())
        {
            if !facts.knows_path(directory) {
                missing.push(json!({
                    "what": "path",
                    "value": directory,
                    "how": format!(
                        "la carpeta '{directory}' no la confirmo ninguna herramienta. \
                         Llamá a find_project o list_directory para verificar que existe."
                    )
                }));
            }
        }

        for path in absolute_paths_in(&step.command) {
            if !facts.knows_path(&path) {
                missing.push(json!({
                    "what": "path",
                    "value": path,
                    "how": format!(
                        "la ruta '{path}' aparece en el comando pero no la devolvio ninguna herramienta. \
                         Confirmala con list_directory o preguntale al usuario."
                    )
                }));
            }
        }

        for program in programs_in(&step.command) {
            if !facts.verified_executables.contains(&program) {
                missing.push(json!({
                    "what": "executable",
                    "name": program,
                    "how": format!(
                        "llamá a which_executable con name=\"{program}\" antes de proponer un comando que lo use."
                    )
                }));
            }
        }

        if mentions_android_device(&step.command) && !facts.listed_android_devices {
            missing.push(json!({
                "what": "android_device",
                "how": "el comando apunta a un dispositivo Android. Llamá a list_android_devices \
                        para usar el serial real en vez de un placeholder."
            }));
        }
    }

    dedupe(missing)
}

fn dedupe(mut values: Vec<Value>) -> Vec<Value> {
    let mut seen: Vec<String> = Vec::new();
    values.retain(|value| {
        let key = value.to_string();
        if seen.contains(&key) {
            false
        } else {
            seen.push(key);
            true
        }
    });
    values
}

/// Extrae rutas absolutas de un comando.
///
/// Reconoce `C:\...`, `C:/...` y `/algo/...`. Deliberadamente no intenta
/// entender comillas ni escapes: el objetivo es detectar que el modelo escribio
/// una ruta, no parsear shell. Un falso positivo cuesta una ronda de
/// herramienta; un falso negativo deja pasar una ruta inventada.
pub fn absolute_paths_in(command: &str) -> Vec<String> {
    let mut paths = Vec::new();

    for raw in command.split(|c: char| c.is_whitespace() || matches!(c, '"' | '\'' | '=')) {
        let token = raw.trim_matches(|c| matches!(c, ',' | ';' | ')' | '(' ));
        if token.len() < 3 {
            continue;
        }

        let bytes = token.as_bytes();
        let is_windows_path = bytes[0].is_ascii_alphabetic()
            && bytes[1] == b':'
            && (bytes[2] == b'\\' || bytes[2] == b'/');
        // En POSIX se exige una barra mas: `/home/x` es una ruta, `/c` es casi
        // siempre una bandera.
        let is_posix_path = bytes[0] == b'/' && token[1..].contains('/');

        if is_windows_path || is_posix_path {
            // Una ruta con variables sin resolver no se puede verificar; la
            // valida el usuario al ejecutar.
            if token.contains("{{") {
                continue;
            }
            paths.push(token.to_string());
        }
    }

    paths
}

/// Extrae los nombres de programa que invoca un comando.
///
/// Se considera "programa" el primer token de cada segmento separado por `&&`,
/// `||`, `;`, `|` o salto de linea. Es una aproximacion: no entiende
/// subshells ni redirecciones complejas. Alcanza para el objetivo, que es
/// obligar a verificar `flutter`, `git`, `adb` y compania.
pub fn programs_in(command: &str) -> Vec<String> {
    let mut programs = Vec::new();

    for segment in command.split(|c| matches!(c, '\n' | '\r' | ';' | '|' | '&')) {
        let Some(first) = segment.split_whitespace().next() else {
            continue;
        };

        let trimmed = first.trim_matches(|c| matches!(c, '"' | '\'' | '(' | ')'));
        let cleaned = trimmed.to_lowercase();
        if cleaned.is_empty() || cleaned.contains("{{") {
            continue;
        }

        // Una ruta absoluta a un ejecutable ya se verifica por la via de las
        // rutas; no hace falta pedir tambien `which`.
        if cleaned.contains('/') || cleaned.contains('\\') {
            continue;
        }
        // Asignaciones de entorno (`VAR=valor cmd`) no son programas.
        if cleaned.contains('=') {
            continue;
        }
        // El nombre original (con mayusculas) hace falta para reconocer un
        // cmdlet de PowerShell (`Get-WmiObject`) por su forma Verbo-Sustantivo
        // — en minusculas la deteccion no serviria de nada.
        if SHELL_BUILTINS.contains(&cleaned.as_str())
            || crate::tools::looks_like_powershell_cmdlet(trimmed)
        {
            continue;
        }

        let name = cleaned.trim_end_matches(".exe").to_string();
        if !programs.contains(&name) {
            programs.push(name);
        }
    }

    programs
}

fn mentions_android_device(command: &str) -> bool {
    let lower = command.to_lowercase();
    lower.contains("adb ") || lower.contains(" -d ") || lower.contains("--device-id")
}

/// JSON Schema del borrador. Es lo unico que el modelo ve del formato, asi que
/// las descripciones estan escritas como instrucciones, no como documentacion.
fn schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "name": {
                "type": "string",
                "description": "Nombre corto del boton, maximo 60 caracteres. Ej: 'Analizar ExampleApp'"
            },
            "description": {
                "type": "string",
                "description": "Una linea explicando que hace"
            },
            "icon": {
                "type": "string",
                "enum": draft::ICONS,
                "description": "Icono del boton. Solo estos valores."
            },
            "color_hex": {
                "type": "string",
                "enum": draft::COLORS,
                "description": "Color del boton. Solo estos valores."
            },
            "summary": {
                "type": "string",
                "description": "Explicacion en espanol de POR QUE el comando quedo asi \
                                (que ruta usaste, que herramienta verificaste, que shell elegiste). \
                                El usuario lo lee para decidir si aprobarlo."
            },
            "steps": {
                "type": "array",
                "description": "Un solo paso = un boton simple. Varios pasos = una macro que los \
                                ejecuta en orden.",
                "items": {
                    "type": "object",
                    "properties": {
                        "name": { "type": "string", "description": "Nombre del paso, max 60 caracteres" },
                        "description": { "type": "string" },
                        "action_type": {
                            "type": "string",
                            "enum": ["terminal", "clipboard"],
                            "description": "'terminal' ejecuta un comando; 'clipboard' copia texto"
                        },
                        "command": {
                            "type": "string",
                            "description": "El comando a ejecutar (o el texto a copiar). \
                                            NO pongas 'cd' aca: para eso esta 'working_directory', \
                                            que NexoDeck resuelve con la sintaxis correcta de cada shell. \
                                            Puede usar {{variables}}, pero cada una tiene que estar \
                                            declarada en 'parameters'."
                        },
                        "terminal": {
                            "type": "string",
                            "enum": ["default_shell", "power_shell", "cmd", "bash"],
                            "description": "Shell a usar. Sacalo de list_shell_capabilities."
                        },
                        "requires_admin": {
                            "type": "boolean",
                            "description": "Solo si el comando realmente necesita elevacion. \
                                            Pedirla de mas hace que el usuario vea un UAC sin motivo."
                        },
                        "show_terminal_window": {
                            "type": "boolean",
                            "description": "true si el usuario tiene que VER la salida (por ejemplo \
                                            un informe de analisis); false si solo importa el efecto."
                        },
                        "working_directory": {
                            "type": "string",
                            "description": "Carpeta desde la que ejecutar. Ruta absoluta confirmada \
                                            con find_project o list_directory. Usa este campo en vez \
                                            de escribir 'cd' dentro del comando."
                        },
                        "delay_ms_after": {
                            "type": "integer",
                            "description": "Pausa en milisegundos antes del paso siguiente. Solo en macros."
                        },
                        "parameters": {
                            "type": "array",
                            "description": "Variables que se le preguntan al usuario al ejecutar. \
                                            Declara aca TODA {{variable}} que uses en el comando.",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "key": { "type": "string", "description": "Nombre sin llaves. Ej: rama" },
                                    "label": { "type": "string", "description": "Como se le pregunta al usuario" },
                                    "kind": { "type": "string", "enum": ["text", "number", "select"] },
                                    "default_value": { "type": "string" },
                                    "options": {
                                        "type": "array",
                                        "items": { "type": "string" },
                                        "description": "Obligatorio y con al menos 2 valores si kind es 'select'"
                                    }
                                },
                                "required": ["key", "label"]
                            }
                        },
                        "auto_subscribe": {
                            "type": "object",
                            "description": "SOLO si este paso ejecuta un comando que dispara un proceso \
                                            asincrono (un job) y el usuario ya te dijo la URL del hub al \
                                            que subscribirse — nunca inventes una URL. NexoDeck arranca la \
                                            suscripcion sola apenas el comando (capturado, \
                                            show_terminal_window=false) termina bien, leyendo este campo \
                                            de su salida JSON.",
                            "properties": {
                                "base_url": {
                                    "type": "string",
                                    "description": "URL base del hub, tal como la dijo el usuario"
                                },
                                "hub_path": { "type": "string", "description": "Ej: /jobsHub" },
                                "invoke_method": { "type": "string", "description": "Ej: SubscribeToJob" },
                                "json_field": {
                                    "type": "string",
                                    "description": "Campo de nivel superior de la salida JSON que trae \
                                                    el id (ej: job_id)"
                                },
                                "allow_invalid_cert": { "type": "boolean" }
                            },
                            "required": ["base_url", "hub_path", "invoke_method", "json_field"]
                        }
                    },
                    "required": ["name", "action_type", "command"]
                }
            }
        },
        "required": ["name", "icon", "color_hex", "summary", "steps"]
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};

    fn ctx() -> ToolContext {
        ToolContext::new(
            vec![PathBuf::from("E:/Proyectos")],
            nexodeck_hardware::HostOs::Windows,
        )
    }

    fn draft_json(command: &str, working_directory: Option<&str>) -> Value {
        json!({
            "name": "Analizar ExampleApp",
            "icon": "code",
            "color_hex": "#6366F1",
            "summary": "corre flutter analyze en el proyecto",
            "steps": [{
                "name": "Analizar",
                "action_type": "terminal",
                "command": command,
                "terminal": "power_shell",
                "show_terminal_window": true,
                "working_directory": working_directory,
            }]
        })
    }

    /// El comportamiento central: sin haber verificado nada, la propuesta se
    /// rechaza y se dice exactamente que herramienta usar.
    #[test]
    fn sin_verificar_nada_la_propuesta_se_rechaza_con_instrucciones() {
        let ctx = ctx();
        let result = ProposeAction.call(
            &draft_json("flutter analyze", Some("E:/Proyectos/ExampleApp")),
            &ctx,
        );

        assert_eq!(result["ok"], false);
        let missing = result["missing"].as_array().unwrap();

        assert!(
            missing.iter().any(|m| m["what"] == "path"),
            "tiene que reclamar la ruta sin confirmar"
        );
        assert!(
            missing
                .iter()
                .any(|m| m["what"] == "executable" && m["name"] == "flutter"),
            "tiene que reclamar el ejecutable sin verificar"
        );
        assert!(
            missing[0]["how"].as_str().unwrap().contains("llamá")
                || missing[0]["how"].as_str().unwrap().contains("Llamá")
                || missing[0]["how"].as_str().unwrap().contains("Confirmala"),
            "el mensaje tiene que decir COMO arreglarlo: {:?}",
            missing[0]["how"]
        );
    }

    /// Y con todo verificado, pasa. Es el mismo borrador que arriba.
    #[test]
    fn con_los_hechos_verificados_la_propuesta_se_acepta() {
        let ctx = ctx();
        ctx.with_facts(|facts| {
            facts.confirm_path(Path::new("E:/Proyectos/ExampleApp"));
            facts.verified_executables.insert("flutter".into());
        });

        let result = ProposeAction.call(
            &draft_json("flutter analyze", Some("E:/Proyectos/ExampleApp")),
            &ctx,
        );

        assert_eq!(result["ok"], true, "{result:?}");
        assert_eq!(result["accepted"], true);
    }

    /// El segundo caso del brief: `flutter run -d <serial>` exige haber
    /// consultado los dispositivos.
    #[test]
    fn un_comando_con_serial_de_android_exige_haber_listado_los_dispositivos() {
        let ctx = ctx();
        ctx.with_facts(|facts| {
            facts.confirm_path(Path::new("E:/Proyectos/ExampleApp"));
            facts.verified_executables.insert("flutter".into());
        });

        let result = ProposeAction.call(
            &draft_json(
                "flutter run -d R5CT30ABCDE --debug",
                Some("E:/Proyectos/ExampleApp"),
            ),
            &ctx,
        );

        assert_eq!(result["ok"], false);
        assert!(result["missing"]
            .as_array()
            .unwrap()
            .iter()
            .any(|m| m["what"] == "android_device"));
    }

    #[test]
    fn una_ruta_inventada_no_pasa_aunque_el_ejecutable_este_verificado() {
        let ctx = ctx();
        ctx.with_facts(|facts| {
            facts.confirm_path(Path::new("E:/Proyectos/ExampleApp"));
            facts.verified_executables.insert("code".into());
        });

        let result = ProposeAction.call(
            &draft_json(r"code E:\Proyectos\ProyectoQueNoExiste", None),
            &ctx,
        );

        assert_eq!(result["ok"], false);
        assert!(result["missing"]
            .as_array()
            .unwrap()
            .iter()
            .any(|m| m["what"] == "path"));
    }

    /// Un borrador estructuralmente roto se rechaza antes de mirar hechos, y
    /// devuelve los problemas concretos para que el modelo corrija.
    #[test]
    fn un_borrador_mal_formado_devuelve_los_problemas_de_validacion() {
        let ctx = ctx();
        let mut json = draft_json("echo hola", None);
        json["icon"] = json!("cohete");

        let result = ProposeAction.call(&json, &ctx);

        assert_eq!(result["ok"], false);
        assert!(result["problems"]
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["field"] == "icon"));
    }

    /// El portapapeles no ejecuta nada: exigirle verificaciones seria gastar
    /// rondas por nada.
    #[test]
    fn el_portapapeles_no_necesita_verificaciones() {
        let ctx = ctx();
        let result = ProposeAction.call(
            &json!({
                "name": "Copiar comando de build",
                "icon": "content_paste",
                "color_hex": "#22C55E",
                "summary": "copia el comando al portapapeles",
                "steps": [{
                    "name": "Copiar",
                    "action_type": "clipboard",
                    "command": "flutter build apk --release en E:/Proyectos/App"
                }]
            }),
            &ctx,
        );

        assert_eq!(result["ok"], true, "{result:?}");
    }

    #[test]
    fn solo_se_acepta_una_propuesta_por_turno() {
        let ctx = ctx();
        ctx.with_facts(|facts| {
            facts.confirm_path(Path::new("E:/Proyectos/ExampleApp"));
            facts.verified_executables.insert("flutter".into());
        });
        let payload = draft_json("flutter analyze", Some("E:/Proyectos/ExampleApp"));

        assert_eq!(ProposeAction.call(&payload, &ctx)["ok"], true);
        let second = ProposeAction.call(&payload, &ctx);
        assert_eq!(second["ok"], false);
        assert!(second["error"].as_str().unwrap().contains("ya emitiste"));
    }

    /// Un rechazo por hechos faltantes **no** puede consumir el unico intento:
    /// si no, el modelo corrige y se encuentra con "ya emitiste un borrador".
    #[test]
    fn un_rechazo_por_hechos_faltantes_no_gasta_el_intento() {
        let ctx = ctx();
        let payload = draft_json("flutter analyze", Some("E:/Proyectos/ExampleApp"));

        assert_eq!(ProposeAction.call(&payload, &ctx)["ok"], false);

        // El modelo corrige y verifica.
        ctx.with_facts(|facts| {
            facts.confirm_path(Path::new("E:/Proyectos/ExampleApp"));
            facts.verified_executables.insert("flutter".into());
        });

        assert_eq!(
            ProposeAction.call(&payload, &ctx)["ok"],
            true,
            "el reintento tiene que poder pasar"
        );
    }

    // ---- helpers de extraccion ----

    #[test]
    fn se_detectan_rutas_de_windows_y_posix() {
        assert_eq!(
            absolute_paths_in(r"code E:\Proyectos\App && cd C:/otra/cosa"),
            vec![r"E:\Proyectos\App", "C:/otra/cosa"]
        );
        assert_eq!(
            absolute_paths_in("code /home/user/app"),
            vec!["/home/user/app"]
        );
    }

    /// `-d`, `/c`, `/s` son banderas, no rutas. Confundirlas obligaria a
    /// verificar cosas que no existen.
    #[test]
    fn las_banderas_no_se_confunden_con_rutas() {
        assert!(absolute_paths_in("flutter run -d abc --debug").is_empty());
        assert!(absolute_paths_in("cmd /c echo hola").is_empty());
    }

    /// Una ruta con variable sin resolver no se puede verificar: la completa el
    /// usuario al ejecutar.
    #[test]
    fn una_ruta_con_variable_no_se_exige_verificada() {
        assert!(absolute_paths_in("code E:/Proyectos/{{proyecto}}").is_empty());
    }

    #[test]
    fn se_detecta_el_programa_de_cada_segmento() {
        assert_eq!(
            programs_in("git pull && flutter analyze"),
            vec!["git", "flutter"]
        );
        assert_eq!(programs_in("adb devices -l | findstr device"), vec!["adb", "findstr"]);
    }

    /// Exigir `which_executable` para `cd` o `echo` quemaria rondas sin
    /// aportar nada.
    #[test]
    fn los_builtins_de_shell_no_cuentan_como_programas() {
        assert!(programs_in("cd E:/x").is_empty());
        assert!(programs_in("echo hola && Set-Location E:/x").is_empty());
    }

    #[test]
    fn una_ruta_absoluta_a_un_ejecutable_no_pide_which() {
        assert!(programs_in(r"C:\Program Files\app\app.exe --run").is_empty());
    }

    #[test]
    fn el_esquema_expone_los_iconos_y_colores_validos() {
        let schema = schema();
        let icons = schema["properties"]["icon"]["enum"].as_array().unwrap();
        assert_eq!(icons.len(), draft::ICONS.len());
        assert!(icons.iter().any(|i| i == "terminal"));
    }

    #[test]
    fn el_esquema_del_paso_expone_auto_subscribe() {
        let schema = schema();
        let auto_subscribe =
            &schema["properties"]["steps"]["items"]["properties"]["auto_subscribe"];

        assert_eq!(auto_subscribe["type"], "object");
        let required = auto_subscribe["required"].as_array().unwrap();
        for field in ["base_url", "hub_path", "invoke_method", "json_field"] {
            assert!(
                required.iter().any(|r| r == field),
                "'{field}' tendria que ser obligatorio en auto_subscribe"
            );
        }
    }
}
