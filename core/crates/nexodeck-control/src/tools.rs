//! Las herramientas que Claude Code puede llamar.
//!
//! ## Un fallo de herramienta se devuelve como resultado, no como error
//!
//! Mismo criterio que `nexodeck-ai/src/tools/mod.rs`, y por el mismo motivo:
//! un error **como resultado** es una senal que el modelo sabe leer y con la
//! que corrige el rumbo; un error de protocolo lo descarrila. Aca eso significa
//! que un argumento que falta sale como `isError: true` con el texto que
//! explica que falta, no como un `-32602` de JSON-RPC.
//!
//! ## Las descripciones son parte del contrato
//!
//! Lo que diga cada `description` es literalmente lo unico que el modelo lee
//! antes de elegir. La de `notify` lleva el estilo de aviso que el usuario
//! pidio, porque si no lo dice ahi no lo dice nadie.

use std::sync::Arc;

use std::fmt::Write as _;

use nexodeck_docs::{
    redact, DigestStatus, DigestTrigger, FindingStatus, NewFinding, ProposalStatus,
    MAX_FINDINGS_PER_CALL,
};
use nexodeck_notify::{Notifier, NotifyLevel, NotifyRequest};
use serde_json::{json, Value};

use crate::ControlState;

/// Cuantas lineas devuelve `tail_run` si no se pide otra cosa.
const DEFAULT_TAIL_LINES: usize = 50;
const MAX_TAIL_LINES: usize = 500;
const DEFAULT_RUN_LIMIT: usize = 20;

pub(crate) struct ToolOutcome {
    pub text: String,
    pub is_error: bool,
    /// Una linea para el panel de la UI. El usuario tiene que poder ver que le
    /// pidieron a su maquina sin leer el JSON entero.
    pub summary: String,
}

impl ToolOutcome {
    fn ok(summary: impl Into<String>, text: impl Into<String>) -> Self {
        ToolOutcome {
            text: text.into(),
            is_error: false,
            summary: summary.into(),
        }
    }

    fn err(summary: impl Into<String>, text: impl Into<String>) -> Self {
        ToolOutcome {
            text: text.into(),
            is_error: true,
            summary: summary.into(),
        }
    }
}

