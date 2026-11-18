//! Superficie FFI del transporte USB (Fase 5).
//!
//! Las dos funciones existen en las dos plataformas a proposito, aunque cada
//! una solo tenga sentido en una: `flutter_rust_bridge` genera el glue para
//! todos los targets a partir de las mismas firmas, asi que cfg-ear las
//! funciones enteras rompe el link del lado que falta. El patron del
//! proyecto (ver `paste_to_clipboard` en `nexodeck-actions`) es firma unica
//! y cuerpo gateado, devolviendo un error claro en la plataforma que no
//! corresponde.

use crate::frb_generated::StreamSink;

/// Estado del **cable**, no de la sesion: los `ConnectionEvent` de una
/// sesion que entro por USB salen por `watch_connection_events` como
/// cualquier otra (misma `TransportHost`), asi que esto solo cubre lo que es
/// especifico del USB -- sobre todo `DriverBlocked`, que es el unico que
/// necesita una accion del usuario.
#[derive(Debug, Clone)]
pub enum UsbEvent {
    PhoneDetected {
        vendor_id: u16,
        product_id: u16,
        product: Option<String>,
    },
    /// Windows tiene atado un driver que no es WinUSB al dispositivo, asi
    /// que no se le puede hablar hasta instalarlo (ver ADR 0002). El puente
    /// sigue reintentando en silencio: apenas cambie el driver, conecta solo.
    DriverBlocked {
        vendor_id: u16,
        product_id: u16,
        driver: Option<String>,
    },
    AccessoryModeStarted,
    AccessoryConnected,
    AccessoryDisconnected,
    Failed {
        detail: String,
    },
}

#[cfg(not(target_os = "android"))]
impl From<nexodeck_transport::usb::UsbEvent> for UsbEvent {
    fn from(e: nexodeck_transport::usb::UsbEvent) -> Self {
        use nexodeck_transport::usb::UsbEvent as E;
        match e {
            E::PhoneDetected {
                vendor_id,
                product_id,
                product,
            } => UsbEvent::PhoneDetected {
                vendor_id,
                product_id,
                product,
            },
            E::DriverBlocked {
                vendor_id,
                product_id,
                driver,
            } => UsbEvent::DriverBlocked {
                vendor_id,
                product_id,
                driver,
            },
            E::AccessoryModeStarted => UsbEvent::AccessoryModeStarted,
            E::AccessoryConnected => UsbEvent::AccessoryConnected,
            E::AccessoryDisconnected => UsbEvent::AccessoryDisconnected,
            E::Failed { detail } => UsbEvent::Failed { detail },
        }
    }
}

/// Rol PC: eventos del puente USB. En Android no hay puente (el cable lo
/// abre el sistema operativo y avisa por intent), asi que el stream queda
/// abierto sin emitir nada en vez de mentir con un error.
pub async fn watch_usb_events(sink: StreamSink<UsbEvent>) {
    #[cfg(not(target_os = "android"))]
    {
        let Some(bridge) = nexodeck_transport::usb::bridge() else {
            // El puente lo levanta `start_transport_host`; si todavia no
            // corrio, no hay a que suscribirse.
            return;
        };
        // Primero el estado actual: los eventos del cable se emiten una sola
        // vez por dispositivo, asi que un stream que abre despues (la UI se
        // monta cuando el usuario entra a la pantalla, no al arrancar la
        // app) se perderia el `DriverBlocked` que ya paso.
        let mut rx = bridge.events();
        if let Some(current) = bridge.last_event() {
            if sink.add(UsbEvent::from(current)).is_err() {
                return;
            }
        }
        while let Ok(event) = rx.recv().await {
            if sink.add(UsbEvent::from(event)).is_err() {
                break;
            }
        }
    }
    #[cfg(target_os = "android")]
    {
        let _ = sink;
        std::future::pending::<()>().await;
    }
}

/// Rol Android: arranca la sesion sobre el fd del accessory que entrego
/// `UsbManager.openAccessory()` del lado Kotlin. Bloquea (async) hasta que
/// el cable se desconecta.
///
/// `paired_device_id` viene de la tabla `devices` de Drift: si ya hubo
/// pairing con esta PC se reconecta con ese id, y si no, se pide uno nuevo
/// con el mismo flujo de PIN que por WiFi.
pub async fn start_usb_accessory_session(
    fd: i32,
    device_name: String,
    paired_device_id: Option<String>,
) -> Result<(), String> {
    #[cfg(target_os = "android")]
    {
        nexodeck_transport::usb::connect_over_accessory_fd(fd, device_name, paired_device_id)
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = (fd, device_name, paired_device_id);
        Err("las sesiones por accessory USB solo existen en Android".into())
    }
}
