//! Transporte USB (AOA). Los dos roles viven aca porque comparten el
//! framing, pero se compilan en plataformas distintas: la PC enumera el bus
//! y hace el handshake (`aoa`/`bridge`/`stream`, con `nusb`), Android recibe
//! el fd del accessory ya abierto desde Kotlin (`android`) y no necesita
//! nada de la capa nativa de USB.

pub(crate) mod framing;
pub(crate) mod session;

#[cfg(not(target_os = "android"))]
pub mod aoa;
#[cfg(not(target_os = "android"))]
pub mod bridge;
#[cfg(not(target_os = "android"))]
pub(crate) mod stream;

#[cfg(target_os = "android")]
pub mod android;

#[cfg(not(target_os = "android"))]
pub use aoa::AccessoryIdentity;
#[cfg(not(target_os = "android"))]
pub use bridge::{UsbBridge, UsbEvent, bridge};

#[cfg(target_os = "android")]
pub use android::connect_over_accessory_fd;