pub(crate) fn definitions() -> Vec<Value> {
    vec![
        json!({
            "name": "notify",
            "title": "Avisar al usuario",
            "description": "Manda un aviso al usuario por los canales que tenga configurados en \
                NexoDeck, tipicamente WhatsApp. Sirve para tareas largas en las que el usuario no \
                esta delante de la pantalla.\n\n\
                ESTILO: pocos, concisos y cortos. Solo hitos que importen y errores. No narres el \
                progreso rutinario ni mandes un aviso por cada paso.\n\n\
                Usa level='always' solo para lo que el usuario tiene que saber si o si (algo se \
                rompio, el disco se llena, un proceso murio); ese nivel no lo filtra ningun canal. \
                Todo lo demas va en 'milestone'.\n\n\
                Con dry_run=true compone el mensaje y te dice por donde saldria, sin mandar nada: \
                usalo para comprobar un canal recien configurado.\n\n\
                El resultado dice por cada canal si se entrego DE VERDAD. Si sale NO ENTREGADO, el \
                usuario no recibio nada: no des el aviso por hecho.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "text": {
                        "type": "string",
                        "description": "El texto del aviso. Corto y concreto."
                    },
                    "level": {
                        "type": "string",
                        "enum": ["milestone", "always"],
                        "description": "'milestone' para un hito normal, 'always' para lo critico."
                    },
                    "dry_run": {
                        "type": "boolean",
                        "description": "Componer y explicar sin mandar nada."
                    }
                },
                "required": ["text"]
            }
        }),
        json!({
            "name": "reply",
            "title": "Contestar a NexoDeck",
            "description": "Contesta a una pregunta que NexoDeck te hizo. El message_id es el numero que venia al \
                principio de la linea que te llego por el vigilante.\n\n\
                La respuesta aparece en el chat de NexoDeck, en el turno de esa pregunta. Escribe para una \
                persona que esta mirando ese chat, no un informe: lo que hiciste, lo que encontraste, y si \
                hay algo que decidir. Si te pidieron un script o un comando, incluilo entero en la \
                respuesta.\n\n\
                Si el message_id no existe o esa pregunta ya vencio, te lo dira: no lo reintentes con otro \
                numero inventado.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "message_id": {
                        "type": "integer",
                        "description": "El numero que venia en la linea de la pregunta."
                    },
                    "text": {
                        "type": "string",
                        "description": "La respuesta."
                    }
                },
                "required": ["message_id", "text"]
            }
        }),
        json!({
            "name": "post_message",
            "title": "Escribirle a NexoDeck",
            "description": "Dile algo a NexoDeck sin que te lo hayan preguntado. Aparece en el chat, como un mensaje \
                suelto.\n\n\
                Sirve para reportar sobre la marcha: que terminaste algo largo, que encontraste un \
                problema, que necesitas una decision. NO es para avisar al usuario cuando esta lejos del \
                ordenador: para eso esta 'notify', que le llega al telefono. Esto solo aparece en la \
                pantalla de NexoDeck.\n\n\
                IMPORTANTE si hay varias terminales abiertas: pasa en 'from' el nombre de tu sesion, el \
                que te dijo el vigilante al arrancar (algo como 'NexoDeck en main'). NexoDeck no puede \
                saberlo por su cuenta -- todas las sesiones le hablan con el mismo token -- y sin eso el \
                mensaje llega sin firma y el usuario no sabe cual de sus terminales le escribio.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "text": { "type": "string", "description": "El mensaje." },
                    "from": {
                        "type": "string",
                        "description": "El nombre de tu sesion, si hay varias abiertas."
                    }
                },
                "required": ["text"]
            }
        }),
        json!({
            "name": "list_runs",
            "title": "Listar ejecuciones",
            "description": "Las ejecuciones de comandos que NexoDeck recuerda, de la mas reciente \
                a la mas vieja, con su estado y cuanto llevan. Son las que se lanzaron desde el \
                deck en modo capturado; un proceso que arranco por fuera de NexoDeck no aparece.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "only_running": {
                        "type": "boolean",
                        "description": "Dejar fuera las que ya terminaron."
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Cuantas devolver como mucho."
                    }
                }
            }
        }),
        json!({
            "name": "tail_run",
            "title": "Ver la salida de una ejecucion",
            "description": "Las ultimas lineas de salida de una ejecucion, por su run_id (sacalo \
                de list_runs). Funciona tambien con ejecuciones ya terminadas, mientras NexoDeck \
                las siga recordando.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "run_id": {
                        "type": "string",
                        "description": "El id que devolvio list_runs."
                    },
                    "lines": {
                        "type": "integer",
                        "description": "Cuantas lineas del final. Por defecto 50."
                    }
                },
                "required": ["run_id"]
            }
        }),
        json!({
            "name": "submit_findings",
            "title": "Mandar hallazgos al buzon de documentacion",
            "description": "Manda hallazgos al buzon de documentacion de NexoDeck. NexoDeck prepara una \
                propuesta de cambios a los documentos del proyecto y EL USUARIO LA APRUEBA EN NEXODECK: \
                tu NO edites esos documentos por estos hallazgos. Llama antes a list_doc_projects para \
                saber que proyectos y documentos hay.\n\n\
                Un hallazgo es UNA afirmacion: lo que se midio, se decidio, se rompio o cambio, y por que. \
                Parte en varios lo que sean varias cosas.\n\n\
                EVIDENCIA, obligatoria en cada hallazgo:\n\
                - label 'M' (medido) exige 'source' concreto: ruta:linea, hash de commit, el comando y \
                su salida, o el log. Si no lo puedes citar, no es medido.\n\
                - label 'S' (supuesto) para lo que se infiere o se espera.\n\n\
                Si algo que dicen hoy los documentos deja de ser cierto, ponlo literal en 'supersedes'.\n\n\
                Pasa en 'from' el nombre de tu sesion. Un reenvio identico en 24 h no se duplica.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "project": {
                        "type": "string",
                        "description": "El id del proyecto, sacado de list_doc_projects."
                    },
                    "from": {
                        "type": "string",
                        "description": "El nombre de tu sesion."
                    },
                    "findings": {
                        "type": "array",
                        "minItems": 1,
                        "maxItems": MAX_FINDINGS_PER_CALL,
                        "items": {
                            "type": "object",
                            "properties": {
                                "kind": {
                                    "type": "string",
                                    "enum": ["measurement", "decision", "bug", "change", "correction", "open_question"]
                                },
                                "title": { "type": "string", "description": "La conclusion en una linea (hasta 120 caracteres)." },
                                "body": { "type": "string", "description": "El detalle y el porque (hasta 4000 caracteres)." },
                                "evidence": {
                                    "type": "array",
                                    "minItems": 1,
                                    "items": {
                                        "type": "object",
                                        "properties": {
                                            "label": { "type": "string", "enum": ["M", "S"] },
                                            "text": { "type": "string" },
                                            "source": { "type": "string", "description": "Obligatorio con label M." }
                                        },
                                        "required": ["label", "text"]
                                    }
                                },
                                "supersedes": { "type": "string", "description": "Cita literal de lo que deja de ser cierto." },
                                "date": { "type": "string", "description": "YYYY-MM-DD, si no es de hoy." },
                                "target_hint": { "type": "string", "enum": ["journal", "plan", "index"] }
                            },
                            "required": ["kind", "title", "body", "evidence"]
                        }
                    }
                },
                "required": ["project", "findings"]
            }
        }),
        json!({
            "name": "list_doc_projects",
            "title": "Proyectos del buzon de documentacion",
            "description": "Los proyectos cuya documentacion alimenta NexoDeck, con sus documentos, que \
                responde cada uno, si el procesado esta encendido y cuantos hallazgos hay en cada estado.",
            "inputSchema": { "type": "object", "properties": {} }
        }),
        json!({
            "name": "finding_status",
            "title": "Estado de hallazgos enviados",
            "description": "En que estado estan hallazgos que mandaste: en cola, con propuesta esperando \
                al usuario, aplicados, rechazados o fallidos (con el motivo). Pasa 'ids', 'batch_id' o \
                'project'. No lo consultes en bucle: preguntalo al terminar tu tarea o cuando el usuario \
                lo pida, porque la propuesta la aprueba una persona.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "ids": { "type": "array", "items": { "type": "string" } },
                    "batch_id": { "type": "string" },
                    "project": { "type": "string" }
                }
            }
        }),
        json!({
            "name": "search_notes",
            "title": "Buscar en las notas de trabajo",
            "description": "Busca en la boveda de notas de trabajo del usuario, y en los hallazgos y commits \
                que NexoDeck cruza con ella. Devuelve fragmentos con su id, titulo, fecha y la ruta de la nota. \
                Usalo antes de ponerte con algo para ver si ya se hablo, se decidio o quedo pendiente. Las notas \
                privadas y las marcadas `ai: false` no aparecen nunca.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Palabras concretas: modulo, tanda, error, cliente. No frases genericas."
                    },
                    "limit": { "type": "integer", "minimum": 1, "maximum": 50 }
                },
                "required": ["query"]
            }
        }),
        json!({
            "name": "get_note",
            "title": "Leer una nota de trabajo",
            "description": "El texto de una nota de la boveda (la ruta tal como la devuelve search_notes), con \
                las notas que enlazan a ella, las mas parecidas y su ultimo digest. Solo lectura: una nota no se \
                edita desde aqui; para completarla, pide un digest con digest_note y el usuario aprobara la \
                propuesta. No devuelve notas con `ai: false`.",
            "inputSchema": {
                "type": "object",
                "properties": { "path": { "type": "string" } },
                "required": ["path"]
            }
        }),
        json!({
            "name": "digest_note",
            "title": "Procesar una nota con el asistente",
            "description": "Manda procesar una nota con el asistente de notas de NexoDeck: varios agentes la \
                relacionan con notas anteriores, hallazgos y commits, y NexoDeck prepara una propuesta \
                (resumen, relacionados, tareas y preguntas abiertas) que el usuario aprueba en la app. Solo \
                encola: no esperes el resultado ni lo consultes en bucle, y no edites la nota a mano por esto.",
            "inputSchema": {
                "type": "object",
                "properties": { "path": { "type": "string" } },
                "required": ["path"]
            }
        }),
        json!({
            "name": "save_note",
            "title": "Guardar una nota en NexoDeck",
            "description": "Guarda un texto TUYO como nota en la boveda del usuario, al momento. Usala cuando \
                el usuario diga 'esto mandalo a NexoDeck', 'guarda este resumen en mis notas' o similar: \
                es EL quien decide que se guarda, no tu por tu cuenta.\n\n\
                Con 'group' la nota nace dentro de esa agrupacion (se crea si no existe); sin 'group' ni \
                'path' va a 'inbox/', con la fecha y un nombre sacado del titulo. Si el usuario no dijo \
                agrupacion, NO la inventes: la bandeja es justo para eso. \
                Con 'path' de una nota que ya existe, se AÑADE al final como una seccion con su hora: \
                nunca se pisa lo que hubiera.\n\n\
                Manda markdown normal y corriente, sin envolverlo en una cerca de codigo y sin \
                frontmatter: NexoDeck normaliza el formato y pone el suyo (el frontmatter que mandes se \
                descarta). El texto entra tal cual lo escribiste, sin que ningun modelo lo reinterprete.\n\n\
                NO es para documentar un proyecto: para eso esta 'submit_findings', que prepara una \
                propuesta y la aprueba el usuario. Esto es la libreta del usuario.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "text": {
                        "type": "string",
                        "description": "El contenido de la nota, en markdown. Lo que el usuario te pidio guardar."
                    },
                    "title": {
                        "type": "string",
                        "description": "Titulo de la nota. Si no lo pasas se usa el '# ' que encabece el texto, o su primera linea."
                    },
                    "path": {
                        "type": "string",
                        "description": "Ruta dentro de la boveda ('temas/malla.md'). Solo si el usuario dijo donde; si ya existe, se añade al final."
                    },
                    "group": {
                        "type": "string",
                        "description": "Agrupacion donde guardarla ('ODM', 'Trabajo de campo'). Solo si el usuario la nombro. Usa list_note_groups para ver las que hay."
                    },
                    "from": {
                        "type": "string",
                        "description": "Tu sesion, como en submit_findings ('NexoDeck en feat/note-editor'). Queda en la nota para saber de donde salio."
                    }
                },
                "required": ["text"]
            }
        }),
        json!({
            "name": "list_note_groups",
            "title": "Agrupaciones de notas",
            "description": "Las agrupaciones de la boveda de notas del usuario, con su nombre, color y cuantas \
                notas tiene cada una. Cada agrupacion es una carpeta de la boveda. Las notas que no estan en \
                ninguna agrupacion viven en 'inbox/'. Consultala antes de guardar o mover una nota en un grupo \
                para usar el nombre que ya existe en vez de crear uno parecido. Tambien lista las carpetas de \
                notas: ademas de la boveda, el usuario puede tener 'notas locales', carpetas suyas que NexoDeck \
                lee en su sitio sin copiarlas; sus notas se nombran '@<carpeta>/<ruta>' y sus agrupaciones \
                '@<carpeta>/<nombre>'.",
            "inputSchema": { "type": "object", "properties": {} }
        }),
        json!({
            "name": "create_note_group",
            "title": "Crear una agrupacion de notas",
            "description": "Crea una agrupacion en la boveda del usuario (una carpeta), con un nombre y un color \
                de identificacion. Si ya existe, le actualiza el nombre o el color que pases, sin duplicarla. \
                Solo cuando el usuario lo pida: no crees agrupaciones por tu cuenta para ordenar sus notas.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "description": "Nombre visible ('Tandas de ODM'). La carpeta se deriva de el, sin tildes."
                    },
                    "color": {
                        "type": "string",
                        "description": "Color #RRGGBB, sutil. Opcional: sin el se usa uno neutro. Por ejemplo #6366F1, #10B981, #F59E0B, #EF4444, #3B82F6, #EC4899."
                    },
                    "folder": {
                        "type": "string",
                        "description": "Id de la carpeta de notas local donde crearla (lo da list_note_groups). Ausente: la boveda principal."
                    }
                },
                "required": ["name"]
            }
        }),
        json!({
            "name": "move_note_to_group",
            "title": "Mover una nota a una agrupacion",
            "description": "Mueve una nota del usuario a otra agrupacion, o la devuelve a 'inbox/' si no pasas \
                'group'. Como cada agrupacion es una carpeta, esto MUEVE EL FICHERO, pero NexoDeck reescribe \
                los [[enlaces]] de otras notas que la citaban por ruta y conserva su historial. Nunca pisa \
                una nota con el mismo nombre. Se niega si la nota tiene una propuesta esperando en el buzon. \
                Solo cuando el usuario lo pida.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Ruta de la nota ('inbox/2026-09-16-resumen.md', o '@apuntes/clientes/acme.md' si es de una carpeta local)."
                    },
                    "group": {
                        "type": "string",
                        "description": "Agrupacion de destino, dentro de la carpeta de destino. Vacio o ausente: vuelve a 'inbox/'."
                    },
                    "folder": {
                        "type": "string",
                        "description": "Id de la carpeta de notas de destino, si es OTRA carpeta (lo da list_note_groups). Ausente: la misma carpeta de la nota. Entre carpetas el fichero se copia, se verifica y solo entonces se borra el original."
                    }
                },
                "required": ["path"]
            }
        }),
    ]
}

