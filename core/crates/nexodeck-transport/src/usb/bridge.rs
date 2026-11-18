//! Puente USB del lado PC: encuentra el telefono, lo pone en accessory mode
//! y corre encima el MISMO loop de sesion que ya usa WiFi.
//!
//! Todo lo que sigue al handshake es reuso puro: `FramedUsb` enmarca los
//! mensajes sobre el canal bulk, `UsbSession` implementa `SessionTransport`,
//! y `server::dispatch_first_message` decide pairing vs reconexion y corre la
//! sesion. Los eventos de sesion (`ConnectionEvent::DeviceConnected`, etc.)
//! salen por el mismo `TransportHost` que WiFi, asi que la capa de arriba no
//! necesita saber por donde entro el dispositivo. Lo unico propio de USB son
//! los `UsbEvent` de aca abajo, que describen el estado del CABLE (no de la
//! sesion) para que la UI pueda pedir el driver cuando haga falta.

use std::collections::HashSet;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use nusb::descriptors::TransferType;
use nusb::transfer::{Bulk, Direction, In, Out};
use nusb::{DeviceId, DeviceInfo, Interface};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::sync::broadcast;

use crate::error::{Result, TransportError};
use crate::server::TransportHost;
use crate::usb::aoa::{self, AccessoryIdentity};
use crate::usb::framing::FramedUsb;
use crate::usb::session::UsbSession;
use crate::usb::stream::UsbStream;

/// Cada cuanto se re-escanea el bus. Un cable no se conecta 10 veces por
/// segundo: 2s es imperceptible para el usuario y mantiene el escaneo lejos
/// de ser un busy-loop. Se prefiere esto a `nusb::watch_devices()` porque el
/// mismo loop tiene que cubrir la re-enumeracion post-handshake (el
/// dispositivo desaparece y vuelve con otro VID/PID), y un unico camino de
/// deteccion es mas facil de razonar que dos.
const SCAN_INTERVAL: Duration = Duration::from_secs(2);

/// Cuanto se espera a que el telefono vuelva al bus despues de
/// `ACCESSORY_START`. En el spike del ADR 0002 tardo ~1s; 10s es holgado y
/// evita quedarse colgado si el handshake en realidad fallo.
const REENUMERATION_TIMEOUT: Duration = Duration::from_secs(10);
const REENUMERATION_POLL: Duration = Duration::from_millis(250);

/// Estado del cable, complementario a los `ConnectionEvent` de la sesion.
#[derive(Debug, Clone)]
pub enum UsbEvent {
    /// Se detecto un dispositivo que parece un Android en modo normal.
    PhoneDetected {
        vendor_id: u16,
        product_id: u16,
        product: Option<String>,
    },
    /// El SO no nos deja reclamar ninguna interfaz del dispositivo: hay un
    /// driver de fabricante atado (caso normal en Windows, ver ADR 0002).
    /// La UI deberia ofrecer instalar WinUSB con `libwdi` -- el puente sigue
    /// reintentando solo, asi que apenas el driver cambie, conecta.
    DriverBlocked {
        vendor_id: u16,
        product_id: u16,
        driver: Option<String>,
    },
    /// Handshake AOA aceptado; el telefono se esta re-enumerando.
    AccessoryModeStarted,
    /// Canal bulk abierto: a partir de aca corre la sesion normal.
    AccessoryConnected,
    /// Se cerro el canal (cable desenchufado, app cerrada del otro lado).
    AccessoryDisconnected,
    Failed {
        detail: String,
    },
}

pub struct UsbBridge {
    events_tx: broadcast::Sender<UsbEvent>,
    /// Ultimo evento emitido, para que quien se suscriba tarde igual sepa en
    /// que estado esta el cable.
    ///
    /// Hace falta porque el escaneo reporta cada cosa **una sola vez** (ver
    /// `ScanMemory`): si la UI abre su stream despues de que se emitio el
    /// `DriverBlocked`, sin esto no se entera nunca y el usuario no ve el
    /// aviso que justamente necesita. Detectado probando la app de verdad:
    /// el banner quedaba vacio con el telefono bloqueado enchufado.
    last_event: Mutex<Option<UsbEvent>>,
}

static BRIDGE: OnceLock<Arc<UsbBridge>> = OnceLock::new();

pub fn bridge() -> Option<Arc<UsbBridge>> {
    BRIDGE.get().cloned()
}

