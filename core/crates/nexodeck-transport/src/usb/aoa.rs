//! Handshake AOA (Android Open Accessory) del lado PC/host.
//!
//! AOA es el protocolo estandar de Android para que un host USB hable con el
//! telefono sin ADB ni Modo Desarrollador (ver
//! `docs/architecture-decision-records/0002-aoa-sobre-adb.md`). El handshake
//! son 3 control transfers vendor-specific sobre EP0 contra el telefono en su
//! modo normal; al tercero el telefono se DESCONECTA y se re-enumera con el
//! VID de Google y un PID de accessory mode, momento en el que pasa a ser un
//! dispositivo bulk generico (ver `bridge.rs`).

use std::time::Duration;

use nusb::transfer::{ControlIn, ControlOut, ControlType, Recipient};
use nusb::{Device, DeviceInfo, Interface};

use crate::error::{Result, TransportError};

/// VID de Google. El telefono se re-enumera con este VID al entrar en
/// accessory mode, sea cual sea su fabricante real.
pub const GOOGLE_VENDOR_ID: u16 = 0x18D1;

/// PIDs de accessory mode (`f_accessory.c` en AOSP). Los cuatro que nos
/// sirven llevan el canal de accessory; los que faltan del rango
/// (`0x2D02`/`0x2D03`) son solo audio + ADB, sin accessory, asi que no
/// exponen los endpoints bulk que necesitamos.
pub const PID_ACCESSORY: u16 = 0x2D00;
pub const PID_ACCESSORY_ADB: u16 = 0x2D01;
pub const PID_ACCESSORY_AUDIO: u16 = 0x2D04;
pub const PID_ACCESSORY_AUDIO_ADB: u16 = 0x2D05;

const REQ_GET_PROTOCOL: u8 = 51; // 0x33
const REQ_SEND_STRING: u8 = 52; // 0x34
const REQ_START: u8 = 53; // 0x35

const STRING_MANUFACTURER: u16 = 0;
const STRING_MODEL: u16 = 1;
const STRING_DESCRIPTION: u16 = 2;
const STRING_VERSION: u16 = 3;
const STRING_URI: u16 = 4;
const STRING_SERIAL: u16 = 5;

/// Los control transfers de EP0 son diminutos y el telefono responde en ms;
/// si no contesta en 2s es que no habla AOA (o que el driver que atendio la
/// interfaz no es WinUSB y esta tragando el request).
const CONTROL_TIMEOUT: Duration = Duration::from_secs(2);

/// Identidad que la PC le declara al telefono durante el handshake.
///
/// **`manufacturer` y `model` no son cosmeticos**: Android los matchea contra
/// el `accessory_filter.xml` de la app (Fase 5-D) para decidir a quien
/// entregarle el accessory. Si no coinciden exactamente, el telefono entra en
/// accessory mode igual pero ninguna app recibe el intent, y la sesion nunca
/// arranca. Cambiar estos defaults obliga a cambiar el XML del lado Android.
#[derive(Debug, Clone)]
pub struct AccessoryIdentity {
    pub manufacturer: String,
    pub model: String,
    pub description: String,
    pub version: String,
    /// Se le ofrece al usuario para descargar la app si ninguna matchea.
    /// `None` = no ofrecer nada.
    pub uri: Option<String>,
    pub serial: Option<String>,
}

impl Default for AccessoryIdentity {
    fn default() -> Self {
        Self {
            manufacturer: "NexoDeck".into(),
            model: "NexoDeck".into(),
            description: "Streamdeck virtual NexoDeck".into(),
            version: "1.0".into(),
            uri: None,
            serial: None,
        }
    }
}

/// `true` si el dispositivo YA esta en accessory mode (es decir, ya se le
/// hizo el handshake, posiblemente en una corrida anterior del programa: el
/// telefono se queda en ese modo mientras el cable siga conectado).
pub fn is_accessory_mode(vendor_id: u16, product_id: u16) -> bool {
    vendor_id == GOOGLE_VENDOR_ID
        && matches!(
            product_id,
            PID_ACCESSORY | PID_ACCESSORY_ADB | PID_ACCESSORY_AUDIO | PID_ACCESSORY_AUDIO_ADB
        )
}