/// `None` si la herramienta no existe: eso si es un error de protocolo y lo
/// traduce quien llama.
pub(crate) async fn call(
    state: &Arc<ControlState>,
    name: &str,
    args: &Value,
) -> Option<ToolOutcome> {
    match name {
        "notify" => Some(notify(state, args).await),
        "reply" => Some(reply(state, args)),
        "post_message" => Some(post_message(state, args)),
        "list_runs" => Some(list_runs(args)),
        "tail_run" => Some(tail_run(args)),
        "submit_findings" => Some(submit_findings(state, args)),
        "list_doc_projects" => Some(list_doc_projects(state)),
        "finding_status" => Some(finding_status(state, args)),
        "search_notes" => Some(search_notes(state, args)),
        "get_note" => Some(get_note(state, args)),
        "digest_note" => Some(digest_note(state, args)),
        "save_note" => Some(save_note(state, args)),
        "list_note_groups" => Some(list_note_groups(state)),
        "create_note_group" => Some(create_note_group(state, args)),
        "move_note_to_group" => Some(move_note_to_group(state, args)),
        _ => None,
    }
}

async fn notify(state: &Arc<ControlState>, args: &Value) -> ToolOutcome {
    let Some(text) = arg_str(args, "text") else {
        return ToolOutcome::err("notify sin texto", "Falta el argumento obligatorio 'text'.");
    };
    if text.trim().is_empty() {
        return ToolOutcome::err("notify sin texto", "El argumento 'text' esta vacio.");
    }

    let level = match arg_str(args, "level").as_deref() {
        None | Some("milestone") => NotifyLevel::Milestone,
        Some("always") => NotifyLevel::Always,
        Some(other) => {
            return ToolOutcome::err(
                "notify con nivel invalido",
                format!("'level' tiene que ser 'milestone' o 'always', no '{other}'."),
            )
        }
    };
    let dry_run = arg_bool(args, "dry_run").unwrap_or(false);

    let channels = state.channels();
    if channels.is_empty() {
        // Es un fallo, y ruidoso. Un aviso que no tiene por donde salir es
        // exactamente lo que este proyecto viene a eliminar.
        return ToolOutcome::err(
            "notify sin canales",
            "NexoDeck no tiene ningun canal de aviso configurado, asi que el aviso NO se mando. \
             Configuralo en el panel de control de NexoDeck.",
        );
    }

    let outcomes = Notifier::new(channels)
        .send(&NotifyRequest {
            text: text.clone(),
            level,
            dry_run,
        })
        .await;

    let failures = outcomes.iter().filter(|o| o.is_failure()).count();
    let delivered = outcomes.iter().filter(|o| o.delivered).count();

    let mut lines = Vec::with_capacity(outcomes.len());
    for outcome in &outcomes {
        let line = if outcome.dry_run {
            format!("{}: ensayo en seco, se ejecutaria  {}", outcome.channel_id, outcome.detail)
        } else if outcome.skipped {
            format!("{}: saltado ({})", outcome.channel_id, outcome.detail)
        } else if outcome.delivered {
            format!(
                "{}: entregado en {}",
                outcome.channel_id,
                format_elapsed(outcome.elapsed_ms)
            )
        } else {
            format!("{}: NO ENTREGADO. {}", outcome.channel_id, outcome.detail)
        };
        lines.push(line);
    }

    let summary = if dry_run {
        format!("notify (en seco): {text}")
    } else if failures > 0 {
        format!("notify FALLIDO: {text}")
    } else {
        format!("notify: {text}")
    };

    // Un ensayo en seco no entrego nada y eso no es un fallo. Fuera del ensayo,
    // que ningun canal haya entregado si lo es.
    if !dry_run && delivered == 0 {
        return ToolOutcome::err(summary, lines.join("\n"));
    }
    if failures > 0 {
        return ToolOutcome::err(summary, lines.join("\n"));
    }
    ToolOutcome::ok(summary, lines.join("\n"))
}