impl UsbBridge {
    /// Arranca el escaneo en segundo plano. Idempotente: llamarlo dos veces
    /// devuelve el mismo puente, sin lanzar un segundo loop (dos loops
    /// peleandose por reclamar la misma interfaz seria un lindo bug
    /// intermitente).
    pub fn start(host: Arc<TransportHost>, identity: AccessoryIdentity) -> Arc<UsbBridge> {
        if let Some(existing) = BRIDGE.get() {
            return existing.clone();
        }

        let (events_tx, _) = broadcast::channel(32);
        let bridge = Arc::new(UsbBridge {
            events_tx: events_tx.clone(),
            last_event: Mutex::new(None),
        });

        match BRIDGE.set(bridge.clone()) {
            Ok(()) => {
                let scan_bridge = bridge.clone();
                tokio::spawn(async move {
                    scan_loop(host, scan_bridge, identity).await;
                });
                bridge
            }
            // Otra tarea gano la carrera: usamos la suya y no lanzamos loop.
            Err(_) => BRIDGE.get().expect("se acaba de setear").clone(),
        }
    }

    pub fn events(&self) -> broadcast::Receiver<UsbEvent> {
        self.events_tx.subscribe()
    }

    /// Estado actual del cable segun el ultimo evento emitido. Quien abre un
    /// stream nuevo deberia mandarlo primero, o se pierde todo lo que paso
    /// antes de suscribirse.
    pub fn last_event(&self) -> Option<UsbEvent> {
        self.last_event.lock().unwrap().clone()
    }

    fn emit(&self, event: UsbEvent) {
        *self.last_event.lock().unwrap() = Some(event.clone());
        let _ = self.events_tx.send(event);
    }
}

/// Marcas por dispositivo para no repetir trabajo ni spamear eventos en cada
/// vuelta del escaneo. Se limpian cuando el dispositivo desaparece del bus,
/// asi que desenchufar y volver a enchufar re-intenta todo desde cero.
///
/// **La clave es el `DeviceId` de nusb, no el par VID/PID**, y no es un
/// detalle teorico: dos Samsung distintos (una tablet y un telefono) se
/// presentan los dos como `04E8:6860`, asi que indexar por VID/PID hace que
/// marcar uno como "ya reportado" o "no habla AOA" silencie tambien al otro.
/// Verificado con los dos aparatos enchufados a la vez.
#[derive(Default)]
struct ScanMemory {
    not_aoa: HashSet<DeviceId>,
    reported_blocked: HashSet<DeviceId>,
    reported_detected: HashSet<DeviceId>,
    reported_failed: HashSet<DeviceId>,
}

impl ScanMemory {
    fn forget_absent(&mut self, present: &HashSet<DeviceId>) {
        self.not_aoa.retain(|id| present.contains(id));
        self.reported_blocked.retain(|id| present.contains(id));
        self.reported_detected.retain(|id| present.contains(id));
        self.reported_failed.retain(|id| present.contains(id));
    }

    /// Traduce un error a evento **una sola vez por dispositivo**.
    ///
    /// El escaneo reintenta cada 2s a proposito (asi el puente se recupera
    /// solo cuando el usuario instala el driver o abre la app en el
    /// telefono), pero eso no puede convertirse en un evento cada 2s: la UI
    /// mostraria el mismo cartel en loop. El reintento es silencioso; lo que
    /// se anuncia es el *cambio* de estado, y la marca se borra sola cuando
    /// el dispositivo se desenchufa.
    fn report_error(
        &mut self,
        bridge: &UsbBridge,
        id: DeviceId,
        info: &DeviceInfo,
        error: TransportError,
    ) {
        let _ = info;
        match error {
            TransportError::UsbDriverBlocked {
                vendor_id,
                product_id,
                driver,
            } => {
                if self.reported_blocked.insert(id) {
                    log::warn!(
                        "USB: driver incompatible en {vendor_id:04x}:{product_id:04x} ({})",
                        driver.as_deref().unwrap_or("desconocido")
                    );
                    bridge.emit(UsbEvent::DriverBlocked {
                        vendor_id,
                        product_id,
                        driver,
                    });
                }
            }
            other => {
                if self.reported_failed.insert(id) {
                    log::warn!("USB: {other}");
                    bridge.emit(UsbEvent::Failed {
                        detail: other.to_string(),
                    });
                }
            }
        }
    }
}