/// Corre el handshake completo contra un telefono en modo normal.
///
/// Al volver `Ok(())` el telefono esta desconectandose para re-enumerarse:
/// el `Device`/`Interface` de aca adentro ya no sirven y se dropean. Quien
/// llama debe esperar a que aparezca el VID/PID de accessory (ver
/// `bridge::wait_for_accessory`).
pub async fn start_accessory_mode(info: &DeviceInfo, identity: &AccessoryIdentity) -> Result<()> {
    let device = info
        .open()
        .await
        .map_err(|e| map_open_error("abriendo el dispositivo", e))?;

    // En Windows los control transfers NO se pueden mandar por el handle del
    // dispositivo (limitacion de WinUSB, `Device::control_*` ni siquiera
    // existe en esa plataforma): hay que reclamar una interfaz y usar la
    // suya. Es el mismo camino en Linux/macOS, asi que no hay ramas por SO.
    let interface = claim_any_interface(&device, info).await?;

    let protocol = get_protocol(&interface).await?;
    if protocol == 0 {
        return Err(TransportError::UsbNotAoaCapable);
    }
    log::info!("AOA: el dispositivo soporta protocolo v{protocol}");

    send_strings(&interface, identity).await?;

    // `ACCESSORY_START` es el punto de no retorno: el telefono se desconecta
    // del bus para volver con otro VID/PID. Es normal que el status stage de
    // ESTE transfer no llegue nunca (el dispositivo ya se fue), asi que un
    // error aca no significa que haya fallado -- quien decide es la espera de
    // re-enumeracion. Solo lo logueamos.
    if let Err(e) = interface
        .control_out(
            ControlOut {
                control_type: ControlType::Vendor,
                recipient: Recipient::Device,
                request: REQ_START,
                value: 0,
                index: 0,
                data: &[],
            },
            CONTROL_TIMEOUT,
        )
        .await
    {
        log::debug!("AOA: ACCESSORY_START devolvio {e} (esperable: el dispositivo se re-enumera)");
    }

    Ok(())
}

/// Reclama la primera interfaz que el SO nos deje reclamar.
///
/// Cual sea da igual: los control transfers van a EP0 con
/// `Recipient::Device`, la interfaz es solo el handle que Windows exige. Lo
/// que importa es el modo de fallar: si NINGUNA se puede reclamar por
/// `Unsupported`, es el caso del ADR 0002 (un driver de fabricante atado a
/// todo el compuesto) y hay que instalar WinUSB con `libwdi` antes de poder
/// hablarle -- se distingue con su propio error para que la UI ofrezca eso en
/// vez de mostrar un "error de USB" generico.
async fn claim_any_interface(device: &Device, info: &DeviceInfo) -> Result<Interface> {
    let numbers: Vec<u8> = info.interfaces().map(|i| i.interface_number()).collect();
    // Si el SO no cacheo las interfaces, al menos intentar la 0.
    let numbers = if numbers.is_empty() { vec![0] } else { numbers };

    let mut blocked = false;
    let mut last_error = None;

    for number in numbers {
        match device.claim_interface(number).await {
            Ok(interface) => return Ok(interface),
            Err(e) => {
                if e.kind() == nusb::ErrorKind::Unsupported {
                    blocked = true;
                }
                log::debug!("AOA: no se pudo reclamar la interfaz {number}: {e}");
                last_error = Some(e);
            }
        }
    }

    if blocked {
        return Err(TransportError::UsbDriverBlocked {
            vendor_id: info.vendor_id(),
            product_id: info.product_id(),
            driver: device_driver_name(info),
        });
    }

    Err(map_open_error(
        "reclamando una interfaz",
        last_error.expect("el loop corrio al menos una vez"),
    ))
}

async fn get_protocol(interface: &Interface) -> Result<u16> {
    let data = interface
        .control_in(
            ControlIn {
                control_type: ControlType::Vendor,
                recipient: Recipient::Device,
                request: REQ_GET_PROTOCOL,
                value: 0,
                index: 0,
                length: 2,
            },
            CONTROL_TIMEOUT,
        )
        .await
        // Un dispositivo que no habla AOA responde con STALL a este request;
        // no es un error de transporte, es "este USB no es un Android".
        .map_err(|_| TransportError::UsbNotAoaCapable)?;

    if data.len() < 2 {
        return Err(TransportError::UsbNotAoaCapable);
    }
    Ok(u16::from_le_bytes([data[0], data[1]]))
}