fn reply(state: &Arc<ControlState>, args: &Value) -> ToolOutcome {
    let Some(message_id) = args.get("message_id").and_then(|v| v.as_u64()) else {
        return ToolOutcome::err(
            "reply sin message_id",
            "Falta el argumento obligatorio 'message_id'. Es el numero que venia al principio de la \
            linea de la pregunta.",
        );
    };
    let Some(text) = arg_str(args, "text") else {
        return ToolOutcome::err("reply sin texto", "Falta el argumento obligatorio 'text'.");
    };

    if state.outbox().reply(message_id, text.clone()) {
        ToolOutcome::ok(
            format!("respuesta a #{message_id}"),
            "Entregada. Ya aparece en el chat de NexoDeck.",
        )
    } else {
        // Se dicen las dos posibilidades en vez de afirmar una: desde aqui no
        // se pueden distinguir, y adivinar mandaria a buscar al sitio
        // equivocado.
        ToolOutcome::err(
            format!("respuesta a #{message_id} sin destino"),
            format!(
                "No hay ninguna pregunta abierta con el id {message_id}. O ya la contestaste, o vencio \
                por haber tardado demasiado, o ese mensaje no esperaba respuesta. No lo reintentes con \
                otro numero: si tienes algo que decir, usa post_message."
            ),
        )
    }
}

fn post_message(state: &Arc<ControlState>, args: &Value) -> ToolOutcome {
    let Some(text) = arg_str(args, "text") else {
        return ToolOutcome::err(
            "post_message sin texto",
            "Falta el argumento obligatorio 'text'.",
        );
    };
    if text.trim().is_empty() {
        return ToolOutcome::err(
            "post_message sin texto",
            "El argumento 'text' esta vacio.",
        );
    }

    // `from` es **cooperativo**: la sesion lo pasa si sus instrucciones se lo
    // dicen, y puede faltar. No se puede exigir porque todas las terminales
    // hablan con el mismo token y el servidor no las distingue; rechazar el
    // mensaje por venir sin firma seria perder lo que la sesion queria decir.
    let from = arg_str(args, "from").filter(|f| !f.trim().is_empty());

    state.outbox().post(text.clone(), from.clone());
    let quien = from.as_deref().unwrap_or("sin firma");
    ToolOutcome::ok(
        format!("mensaje de {quien}: {}", first_line(&text)),
        "Publicado en el chat de NexoDeck.",
    )
}

/// Para el resumen del panel: un mensaje de diez lineas no cabe en una fila.
fn first_line(text: &str) -> String {
    let line = text.lines().next().unwrap_or("").trim();
    if line.chars().count() > 80 {
        format!("{}...", line.chars().take(77).collect::<String>())
    } else {
        line.to_string()
    }
}

fn list_runs(args: &Value) -> ToolOutcome {
    let only_running = arg_bool(args, "only_running").unwrap_or(false);
    let limit = arg_usize(args, "limit").unwrap_or(DEFAULT_RUN_LIMIT).clamp(1, 200);

    let runs: Vec<_> = nexodeck_actions::runner()
        .list()
        .into_iter()
        .filter(|run| !only_running || run.is_running())
        .take(limit)
        .collect();

    if runs.is_empty() {
        let text = if only_running {
            "No hay ninguna ejecucion en curso."
        } else {
            "NexoDeck no recuerda ninguna ejecucion."
        };
        return ToolOutcome::ok("list_runs: ninguna", text);
    }

    let lines: Vec<String> = runs
        .iter()
        .map(|run| {
            let state = match run.status {
                None => format!("corriendo {}", format_elapsed(run.elapsed_ms)),
                Some(nexodeck_actions::RunStatus::Succeeded) => {
                    format!("ok en {}", format_elapsed(run.elapsed_ms))
                }
                Some(nexodeck_actions::RunStatus::Failed) => format!(
                    "FALLO codigo {} en {}",
                    run.exit_code
                        .map(|c| c.to_string())
                        .unwrap_or_else(|| "desconocido".into()),
                    format_elapsed(run.elapsed_ms)
                ),
                Some(nexodeck_actions::RunStatus::Cancelled) => {
                    format!("cancelada tras {}", format_elapsed(run.elapsed_ms))
                }
                Some(nexodeck_actions::RunStatus::Detached) => {
                    format!("lanzada, sin seguir, tras {}", format_elapsed(run.elapsed_ms))
                }
            };
            format!("{}  [{}]  {} — {}", run.run_id, state, run.label, run.command)
        })
        .collect();

    let running = runs.iter().filter(|r| r.is_running()).count();
    ToolOutcome::ok(
        format!("list_runs: {} en curso de {}", running, runs.len()),
        lines.join("\n"),
    )
}

