//! El sentido que faltaba: **de NexoDeck hacia Claude Code**.
//!
//! El servidor MCP solo contesta. Claude Code no expone ningun servidor al que
//! llamar, asi que un webhook añadiria un salto para nada. La via que si
//! funciona es la que el usuario ya usa con el puente de WhatsApp: **un proceso
//! que emite una linea por mensaje**, vigilado con la herramienta Monitor de
//! Claude Code. Cada linea llega a la sesion como una notificacion.
//!
//! Aqui vive la cola que ese proceso consulta, y el registro de que sesiones
//! estan escuchando.
//!
//! ## Varias sesiones a la vez: la identidad la pone el vigilante
//!
//! Con cinco terminales de Claude Code abiertas hay cinco vigilantes, y una
//! cola sin destinatario se los entregaria todo a todos. Por eso los mensajes
//! van **dirigidos**.
//!
//! **No hace falta ninguna bandera de Claude Code**: quien lanza el vigilante
//! sabe donde esta, asi que el vigilante se presenta con su carpeta y su rama.
//! Su identificador es su pid, que es unico en la maquina mientras viva.
//!
//! Y detectar una sesion muerta es fiable **porque la vigilancia es
//! independiente de lo que Claude Code este haciendo**: el vigilante consulta
//! cada 25 s pase lo que pase, asi que dejar de consultar significa que la
//! terminal se cerro, y eso no se confunde con "esta pensando".
//!
//! ## Las tres reglas son las de `vigilar-cc.sh`, y no son opcionales
//!
//! 1. **Marca de agua que solo avanza tras emitir.** El oyente pide "lo que hay
//!    despues de N" y decide el mismo cuando avanza su N. Si muere a mitad, la
//!    vuelta siguiente repite en vez de saltarse: repetir molesta, perder no se
//!    arregla. Por eso los mensajes **se conservan** despues de entregarse.
//! 2. **Cada mensaje lleva identificador.** Sin el, la respuesta no sabria a que
//!    pregunta pertenece y el chat no podria colocarla en su turno.
//! 3. **El silencio se distingue de la muerte.** Una pregunta sin respuesta
//!    vence, y si su sesion desaparece vence **antes y diciendo por que**.

use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde::Serialize;
use tokio::sync::{broadcast, Notify};

/// Cuantos mensajes se conservan tras entregarse, para que un oyente que se
/// reconecta con una marca vieja los pueda repescar.
const RING_CAPACITY: usize = 200;

/// Cuanto espera el oyente antes de volver con las manos vacias.
const POLL_TIMEOUT: Duration = Duration::from_secs(25);

/// Cuanto se espera una respuesta antes de darla por perdida. Claude Code puede
/// tardar minutos de verdad: lee ficheros, corre comandos y verifica.
const REPLY_TIMEOUT: Duration = Duration::from_secs(15 * 60);

/// Sin consultar durante esto, la sesion se da por cerrada.
///
/// Son tres consultas perdidas (el oyente vuelve cada 25 s), mismo criterio que
/// el `FAILURES=3` con el que el propio vigilante decide que el canal cayo.
pub const SESSION_STALE_AFTER: Duration = Duration::from_secs(90);

const BROADCAST_CAPACITY: usize = 128;

/// Una sesion de Claude Code que esta escuchando.
#[derive(Debug, Clone, Serialize)]
pub struct CorrespondentSession {
    /// El pid del vigilante. Unico en la maquina mientras viva.
    pub id: String,
    /// Como se llama para el usuario: la carpeta y la rama, o lo que se le
    /// haya pasado con `--name`.
    pub label: String,
    pub cwd: String,
    pub last_seen_secs_ago: u32,
    /// Dejo de consultar: la terminal se cerro.
    pub stale: bool,
}

struct SessionRecord {
    label: String,
    cwd: String,
    last_seen: Instant,
}