async fn scan_loop(host: Arc<TransportHost>, bridge: Arc<UsbBridge>, identity: AccessoryIdentity) {
    let mut memory = ScanMemory::default();

    loop {
        tokio::time::sleep(SCAN_INTERVAL).await;

        let devices: Vec<DeviceInfo> = match nusb::list_devices().await {
            Ok(iter) => iter.collect(),
            Err(e) => {
                log::warn!("USB: no se pudo listar el bus: {e}");
                continue;
            }
        };

        let present: HashSet<DeviceId> = devices.iter().map(|d| d.id()).collect();
        memory.forget_absent(&present);

        // Si ya hay un telefono en accessory mode (porque le hicimos el
        // handshake antes, o porque quedo asi de una corrida anterior),
        // atenderlo tiene prioridad: no hace falta handshake de nuevo.
        if let Some(accessory) = devices
            .iter()
            .find(|d| aoa::is_accessory_mode(d.vendor_id(), d.product_id()))
        {
            let id = accessory.id();
            match serve_accessory_device(&host, &bridge, accessory).await {
                // Sirvio al menos una sesion: si mas adelante falla, es un
                // estado nuevo y vuelve a ser noticia.
                Ok(()) => {
                    memory.reported_blocked.remove(&id);
                    memory.reported_failed.remove(&id);
                }
                Err(e) => memory.report_error(&bridge, id, accessory, e),
            }
            continue;
        }

        // Se prueban TODOS los candidatos, no solo el primero: con varios
        // Android enchufados (o un Android y algo que se le parece), quedarse
        // con el primero significaria no llegar nunca al segundo.
        // Se materializa la lista antes de entrar al loop para que el
        // prestamo de `memory` del filtro termine aca: el cuerpo la muta.
        let candidates: Vec<&DeviceInfo> = devices
            .iter()
            .filter(|d| !memory.not_aoa.contains(&d.id()) && looks_like_android(d))
            .collect();

        for candidate in candidates {
            let id = candidate.id();
            if memory.reported_detected.insert(id) {
                bridge.emit(UsbEvent::PhoneDetected {
                    vendor_id: candidate.vendor_id(),
                    product_id: candidate.product_id(),
                    product: candidate.product_string().map(|s| s.to_string()),
                });
            }

            match aoa::start_accessory_mode(candidate, &identity).await {
                Ok(()) => {
                    bridge.emit(UsbEvent::AccessoryModeStarted);
                    match wait_for_accessory().await {
                        Some(accessory) => {
                            let accessory_id = accessory.id();
                            if let Err(e) =
                                serve_accessory_device(&host, &bridge, &accessory).await
                            {
                                memory.report_error(&bridge, accessory_id, &accessory, e);
                            }
                        }
                        None => {
                            // El handshake no tiro error pero el dispositivo
                            // no volvio: no insistir en un loop cerrado
                            // contra el mismo aparato.
                            memory.not_aoa.insert(id);
                            memory.report_error(
                                &bridge,
                                id,
                                candidate,
                                TransportError::Usb(
                                    "el dispositivo no volvio en accessory mode".into(),
                                ),
                            );
                        }
                    }
                    // Un handshake exitoso cambia el bus entero (el aparato
                    // se re-enumera); el resto de la lista ya no es valido.
                    break;
                }
                Err(TransportError::UsbNotAoaCapable) => {
                    // No es un Android (o no habla AOA): dejarlo en paz hasta
                    // que se desenchufe. Ni siquiera se emite evento -- que
                    // haya un mouse en el bus no es noticia para el usuario.
                    memory.not_aoa.insert(id);
                }
                Err(e) => memory.report_error(&bridge, id, candidate, e),
            }
        }
    }
}

/// Heuristica para decidir a que dispositivos vale la pena hablarles AOA.
///
/// Importa que sea conservadora: el handshake reclama una interfaz, y
/// reclamar la del mouse o la del teclado le sacaria el dispositivo al driver
/// del sistema mientras dure el intento. Se descartan las clases que
/// claramente no son un telefono y se aceptan las que un Android expone en
/// sus modos habituales (MTP/PTP o vendor-specific, incluida la firma de
/// ADB), o los dispositivos que no declaran interfaces en el cache del SO.
fn looks_like_android(info: &DeviceInfo) -> bool {
    let interfaces: Vec<(u8, u8, u8)> = info
        .interfaces()
        .map(|i| (i.class(), i.subclass(), i.protocol()))
        .collect();
    looks_like_android_interfaces(&interfaces)
}