fn tail_run(args: &Value) -> ToolOutcome {
    let Some(run_id) = arg_str(args, "run_id") else {
        return ToolOutcome::err(
            "tail_run sin id",
            "Falta el argumento obligatorio 'run_id'. Sacalo de list_runs.",
        );
    };
    let lines = arg_usize(args, "lines")
        .unwrap_or(DEFAULT_TAIL_LINES)
        .clamp(1, MAX_TAIL_LINES);

    let output = nexodeck_actions::runner().output(&run_id);
    if output.is_empty() {
        // No se puede distinguir "no existe" de "existe y no dijo nada", asi
        // que se dicen las dos posibilidades en vez de afirmar una.
        return ToolOutcome::ok(
            format!("tail_run {run_id}: sin salida"),
            format!(
                "Sin salida para '{run_id}'. O la ejecucion todavia no imprimio nada, o ese id no \
                 existe: comprobalo con list_runs."
            ),
        );
    }

    let start = output.len().saturating_sub(lines);
    let shown = &output[start..];
    let mut text = String::new();
    if start > 0 {
        text.push_str(&format!("[se omiten {start} lineas anteriores]\n"));
    }
    text.push_str(&shown.join("\n"));

    ToolOutcome::ok(
        format!("tail_run {run_id}: {} lineas", shown.len()),
        text,
    )
}

// ---------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------

/// Duracion legible **con escalon de horas**.
///
/// No es cosmetico: una cadena de ODM corre tres o cuatro horas, y sin el
/// escalon se leeria como un numero de minutos de cuatro cifras que hay que
/// dividir mentalmente. Mismo motivo que `formatRunElapsed` del lado Dart.
fn docs_not_ready(tool: &str) -> ToolOutcome {
    ToolOutcome::err(
        format!("{tool}: buzon no inicializado"),
        "El buzon de documentacion no esta inicializado en NexoDeck. Dile al usuario que abra NexoDeck; \
        los hallazgos no se han guardado.",
    )
}

fn submit_findings(state: &Arc<ControlState>, args: &Value) -> ToolOutcome {
    let Some(docs) = state.docs() else {
        return docs_not_ready("submit_findings");
    };
    let Some(project) = arg_str(args, "project").filter(|p| !p.trim().is_empty()) else {
        return ToolOutcome::err(
            "submit_findings sin proyecto",
            "Falta 'project'. Usa list_doc_projects para ver los validos.",
        );
    };
    let Some(raw) = args.get("findings") else {
        return ToolOutcome::err("submit_findings sin hallazgos", "Falta 'findings'.");
    };
    // El error de serde dice exactamente que campo sobra o falta ("unknown
    // variant `medida`, expected one of..."), que es lo que el modelo necesita.
    let items: Vec<NewFinding> = match serde_json::from_value(raw.clone()) {
        Ok(items) => items,
        Err(e) => {
            return ToolOutcome::err(
                "submit_findings con formato invalido",
                format!("'findings' no tiene la forma esperada: {e}"),
            )
        }
    };
    let project = project.trim().to_string();
    let received = items.len();

    match docs.submit(&project, arg_str(args, "from"), items, jiff::Timestamp::now()) {
        Ok(outcome) => {
            let new = received - outcome.duplicates.len();
            let mut text = format!(
                "Guardados en el buzon de '{project}' (lote {}):\n",
                outcome.batch_id
            );
            for id in &outcome.ids {
                let note = if outcome.duplicates.contains(id) {
                    "ya estaba; no se duplico"
                } else {
                    "en cola"
                };
                let _ = writeln!(text, "- {id} ({note})");
            }
            text.push_str(
                "\nNexoDeck preparara una propuesta y el usuario la aprobara en NexoDeck. No edites esos \
                documentos por estos hallazgos.",
            );
            if docs.inbox().config().is_ok_and(|c| !c.worker_enabled) {
                text.push_str(
                    "\n\nOJO: el procesado esta APAGADO en NexoDeck, asi que quedan guardados sin procesar. \
                    Diselo al usuario: se enciende en \"Buzon de documentacion\".",
                );
            }
            ToolOutcome::ok(
                format!("hallazgos para {project}: {received} ({new} nuevos)"),
                text,
            )
        }
        Err(e) => ToolOutcome::err(
            format!("hallazgos rechazados: {}", first_line(&e.to_string())),
            e.to_string(),
        ),
    }
}

fn list_doc_projects(state: &Arc<ControlState>) -> ToolOutcome {
    let Some(docs) = state.docs() else {
        return docs_not_ready("list_doc_projects");
    };
    let snapshot = match docs.snapshot() {
        Ok(snapshot) => snapshot,
        Err(e) => return ToolOutcome::err("no se pudo leer el buzon", e.to_string()),
    };
    let config = &snapshot.config;
    if config.projects.is_empty() {
        return ToolOutcome::ok(
            "proyectos: ninguno",
            "NexoDeck no tiene proyectos de documentacion configurados todavia. No mandes hallazgos: \
            diselo al usuario.",
        );
    }

    let mut text = String::new();
    let _ = writeln!(
        text,
        "Procesado: {}",
        if config.worker_enabled { "encendido" } else { "APAGADO (los hallazgos se guardan pero no se procesan)" }
    );
    match &config.remote {
        Some(remote) => {
            let _ = writeln!(text, "Modelo remoto: {} ({})", remote.model, remote.provider_id);
        }
        None => text.push_str("Modelo remoto: ninguno configurado\n"),
    }

    for project in &config.projects {
        let mine: Vec<_> = snapshot.findings.iter().filter(|f| f.project == project.id).collect();
        let count = |pred: &dyn Fn(&FindingStatus) -> bool| mine.iter().filter(|f| pred(&f.status)).count();
        let queued = count(&|s| matches!(s, FindingStatus::Queued | FindingStatus::Proposing));
        let waiting = count(&|s| matches!(s, FindingStatus::WaitingModel { .. }));
        let failed = count(&|s| matches!(s, FindingStatus::Failed { .. }));
        let pending = snapshot
            .proposals
            .iter()
            .filter(|p| p.project == project.id && p.is_pending())
            .count();

        let _ = writeln!(text, "\n{} - {}", project.id, project.name);
        let _ = writeln!(text, "  repositorio: {}", project.repo_root);
        for doc in &project.documents {
            let _ = writeln!(text, "  - {} ({}): {}", doc.path, doc.role.as_str(), doc.answers);
        }
        let _ = writeln!(
            text,
            "  hallazgos: {queued} en cola, {waiting} esperando modelo, {failed} fallidos; {pending} propuestas esperando al usuario"
        );
    }

    ToolOutcome::ok(
        format!("proyectos: {}", config.project_ids().join(", ")),
        text,
    )
}

