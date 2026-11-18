//! Corre el puente USB real (escaneo + handshake + sesion) fuera de la app y
//! muestra sus eventos, para depurar la Fase 5 sin Flutter de por medio.
//!
//! A diferencia de `usb_scan`, esto SI le habla al telefono: hace el
//! handshake AOA contra el primer candidato que encuentre. Con la app de
//! Android (Fase 5-D) del otro lado, deberia terminar en
//! `AccessoryConnected` y de ahi en adelante corre el pairing normal.
//!
//! `cargo run -p nexodeck-transport --example usb_bridge_watch`

use std::time::Duration;

use nexodeck_transport::server::{HostConfig, TransportHost};
use nexodeck_transport::usb::{AccessoryIdentity, UsbBridge};

#[tokio::main(flavor = "multi_thread")]
async fn main() {
    // Los `log::debug!` del handshake son el diagnostico util cuando el
    // claim falla (dicen que interfaz se intento y con que error); sin
    // logger inicializado se descartan y solo queda el evento generico.
    //
    // El filtro va acotado a este crate a proposito: `mdns-sd` en `debug`
    // emite decenas de lineas por segundo (probing, tiebreaking) y tapa por
    // completo lo unico que interesa aca, que es el cable.
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or("nexodeck_transport=debug"),
    )
    .init();

    // Puerto 0 y no 58643: asi no choca con la app de escritorio si esta
    // abierta -- lo que se quiere ejercitar aca es el cable, no el WiFi.
    let host = TransportHost::start(HostConfig {
        device_name: "NexoDeck (diagnostico USB)".into(),
        port: 0,
    })
    .await
    .expect("el host de transporte deberia arrancar");

    let bridge = UsbBridge::start(host, AccessoryIdentity::default());
    let mut events = bridge.events();

    println!("escaneando el bus USB, Ctrl-C para salir...\n");
    loop {
        match tokio::time::timeout(Duration::from_secs(30), events.recv()).await {
            Ok(Ok(event)) => println!("{event:?}"),
            Ok(Err(e)) => {
                eprintln!("el canal de eventos se cerro: {e}");
                return;
            }
            Err(_) => println!("(sin eventos nuevos en 30s)"),
        }
    }
}