/// Un mensaje esperando a que Claude Code lo recoja.
#[derive(Debug, Clone, Serialize)]
pub struct OutboxMessage {
    /// Monotono y creciente. Es la marca de agua del oyente.
    pub seq: u64,
    /// `true` si espera respuesta. `false` es un aviso suelto.
    pub expects_reply: bool,
    pub text: String,
    /// A que sesion va. `None` es **para todas**: un aviso general no tiene por
    /// que elegir terminal.
    pub target: Option<String>,
}

/// Lo que le pasa a la correspondencia, para que el chat lo pinte.
#[derive(Debug, Clone)]
pub enum CorrespondentEvent {
    /// El oyente recogio el mensaje. Es el acuse de que hay alguien al otro
    /// lado: sin esto, "todavia no contesto" y "no hay nadie escuchando" se
    /// verian igual.
    Delivered { seq: u64, session: String },
    Replied { seq: u64, text: String },
    /// Claude Code dijo algo sin que nadie preguntara. `from` es cooperativo:
    /// la sesion lo pasa si sus instrucciones se lo dicen, y puede faltar.
    Posted { text: String, from: Option<String> },
    /// Vencio. `reason` distingue "nadie contesto a tiempo" de "la sesion a la
    /// que se le pregunto se cerro", que se arreglan distinto.
    TimedOut { seq: u64, reason: String },
    /// Aparecio o desaparecio una sesion. El selector del chat se redibuja.
    SessionsChanged,
}

struct PendingAsk {
    seq: u64,
    asked_at: Instant,
    /// A quien se le pregunto. `None` si fue a todas.
    target: Option<String>,
}

pub struct Outbox {
    seq: AtomicU64,
    /// Anillo de los ultimos mensajes, entregados o no. Ver la regla 1.
    ring: Mutex<VecDeque<OutboxMessage>>,
    pending: Mutex<Vec<PendingAsk>>,
    /// Hasta donde confirmo cada sesion. **Una marca por sesion**: con una sola
    /// global, el primero en confirmar tapaba a los demas.
    delivered: Mutex<HashMap<String, u64>>,
    sessions: Mutex<HashMap<String, SessionRecord>>,
    notify: Notify,
    events: broadcast::Sender<CorrespondentEvent>,
}

impl Default for Outbox {
    fn default() -> Self {
        let (events, _) = broadcast::channel(BROADCAST_CAPACITY);
        Outbox {
            seq: AtomicU64::new(0),
            ring: Mutex::new(VecDeque::new()),
            pending: Mutex::new(Vec::new()),
            delivered: Mutex::new(HashMap::new()),
            sessions: Mutex::new(HashMap::new()),
            notify: Notify::new(),
            events,
        }
    }
}

impl Outbox {
    pub fn subscribe(&self) -> broadcast::Receiver<CorrespondentEvent> {
        self.events.subscribe()
    }

    // ------------------------------------------------------------------
    // Sesiones
    // ------------------------------------------------------------------

    /// El vigilante se presenta. Registrarse y seguir vivo son el mismo acto:
    /// esto se llama en **cada** consulta, no una vez al arrancar.
    pub fn register_session(&self, id: &str, label: &str, cwd: &str) {
        let mut changed = false;
        if let Ok(mut sessions) = self.sessions.lock() {
            match sessions.get_mut(id) {
                Some(record) => {
                    // Volver de "cerrada" tambien es un cambio que la UI tiene
                    // que ver.
                    changed = record.last_seen.elapsed() >= SESSION_STALE_AFTER
                        || record.label != label;
                    record.label = label.to_string();
                    record.cwd = cwd.to_string();
                    record.last_seen = Instant::now();
                }
                None => {
                    sessions.insert(
                        id.to_string(),
                        SessionRecord {
                            label: label.to_string(),
                            cwd: cwd.to_string(),
                            last_seen: Instant::now(),
                        },
                    );
                    changed = true;
                }
            }
        }
        if changed {
            let _ = self.events.send(CorrespondentEvent::SessionsChanged);
        }
    }