fn finding_status(state: &Arc<ControlState>, args: &Value) -> ToolOutcome {
    let Some(docs) = state.docs() else {
        return docs_not_ready("finding_status");
    };
    let ids: Option<Vec<String>> = args.get("ids").and_then(|v| v.as_array()).map(|list| {
        list.iter()
            .filter_map(|v| v.as_str().map(str::to_string))
            .collect()
    });
    let batch = arg_str(args, "batch_id");
    let project = arg_str(args, "project");
    if ids.is_none() && batch.is_none() && project.is_none() {
        return ToolOutcome::err(
            "finding_status sin filtro",
            "Pasa 'ids', 'batch_id' o 'project'.",
        );
    }

    let snapshot = match docs.snapshot() {
        Ok(snapshot) => snapshot,
        Err(e) => return ToolOutcome::err("no se pudo leer el buzon", e.to_string()),
    };

    let matching: Vec<_> = snapshot
        .findings
        .iter()
        .filter(|f| ids.as_ref().is_none_or(|ids| ids.contains(&f.id)))
        .filter(|f| batch.as_ref().is_none_or(|b| &f.batch_id == b))
        .filter(|f| project.as_ref().is_none_or(|p| &f.project == p))
        .rev()
        .take(50)
        .collect();

    if matching.is_empty() {
        return ToolOutcome::ok("estado: nada", "No hay hallazgos que coincidan.");
    }

    let proposal_state = |id: &str| {
        snapshot
            .proposals
            .iter()
            .find(|p| p.id == id)
            .map(|p| match &p.status {
                ProposalStatus::NeedsReview { .. } => " (los documentos cambiaron; el usuario tiene que revisarla otra vez)",
                ProposalStatus::Stale { .. } => " (ya no aplica; hay que regenerarla)",
                _ => "",
            })
            .unwrap_or("")
    };

    let mut text = String::new();
    for finding in matching.iter().rev() {
        let status = match &finding.status {
            FindingStatus::Queued => "en cola".to_string(),
            FindingStatus::Proposing => "preparando la propuesta".to_string(),
            FindingStatus::Proposed { proposal_id } => format!(
                "propuesta {proposal_id} esperando al usuario{}",
                proposal_state(proposal_id)
            ),
            FindingStatus::Applied { proposal_id } => {
                format!("aplicado en los documentos (propuesta {proposal_id})")
            }
            FindingStatus::Rejected { note, .. } => match note {
                Some(note) => format!("rechazado por el usuario: {note}"),
                None => "rechazado por el usuario".to_string(),
            },
            FindingStatus::Failed { reason } => format!("fallo: {reason}"),
            FindingStatus::WaitingModel { reason, retry_at, .. } => match retry_at {
                Some(at) => format!("esperando modelo ({reason}); se reintenta a las {at}"),
                None => format!("esperando modelo ({reason})"),
            },
        };
        let _ = writeln!(
            text,
            "- {} · {} · {status}",
            finding.id,
            first_line(&finding.content.title)
        );
    }

    ToolOutcome::ok(format!("estado de {} hallazgos", matching.len()), text)
}

/// Guarda en la boveda algo que el usuario pidio guardar.
///
/// **Escribe directo, sin pasar por el buzon**, y es la unica herramienta que lo
/// hace. La diferencia con `submit_findings` no es tecnica sino de quien decide:
/// alli un modelo propone cambios a la documentacion de un proyecto y el usuario
/// los aprueba; aqui el usuario ya dijo "guarda esto" y lo que se escribe es el
/// texto que el acaba de leer. Meterlo en el buzon convertiria una libreta en un
/// tramite.
///
/// El formato lo arregla NexoDeck (`nexodeck-docs/src/notes/capture.rs`): quien
/// llama manda lo que sea y aqui se sanea. Y **nunca se pisa una nota**.
fn save_note(state: &Arc<ControlState>, args: &Value) -> ToolOutcome {
    let Some(docs) = state.docs() else {
        return notes_not_ready("save_note");
    };
    let Some(text) = arg_str(args, "text").filter(|t| !t.trim().is_empty()) else {
        return ToolOutcome::err(
            "save_note sin texto",
            "Falta 'text': es el contenido de la nota, en markdown. No se ha guardado nada.",
        );
    };

    let title = arg_str(args, "title");
    let path = arg_str(args, "path");
    let group = arg_str(args, "group");
    let from = arg_str(args, "from");
    let existed = path.is_some();

    match docs.capture_note(
        &text,
        title.as_deref(),
        path.as_deref(),
        group.as_deref(),
        from.as_deref(),
        jiff::Timestamp::now(),
    ) {
        Ok(note) => {
            // El resumen es lo que el usuario ve en el panel del servidor de
            // control: tiene que poder reconocer que nota le acaban de tocar.
            let summary = format!("nota guardada: {}", note.path);
            let detail = if existed {
                format!(
                    "Guardada en '{}' (se añadio al final, no se piso nada).\nTitulo: {}",
                    note.path, note.title
                )
            } else {
                format!("Nota creada: '{}'.\nTitulo: {}", note.path, note.title)
            };
            ToolOutcome::ok(
                summary,
                format!(
                    "{detail}\n\nYa esta en la boveda del usuario; la vera en NexoDeck y en el movil. \
                    Dile donde quedo."
                ),
            )
        }
        Err(error) => ToolOutcome::err(
            "save_note fallo",
            format!("No se pudo guardar la nota: {error}. NO se ha escrito nada."),
        ),
    }
}

/// Las agrupaciones de la boveda. Cada una es una carpeta (`notes/groups.rs`).
fn list_note_groups(state: &Arc<ControlState>) -> ToolOutcome {
    let Some(docs) = state.docs() else {
        return notes_not_ready("list_note_groups");
    };
    // Las carpetas solo se enseñan si hay alguna local: con la boveda sola, una
    // linea mas no dice nada.
    let folders = match docs.note_folders() {
        Ok(folders) if folders.iter().any(|f| f.local) => {
            let mut text = String::from("Carpetas de notas:\n");
            for folder in &folders {
                text.push_str(&format!(
                    "- {} · id '{}' · {}{}{}\n",
                    folder.name,
                    folder.id,
                    if folder.local { "notas locales, leidas en su sitio" } else { "boveda principal" },
                    if folder.local { format!(" · notas '@{}/…'", folder.id) } else { String::new() },
                    if folder.available { "" } else { " · NO DISPONIBLE ahora" },
                ));
            }
            text.push('\n');
            text
        }
        _ => String::new(),
    };
    match docs.note_groups() {
        Ok(groups) if groups.is_empty() => ToolOutcome::ok(
            "agrupaciones: ninguna",
            format!(
                "{folders}No hay agrupaciones todavia; las notas sueltas estan en 'inbox/'. Si el \
                usuario quiere una, create_note_group, o save_note con 'group'."
            ),
        ),
        Ok(groups) => {
            let mut text = format!(
                "{folders}{} agrupaciones (cada una es una carpeta):\n",
                groups.len()
            );
            for group in &groups {
                text.push_str(&format!(
                    "- {} · carpeta '{}' · {} · {} notas\n",
                    group.name, group.id, group.color_hex, group.notes
                ));
            }
            text.push_str("\nLas notas sin agrupacion estan en 'inbox/'.");
            ToolOutcome::ok(format!("agrupaciones: {}", groups.len()), text)
        }
        Err(error) => ToolOutcome::err(
            "list_note_groups fallo",
            format!("No se pudieron leer las agrupaciones: {error}"),
        ),
    }
}

