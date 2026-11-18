//! Avisos hacia **fuera** de la maquina.
//!
//! NexoDeck ya sabia avisar dentro de si mismo (los toasts del Run Center) y al
//! telefono emparejado (`MessageV1::ActionRunUpdate`). Lo que no sabia hacer es
//! mandar un mensaje a donde el usuario mira cuando **no** esta delante del PC.
//! Este crate es esa pieza, y nada mas que esa pieza.
//!
//! ## No trae ningun integrador dentro, y es a proposito
//!
//! Aca no hay codigo de WhatsApp, ni de OpenClaw, ni de SSH. Un canal es **un
//! comando que se ejecuta**, y el pegamento concreto de cada maquina vive en
//! configuracion. En el equipo principal ese comando termina invocando
//! `avisar.sh`, que ya resuelve el contenedor del bot por prefijo y sabe que el
//! sufijo `-1` cambia al redesplegar. Meter todo eso dentro de NexoDeck lo
//! ataria a una instalacion concreta de Example, que es justo lo contrario de
//! lo que este proyecto quiere ser.
//!
//! ## El fallo se devuelve, nunca se traga
//!
//! [`NotifyOutcome`] lleva `delivered` y el detalle del error. Es la razon de
//! existir de `avisar.sh`: las funciones `avisar()` internas del pipeline
//! mandaban su salida a `/dev/null`, y **un aviso no entregado se parecia
//! exactamente a uno entregado**. Quien llama a [`Notifier::send`] tiene que
//! poder distinguirlos, porque en una tanda de horas el aviso es la unica
//! senal que hay.

mod command;

pub use command::{CommandChannel, MessageDelivery, MESSAGE_PLACEHOLDER};

/// Importancia de un aviso.
///
/// Replica los dos niveles que `odm-watch.sh` aprendio a distinguir: `avisar()`
/// se puede silenciar con `TANDA_AVISOS=ninguno`, y `avisar_siempre()` no. La
/// tanda I se perdio a las 08:20 del 27-ago justamente por no tener el segundo.
///
/// El orden importa: `Milestone < Always`, y es lo que compara
/// [`CommandChannel::min_level`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NotifyLevel {
    /// Un hito del trabajo que se vigila. Silenciable.
    Milestone,
    /// Algo que el usuario tiene que saber si o si: disco lleno, proceso
    /// muerto, canal caido. **Nunca se silencia.**
    Always,
}

impl Default for NotifyLevel {
    fn default() -> Self {
        NotifyLevel::Milestone
    }
}

/// Lo que se pide mandar.
#[derive(Debug, Clone)]
pub struct NotifyRequest {
    pub text: String,
    pub level: NotifyLevel,
    /// Compone y valida todo, pero **no ejecuta el comando**. Es el `--seco`
    /// que ya usan los vigilantes del VPS: sirve para verificar un canal recien
    /// configurado sin gastarle un WhatsApp al usuario.
    pub dry_run: bool,
}

/// Que paso con **un** canal. Uno por canal intentado, siempre.
#[derive(Debug, Clone)]
pub struct NotifyOutcome {
    pub channel_id: String,
    pub delivered: bool,
    /// `None` si el proceso no llego a arrancar o si se agoto el tiempo.
    pub exit_code: Option<i32>,
    /// En lenguaje del usuario cuando se puede, y si no, la ultima salida del
    /// comando. Vacio cuando `delivered` es `true` y el comando no dijo nada.
    pub detail: String,
    pub elapsed_ms: u32,
    /// El canal existe pero pidio no recibir este nivel. No es un fallo, y por
    /// eso se distingue de `delivered: false`.
    pub skipped: bool,
    pub dry_run: bool,
}

impl NotifyOutcome {
    /// Hay **tres** formas de no entregar y solo una es un fallo.
    ///
    /// Un canal saltado no llego a intentarlo, y un ensayo en seco no queria
    /// intentarlo. Definir el fallo como "no entregado" a secas convierte a los
    /// dos en errores, y entonces comprobar un canal recien configurado
    /// contesta que esta roto.
    pub fn is_failure(&self) -> bool {
        !self.delivered && !self.skipped && !self.dry_run
    }
}