async fn send_strings(interface: &Interface, identity: &AccessoryIdentity) -> Result<()> {
    // manufacturer y model son obligatorios; el resto es opcional pero
    // barato de mandar y ayuda a que el usuario entienda que le esta pidiendo
    // permiso el telefono.
    let mut strings = vec![
        (STRING_MANUFACTURER, identity.manufacturer.as_str()),
        (STRING_MODEL, identity.model.as_str()),
        (STRING_DESCRIPTION, identity.description.as_str()),
        (STRING_VERSION, identity.version.as_str()),
    ];
    if let Some(uri) = &identity.uri {
        strings.push((STRING_URI, uri.as_str()));
    }
    if let Some(serial) = &identity.serial {
        strings.push((STRING_SERIAL, serial.as_str()));
    }

    for (index, value) in strings {
        let payload = nul_terminated(value);
        interface
            .control_out(
                ControlOut {
                    control_type: ControlType::Vendor,
                    recipient: Recipient::Device,
                    request: REQ_SEND_STRING,
                    value: 0,
                    index,
                    data: &payload,
                },
                CONTROL_TIMEOUT,
            )
            .await
            .map_err(|e| TransportError::Usb(format!("enviando string AOA {index}: {e}")))?;
    }

    Ok(())
}

/// AOA espera strings UTF-8 **terminados en NUL** (`f_accessory.c` copia
/// hasta el NUL); mandar el string "pelado" de Rust deja al kernel leyendo
/// basura o truncando.
fn nul_terminated(value: &str) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(value.len() + 1);
    bytes.extend_from_slice(value.as_bytes());
    bytes.push(0);
    bytes
}

#[cfg(target_os = "windows")]
fn device_driver_name(info: &DeviceInfo) -> Option<String> {
    info.driver().map(|d| d.to_string())
}

#[cfg(not(target_os = "windows"))]
fn device_driver_name(_info: &DeviceInfo) -> Option<String> {
    None
}

fn map_open_error(context: &str, error: nusb::Error) -> TransportError {
    match error.kind() {
        // Linux sin la regla de udev: el dispositivo esta ahi pero no
        // tenemos permiso de hablarle.
        nusb::ErrorKind::PermissionDenied => TransportError::Usb(format!(
            "{context}: permiso denegado (falta la regla de udev para 18d1)"
        )),
        _ => TransportError::Usb(format!("{context}: {error}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accessory_pids_reconocidos() {
        assert!(is_accessory_mode(GOOGLE_VENDOR_ID, PID_ACCESSORY));
        assert!(is_accessory_mode(GOOGLE_VENDOR_ID, PID_ACCESSORY_ADB));
        assert!(is_accessory_mode(GOOGLE_VENDOR_ID, PID_ACCESSORY_AUDIO));
        assert!(is_accessory_mode(GOOGLE_VENDOR_ID, PID_ACCESSORY_AUDIO_ADB));
    }

    #[test]
    fn telefono_en_modo_normal_no_es_accessory() {
        // Samsung en modo normal (el del spike del ADR 0002).
        assert!(!is_accessory_mode(0x04E8, 0x6860));
        // Los PIDs de solo-audio del mismo rango de Google no llevan el
        // canal de accessory, asi que no nos sirven.
        assert!(!is_accessory_mode(GOOGLE_VENDOR_ID, 0x2D02));
        assert!(!is_accessory_mode(GOOGLE_VENDOR_ID, 0x2D03));
        // Un Pixel en modo normal tiene VID de Google pero PID cualquiera.
        assert!(!is_accessory_mode(GOOGLE_VENDOR_ID, 0x4EE1));
    }

    #[test]
    fn strings_aoa_van_terminados_en_nul() {
        assert_eq!(nul_terminated("NexoDeck"), b"NexoDeck\0");
        assert_eq!(nul_terminated(""), b"\0");
    }
}