/// Crea una agrupacion, o actualiza su nombre y color si ya existia.
fn create_note_group(state: &Arc<ControlState>, args: &Value) -> ToolOutcome {
    let Some(docs) = state.docs() else {
        return notes_not_ready("create_note_group");
    };
    let Some(name) = arg_str(args, "name").filter(|n| !n.trim().is_empty()) else {
        return ToolOutcome::err(
            "create_note_group sin nombre",
            "Falta 'name': el nombre de la agrupacion. No se ha creado nada.",
        );
    };
    let color = arg_str(args, "color");
    let folder = arg_str(args, "folder");
    match docs.upsert_note_group(&name, color.as_deref(), None, folder.as_deref()) {
        Ok(group) => ToolOutcome::ok(
            format!("agrupacion lista: {}", group.id),
            format!(
                "Agrupacion '{}' lista: carpeta '{}', color {}, {} notas.\n\nPara meter notas en \
                ella: save_note con 'group', o move_note_to_group.",
                group.name, group.id, group.color_hex, group.notes
            ),
        ),
        Err(error) => ToolOutcome::err(
            "create_note_group fallo",
            format!("No se pudo crear la agrupacion: {error}. No se ha creado nada."),
        ),
    }
}

/// Mueve una nota de agrupacion. **Mueve el fichero**, y por eso reescribe los
/// enlaces y los digests que la citaban por ruta (`DocsService::move_note`).
fn move_note_to_group(state: &Arc<ControlState>, args: &Value) -> ToolOutcome {
    let Some(docs) = state.docs() else {
        return notes_not_ready("move_note_to_group");
    };
    let Some(path) = arg_str(args, "path").filter(|p| !p.trim().is_empty()) else {
        return ToolOutcome::err(
            "move_note_to_group sin ruta",
            "Falta 'path': la nota a mover. No se ha movido nada.",
        );
    };
    let mut group = arg_str(args, "group");
    let mut folder = arg_str(args, "folder");
    // Un modelo que copia el id tal como lo da list_note_groups
    // (`@apuntes/clientes`) dice carpeta y agrupacion a la vez: se parte, en vez
    // de rechazarlo por no ser un nombre de carpeta valido.
    if let Some(id) = group.clone() {
        if let (Some(from), inner) = nexodeck_docs::split_virtual(id.trim()) {
            if folder.as_deref().is_some_and(|f| f.trim() != from) {
                return ToolOutcome::err(
                    "move_note_to_group con carpetas distintas",
                    format!(
                        "'group' es de la carpeta '{from}' pero 'folder' dice '{}'. No se ha movido nada.",
                        folder.unwrap_or_default()
                    ),
                );
            }
            folder = Some(from.to_string());
            group = Some(inner.to_string());
        }
    }
    match docs.move_note(path.trim(), group.as_deref(), folder.as_deref()) {
        Ok(outcome) if outcome.from == outcome.to => ToolOutcome::ok(
            format!("nota sin mover: {}", outcome.to),
            format!("'{}' ya estaba ahi: no se ha movido nada.", outcome.to),
        ),
        Ok(outcome) => {
            let mut text = format!("Movida: '{}' -> '{}'.", outcome.from, outcome.to);
            // Lo que se reescribio en otras notas se dice siempre: son ficheros
            // del usuario que cambiaron sin que el los tocara.
            if outcome.relinked.is_empty() {
                text.push_str("\nNinguna otra nota la citaba por ruta: no se toco nada mas.");
            } else {
                text.push_str(&format!(
                    "\nSe reescribieron enlaces en {} notas:",
                    outcome.relinked.len()
                ));
                for note in &outcome.relinked {
                    text.push_str(&format!("\n- {} ({} enlaces)", note.path, note.links));
                }
            }
            if outcome.digests > 0 {
                text.push_str(&format!(
                    "\nSus {} digests siguen asociados a la ruta nueva.",
                    outcome.digests
                ));
            }
            ToolOutcome::ok(format!("nota movida: {}", outcome.to), text)
        }
        Err(error) => ToolOutcome::err(
            "move_note_to_group fallo",
            format!("No se pudo mover la nota: {error}"),
        ),
    }
}

/// Las herramientas de notas viven en el buzon: sin buzon no hay boveda.
fn notes_not_ready(tool: &str) -> ToolOutcome {
    ToolOutcome::err(
        format!("{tool}: buzon no inicializado"),
        "El asistente de notas vive en el buzon de documentacion, que no esta inicializado en NexoDeck. \
        Dile al usuario que abra NexoDeck.",
    )
}

fn search_notes(state: &Arc<ControlState>, args: &Value) -> ToolOutcome {
    let Some(docs) = state.docs() else {
        return notes_not_ready("search_notes");
    };
    let Some(query) = arg_str(args, "query").filter(|q| !q.trim().is_empty()) else {
        return ToolOutcome::err("search_notes sin consulta", "Falta 'query'.");
    };
    let query = query.trim().to_string();
    let hits = match docs.search_notes(&query, arg_usize(args, "limit").unwrap_or(10)) {
        Ok(hits) => hits,
        Err(e) => {
            return ToolOutcome::err(
                format!("search_notes: {}", first_line(&e.to_string())),
                e.to_string(),
            )
        }
    };
    if hits.is_empty() {
        return ToolOutcome::ok(
            format!("notas: nada para '{query}'"),
            "No hay nada en la boveda, en los hallazgos ni en los commits que coincida.",
        );
    }

    // Claude Code tambien es un modelo remoto: los secretos se quitan igual que
    // antes de mandarle una nota a los agentes de NexoDeck.
    let mut text = String::new();
    for hit in &hits {
        let date = hit.date.as_deref().map(|d| format!(", {d}")).unwrap_or_default();
        let _ = writeln!(text, "- [{}] ({}{date}) {}", hit.id, hit.kind.as_str(), redact(&hit.title).0);
        let _ = writeln!(text, "    {}", redact(&hit.snippet).0);
        if let Some(path) = &hit.path {
            let _ = writeln!(text, "    nota: {path}");
        }
    }
    ToolOutcome::ok(format!("notas: {} resultados para '{query}'", hits.len()), text)
}

