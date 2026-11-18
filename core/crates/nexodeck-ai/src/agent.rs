//! El bucle del agente: conversacion, herramientas y borrador.
//!
//! Un "turno" es todo lo que pasa entre que el usuario escribe algo y que el
//! asistente le responde: puede incluir varias idas y vueltas con herramientas.
//! El historial vive aca (en memoria, no en Drift: no aporta al objetivo y
//! costaria una migracion).
//!
//! Los eventos salen por un `broadcast` de tokio. **No** se exponen como un
//! `Stream` de valores que puedan compararse por igualdad: el lado Flutter tiene
//! que suscribirse directo al stream y nunca con `ref.listen` sobre un provider,
//! porque Riverpod descarta el valor cuando es `==` al anterior y dos
//! `AssistantToken(" ")` seguidos son identicos. Un stream de tokens es el peor
//! caso posible de ese bug, ya documentado en `CLAUDE.md`.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use tokio::sync::{Mutex, broadcast};

use crate::draft::ActionDraft;
use crate::error::{AiError, AiResult};
use crate::openai::types::{ChatMessage, ChatRequest};
use crate::openai::{self, stream::StreamDelta};
use crate::prompt;
use crate::provider::ChatProvider;
use crate::safety;
use crate::tools::{ToolContext, ToolRegistry};

/// Tope de rondas de herramientas por turno.
///
/// Sin tope, un modelo chico se cuelga alternando `list_directory` y
/// `find_project` para siempre. Ocho alcanza de sobra para el caso del brief
/// (buscar proyecto, listar, verificar dos ejecutables, ver dispositivos,
/// proponer) y corta el bucle patologico antes de que el usuario se canse.
pub const MAX_TOOL_ROUNDS: u32 = 8;

/// Capacidad del canal de eventos. Generosa porque los tokens llegan rapido y
/// un suscriptor lento (la UI durante un rebuild) no puede perder texto.
const EVENT_CHANNEL_CAPACITY: usize = 512;

#[derive(Debug, Clone)]
pub enum AgentEvent {
    /// Fragmento de texto visible. Se emite tal cual llega.
    AssistantToken(String),
    /// El modelo esta razonando. No se emite el contenido: es monologo interno.
    Thinking,
    /// Mensaje completo del asistente, al cerrar el turno.
    AssistantMessage(String),
    ToolStarted {
        name: String,
        summary: String,
    },
    ToolFinished {
        name: String,
        ok: bool,
        summary: String,
    },
    /// Borrador aceptado, con su nivel de riesgo ya calculado.
    DraftReady {
        draft: ActionDraft,
        risk: safety::RiskLevel,
    },
    TurnDone,
    Failed {
        detail: String,
    },
}

pub struct AgentSession {
    provider: ChatProvider,
    registry: Arc<ToolRegistry>,
    context: Arc<ToolContext>,
    history: Mutex<Vec<ChatMessage>>,
    events: broadcast::Sender<AgentEvent>,
    busy: AtomicBool,
    cancel: Arc<AtomicBool>,
    client: reqwest::Client,
}