/// Los canales configurados. Se construye desde `app_settings` en cada envio:
/// no hay estado que valga la pena cachear y asi un cambio de configuracion
/// surte efecto en el acto.
#[derive(Debug, Clone, Default)]
pub struct Notifier {
    pub channels: Vec<CommandChannel>,
}

impl Notifier {
    pub fn new(channels: Vec<CommandChannel>) -> Self {
        Self { channels }
    }

    /// Manda `request` por todos los canales y devuelve **un resultado por
    /// canal**, en orden.
    ///
    /// Los canales se recorren en serie, no en paralelo. Son uno o dos y cada
    /// uno tarda segundos; lanzarlos a la vez complicaria el codigo para
    /// ahorrar un tiempo que nadie esta esperando.
    ///
    /// No devuelve `Result`: el fallo de un canal es un dato del resultado, no
    /// un error de la operacion. Que el canal de WhatsApp este caido no
    /// invalida el aviso que si salio por el otro.
    pub async fn send(&self, request: &NotifyRequest) -> Vec<NotifyOutcome> {
        let mut out = Vec::with_capacity(self.channels.len());
        for channel in &self.channels {
            out.push(channel.send(request).await);
        }
        out
    }

    /// Ningun canal configurado. Quien llama lo tiene que decir en la UI: un
    /// aviso que no tiene por donde salir es exactamente el fallo mudo que este
    /// crate viene a eliminar.
    pub fn is_empty(&self) -> bool {
        self.channels.is_empty()
    }
}

/// Lee la lista de canales desde el JSON que guarda `app_settings`.
///
/// Tolera campos ausentes y **descarta los canales que no se entienden en vez
/// de fallar entera**: una configuracion escrita por una version mas nueva no
/// puede dejar a la maquina sin ningun aviso.
pub fn channels_from_json(raw: &str) -> Vec<CommandChannel> {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(raw) else {
        return Vec::new();
    };
    let Some(items) = value.as_array() else {
        return Vec::new();
    };
    items
        .iter()
        .filter_map(|item| serde_json::from_value::<CommandChannel>(item.clone()).ok())
        .filter(|channel: &CommandChannel| !channel.program.trim().is_empty())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn level_orders_milestone_below_always() {
        assert!(NotifyLevel::Milestone < NotifyLevel::Always);
    }

    #[test]
    fn skipped_channel_is_not_a_failure() {
        let outcome = NotifyOutcome {
            channel_id: "x".into(),
            delivered: false,
            exit_code: None,
            detail: String::new(),
            elapsed_ms: 0,
            skipped: true,
            dry_run: false,
        };
        assert!(!outcome.is_failure());
    }

    /// Un ensayo en seco no entrega nada, y eso no es un fallo. Sin esto,
    /// comprobar un canal recien configurado contesta que esta roto.
    #[test]
    fn a_dry_run_is_not_a_failure_even_though_nothing_was_delivered() {
        let outcome = NotifyOutcome {
            channel_id: "x".into(),
            delivered: false,
            exit_code: None,
            detail: "bash -lc ...".into(),
            elapsed_ms: 0,
            skipped: false,
            dry_run: true,
        };
        assert!(!outcome.is_failure());
    }

    /// La contracara: un intento de verdad que no entrego SI es un fallo.
    #[test]
    fn a_real_attempt_that_did_not_deliver_is_a_failure() {
        let outcome = NotifyOutcome {
            channel_id: "x".into(),
            delivered: false,
            exit_code: Some(1),
            detail: "SIN_CONTENEDOR".into(),
            elapsed_ms: 120,
            skipped: false,
            dry_run: false,
        };
        assert!(outcome.is_failure());
    }

    #[test]
    fn json_drops_unusable_channels_but_keeps_the_rest() {
        let raw = r#"[
            {"id":"wa","label":"WhatsApp","program":"bash","args":["-lc","x"]},
            {"id":"roto","label":"Sin programa","program":"   ","args":[]},
            {"id":"futuro","kind":"webhook","url":"https://x"}
        ]"#;
        let channels = channels_from_json(raw);
        assert_eq!(channels.len(), 1);
        assert_eq!(channels[0].id, "wa");
    }

    #[test]
    fn json_garbage_yields_no_channels_instead_of_panicking() {
        assert!(channels_from_json("no soy json").is_empty());
        assert!(channels_from_json("{}").is_empty());
    }
}
