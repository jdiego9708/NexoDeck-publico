//! Diagnostico del bus USB, para depurar la Fase 5 sin levantar la app.
//!
//! Es de SOLO LECTURA: enumera y clasifica, nunca abre ni reclama una
//! interfaz. Eso importa -- reclamar la interfaz de un mouse o un teclado se
//! la sacaria a su driver mientras dure el intento, asi que este ejemplo
//! sirve justamente para confirmar contra un bus real que la heuristica de
//! `looks_like_android` no marca como candidato nada que no sea un telefono,
//! antes de dejar que el puente le hable a algo.
//!
//! `cargo run -p nexodeck-transport --example usb_scan`

use nexodeck_transport::usb::{
    aoa,
    bridge::{looks_like_android_interfaces, probe_accessory_endpoints},
};

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let devices: Vec<_> = match nusb::list_devices().await {
        Ok(devices) => devices.collect(),
        Err(e) => {
            eprintln!("no se pudo listar el bus USB: {e}");
            return;
        }
    };

    println!("{} dispositivos en el bus\n", devices.len());

    for device in &devices {
        let vid = device.vendor_id();
        let pid = device.product_id();
        let interfaces: Vec<(u8, u8, u8)> = device
            .interfaces()
            .map(|i| (i.class(), i.subclass(), i.protocol()))
            .collect();

        let veredicto = if aoa::is_accessory_mode(vid, pid) {
            "ACCESSORY MODE (listo para abrir el canal bulk)"
        } else if looks_like_android_interfaces(&interfaces) {
            "candidato: se le intentaria el handshake AOA"
        } else {
            "ignorado"
        };

        println!(
            "{vid:04x}:{pid:04x}  {:<28} {:<24} -> {veredicto}",
            device.product_string().unwrap_or("(sin nombre)"),
            device.manufacturer_string().unwrap_or("(sin fabricante)"),
        );
        for (class, subclass, protocol) in &interfaces {
            println!("            interfaz class={class:02x} subclass={subclass:02x} protocol={protocol:02x}");
        }

        // Contra un telefono que ya esta en accessory mode se puede verificar
        // lo unico que no cubren los tests: que el driver del lado Windows
        // permita reclamar la interfaz y que los endpoints bulk esten donde
        // se los espera. Es lo maximo que se puede probar sin la app de
        // Android (Fase 5-D) del otro lado del cable.
        if aoa::is_accessory_mode(vid, pid) {
            match probe_accessory_endpoints(device).await {
                Ok((bulk_in, bulk_out)) => println!(
                    "            canal bulk OK: IN=0x{bulk_in:02x} OUT=0x{bulk_out:02x}"
                ),
                Err(e) => println!("            no se pudo abrir el canal bulk: {e}"),
            }
        }
    }
}