fn get_note(state: &Arc<ControlState>, args: &Value) -> ToolOutcome {
    let Some(docs) = state.docs() else {
        return notes_not_ready("get_note");
    };
    let Some(path) = arg_str(args, "path").filter(|p| !p.trim().is_empty()) else {
        return ToolOutcome::err(
            "get_note sin ruta",
            "Falta 'path' (la ruta de la nota, como la devuelve search_notes).",
        );
    };
    let details = match docs.note_details(path.trim()) {
        Ok(details) => details,
        Err(e) => {
            return ToolOutcome::err(
                format!("get_note: {}", first_line(&e.to_string())),
                e.to_string(),
            )
        }
    };
    let summary = &details.summary;
    if summary.ai_excluded {
        return ToolOutcome::err(
            format!("get_note: {} excluida", summary.path),
            "Esa nota tiene `ai: false`: el usuario no quiere que la lea ninguna IA.",
        );
    }

    let mut text = String::new();
    let date = summary.date.as_deref().map(|d| format!(", {d}")).unwrap_or_default();
    let _ = writeln!(
        text,
        "{} ({}, rol {}{date})\n",
        summary.title,
        summary.path,
        summary.role.as_str()
    );
    let _ = writeln!(text, "{}", redact(&details.text).0.trim_end());
    if !details.backlinks.is_empty() {
        let _ = writeln!(text, "\nEnlazan a esta nota: {}", details.backlinks.join(", "));
    }
    if !details.related.is_empty() {
        text.push_str("\nParecidas:\n");
        for candidate in &details.related {
            let _ = writeln!(text, "- [{}] {}", candidate.id, redact(&candidate.title).0);
        }
    }
    if let Some(last) = details.digests.last() {
        let _ = writeln!(text, "\nUltimo digest: {} ({})", last.id, digest_state(&last.status));
    }
    ToolOutcome::ok(format!("nota {}", summary.path), text)
}

fn digest_note(state: &Arc<ControlState>, args: &Value) -> ToolOutcome {
    let Some(docs) = state.docs() else {
        return notes_not_ready("digest_note");
    };
    let Some(path) = arg_str(args, "path").filter(|p| !p.trim().is_empty()) else {
        return ToolOutcome::err(
            "digest_note sin ruta",
            "Falta 'path' (la ruta de la nota, como la devuelve search_notes).",
        );
    };
    match docs.digest_note(path.trim(), DigestTrigger::Mcp, jiff::Timestamp::now()) {
        Ok(digest) => {
            let mut text = format!(
                "Digest {} de '{}': {}.\n\nNexoDeck preparara una propuesta y el usuario la aprobara en la app. \
                No edites esa nota por esto ni consultes el resultado en bucle.",
                digest.id,
                digest.note,
                digest_state(&digest.status)
            );
            if docs.inbox().config().is_ok_and(|c| !c.worker_enabled) {
                text.push_str(
                    "\n\nOJO: el procesado esta APAGADO en NexoDeck, asi que queda en cola sin procesar. \
                    Diselo al usuario: se enciende en \"Buzon de documentacion\".",
                );
            }
            ToolOutcome::ok(format!("digest de {}", digest.note), text)
        }
        Err(e) => ToolOutcome::err(
            format!("digest_note: {}", first_line(&e.to_string())),
            e.to_string(),
        ),
    }
}

fn digest_state(status: &DigestStatus) -> String {
    match status {
        DigestStatus::Queued => "en cola".to_string(),
        DigestStatus::Running => "procesandose".to_string(),
        DigestStatus::Proposed { proposal_id } => {
            format!("propuesta {proposal_id} esperando al usuario")
        }
        DigestStatus::Skipped { reason } => format!("no hacia falta: {reason}"),
        DigestStatus::Failed { reason } => format!("fallo: {reason}"),
        DigestStatus::WaitingModel { reason, .. } => format!("esperando modelo ({reason})"),
    }
}

fn format_elapsed(ms: u32) -> String {
    let total_secs = ms / 1000;
    let hours = total_secs / 3600;
    let mins = (total_secs % 3600) / 60;
    let secs = total_secs % 60;

    if hours > 0 {
        format!("{hours}h {mins:02}m")
    } else if mins > 0 {
        format!("{mins}m {secs:02}s")
    } else {
        format!("{}.{} s", secs, (ms % 1000) / 100)
    }
}

fn arg_str(args: &Value, key: &str) -> Option<String> {
    args.get(key)?.as_str().map(|s| s.to_string())
}

fn arg_bool(args: &Value, key: &str) -> Option<bool> {
    args.get(key)?.as_bool()
}

fn arg_usize(args: &Value, key: &str) -> Option<usize> {
    let raw = args.get(key)?.as_i64()?;
    usize::try_from(raw).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn elapsed_switches_to_hours_so_an_odm_chain_stays_readable() {
        assert_eq!(format_elapsed(3_400), "3.4 s");
        assert_eq!(format_elapsed(75_000), "1m 15s");
        // Tres horas y media: lo que dura una cadena de ODM.
        assert_eq!(format_elapsed(12_600_000), "3h 30m");
    }

    #[test]
    fn every_tool_declares_a_name_and_a_schema() {
        let defs = definitions();
        assert_eq!(defs.len(), 15);
        for def in defs {
            assert!(def["name"].as_str().is_some_and(|n| !n.is_empty()));
            assert!(def["description"].as_str().is_some_and(|d| d.len() > 40));
            assert_eq!(def["inputSchema"]["type"], "object");
        }
    }

    /// El estilo de aviso solo existe si esta escrito en la descripcion: es lo
    /// unico que el modelo lee antes de elegir como redactar.
    #[test]
    fn the_notify_description_carries_the_style_rule() {
        let defs = definitions();
        let notify = defs.iter().find(|d| d["name"] == "notify").unwrap();
        let description = notify["description"].as_str().unwrap();
        assert!(description.contains("ESTILO"));
        assert!(description.contains("errores"));
    }

    #[tokio::test]
    async fn a_missing_required_argument_comes_back_as_a_readable_tool_error() {
        let outcome = tail_run(&json!({}));
        assert!(outcome.is_error);
        assert!(outcome.text.contains("run_id"));
    }

    #[test]
    fn an_unknown_run_says_both_possibilities_instead_of_guessing() {
        let outcome = tail_run(&json!({ "run_id": "no_existe" }));
        assert!(!outcome.is_error);
        assert!(outcome.text.contains("list_runs"));
    }

    #[test]
    fn limits_are_clamped_so_a_silly_number_cannot_blow_up_the_answer() {
        let outcome = list_runs(&json!({ "limit": 100000 }));
        assert!(!outcome.is_error);
        let outcome = list_runs(&json!({ "limit": -5 }));
        assert!(!outcome.is_error);
    }
}