    /// Las sesiones conocidas, las vivas primero.
    ///
    /// Las cerradas **no se borran en el acto**: se marcan. Que una terminal que
    /// se acaba de cerrar desaparezca de golpe deja al usuario sin entender que
    /// paso con la pregunta que le habia mandado.
    pub fn sessions(&self) -> Vec<CorrespondentSession> {
        let Ok(sessions) = self.sessions.lock() else {
            return Vec::new();
        };
        let mut out: Vec<CorrespondentSession> = sessions
            .iter()
            .map(|(id, record)| {
                let age = record.last_seen.elapsed();
                CorrespondentSession {
                    id: id.clone(),
                    label: record.label.clone(),
                    cwd: record.cwd.clone(),
                    last_seen_secs_ago: age.as_secs().min(u64::from(u32::MAX)) as u32,
                    stale: age >= SESSION_STALE_AFTER,
                }
            })
            .collect();
        out.sort_by(|a, b| {
            a.stale
                .cmp(&b.stale)
                .then(a.label.cmp(&b.label))
        });
        out
    }

    fn is_stale(&self, id: &str) -> bool {
        self.sessions
            .lock()
            .map(|sessions| match sessions.get(id) {
                Some(record) => record.last_seen.elapsed() >= SESSION_STALE_AFTER,
                // Una sesion que nunca se registro cuenta como cerrada: no hay
                // nadie que pueda recoger lo que se le mande.
                None => true,
            })
            .unwrap_or(true)
    }

    // ------------------------------------------------------------------
    // Cola
    // ------------------------------------------------------------------

    /// Encola un mensaje y devuelve su marca. `target` en `None` va a todas.
    pub fn push(&self, text: String, expects_reply: bool, target: Option<String>) -> u64 {
        let seq = self.seq.fetch_add(1, Ordering::Relaxed) + 1;
        let message = OutboxMessage {
            seq,
            expects_reply,
            text,
            target: target.clone(),
        };

        if let Ok(mut ring) = self.ring.lock() {
            ring.push_back(message);
            while ring.len() > RING_CAPACITY {
                ring.pop_front();
            }
        }
        if expects_reply {
            if let Ok(mut pending) = self.pending.lock() {
                pending.push(PendingAsk {
                    seq,
                    asked_at: Instant::now(),
                    target,
                });
            }
        }

        self.notify.notify_waiters();
        seq
    }

    /// Lo que haya despues de `since` **para esta sesion**. Espera si no hay
    /// nada.
    ///
    /// Devolver vacio tras la espera **no es un error**: es como el oyente
    /// comprueba que el canal sigue vivo sin mantener una conexion abierta para
    /// siempre.
    pub async fn poll(&self, since: u64, session: &str) -> Vec<OutboxMessage> {
        let ready = self.since(since, session);
        if !ready.is_empty() {
            return ready;
        }

        // `notified()` se arma ANTES de volver a mirar: al reves habria una
        // ventana en la que un `push` entre la comprobacion y la espera se
        // perderia hasta el siguiente mensaje.
        let waiter = self.notify.notified();
        let ready = self.since(since, session);
        if !ready.is_empty() {
            return ready;
        }
        let _ = tokio::time::timeout(POLL_TIMEOUT, waiter).await;
        self.since(since, session)
    }