/// La heuristica en si, sobre las ternas `(class, subclass, protocol)` de las
/// interfaces. Publica para poder auditarla contra un bus real sin abrir
/// nada: ver `examples/usb_scan.rs`.
pub fn looks_like_android_interfaces(interfaces: &[(u8, u8, u8)]) -> bool {
    /// Clases estandar que un telefono nunca usa como unica funcion y que si
    /// usan periféricos que no queremos tocar.
    const NEVER: &[u8] = &[
        0x01, // audio
        0x03, // HID (mouse/teclado)
        0x07, // impresora
        0x08, // almacenamiento masivo
        0x09, // hub
        0x0E, // video (webcams)
        0x0D, // seguridad
        0xE0, // wireless controller (dongles bluetooth)
    ];
    const IMAGE: u8 = 0x06; // PTP/MTP: el modo "transferir fotos/archivos"
    const VENDOR_SPECIFIC: u8 = 0xFF; // MTP de Android y la interfaz de ADB

    if interfaces.is_empty() {
        // Modo "solo carga": el telefono no expone nada util, pero sigue
        // respondiendo AOA por EP0. Vale la pena intentar.
        return true;
    }

    if interfaces.iter().any(|(class, _, _)| NEVER.contains(class)) {
        return false;
    }

    interfaces
        .iter()
        .any(|(class, _, _)| *class == IMAGE || *class == VENDOR_SPECIFIC)
}

/// Espera a que el telefono vuelva al bus con el VID/PID de accessory.
async fn wait_for_accessory() -> Option<DeviceInfo> {
    let deadline = tokio::time::Instant::now() + REENUMERATION_TIMEOUT;
    loop {
        if let Ok(devices) = nusb::list_devices().await {
            if let Some(found) =
                devices.into_iter().find(|d| aoa::is_accessory_mode(d.vendor_id(), d.product_id()))
            {
                return Some(found);
            }
        }
        if tokio::time::Instant::now() >= deadline {
            return None;
        }
        tokio::time::sleep(REENUMERATION_POLL).await;
    }
}

/// Abre el canal y corre una sesion completa encima.
///
/// El error de apertura se propaga en vez de convertirse en evento aca:
/// quien sabe si esto ya se reporto (y por lo tanto si hay que volver a
/// molestar a la UI) es el `ScanMemory` del loop, que ve todas las vueltas.
/// Emitir desde aca es lo que hacia que un accessory con el driver
/// bloqueado escupiera un evento cada 2 segundos.
async fn serve_accessory_device(
    host: &Arc<TransportHost>,
    bridge: &Arc<UsbBridge>,
    info: &DeviceInfo,
) -> Result<()> {
    let stream = open_accessory_stream(info).await?;

    bridge.emit(UsbEvent::AccessoryConnected);
    let outcome = serve_stream(host.clone(), stream).await;
    bridge.emit(UsbEvent::AccessoryDisconnected);
    if let Err(e) = &outcome {
        log::warn!("USB: la sesion termino con error: {e}");
    }
    // Una sesion que termina con error igual "sirvio": el canal se abrio y
    // se cerro, que es lo que le importa al loop para decidir si el estado
    // del cable cambio.
    Ok(())
}

async fn open_accessory_interface(info: &DeviceInfo) -> Result<Interface> {
    let device = info
        .open()
        .await
        .map_err(|e| TransportError::Usb(format!("abriendo el accessory: {e}")))?;

    // En accessory mode el telefono expone una sola interfaz con los dos
    // endpoints bulk; el driver de kernel (`f_accessory.c`) no implementa
    // Microsoft OS Descriptors, asi que en Windows este VID/PID tambien
    // necesita WinUSB instalado (segundo momento del ADR 0002) y el claim
    // falla igual que antes si no esta.
    device.claim_interface(0).await.map_err(|e| {
        if e.kind() == nusb::ErrorKind::Unsupported {
            TransportError::UsbDriverBlocked {
                vendor_id: info.vendor_id(),
                product_id: info.product_id(),
                driver: None,
            }
        } else {
            TransportError::Usb(format!("reclamando la interfaz del accessory: {e}"))
        }
    })
}

/// Diagnostico: abre el accessory igual que el puente y devuelve las
/// direcciones de sus endpoints bulk `(in, out)`, sin correr ninguna sesion.
/// Sirve para verificar contra un telefono real que el driver esta bien
/// instalado y que los endpoints son los esperados (ver
/// `examples/usb_scan.rs`) sin necesitar la app de Android del otro lado.
pub async fn probe_accessory_endpoints(info: &DeviceInfo) -> Result<(u8, u8)> {
    let interface = open_accessory_interface(info).await?;
    find_bulk_endpoints(&interface)
}

