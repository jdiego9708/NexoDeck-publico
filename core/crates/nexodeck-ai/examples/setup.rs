use std::sync::Arc;
use std::sync::atomic::AtomicBool;

use nexodeck_ai::download::DownloadEvent;
use nexodeck_ai::plan::plan_runtime;
use nexodeck_ai::setup::{self, format_bytes};
use nexodeck_ai::sidecar::{LlamaServer, ServerSpec};
use nexodeck_hardware::probe_host_capabilities;
use tokio::sync::mpsc;

/// Descarga el runtime y el modelo y levanta `llama-server`, sin Flutter de por
/// medio. Es el hito verificable de los pasos 3 y 4.
///
/// ```sh
/// cargo run -p nexodeck-ai --example setup
/// cargo run -p nexodeck-ai --example setup -- --download-only
/// cargo run -p nexodeck-ai --example setup -- --model granite-3.3-2b-instruct-q4km
/// ```
///
/// Que mirar:
/// - Cortar la red a mitad de la descarga y relanzar: tiene que **reanudar**,
///   no empezar de cero (se ve en `resumed_from` del evento `Started`).
/// - En Windows **no** tiene que aparecer ninguna consola negra.
/// - Al terminar, cero `llama-server.exe` en el Administrador de tareas.
#[tokio::main]
async fn main() {
    let _ = env_logger::builder()
        .filter_level(log::LevelFilter::Info)
        .try_init();

    let args: Vec<String> = std::env::args().skip(1).collect();
    let download_only = args.iter().any(|a| a == "--download-only");
    let model_id = args
        .iter()
        .position(|a| a == "--model")
        .and_then(|i| args.get(i + 1))
        .cloned();

    let models_dir = nexodeck_ai::paths::models_dir().expect("no se pudo crear el directorio de modelos");
    let caps = probe_host_capabilities(&models_dir);
    let plan = plan_runtime(&caps);

    let setup_plan = match setup::resolve_setup(&plan, caps.os, model_id.as_deref()) {
        Ok(setup_plan) => setup_plan,
        Err(error) => {
            eprintln!("No se pudo resolver el setup: {error}");
            std::process::exit(1);
        }
    };

    println!("Backend : {}", plan.backend.as_str());
    println!("Runtime : {}", setup_plan.runtime.display_name);
    println!(
        "Modelo  : {} ({})",
        setup_plan.model.display_name, setup_plan.model.quantization
    );
    println!(
        "Descarga: {} en total",
        format_bytes(setup_plan.total_download_bytes())
    );
    println!("Destino : {}", models_dir.display());
    println!();

    if let Err(error) = setup::check_disk_space(&setup_plan) {
        eprintln!("{error}");
        std::process::exit(1);
    }

    let (tx, mut rx) = mpsc::channel::<DownloadEvent>(64);
    let printer = tokio::spawn(async move {
        while let Some(event) = rx.recv().await {
            print_event(event);
        }
    });

    let cancel = Arc::new(AtomicBool::new(false));
    let installed = match setup::ensure_installed(&setup_plan, &tx, cancel).await {
        Ok(installed) => installed,
        Err(error) => {
            drop(tx);
            let _ = printer.await;
            eprintln!("\nFallo el setup: {error}");
            std::process::exit(1);
        }
    };
    drop(tx);
    let _ = printer.await;

    println!("\nInstalado:");
    println!("  server : {}", installed.server_path.display());
    println!("  modelo : {}", installed.model_path.display());

    if download_only {
        println!("\n--download-only: no se levanta el server.");
        return;
    }

    let gpu_layers = nexodeck_ai::gpu_layers_for(setup_plan.model, &plan);
    println!(
        "\nLevantando llama-server (-ngl {gpu_layers}, --threads {}, --ctx-size {})...",
        plan.threads, plan.context_size
    );

    let spec = ServerSpec {
        server_path: installed.server_path.clone(),
        model_path: installed.model_path.clone(),
        model_alias: setup_plan.model.id.to_string(),
        gpu_layers,
        threads: plan.threads,
        context_size: plan.context_size,
    };

    let started = std::time::Instant::now();
    let server = match LlamaServer::start(&spec).await {
        Ok(server) => server,
        Err(error) => {
            eprintln!("\n{error}");
            std::process::exit(1);
        }
    };

    println!(
        "Listo en {:.1}s -> {} (capas en GPU: {})",
        started.elapsed().as_secs_f64(),
        server.base_url(),
        server.gpu_layers
    );

    // Prueba minima de que el server esta realmente servible, no solo vivo.
    match reqwest::get(format!("{}/v1/models", server.base_url())).await {
        Ok(response) => {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            println!("\nGET /v1/models -> {status}\n{body}");
        }
        Err(error) => eprintln!("\nGET /v1/models fallo: {error}"),
    }

    println!("\nApagando el server...");
    server.shutdown().await;
    println!("Listo. No deberia quedar ningun llama-server vivo.");
}

fn print_event(event: DownloadEvent) {
    match event {
        DownloadEvent::Started {
            asset,
            total_bytes,
            resumed_from,
        } => {
            if resumed_from > 0 {
                println!(
                    "\n[{asset}] reanudando desde {} de {}",
                    format_bytes(resumed_from),
                    format_bytes(total_bytes)
                );
            } else {
                println!("\n[{asset}] descargando {}", format_bytes(total_bytes));
            }
        }
        DownloadEvent::Progress {
            downloaded,
            total_bytes,
            bytes_per_sec,
            ..
        } => {
            let percent = if total_bytes > 0 {
                (downloaded as f64 / total_bytes as f64) * 100.0
            } else {
                0.0
            };
            print!(
                "\r  {percent:>5.1}%  {} / {}  ({}/s)      ",
                format_bytes(downloaded),
                format_bytes(total_bytes),
                format_bytes(bytes_per_sec)
            );
            use std::io::Write;
            let _ = std::io::stdout().flush();
        }
        DownloadEvent::Verifying { asset } => println!("\n[{asset}] verificando SHA256..."),
        DownloadEvent::Extracting { asset } => println!("[{asset}] descomprimiendo..."),
        DownloadEvent::Finished { asset, .. } => println!("[{asset}] listo"),
        DownloadEvent::Failed { asset, detail } => println!("\n[{asset}] FALLO: {detail}"),
    }
}
