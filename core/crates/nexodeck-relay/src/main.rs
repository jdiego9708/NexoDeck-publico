//! `nexodeck-relay --port <puerto> [--allow-token <hex>]...`
//!
//! Un solo binario, sin estado en disco y sin archivo de configuracion:
//! mover el relay a otro VPS es copiar este ejecutable, dejar una unidad de
//! systemd y abrir un puerto.

use std::collections::HashSet;

use nexodeck_relay::{hello, serve, RelayConfig};

#[tokio::main(flavor = "multi_thread")]
async fn main() {
    let mut port: u16 = 58644;
    let mut allowed: HashSet<[u8; hello::TOKEN_LEN]> = HashSet::new();
    let mut max_connections = 64usize;

    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--port" => {
                i += 1;
                match args.get(i).and_then(|v| v.parse().ok()) {
                    Some(p) => port = p,
                    None => fatal("--port necesita un numero de puerto"),
                }
            }
            "--allow-token" => {
                i += 1;
                let hex = args.get(i).cloned().unwrap_or_default();
                match hello::token_from_hex(&hex) {
                    Some(t) => {
                        allowed.insert(t);
                    }
                    None => fatal("--allow-token necesita 64 caracteres hexadecimales"),
                }
            }
            "--max-connections" => {
                i += 1;
                match args.get(i).and_then(|v| v.parse().ok()) {
                    Some(n) => max_connections = n,
                    None => fatal("--max-connections necesita un numero"),
                }
            }
            "--help" | "-h" => {
                println!(
                    "uso: nexodeck-relay [--port N] [--allow-token <hex64>]... [--max-connections N]"
                );
                return;
            }
            otro => fatal(&format!("argumento desconocido: {otro}")),
        }
        i += 1;
    }

    let listener = match tokio::net::TcpListener::bind(("0.0.0.0", port)).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("no se pudo escuchar en el puerto {port}: {e}");
            std::process::exit(1);
        }
    };

    if allowed.is_empty() {
        eprintln!(
            "AVISO: sin --allow-token, cualquiera que conozca esta direccion puede \
             usar el relay como punto de encuentro para su propio trafico."
        );
    }
    println!(
        "nexodeck-relay escuchando en 0.0.0.0:{port} (tokens permitidos: {}, tope {max_connections})",
        if allowed.is_empty() {
            "todos".to_string()
        } else {
            allowed.len().to_string()
        }
    );

    serve(
        listener,
        RelayConfig {
            allowed_tokens: if allowed.is_empty() {
                None
            } else {
                Some(allowed)
            },
            max_connections,
            ..RelayConfig::default()
        },
    )
    .await;
}

fn fatal(msg: &str) -> ! {
    eprintln!("{msg}");
    std::process::exit(2);
}
