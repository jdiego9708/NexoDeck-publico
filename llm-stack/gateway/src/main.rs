//! Línea de órdenes de la pasarela.
//!
//! ```text
//! llm-gateway [--dir DIRECTORIO] <orden>
//!
//!   serve                  Arranca la pasarela (crea gateway.json con valores por defecto si falta)
//!   init                   Solo crea gateway.json y enseña dónde están los ficheros
//!   paths                  Enseña las rutas de configuración y claves
//!   keys add NOMBRE        Crea una clave y la enseña UNA vez
//!   keys list              Lista las claves (nombre y fecha; nunca la clave)
//!   keys remove NOMBRE     Revoca una clave (surte efecto sin reiniciar)
//! ```

use std::net::SocketAddr;
use std::path::PathBuf;
use std::process::ExitCode;

use llm_gateway::auth::KeyStore;
use llm_gateway::config::{Config, Paths};
use llm_gateway::decisions::DecisionLog;
use llm_gateway::{build_app_with_reload, logging};

const USAGE: &str = "\
Uso: llm-gateway [--dir DIRECTORIO] <orden>

  serve                  Arranca la pasarela
  init                   Crea gateway.json con valores por defecto
  paths                  Enseña las rutas de configuración y claves
  keys add NOMBRE        Crea una clave y la enseña UNA sola vez
  keys list              Lista las claves (nombre y fecha; nunca la clave)
  keys remove NOMBRE     Revoca una clave";

fn main() -> ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    match run(arguments) {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("{message}");
            ExitCode::FAILURE
        }
    }
}

fn run(mut arguments: Vec<String>) -> Result<(), String> {
    let mut directory: Option<PathBuf> = None;
    if arguments.first().map(String::as_str) == Some("--dir") {
        if arguments.len() < 2 {
            return Err(format!("Falta el directorio tras --dir.\n{USAGE}"));
        }
        directory = Some(PathBuf::from(arguments.remove(1)));
        arguments.remove(0);
    }
    let directory = directory
        .or_else(Paths::default_dir)
        .ok_or("No se pudo determinar el directorio de datos; usa --dir.")?;
    let paths = Paths::in_dir(directory);

    let words: Vec<&str> = arguments.iter().map(String::as_str).collect();
    match words.as_slice() {
        ["serve"] => serve(paths),
        ["init"] => init(&paths),
        ["paths"] => {
            print_paths(&paths);
            Ok(())
        }
        ["keys", "add", name] => keys_add(&paths, name),
        ["keys", "list"] => keys_list(&paths),
        ["keys", "remove", name] => keys_remove(&paths, name),
        _ => Err(USAGE.to_string()),
    }
}

fn print_paths(paths: &Paths) {
    println!("directorio:    {}", paths.dir.display());
    println!("configuración: {}", paths.config.display());
    println!("claves:        {}", paths.keys.display());
}

fn init(paths: &Paths) -> Result<(), String> {
    let created = Config::write_default_if_missing(&paths.config)
        .map_err(|error| format!("No se pudo crear {}: {error}", paths.config.display()))?;
    println!(
        "{}",
        if created { "Creada la configuración por defecto." } else { "La configuración ya existía; no se toca." }
    );
    print_paths(paths);
    Ok(())
}

fn keys_add(paths: &Paths, name: &str) -> Result<(), String> {
    let key = KeyStore::new(paths.keys.clone())
        .add(name)
        .map_err(|error| format!("No se pudo crear la clave: {error}"))?;
    println!("Clave '{name}' creada. Guárdala ahora: no se puede volver a ver.\n");
    println!("{key}");
    Ok(())
}

fn keys_list(paths: &Paths) -> Result<(), String> {
    let entries = KeyStore::new(paths.keys.clone())
        .list()
        .map_err(|error| format!("No se pudieron leer las claves: {error}"))?;
    if entries.is_empty() {
        println!("No hay ninguna clave: la pasarela rechazará todas las peticiones.");
    }
    for entry in entries {
        println!(
            "{:<24} creada {}  hash {}…",
            entry.name,
            logging::utc_timestamp(entry.created_unix),
            &entry.sha256[..entry.sha256.len().min(12)]
        );
    }
    Ok(())
}

fn keys_remove(paths: &Paths, name: &str) -> Result<(), String> {
    let removed = KeyStore::new(paths.keys.clone())
        .remove(name)
        .map_err(|error| format!("No se pudo revocar la clave: {error}"))?;
    if removed {
        println!("Clave '{name}' revocada.");
        Ok(())
    } else {
        Err(format!("No existe ninguna clave llamada '{name}'."))
    }
}

fn serve(paths: Paths) -> Result<(), String> {
    Config::write_default_if_missing(&paths.config)
        .map_err(|error| format!("No se pudo crear {}: {error}", paths.config.display()))?;
    let config = Config::load(&paths.config).map_err(|error| error.to_string())?;
    let keys = KeyStore::new(paths.keys.clone());

    if keys.list().map(|entries| entries.is_empty()).unwrap_or(true) {
        logging::line(&format!(
            "AVISO: no hay ninguna clave en {}: todas las peticiones darán 401. Crea una con `llm-gateway keys add NOMBRE`.",
            paths.keys.display()
        ));
    }
    match config.listen.parse::<SocketAddr>() {
        Ok(address) if !address.ip().is_loopback() => logging::line(&format!(
            "AVISO: escucha en {address}, fuera de loopback: cualquier equipo de la red podrá intentar autenticarse."
        )),
        _ => {}
    }

    // Un fallo al abrir el registro de decisiones no impide servir: se avisa y se sigue sin él.
    let decisions = DecisionLog::to_file(&paths.decisions).unwrap_or_else(|error| {
        logging::line(&format!(
            "AVISO: no se pudo abrir {}: {error}. El modelo `auto` funcionará sin registrar decisiones.",
            paths.decisions.display()
        ));
        DecisionLog::disabled()
    });

    let runtime = tokio::runtime::Runtime::new().map_err(|error| format!("No se pudo crear el runtime: {error}"))?;
    runtime.block_on(async move {
        let listener = tokio::net::TcpListener::bind(&config.listen)
            .await
            .map_err(|error| format!("No se pudo escuchar en {}: {error} (¿ya hay otra pasarela?)", config.listen))?;
        logging::line(&format!(
            "pasarela escuchando en http://{} con {} modelo(s) configurado(s)",
            config.listen,
            config.backends.len()
        ));
        axum::serve(
            listener,
            build_app_with_reload(config, keys, decisions, paths.config.clone()),
        )
            .with_graceful_shutdown(async {
                let _ = tokio::signal::ctrl_c().await;
                logging::line("cerrando");
            })
            .await
            .map_err(|error| format!("La pasarela se detuvo con un error: {error}"))
    })
}