impl AgentSession {
    pub fn new(provider: ChatProvider, context: Arc<ToolContext>) -> Self {
        let (events, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        let system = prompt::system_prompt(context.os, &context.allowed_roots());

        AgentSession {
            provider,
            registry: Arc::new(ToolRegistry::standard()),
            context,
            history: Mutex::new(vec![ChatMessage::system(system)]),
            events,
            busy: AtomicBool::new(false),
            cancel: Arc::new(AtomicBool::new(false)),
            client: openai::chat_client(),
        }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<AgentEvent> {
        self.events.subscribe()
    }

    pub fn provider_label(&self) -> String {
        self.provider.label()
    }

    /// El modelo local de esta sesion, si lo es. Ver
    /// [`ChatProvider::local_endpoint`].
    pub fn local_endpoint(&self) -> Option<crate::provider::ModelEndpoint> {
        self.provider.local_endpoint()
    }

    /// Vuelve a empezar: se descarta el historial y lo verificado.
    pub async fn reset(&self) {
        let system = prompt::system_prompt(self.context.os, &self.context.allowed_roots());
        *self.history.lock().await = vec![ChatMessage::system(system)];
        self.context.reset_facts();
    }

    /// Actualiza carpetas permitidas y deck **sin** recrear la sesion.
    ///
    /// El system prompt ya enviado sigue nombrando las carpetas viejas (no se
    /// puede reescribir el historial sin confundir al modelo), pero lo que
    /// manda es `is_readable`: una carpeta que se saco deja de leerse en el
    /// acto aunque el prompt todavia la mencione.
    pub fn update_context(&self, roots: Vec<std::path::PathBuf>, deck: Vec<crate::tools::DeckActionRef>) {
        self.context.set_allowed_roots(roots);
        self.context.set_deck(deck);
    }

    /// Corta el turno en curso.
    pub fn cancel(&self) {
        self.cancel.store(true, Ordering::Relaxed);
    }

    pub fn is_busy(&self) -> bool {
        self.busy.load(Ordering::Relaxed)
    }

    pub async fn shutdown(self) {
        self.provider.shutdown().await;
    }

    /// Procesa un mensaje del usuario de punta a punta.
    ///
    /// Todo fallo se emite como [`AgentEvent::Failed`] **ademas** de
    /// devolverse: el proyecto ya perdio tiempo tres veces con errores que
    /// desaparecian sin dejar rastro (ver "Fallos de conexion" en `CLAUDE.md`),
    /// y un chat que se queda mudo es exactamente ese sintoma.
    pub async fn send_user_message(&self, text: String) -> AiResult<()> {
        if self.busy.swap(true, Ordering::Relaxed) {
            return Err(AiError::Busy);
        }
        self.cancel.store(false, Ordering::Relaxed);

        let result = self.run_turn(text).await;

        self.busy.store(false, Ordering::Relaxed);

        match &result {
            Ok(()) => {
                let _ = self.events.send(AgentEvent::TurnDone);
            }
            Err(error) => {
                let _ = self.events.send(AgentEvent::Failed {
                    detail: self.explain(error),
                });
            }
        }

        result
    }

    /// Agrega el diagnostico del sidecar cuando lo hay. Un
    /// "error hablando con el modelo" sin el stderr del server no le sirve a
    /// nadie.
    fn explain(&self, error: &AiError) -> String {
        match error {
            AiError::Provider(_) | AiError::BadResponse(_) => {
                match self.provider.diagnostics().filter(|tail| !tail.is_empty()) {
                    Some(tail) => {
                        let last: Vec<&str> = tail.lines().rev().take(5).collect();
                        format!(
                            "{error}\n\nUltimas lineas del motor:\n{}",
                            last.into_iter().rev().collect::<Vec<_>>().join("\n")
                        )
                    }
                    None => error.to_string(),
                }
            }
            other => other.to_string(),
        }
    }

    async fn run_turn(&self, text: String) -> AiResult<()> {
        // Los hechos verificados **si** se arrastran entre mensajes: si el
        // usuario responde una aclaracion, obligar a reconfirmar la ruta que ya
        // se encontro seria absurdo. Lo unico que se reinicia es el contador de
        // propuestas.
        self.context.with_facts(|facts| facts.proposals = 0);

        self.history.lock().await.push(ChatMessage::user(text));

        for round in 0..MAX_TOOL_ROUNDS {
            self.provider.touch();

            let messages = self.history.lock().await.clone();
            let mut request = ChatRequest::new(self.provider.model(), messages)
                .with_tools(self.registry.definitions());
            if self.provider.disable_thinking() {
                request = request.without_thinking();
            }

            let events = self.events.clone();
            let completion = openai::stream_chat(
                &self.client,
                self.provider.base_url(),
                self.provider.api_key(),
                &request,
                Arc::clone(&self.cancel),
                move |delta| {
                    let event = match delta {
                        StreamDelta::Content(text) => AgentEvent::AssistantToken(text),
                        StreamDelta::Reasoning(_) => AgentEvent::Thinking,
                        StreamDelta::ToolCallStarted { name } => AgentEvent::ToolStarted {
                            summary: describe_tool(&name),
                            name,
                        },
                    };
                    let _ = events.send(event);
                },
            )
            .await?;

            if !completion.wants_tools() {
                let message = completion.content.trim().to_string();
                self.history
                    .lock()
                    .await
                    .push(ChatMessage::assistant_text(message.clone()));
                let _ = self.events.send(AgentEvent::AssistantMessage(message));
                return Ok(());
            }

            // El asistente pidio herramientas: su mensaje (con los tool calls)
            // tiene que entrar al historial ANTES de las respuestas, o el
            // modelo pierde la referencia de que pidio.
            self.history.lock().await.push(ChatMessage::assistant_tool_calls(
                Some(completion.content.clone()).filter(|c| !c.trim().is_empty()),
                completion.tool_calls.clone(),
            ));

            for call in &completion.tool_calls {
                let name = call.function.name.clone();
                let arguments = call.function.arguments.clone();

                let registry = Arc::clone(&self.registry);
                let context = Arc::clone(&self.context);
                let dispatch_name = name.clone();

                // Las herramientas hacen I/O de disco y lanzan procesos:
                // bloquean. Correrlas en el executor async congelaria el mismo
                // runtime que mueve el WebSocket del transporte y el USB.
                let result = tokio::task::spawn_blocking(move || {
                    registry.dispatch(&dispatch_name, &arguments, &context)
                })
                .await
                .unwrap_or_else(|error| {
                    serde_json::json!({
                        "ok": false,
                        "error": format!("la herramienta fallo inesperadamente: {error}")
                    })
                });

                let ok = result["ok"].as_bool().unwrap_or(false);
                let _ = self.events.send(AgentEvent::ToolFinished {
                    name: name.clone(),
                    ok,
                    summary: summarize_result(&name, &result),
                });

                // El borrador aceptado se saca de los **argumentos** de la
                // llamada, no del resultado: la herramienta solo dice si paso
                // el gate.
                if ok && ToolRegistry::is_terminal(&name) {
                    if let Ok(args) = serde_json::from_str::<serde_json::Value>(&call.function.arguments)
                    {
                        if let Ok(draft) = serde_json::from_value::<ActionDraft>(args) {
                            let risk = safety::draft_risk_level(
                                draft.steps.iter().map(|step| step.command.as_str()),
                            );
                            let _ = self.events.send(AgentEvent::DraftReady {
                                draft: draft.clone(),
                                risk,
                            });
                        }
                    }
                }

                self.history.lock().await.push(ChatMessage::tool_result(
                    call.id.clone(),
                    result.to_string(),
                ));
            }

            // Ultima ronda: se le pide cerrar preguntando en vez de dejarlo
            // seguir pidiendo herramientas que ya no se van a ejecutar.
            if round + 1 == MAX_TOOL_ROUNDS {
                self.history
                    .lock()
                    .await
                    .push(ChatMessage::system(prompt::OUT_OF_ROUNDS));
            }
        }

        // Una vuelta final sin herramientas, para que el modelo pueda decir
        // algo util. Si tampoco lo logra, se reporta el tope alcanzado.
        let messages = self.history.lock().await.clone();
        let mut request = ChatRequest::new(self.provider.model(), messages);
        if self.provider.disable_thinking() {
            request = request.without_thinking();
        }
        let events = self.events.clone();

        let completion = openai::stream_chat(
            &self.client,
            self.provider.base_url(),
            self.provider.api_key(),
            &request,
            Arc::clone(&self.cancel),
            move |delta| {
                if let StreamDelta::Content(text) = delta {
                    let _ = events.send(AgentEvent::AssistantToken(text));
                }
            },
        )
        .await?;

        let message = completion.content.trim().to_string();
        if message.is_empty() {
            return Err(AiError::ToolRoundsExhausted {
                max: MAX_TOOL_ROUNDS,
            });
        }

        self.history
            .lock()
            .await
            .push(ChatMessage::assistant_text(message.clone()));
        let _ = self.events.send(AgentEvent::AssistantMessage(message));
        Ok(())
    }
}

/// Texto para la UI mientras corre una herramienta. En espanol y en terminos
/// del usuario: "revisando el disco", no "list_directory".
fn describe_tool(name: &str) -> String {
    match name {
        "list_directory" => "Mirando una carpeta",
        "find_project" => "Buscando el proyecto",
        "read_text_file" => "Leyendo un archivo",
        "which_executable" => "Verificando si el programa esta instalado",
        "list_shell_capabilities" => "Viendo que terminales hay",
        "list_android_devices" => "Buscando dispositivos Android",
        "list_existing_actions" => "Revisando tus botones",
        "propose_action" => "Armando el borrador",
        _ => "Trabajando",
    }
    .to_string()
}

/// Resumen del resultado, tambien para la UI.
///
/// La primera linea es lo unico que se ve colapsado (la UI la corta con
/// elipsis): tiene que seguir siendo un conteo corto, nunca el JSON entero.
/// El detalle real (rutas, nombres) va DESPUES de un salto de linea via
/// `with_detail` — antes no iba en absoluto ("un listado de 120 archivos en
/// una burbuja de chat no le sirve a nadie"), pero eso asumia que la burbuja
/// siempre estaba a la vista; con el trace ahora colapsable por defecto, el
/// detalle solo se ve si el usuario lo pide expandiendo esa fila.
fn summarize_result(name: &str, result: &serde_json::Value) -> String {
    if result["ok"].as_bool() == Some(false) {
        return result["error"]
            .as_str()
            .map(|error| error.chars().take(160).collect())
            .unwrap_or_else(|| "no se pudo".to_string());
    }

    match name {
        "list_directory" => {
            let dirs = result["directories"].as_array().cloned().unwrap_or_default();
            let files = result["files"].as_array().cloned().unwrap_or_default();
            let summary = format!("{} carpetas, {} archivos", dirs.len(), files.len());
            let names: Vec<String> = dirs
                .iter()
                .chain(files.iter())
                .filter_map(|v| v.as_str().map(str::to_string))
                .collect();
            with_detail(summary, &names)
        }
        "find_project" => {
            let matches = result["matches"].as_array().cloned().unwrap_or_default();
            match matches.len() {
                0 => "sin resultados".to_string(),
                1 => matches[0]["path"]
                    .as_str()
                    .unwrap_or("1 resultado")
                    .to_string(),
                n => {
                    let paths: Vec<String> = matches
                        .iter()
                        .filter_map(|m| m["path"].as_str().map(str::to_string))
                        .collect();
                    with_detail(format!("{n} resultados"), &paths)
                }
            }
        }
        "which_executable" => {
            if result["builtin"].as_bool() == Some(true) {
                format!(
                    "{} es un builtin del shell",
                    result["name"].as_str().unwrap_or("eso")
                )
            } else if result["found"].as_bool() == Some(true) {
                // Sin version legible se dice que esta instalado igual: el dato
                // que importa es que existe.
                result["version"]
                    .as_str()
                    .map(|version| version.chars().take(80).collect())
                    .unwrap_or_else(|| {
                        format!(
                            "{} esta instalado",
                            result["name"].as_str().unwrap_or("el programa")
                        )
                    })
            } else {
                format!(
                    "{} no esta instalado",
                    result["name"].as_str().unwrap_or("el programa")
                )
            }
        }
        "list_android_devices" => match result["devices"].as_array().map_or(0, Vec::len) {
            0 => "ningun telefono conectado".to_string(),
            n => format!("{n} dispositivo(s)"),
        },
        "propose_action" => "borrador listo".to_string(),
        _ => "listo".to_string(),
    }
}

/// Suma el detalle real detras del resumen corto, separado por un salto de
/// linea — la vista colapsada solo muestra la primera linea (se corta con
/// elipsis), la expandida muestra todo. Tope de 25 items: mas que eso en una
/// sola herramienta ya es un caso raro, y seguir sumando no ayuda a leerlo.
fn with_detail(summary: String, items: &[String]) -> String {
    if items.is_empty() {
        return summary;
    }
    const MAX_ITEMS: usize = 25;
    let mut detail = items.iter().take(MAX_ITEMS).cloned().collect::<Vec<_>>().join("\n");
    if items.len() > MAX_ITEMS {
        detail.push_str(&format!("\n... y {} mas", items.len() - MAX_ITEMS));
    }
    format!("{summary}\n{detail}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn cada_herramienta_tiene_un_texto_en_espanol_para_la_ui() {
        for name in [
            "list_directory",
            "find_project",
            "read_text_file",
            "which_executable",
            "list_shell_capabilities",
            "list_android_devices",
            "list_existing_actions",
            "propose_action",
        ] {
            let text = describe_tool(name);
            assert!(!text.is_empty());
            assert!(
                !text.contains('_'),
                "'{text}' parece el nombre tecnico, no algo para el usuario"
            );
        }
    }

    /// La PRIMERA linea (lo unico que se ve colapsado, la UI la corta con
    /// elipsis) tiene que seguir siendo el conteo corto. El detalle real
    /// esta ahora permitido, pero DESPUES de un salto de linea — la fila
    /// solo lo muestra si el usuario la expande a proposito.
    #[test]
    fn el_resumen_de_un_listado_lleva_el_conteo_primero_y_el_detalle_despues() {
        let result = json!({
            "ok": true,
            "directories": ["lib", "test", "android"],
            "files": ["pubspec.yaml", "README.md"]
        });

        let summary = summarize_result("list_directory", &result);
        let mut lines = summary.lines();
        assert_eq!(lines.next(), Some("3 carpetas, 2 archivos"));
        assert!(summary.contains("pubspec.yaml"));
    }

    /// Un listado gigante no puede volcar cientos de lineas: se corta con un
    /// aviso de cuantas quedaron afuera.
    #[test]
    fn un_listado_enorme_se_corta_con_aviso() {
        let files: Vec<String> = (0..40).map(|i| format!("archivo{i}.txt")).collect();
        let result = json!({ "ok": true, "directories": [], "files": files });

        let summary = summarize_result("list_directory", &result);
        assert!(summary.contains("... y 15 mas"));
        assert!(!summary.contains("archivo39.txt"));
    }

    #[test]
    fn el_resumen_de_un_unico_proyecto_muestra_la_ruta() {
        let result = json!({
            "ok": true,
            "matches": [{ "path": "E:/Proyectos/ExampleApp", "project_type": "flutter/dart" }]
        });

        assert_eq!(
            summarize_result("find_project", &result),
            "E:/Proyectos/ExampleApp"
        );
    }

    /// El caso real que motivo esto: "Buscando el proyecto · 11 resultados"
    /// no decia CUALES eran los 11. Ahora la primera linea sigue siendo el
    /// conteo (para el colapsado), y las rutas van despues (para expandir).
    #[test]
    fn el_resumen_de_varios_proyectos_lleva_las_rutas() {
        let result = json!({
            "ok": true,
            "matches": [
                { "path": "E:/RepositoriosFix/ExampleApi", "project_type": "dotnet" },
                { "path": "C:/proyecto/pycache/RepositoriosFix/ExampleApi", "project_type": "" },
            ]
        });

        let summary = summarize_result("find_project", &result);
        let mut lines = summary.lines();
        assert_eq!(lines.next(), Some("2 resultados"));
        assert!(summary.contains("E:/RepositoriosFix/ExampleApi"));
        assert!(summary.contains("C:/proyecto/pycache/RepositoriosFix/ExampleApi"));
    }

    #[test]
    fn el_resumen_de_un_error_muestra_el_motivo_recortado() {
        let result = json!({ "ok": false, "error": "a".repeat(300) });
        let summary = summarize_result("list_directory", &result);

        assert!(summary.len() <= 160);
    }

    #[test]
    fn un_ejecutable_faltante_se_resume_como_tal() {
        let result = json!({ "ok": true, "found": false, "name": "flutter" });
        assert_eq!(
            summarize_result("which_executable", &result),
            "flutter no esta instalado"
        );
    }

    #[test]
    fn sin_dispositivos_el_resumen_lo_dice() {
        let result = json!({ "ok": true, "devices": [] });
        assert_eq!(
            summarize_result("list_android_devices", &result),
            "ningun telefono conectado"
        );
    }
}
