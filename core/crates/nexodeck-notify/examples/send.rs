//! Manda un aviso por un canal de tipo script de bash, sin Flutter de por
//! medio.
//!
//! Existe por el mismo motivo que `cargo run -p nexodeck-hardware --example
//! snapshot`: cuando un aviso no llega, hay que poder separar "el canal esta
//! mal configurado" de "el destino esta caido" sin abrir la app.
//!
//! ```sh
//! cargo run -p nexodeck-notify --example send -- <ruta-del-script> "<texto>"
//! cargo run -p nexodeck-notify --example send -- <ruta-del-script> "<texto>" --seco
//! ```
//!
//! Con `--seco` compone y explica lo que ejecutaria, sin ejecutar nada. La ruta
//! del script va en formato de bash (`/d/...`) y el script tiene que aceptar el
//! texto por su entrada estandar, como hace `avisar.sh` con `-`.

use nexodeck_notify::{
    CommandChannel, MessageDelivery, Notifier, NotifyLevel, NotifyRequest,
};

/// Ruta corta 8.3 de Git Bash. Con la larga habria que citarla y las comillas
/// quedarian anidadas con las del `-lc`.
const GIT_BASH: &str = r"C:\PROGRA~1\Git\bin\bash.exe";

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let dry_run = args.iter().any(|a| a == "--seco");
    let positional: Vec<&String> = args.iter().filter(|a| !a.starts_with("--")).collect();

    let (Some(script), Some(text)) = (positional.first(), positional.get(1)) else {
        eprintln!("uso: send -- <ruta-del-script-en-formato-bash> \"<texto>\" [--seco]");
        std::process::exit(2);
    };

    let channel = CommandChannel {
        id: "diagnostico".into(),
        label: "Diagnostico".into(),
        program: GIT_BASH.into(),
        // `-l` fija HOME, sin lo cual el `ssh` del script no encuentra su
        // `~/.ssh/config`. La ruta del script viaja como `$0` y el texto por
        // stdin: asi ningun shell llega a parsear el mensaje.
        args: vec![
            "-lc".into(),
            r#"bash "$0" -"#.into(),
            (*script).clone(),
        ],
        delivery: MessageDelivery::Stdin,
        min_level: NotifyLevel::Milestone,
        timeout_secs: Some(60),
        enabled: true,
    };

    let outcomes = Notifier::new(vec![channel])
        .send(&NotifyRequest {
            text: (*text).clone(),
            level: NotifyLevel::Always,
            dry_run,
        })
        .await;

    let mut failed = false;
    for outcome in &outcomes {
        if outcome.dry_run {
            println!("ENSAYO EN SECO -> {}", outcome.detail);
        } else if outcome.delivered {
            println!("ENTREGADO en {} ms", outcome.elapsed_ms);
        } else {
            failed = true;
            println!(
                "NO ENTREGADO (codigo {:?}) tras {} ms: {}",
                outcome.exit_code, outcome.elapsed_ms, outcome.detail
            );
        }
    }

    // Codigo distinto de 0 si no se entrego, igual que `avisar.sh`: un aviso no
    // entregado no se puede parecer a uno entregado, tampoco aca.
    if failed {
        std::process::exit(1);
    }
}