async fn open_accessory_stream(info: &DeviceInfo) -> Result<UsbStream> {
    let interface = open_accessory_interface(info).await?;
    let (in_address, out_address) = find_bulk_endpoints(&interface)?;

    let read_endpoint = interface
        .endpoint::<Bulk, In>(in_address)
        .map_err(|e| TransportError::Usb(format!("endpoint bulk IN: {e}")))?;
    let write_endpoint = interface
        .endpoint::<Bulk, Out>(out_address)
        .map_err(|e| TransportError::Usb(format!("endpoint bulk OUT: {e}")))?;

    Ok(UsbStream::new(read_endpoint, write_endpoint))
}

fn find_bulk_endpoints(interface: &Interface) -> Result<(u8, u8)> {
    let descriptor = interface
        .descriptor()
        .ok_or_else(|| TransportError::Usb("la interfaz no tiene descriptor activo".into()))?;

    let mut in_address = None;
    let mut out_address = None;
    for endpoint in descriptor.endpoints() {
        if endpoint.transfer_type() != TransferType::Bulk {
            continue;
        }
        match endpoint.direction() {
            Direction::In if in_address.is_none() => in_address = Some(endpoint.address()),
            Direction::Out if out_address.is_none() => out_address = Some(endpoint.address()),
            _ => {}
        }
    }

    match (in_address, out_address) {
        (Some(i), Some(o)) => Ok((i, o)),
        _ => Err(TransportError::Usb(
            "el accessory no expone los dos endpoints bulk esperados".into(),
        )),
    }
}

/// Corre una sesion completa sobre un canal ya abierto.
///
/// Generico sobre el canal a proposito: el puente real le pasa un
/// `UsbStream` (dos endpoints bulk de `nusb`), y los tests le pasan un
/// `tokio::io::duplex`, que ejercita exactamente el mismo camino de codigo
/// (framing + `SessionTransport` + pairing) sin depender de que haya un
/// telefono enchufado.
pub(crate) async fn serve_stream<S>(host: Arc<TransportHost>, stream: S) -> Result<()>
where
    S: AsyncRead + AsyncWrite + Unpin + Send,
{
    let session = UsbSession(FramedUsb::new(stream));
    crate::server::dispatch_first_message(host, session).await
}

#[cfg(test)]
mod tests {
    use super::*;

    use nexodeck_protocol::{DevicePlatformWire, MessageV1};

    use crate::server::{HostConfig, PairingEvent, TransportHost};

    const ADB: (u8, u8, u8) = (0xFF, 0x42, 0x01);
    const MTP_VENDOR: (u8, u8, u8) = (0xFF, 0xFF, 0x00);
    const PTP: (u8, u8, u8) = (0x06, 0x01, 0x01);

    #[test]
    fn un_android_en_sus_modos_habituales_es_candidato() {
        assert!(looks_like_android_interfaces(&[MTP_VENDOR]));
        assert!(looks_like_android_interfaces(&[PTP]));
        assert!(looks_like_android_interfaces(&[MTP_VENDOR, ADB]));
        // El compuesto del spike del ADR 0002: 4 interfaces, todas
        // vendor-specific o MTP.
        assert!(looks_like_android_interfaces(&[
            MTP_VENDOR,
            MTP_VENDOR,
            ADB,
            (0xFF, 0x42, 0x02)
        ]));
    }

    #[test]
    fn modo_solo_carga_sin_interfaces_se_intenta_igual() {
        // El telefono no expone funciones pero sigue contestando AOA por
        // EP0; descartarlo aca haria que "conectar el cable sin elegir modo"
        // nunca funcione.
        assert!(looks_like_android_interfaces(&[]));
    }

    #[test]
    fn perifericos_comunes_no_se_tocan() {
        // Reclamarles la interfaz se la sacaria a su driver: mouse, teclado,
        // webcam, pendrive y hubs quedan fuera aunque compartan el bus.
        assert!(!looks_like_android_interfaces(&[(0x03, 0x01, 0x02)]));
        assert!(!looks_like_android_interfaces(&[(0x0E, 0x01, 0x00)]));
        assert!(!looks_like_android_interfaces(&[(0x08, 0x06, 0x50)]));
        assert!(!looks_like_android_interfaces(&[(0x09, 0x00, 0x00)]));
        assert!(!looks_like_android_interfaces(&[(0x01, 0x01, 0x00)]));
    }

