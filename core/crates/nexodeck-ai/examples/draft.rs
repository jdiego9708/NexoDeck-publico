use std::io::Write;
use std::sync::Arc;
use std::sync::atomic::AtomicBool;

use nexodeck_ai::agent::{AgentEvent, AgentSession};
use nexodeck_ai::download::DownloadEvent;
use nexodeck_ai::plan::plan_runtime;
use nexodeck_ai::provider::ChatProvider;
use nexodeck_ai::setup;
use nexodeck_ai::sidecar::{LlamaServer, ServerSpec};
use nexodeck_ai::tools::{ToolContext, default_allowed_roots};
use nexodeck_hardware::probe_host_capabilities;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::mpsc;

/// El hito real del Bloque B: el agente completo, **sin Flutter de por medio**.
///
/// ```sh
/// cargo run -p nexodeck-ai --example draft -- "quiero un boton que abra mi proyecto ExampleApp y corra flutter analyze"
/// cargo run -p nexodeck-ai --example draft -- --model qwen3-14b-q4km "..."
/// ```
///
/// Que verificar:
/// - El asistente **pregunta primero**. Si emite un borrador sin haber usado
///   herramientas, el gate de `propose_action` esta roto.
/// - Se le contesta por stdin y sigue la conversacion.
/// - Termina imprimiendo el borrador ya validado, con su nivel de riesgo.
#[tokio::main]
async fn main() {
    let _ = env_logger::builder()
        .filter_level(log::LevelFilter::Warn)
        .try_init();

    let args: Vec<String> = std::env::args().skip(1).collect();
    let model_id = args
        .iter()
        .position(|a| a == "--model")
        .and_then(|i| args.get(i + 1))
        .cloned();
    let prompt = args
        .iter()
        .filter(|a| !a.starts_with("--"))
        .filter(|a| Some(a.as_str()) != model_id.as_deref())
        .cloned()
        .collect::<Vec<_>>()
        .join(" ");

    if prompt.trim().is_empty() {
        eprintln!("Uso: cargo run -p nexodeck-ai --example draft -- [--model <id>] \"lo que quiero\"");
        std::process::exit(2);
    }

    // ---- 1. Motor ----
    let models_dir = nexodeck_ai::paths::models_dir().expect("directorio de modelos");
    let caps = probe_host_capabilities(&models_dir);
    let plan = plan_runtime(&caps);
    let setup_plan =
        setup::resolve_setup(&plan, caps.os, model_id.as_deref()).expect("resolver el setup");

    println!(
        "Motor: {} sobre {}",
        setup_plan.model.display_name,
        plan.backend.as_str()
    );

    let (tx, mut rx) = mpsc::channel::<DownloadEvent>(64);
    tokio::spawn(async move {
        while let Some(event) = rx.recv().await {
            if let DownloadEvent::Progress {
                asset,
                downloaded,
                total_bytes,
                ..
            } = event
            {
                let percent = if total_bytes > 0 {
                    downloaded as f64 / total_bytes as f64 * 100.0
                } else {
                    0.0
                };
                print!("\r  descargando {asset}: {percent:.0}%   ");
                let _ = std::io::stdout().flush();
            }
        }
    });

    let installed = setup::ensure_installed(&setup_plan, &tx, Arc::new(AtomicBool::new(false)))
        .await
        .expect("instalar el motor");
    drop(tx);

    let gpu_layers = nexodeck_ai::gpu_layers_for(setup_plan.model, &plan);
    let server = LlamaServer::start(&ServerSpec {
        server_path: installed.server_path,
        model_path: installed.model_path,
        model_alias: setup_plan.model.id.to_string(),
        gpu_layers,
        threads: plan.threads,
        context_size: plan.context_size,
    })
    .await
    .expect("levantar llama-server");

    // ---- 2. Agente ----
    let roots = default_allowed_roots();
    println!(
        "Carpetas legibles: {}\n",
        roots
            .iter()
            .map(|r| r.to_string_lossy().to_string())
            .collect::<Vec<_>>()
            .join(", ")
    );

    let context = Arc::new(ToolContext::new(roots, caps.os));
    let session = Arc::new(AgentSession::new(
        ChatProvider::Sidecar {
            server,
            model_id: setup_plan.model.id.to_string(),
            display_name: setup_plan.model.display_name.to_string(),
            supports_thinking: setup_plan.model.supports_thinking,
        },
        context,
    ));

    let mut events = session.subscribe();
    let printer = tokio::spawn(async move {
        let mut drafts = 0u32;
        while let Ok(event) = events.recv().await {
            match event {
                AgentEvent::AssistantToken(text) => {
                    print!("{text}");
                    let _ = std::io::stdout().flush();
                }
                AgentEvent::Thinking => {}
                AgentEvent::AssistantMessage(_) => println!(),
                AgentEvent::ToolStarted { summary, .. } => {
                    println!("\n  · {summary}...");
                }
                AgentEvent::ToolFinished { name, ok, summary } => {
                    println!("  {} {name}: {summary}", if ok { "✓" } else { "✗" });
                }
                AgentEvent::DraftReady { draft, risk } => {
                    drafts += 1;
                    println!("\n{}", "=".repeat(70));
                    println!("BORRADOR  ·  riesgo: {}", risk.as_str());
                    println!("{}", "=".repeat(70));
                    println!("{} [{} / {}]", draft.name, draft.icon, draft.color_hex);
                    if let Some(description) = &draft.description {
                        println!("{description}");
                    }
                    println!("\n{}\n", draft.summary);
                    for (index, step) in draft.steps.iter().enumerate() {
                        println!("  {}. {} ({:?})", index + 1, step.name, step.terminal);
                        if let Some(dir) = &step.working_directory {
                            println!("     cwd: {dir}");
                        }
                        println!("     $ {}", step.command);
                        for param in &step.parameters {
                            println!(
                                "     ?  {{{{{}}}}}  {} ({:?})",
                                param.key, param.label, param.kind
                            );
                        }
                        println!(
                            "     comando final:\n       {}",
                            nexodeck_ai::draft::fold_working_directory(step)
                                .replace('\n', "\n       ")
                        );
                    }
                    println!("{}", "=".repeat(70));
                }
                AgentEvent::TurnDone => print!("\n> "),
                AgentEvent::Failed { detail } => println!("\n[ERROR] {detail}"),
            }
            let _ = std::io::stdout().flush();
            if drafts > 0 {
                // Se sigue escuchando: el usuario puede pedir cambios.
            }
        }
    });

    // ---- 3. Conversacion ----
    println!("> {prompt}");
    if let Err(error) = session.send_user_message(prompt).await {
        eprintln!("\n{error}");
    }

    let mut stdin = BufReader::new(tokio::io::stdin()).lines();
    while let Ok(Some(line)) = stdin.next_line().await {
        let line = line.trim().to_string();
        if line.is_empty() {
            print!("> ");
            let _ = std::io::stdout().flush();
            continue;
        }
        if line == "/salir" || line == "/exit" {
            break;
        }
        if line == "/reset" {
            session.reset().await;
            println!("(conversacion reiniciada)\n> ");
            continue;
        }
        if let Err(error) = session.send_user_message(line).await {
            eprintln!("\n{error}");
        }
    }

    printer.abort();
    println!("\nApagando el motor...");
    Arc::try_unwrap(session)
        .unwrap_or_else(|_| panic!("quedo una referencia viva a la sesion"))
        .shutdown()
        .await;
    println!("Listo.");
}