    fn since(&self, since: u64, session: &str) -> Vec<OutboxMessage> {
        self.ring
            .lock()
            .map(|ring| {
                ring.iter()
                    .filter(|m| m.seq > since)
                    // Sin destinatario va a todas; con destinatario, solo a esa.
                    .filter(|m| match &m.target {
                        None => true,
                        Some(target) => target == session,
                    })
                    .cloned()
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default()
    }

    /// El oyente confirma hasta donde llego. Solo avanza: una confirmacion
    /// vieja de un oyente que se reconecto no puede hacer retroceder la marca.
    pub fn confirm_delivered(&self, session: &str, up_to: u64) {
        let previous = self
            .delivered
            .lock()
            .map(|mut delivered| {
                let entry = delivered.entry(session.to_string()).or_insert(0);
                let previous = *entry;
                if up_to > previous {
                    *entry = up_to;
                }
                previous
            })
            .unwrap_or(0);

        if up_to > previous {
            for seq in (previous + 1)..=up_to {
                let _ = self.events.send(CorrespondentEvent::Delivered {
                    seq,
                    session: session.to_string(),
                });
            }
        }
    }

    /// Solo lo usan los tests: el resto del sistema pregunta
    /// [`Outbox::anyone_delivered`], que es lo que el chat necesita saber.
    #[cfg_attr(not(test), allow(dead_code))]
    pub fn delivered_up_to(&self, session: &str) -> u64 {
        self.delivered
            .lock()
            .map(|d| d.get(session).copied().unwrap_or(0))
            .unwrap_or(0)
    }

    /// Si **alguna** sesion recogio algo alguna vez. Con mensajes encolados y
    /// esto en `false`, no hay nadie escuchando.
    pub fn anyone_delivered(&self) -> bool {
        self.delivered
            .lock()
            .map(|d| d.values().any(|&v| v > 0))
            .unwrap_or(false)
    }

    /// Claude Code contesta a una pregunta. `false` si esa marca no estaba
    /// esperando respuesta.
    pub fn reply(&self, seq: u64, text: String) -> bool {
        let found = self
            .pending
            .lock()
            .map(|mut pending| {
                let before = pending.len();
                pending.retain(|ask| ask.seq != seq);
                pending.len() != before
            })
            .unwrap_or(false);

        if found {
            let _ = self.events.send(CorrespondentEvent::Replied { seq, text });
        }
        found
    }

    /// Un mensaje que Claude Code manda por su cuenta.
    pub fn post(&self, text: String, from: Option<String>) {
        let _ = self.events.send(CorrespondentEvent::Posted { text, from });
    }

    /// Vence las preguntas perdidas. Dos motivos distintos, y se dicen distinto:
    ///
    /// - **La sesion se cerro**: vence enseguida. Esperar los quince minutos de
    ///   una terminal que ya no existe es hacer perder el tiempo al usuario.
    /// - **Nadie contesto a tiempo**: vence al cumplirse el plazo.
    pub fn expire_old(&self) {
        let vencidas: Vec<(u64, String)> = self
            .pending
            .lock()
            .map(|mut pending| {
                let now = Instant::now();
                let mut vencidas = Vec::new();
                pending.retain(|ask| {
                    let sesion_cerrada = ask
                        .target
                        .as_deref()
                        .map(|target| self.is_stale(target))
                        .unwrap_or(false);
                    if sesion_cerrada {
                        vencidas.push((
                            ask.seq,
                            "la sesión de Claude Code a la que se le preguntó se cerró"
                                .to_string(),
                        ));
                        return false;
                    }
                    if now.duration_since(ask.asked_at) >= REPLY_TIMEOUT {
                        vencidas.push((ask.seq, "nadie contestó a tiempo".to_string()));
                        return false;
                    }
                    true
                });
                vencidas
            })
            .unwrap_or_default();

        for (seq, reason) in vencidas {
            let _ = self.events.send(CorrespondentEvent::TimedOut { seq, reason });
        }
    }

    /// Marca como cerradas las sesiones que dejaron de consultar, y avisa una
    /// sola vez por cambio.
    fn notice_stale_sessions(&self) {
        let hay_cambio = self
            .sessions
            .lock()
            .map(|sessions| {
                sessions
                    .values()
                    .any(|r| r.last_seen.elapsed() >= SESSION_STALE_AFTER)
            })
            .unwrap_or(false);
        if hay_cambio {
            let _ = self.events.send(CorrespondentEvent::SessionsChanged);
        }
    }

    pub fn pending_count(&self) -> usize {
        self.pending.lock().map(|p| p.len()).unwrap_or(0)
    }
}

/// Arranca la tarea que vence las preguntas y marca las sesiones cerradas.
pub fn spawn_expiry_task(outbox: Arc<Outbox>) {
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval_at(
            tokio::time::Instant::now() + Duration::from_secs(30),
            Duration::from_secs(30),
        );
        loop {
            ticker.tick().await;
            outbox.expire_old();
            outbox.notice_stale_sessions();
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    const S1: &str = "1001";
    const S2: &str = "1002";

    #[tokio::test]
    async fn a_pending_message_comes_back_immediately() {
        let outbox = Outbox::default();
        let seq = outbox.push("hola".into(), true, Some(S1.into()));
        assert_eq!(seq, 1);

        let ready = outbox.poll(0, S1).await;
        assert_eq!(ready.len(), 1);
        assert_eq!(ready[0].text, "hola");
        assert!(ready[0].expects_reply);
    }

    /// **El caso de las cinco terminales.** Un mensaje dirigido llega solo a su
    /// sesion; sin esto las cinco recibirian todo.
    #[tokio::test]
    async fn an_addressed_message_reaches_only_its_session() {
        let outbox = Outbox::default();
        outbox.push("para la primera".into(), true, Some(S1.into()));

        assert_eq!(outbox.poll(0, S1).await.len(), 1);
        // La segunda no lo ve, y su espera se corta por timeout, no por mensaje.
        assert!(
            tokio::time::timeout(Duration::from_millis(200), outbox.poll(0, S2))
                .await
                .is_err()
        );
    }

    /// Un aviso general no elige terminal: lo reciben todas.
    #[tokio::test]
    async fn an_unaddressed_message_reaches_every_session() {
        let outbox = Outbox::default();
        outbox.push("aviso para todos".into(), false, None);

        assert_eq!(outbox.poll(0, S1).await.len(), 1);
        assert_eq!(outbox.poll(0, S2).await.len(), 1);
    }

    /// La regla 1: entregar no borra. Un oyente que muere sin avanzar su marca
    /// tiene que poder repescar lo mismo en la vuelta siguiente.
    #[tokio::test]
    async fn delivering_does_not_consume_so_a_dead_listener_can_repesca() {
        let outbox = Outbox::default();
        outbox.push("uno".into(), false, None);
        outbox.push("dos".into(), false, None);

        assert_eq!(outbox.poll(0, S1).await.len(), 2);
        assert_eq!(outbox.poll(0, S1).await.len(), 2);
        assert_eq!(outbox.poll(1, S1).await.len(), 1);
    }

    /// **Cada sesion lleva su propia marca.** Con una sola global, el primero en
    /// confirmar tapaba a los demas y los otros se perdian mensajes.
    #[tokio::test]
    async fn each_session_keeps_its_own_watermark() {
        let outbox = Outbox::default();
        outbox.push("para todas".into(), false, None);

        outbox.confirm_delivered(S1, 1);
        assert_eq!(outbox.delivered_up_to(S1), 1);
        assert_eq!(outbox.delivered_up_to(S2), 0);
        // Y la segunda sigue viendo el mensaje que aun no confirmo.
        assert_eq!(outbox.poll(0, S2).await.len(), 1);
    }

    #[tokio::test]
    async fn an_empty_poll_returns_empty_instead_of_hanging_forever() {
        let outbox = Outbox::default();
        tokio::time::timeout(Duration::from_millis(200), outbox.poll(0, S1))
            .await
            .unwrap_err();
    }

    #[tokio::test]
    async fn a_waiting_listener_wakes_up_on_a_new_message() {
        let outbox = Arc::new(Outbox::default());
        let waiter = {
            let outbox = Arc::clone(&outbox);
            tokio::spawn(async move { outbox.poll(0, S1).await })
        };

        tokio::time::sleep(Duration::from_millis(50)).await;
        outbox.push("tarde".into(), false, None);

        let ready = tokio::time::timeout(Duration::from_secs(2), waiter)
            .await
            .expect("no tenia que agotar el tiempo")
            .expect("la tarea no tenia que panickear");
        assert_eq!(ready.len(), 1);
    }

    #[tokio::test]
    async fn a_reply_matches_its_question_and_an_unknown_one_says_so() {
        let outbox = Outbox::default();
        let mut events = outbox.subscribe();
        let seq = outbox.push("pregunta".into(), true, Some(S1.into()));

        assert!(outbox.reply(seq, "respuesta".into()));
        match events.recv().await.unwrap() {
            CorrespondentEvent::Replied { seq: got, text } => {
                assert_eq!(got, seq);
                assert_eq!(text, "respuesta");
            }
            other => panic!("evento inesperado: {other:?}"),
        }

        assert!(!outbox.reply(seq, "otra vez".into()));
        assert!(!outbox.reply(999, "inventada".into()));
    }

    #[tokio::test]
    async fn a_message_that_expects_no_reply_never_becomes_pending() {
        let outbox = Outbox::default();
        let seq = outbox.push("aviso".into(), false, None);
        assert_eq!(outbox.pending_count(), 0);
        assert!(!outbox.reply(seq, "no deberia".into()));
    }

    #[test]
    fn the_ring_stays_bounded_so_a_long_session_cannot_grow_forever() {
        let outbox = Outbox::default();
        for i in 0..(RING_CAPACITY + 50) {
            outbox.push(format!("m{i}"), false, None);
        }
        assert_eq!(outbox.ring.lock().unwrap().len(), RING_CAPACITY);
    }

    // --- Sesiones ---------------------------------------------------

    #[test]
    fn a_listener_that_polls_is_a_live_session() {
        let outbox = Outbox::default();
        outbox.register_session(S1, "NexoDeck · main", "D:/Repositorios/NexoDeck");

        let sesiones = outbox.sessions();
        assert_eq!(sesiones.len(), 1);
        assert_eq!(sesiones[0].id, S1);
        assert_eq!(sesiones[0].label, "NexoDeck · main");
        assert!(!sesiones[0].stale);
    }

    /// Aparecer y cambiar de nombre avisan; volver a consultar sin cambios no,
    /// o el selector se redibujaria cada 25 segundos.
    #[tokio::test]
    async fn appearing_notifies_but_a_routine_poll_does_not() {
        let outbox = Outbox::default();
        let mut events = outbox.subscribe();

        outbox.register_session(S1, "NexoDeck", "/x");
        assert!(matches!(
            events.recv().await.unwrap(),
            CorrespondentEvent::SessionsChanged
        ));

        outbox.register_session(S1, "NexoDeck", "/x");
        assert!(
            tokio::time::timeout(Duration::from_millis(100), events.recv())
                .await
                .is_err(),
            "una consulta de rutina no tenia que avisar"
        );
    }

    /// **Una pregunta a una sesion que nunca existio vence enseguida**, con el
    /// motivo. Esperar los quince minutos de una terminal que no esta es hacer
    /// perder el tiempo.
    #[tokio::test]
    async fn asking_a_session_that_is_not_there_fails_fast_with_a_reason() {
        let outbox = Outbox::default();
        let mut events = outbox.subscribe();
        let seq = outbox.push("hola?".into(), true, Some("no-existe".into()));

        outbox.expire_old();

        match events.recv().await.unwrap() {
            CorrespondentEvent::TimedOut { seq: got, reason } => {
                assert_eq!(got, seq);
                assert!(reason.contains("cerró"), "motivo: {reason}");
            }
            other => panic!("evento inesperado: {other:?}"),
        }
        assert_eq!(outbox.pending_count(), 0);
    }

    /// Y una pregunta a una sesion viva **no** vence.
    #[test]
    fn asking_a_live_session_does_not_expire() {
        let outbox = Outbox::default();
        outbox.register_session(S1, "NexoDeck", "/x");
        outbox.push("hola?".into(), true, Some(S1.into()));

        outbox.expire_old();
        assert_eq!(outbox.pending_count(), 1);
    }

    /// Un aviso general sin destinatario tampoco vence por sesiones cerradas:
    /// no se le pregunto a nadie en concreto.
    #[test]
    fn an_unaddressed_question_does_not_expire_for_a_closed_session() {
        let outbox = Outbox::default();
        outbox.push("para quien sea".into(), true, None);
        outbox.expire_old();
        assert_eq!(outbox.pending_count(), 1);
    }
}
