//! Host WiFi de diagnostico: levanta el mismo `TransportHost` que la app y
//! imprime CADA evento de sesion que emite, sin Flutter de por medio.
//!
//! Sirve para localizar de que lado esta un problema cuando el telefono
//! "hace algo" y la app no reacciona: si el evento aparece aca, el
//! transporte esta bien y hay que mirar el lado Dart; si no aparece, el
//! problema es del transporte.
//!
//! Reusa la identidad TLS persistida (`ProjectDirs`), asi que el
//! fingerprint es el mismo que el de la app y un telefono ya emparejado
//! reconecta sin volver a pedir PIN. Los ids autorizados se pasan por
//! argumento porque la tabla `devices` vive en Drift, del lado Dart:
//!
//! `cargo run -p nexodeck-transport --example wifi_host_watch -- <device_id>...`

use std::time::Duration;

use nexodeck_protocol::RemoteAction;
use nexodeck_transport::server::{
    ConnectionEvent, HostConfig, PairingEvent, TransportHost, DEFAULT_PORT,
};

/// Mismo valor que `Platform.localHostname` del lado Dart.
fn hostname() -> String {
    std::env::var("COMPUTERNAME")
        .or_else(|_| std::env::var("HOSTNAME"))
        .unwrap_or_else(|_| "NexoDeck".into())
}

#[tokio::main(flavor = "multi_thread")]
async fn main() {
    // Acotado a este crate: `mdns-sd` en debug emite decenas de lineas por
    // segundo y tapa lo unico que interesa. En `warn` entra el rechazo de
    // reconexion, que no tiene evento propio y de otro modo es invisible.
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or("nexodeck_transport=warn"),
    )
    .init();

    // `--pair` arma el pairing y acepta automaticamente al primer
    // dispositivo que lo pida. Existe para poder correr el flujo COMPLETO
    // de punta a punta sin la app de escritorio: el rol PC necesita dos
    // acciones humanas (armar y confirmar) que de otro modo solo se pueden
    // dar con clics, y no hay automatizacion de UI de escritorio en este
    // entorno. El lado Android si se puede manejar con `adb shell input`.
    //
    // Auto-confirmar es aceptable AQUI y solo aqui: es un binario de
    // diagnostico que el desarrollador corre a proposito. La app real
    // muestra el PIN y espera la confirmacion humana, que es lo que hace
    // que el PIN sirva de algo.
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let auto_pair = args.iter().any(|a| a == "--pair");
    args.retain(|a| a != "--pair");
    let authorized: Vec<String> = args;

    let host = TransportHost::start(HostConfig {
        // El nombre NO es cosmetico: el rol Android reconecta buscando por
        // nombre de instancia mDNS contra el que guardo al emparejar (ver
        // las simplificaciones de Fase 4), asi que si este host se anuncia
        // distinto al de la app, el telefono nunca lo encuentra. Se toma el
        // hostname igual que `main.dart`.
        device_name: hostname(),
        port: DEFAULT_PORT,
    })
    .await
    .expect("el host deberia arrancar");

    if authorized.is_empty() {
        println!("sin device_ids autorizados: solo se podra emparejar de cero");
    } else {
        println!("autorizando {} dispositivo(s)", authorized.len());
        host.sync_authorized_devices(authorized.into_iter().map(|id| (id, true)).collect());
    }

    println!("fingerprint: {}", host.cert_fingerprint());
    println!("escuchando en el puerto {}", host.port());

    if auto_pair {
        match host.arm_pairing() {
            Ok(pin) => println!("PIN: {pin}  (se aceptara automaticamente)"),
            Err(e) => println!("no se pudo armar el pairing: {e}"),
        }
    }
    println!();

    let mut pairing = host.pairing_events();
    let mut connection = host.connection_events();

    loop {
        tokio::select! {
            ev = pairing.recv() => match ev {
                Ok(ev) => {
                    println!("PAIRING    {ev:?}");
                    if auto_pair {
                        if let PairingEvent::DeviceRequestedPairing { .. } = &ev {
                            match host.confirm_pairing(true) {
                                Ok(()) => println!("           -> aceptado"),
                                Err(e) => println!("           -> no se pudo aceptar: {e}"),
                            }
                        }
                    }
                }
                Err(e) => { eprintln!("canal de pairing cerrado: {e}"); return; }
            },
            ev = connection.recv() => match ev {
                Ok(ev) => {
                    println!("CONNECTION {ev:?}");
                    // Sin catalogo el telefono muestra la grilla vacia y no
                    // hay nada que tocar, con lo cual no se puede observar
                    // el `ActionExecutionRequested` que es lo que se quiere
                    // diagnosticar. Se empuja uno de mentira.
                    if let ConnectionEvent::DeviceConnected { device_id } = &ev {
                        let catalogo = vec![
                            RemoteAction {
                                id: "diagnostico-1".into(),
                                name: "Accion de diagnostico".into(),
                                icon: "terminal".into(),
                                color_hex: "#6C5CE7".into(),
                                group_id: None,
                                group_name: None,
                                group_color_hex: None,
                                kind: nexodeck_protocol::RemoteActionKind::Terminal,
                                parameters: vec![],
                                step_count: 0,
                            },
                            // Segunda accion con parametros: sirve para
                            // ejercitar el prompt del telefono sin depender
                            // de la app de escritorio. Los valores cargados
                            // vuelven en el `ActionExecutionRequested` que
                            // se imprime arriba.
                            RemoteAction {
                                id: "diagnostico-params".into(),
                                name: "Con parametros".into(),
                                icon: "bolt".into(),
                                color_hex: "#EF4444".into(),
                                group_id: None,
                                group_name: None,
                                group_color_hex: None,
                                kind: nexodeck_protocol::RemoteActionKind::Terminal,
                                parameters: vec![
                                    nexodeck_protocol::RemoteActionParam {
                                        key: "mensaje".into(),
                                        label: "Mensaje".into(),
                                        kind: nexodeck_protocol::RemoteParamKind::Text,
                                        default_value: Some("hola".into()),
                                        options: vec![],
                                    },
                                    nexodeck_protocol::RemoteActionParam {
                                        key: "entorno".into(),
                                        label: "Entorno".into(),
                                        kind: nexodeck_protocol::RemoteParamKind::Select,
                                        default_value: None,
                                        options: vec!["staging".into(), "produccion".into()],
                                    },
                                ],
                                step_count: 0,
                            },
                        ];
                        match host.send_actions_catalog(device_id, catalogo) {
                            Ok(()) => println!("           -> catalogo de prueba enviado"),
                            Err(e) => println!("           -> no se pudo enviar el catalogo: {e}"),
                        }
                    }
                }
                Err(e) => { eprintln!("canal de conexion cerrado: {e}"); return; }
            },
            _ = tokio::time::sleep(Duration::from_secs(30)) => {
                println!("(sin eventos en 30s)");
            }
        }
    }
}
