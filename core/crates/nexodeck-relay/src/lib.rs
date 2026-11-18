//! Relay de encuentro: empareja DOS conexiones entrantes que presentan el
//! mismo token y despues solo copia bytes entre ellas.
//!
//! Existe porque las dos puntas estan detras de NAT --la PC bajo el CGNAT
//! del proveedor, el telefono bajo el del operador movil-- y dos maquinas
//! donde ninguna puede recibir conexiones no pueden encontrarse solas. Eso
//! no se arregla con codigo en las puntas: hace falta un tercero con IP
//! publica.
//!
//! Dos propiedades que lo hacen defendible en un servidor ajeno:
//!
//! - **Nunca termina el TLS.** Lo que viaja adentro sigue cifrado punta a
//!   punta y el certificate pinning de NexoDeck queda intacto: el relay ve
//!   bytes opacos.
//! - **Nunca abre conexiones salientes.** Solo empareja dos ENTRANTES. Ni
//!   con el token robado se lo puede usar de proxy para alcanzar otra
//!   maquina de la red donde este alojado.

pub mod hello;

// Todo lo que sigue es el SERVIDOR del relay. `nexodeck-transport` usa este
// crate con `default-features = false` para quedarse solo con `hello`, que
// no necesita tokio ni nada mas.
#[cfg(feature = "server")]
mod server;
#[cfg(feature = "server")]
pub use server::{serve, RelayConfig};