    #[test]
    fn un_compuesto_con_una_funcion_descartada_no_se_toca() {
        // Un teclado con una interfaz vendor-specific para sus macros no es
        // un telefono: alcanza UNA clase prohibida para descartar todo el
        // dispositivo, porque el claim es por dispositivo, no por funcion.
        assert!(!looks_like_android_interfaces(&[
            (0x03, 0x01, 0x01),
            MTP_VENDOR
        ]));
    }

    /// Pairing completo sobre un canal de bytes crudo, que es todo lo que
    /// `UsbStream` es una vez abierto el accessory: ejercita el mismo camino
    /// que un telefono real (framing con length-prefix -> `SessionTransport`
    /// -> `dispatch_first_message` -> sesion) reemplazando solo la capa
    /// fisica por un `duplex` en memoria. Lo que NO cubre es el handshake
    /// AOA ni la enumeracion USB, que necesitan hardware.
    ///
    /// Unico test del crate que arranca un `TransportHost`: es un singleton
    /// de proceso (`OnceLock`), asi que si se agrega otro que tambien lo
    /// arranque, tienen que compartir instancia o pelearan por el estado de
    /// pairing.
    #[tokio::test(flavor = "multi_thread")]
    async fn pairing_completo_sobre_un_canal_de_bytes_crudo() {
        let host = TransportHost::start(HostConfig {
            device_name: "TestHostUsb".into(),
            port: 0,
        })
        .await
        .expect("el host deberia arrancar");

        let mut pairing_events = host.pairing_events();
        let pin = host.arm_pairing().expect("arm_pairing");

        // Un extremo se lo queda el puente (como si viniera del cable), el
        // otro hace de telefono en este mismo proceso.
        let (bridge_side, phone_side) = tokio::io::duplex(64 * 1024);
        let session_host = host.clone();
        tokio::spawn(async move {
            let _ = serve_stream(session_host, bridge_side).await;
        });

        let mut phone = FramedUsb::new(phone_side);
        phone
            .send_message(&MessageV1::PairHello {
                device_name: "TestAndroidUsb".into(),
                platform: DevicePlatformWire::Android,
            })
            .await
            .expect("PairHello");

        match recv(&mut phone).await {
            MessageV1::PairPin { pin: received, .. } => assert_eq!(
                received, pin,
                "el PIN que viaja por el cable debe ser el que genero arm_pairing"
            ),
            other => panic!("se esperaba PairPin, llego {other:?}"),
        }

        phone
            .send_message(&MessageV1::PairConfirm)
            .await
            .expect("PairConfirm");

        // La PC ve la solicitud recien despues del PairConfirm del telefono.
        match tokio::time::timeout(Duration::from_secs(5), pairing_events.recv())
            .await
            .expect("timeout esperando el evento de pairing")
            .expect("canal de eventos cerrado")
        {
            PairingEvent::DeviceRequestedPairing { device_name, .. } => {
                assert_eq!(device_name, "TestAndroidUsb")
            }
            other => panic!("evento inesperado: {other:?}"),
        }
        host.confirm_pairing(true).expect("confirm_pairing");

        let device_id = match recv(&mut phone).await {
            MessageV1::PairAccepted { device_id, .. } => device_id,
            other => panic!("se esperaba PairAccepted, llego {other:?}"),
        };
        assert!(!device_id.is_empty());

        // Y con la sesion ya corriendo, el hardware empieza a fluir por el
        // mismo canal sin ningun paso extra propio de USB.
        match recv(&mut phone).await {
            MessageV1::HardwareSnapshot(snapshot) => {
                assert!(
                    snapshot.ram_total_mb > 0.0,
                    "el snapshot deberia traer datos reales de la maquina"
                )
            }
            other => panic!("se esperaba HardwareSnapshot, llego {other:?}"),
        }
    }

    async fn recv<S>(framed: &mut FramedUsb<S>) -> MessageV1
    where
        S: AsyncRead + AsyncWrite + Unpin,
    {
        tokio::time::timeout(Duration::from_secs(5), framed.recv_message())
            .await
            .expect("timeout esperando un mensaje")
            .expect("error de framing")
            .expect("el canal no deberia cerrarse")
    }
}
