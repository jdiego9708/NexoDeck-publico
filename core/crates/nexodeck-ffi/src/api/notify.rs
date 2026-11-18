//! Avisos hacia fuera de la maquina.
//!
//! El motor esta en `nexodeck-notify`; aca solo viven los DTOs que cruzan el
//! puente, por la misma razon que el resto de este crate: `nexodeck-ffi` es el
//! unico lugar donde vive la forma exacta del dato que ve Dart.
//!
//! **Los canales no se guardan de este lado.** La configuracion vive en
//! `app_settings` (Drift, o sea Dart) y viaja como JSON en cada llamada. Asi un
//! cambio de configuracion surte efecto en el acto, sin invalidar ninguna
//! cache, y Rust no tiene que enterarse de que existe una base de datos.

use nexodeck_notify::{channels_from_json, Notifier, NotifyRequest};

/// Espejo de `nexodeck_notify::NotifyLevel`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NotifyLevel {
    /// Un hito de lo que se vigila. Un canal puede pedir no recibirlos.
    Milestone,
    /// Critico: disco lleno, proceso muerto, canal caido. Ningun canal lo
    /// filtra.
    Always,
}

impl From<NotifyLevel> for nexodeck_notify::NotifyLevel {
    fn from(value: NotifyLevel) -> Self {
        match value {
            NotifyLevel::Milestone => nexodeck_notify::NotifyLevel::Milestone,
            NotifyLevel::Always => nexodeck_notify::NotifyLevel::Always,
        }
    }
}

/// Que paso con un canal. Hay uno por canal intentado, **siempre**, incluidos
/// los que se saltaron.
///
/// `delivered` y `detail` son la razon de ser de todo esto: un aviso que no
/// salio tiene que ser distinguible de uno que si. Las funciones `avisar()`
/// internas del pipeline de ODM mandaban su salida a `/dev/null` y por eso los
/// dos casos se veian igual.
#[derive(Debug, Clone)]
pub struct NotifyOutcome {
    pub channel_id: String,
    pub delivered: bool,
    pub exit_code: Option<i32>,
    pub detail: String,
    pub elapsed_ms: u32,
    /// El canal existe pero no acepta este nivel, o esta desactivado. No es un
    /// fallo, y la UI no lo debe pintar como tal.
    pub skipped: bool,
    pub dry_run: bool,
    /// `true` si esto es un fallo de verdad. Se calcula aca para que las dos
    /// puntas no tengan la misma regla escrita dos veces.
    pub failed: bool,
}

impl From<nexodeck_notify::NotifyOutcome> for NotifyOutcome {
    fn from(value: nexodeck_notify::NotifyOutcome) -> Self {
        let failed = value.is_failure();
        NotifyOutcome {
            channel_id: value.channel_id,
            delivered: value.delivered,
            exit_code: value.exit_code,
            detail: value.detail,
            elapsed_ms: value.elapsed_ms,
            skipped: value.skipped,
            dry_run: value.dry_run,
            failed,
        }
    }
}

/// Manda `text` por todos los canales de `channels_json` y devuelve un
/// resultado por canal.
///
/// **Es `async` por obligacion**, no por gusto: frb corre las funciones `async`
/// dentro de su propio `tokio::runtime::Runtime`, y adentro se lanzan procesos
/// con `tokio::process`. Desde una funcion sincrona no habria reactor.
///
/// No devuelve `Result`: que un canal falle no invalida la operacion ni el
/// aviso que si salio por otro. Un vector vacio significa que **no hay ningun
/// canal configurado**, que la UI tiene que decir en voz alta — un aviso sin
/// por donde salir es exactamente el fallo mudo que esto viene a eliminar.
pub async fn send_notification(
    channels_json: String,
    text: String,
    level: NotifyLevel,
    dry_run: bool,
) -> Vec<NotifyOutcome> {
    let notifier = Notifier::new(channels_from_json(&channels_json));
    notifier
        .send(&NotifyRequest {
            text,
            level: level.into(),
            dry_run,
        })
        .await
        .into_iter()
        .map(NotifyOutcome::from)
        .collect()
}

/// Cuantos canales entiende NexoDeck del JSON guardado. Sirve para que la UI
/// avise de una configuracion que no se pudo leer **antes** de que haga falta
/// mandar el primer aviso de verdad.
pub fn count_notify_channels(channels_json: String) -> u32 {
    channels_from_json(&channels_json).len() as u32
}
