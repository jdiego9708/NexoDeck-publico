//! Rol Android del transporte USB: corre la sesion sobre el file descriptor
//! crudo del accessory.
//!
//! El fd lo consigue Kotlin (`UsbManager.openAccessory()` ->
//! `ParcelFileDescriptor.detachFd()`) y viaja hasta aca como un simple
//! entero, por MethodChannel + FFI. **Los bytes del protocolo nunca pasan
//! por Dart**: Dart solo transporta el numero del fd una vez, y de ahi en
//! adelante Rust lee y escribe directo sobre el.

use std::os::fd::{FromRawFd, RawFd};

use nexodeck_protocol::{DevicePlatformWire, MessageV1};

use crate::client;
use crate::error::Result;
use crate::usb::framing::FramedUsb;
use crate::usb::session::UsbSession;

/// Toma posesion del fd del accessory y corre la sesion hasta que el cable
/// se desconecta (o la PC cierra).
///
/// `paired_device_id` decide el primer mensaje, igual que en WiFi: si ya
/// hubo pairing, se reconecta con ese id; si no, se pide uno nuevo.
///
/// # Safety
///
/// El `fd` tiene que venir de `ParcelFileDescriptor.detachFd()`, que
/// renuncia explicitamente a la propiedad del descriptor. Pasar un fd que
/// sigue siendo de otro dueño (por ejemplo el de un `ParcelFileDescriptor`
/// vivo) termina en un doble close.
pub async fn connect_over_accessory_fd(
    fd: RawFd,
    device_name: String,
    paired_device_id: Option<String>,
) -> Result<()> {
    // SAFETY: contrato documentado arriba -- Kotlin ya solto el fd.
    let std_file = unsafe { std::fs::File::from_raw_fd(fd) };
    // `tokio::fs::File` atiende cada lectura/escritura en el pool de
    // bloqueo, que es justo lo que hace falta aca: el fd del accessory es un
    // char device (`/dev/usb_accessory`), no un socket, asi que no se puede
    // registrar en el reactor de tokio ni tratar como pipe (`tokio::net::
    // unix::pipe` exige un FIFO y lo rechazaria).
    let file = tokio::fs::File::from_std(std_file);
    let session = UsbSession(FramedUsb::new(file));

    let first = match paired_device_id {
        Some(device_id) => MessageV1::Reconnect { device_id },
        None => MessageV1::PairHello {
            device_name,
            platform: DevicePlatformWire::Android,
        },
    };

    client::client().run_over_session(session, first).await
}
