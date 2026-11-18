//! Registro de decisiones del modelo `auto` y de sus resultados verificados (el equivalente de
//! «Router Replay» de la receta).
//!
//! Un fichero `decisions.jsonl`, una línea JSON por evento, de dos tipos unidos por `id`:
//!
//! - `"type": "decision"`: qué se decidió para una petición `auto` (modelo, longitud, conmutación…).
//! - `"type": "outcome"`: el **resultado verificado** de esa petición, que informa quien la comprobó
//!   (tests, compilación, revisión) con `POST /v1/feedback`. La pasarela no puede saber si una
//!   respuesta es buena; quien la verifica, sí. Sin este dato, las decisiones registradas no dicen si
//!   fueron acertadas, y sin eso las fases 9 y 10 (simulador y bucle) no tienen nada que optimizar.
//!
//! **Nunca lleva el texto de la petición**: solo medidas. Un fallo al escribir no rompe la petición:
//! se avisa una vez y se sigue sirviendo.
//!
//! Los ids de las últimas [`RECENT_CAPACITY`] decisiones se recuerdan (y se recuperan del fichero al
//! reiniciar) para poder aceptar un resultado solo de una decisión que existe, hecha por la misma
//! clave y que todavía no lo tiene.

use std::collections::{HashMap, VecDeque};
use std::fs::{File, OpenOptions};
use std::io::{self, BufRead, BufReader, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use serde_json::Value;

use crate::auth::to_hex;
use crate::logging;

/// Cuántas decisiones recientes se recuerdan para aceptar su resultado.
pub const RECENT_CAPACITY: usize = 10_000;

/// Identificador de una petición enrutada: `req_` + 8 bytes aleatorios en hexadecimal.
pub fn new_request_id() -> String {
    let mut bytes = [0u8; 8];
    // Si el sistema no da aleatoriedad (no debería pasar), se cae a la hora en nanosegundos: sigue
    // siendo único en la práctica y el id no es un secreto.
    if getrandom::fill(&mut bytes).is_err() {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|elapsed| elapsed.as_nanos() as u64)
            .unwrap_or(0);
        bytes = nanos.to_le_bytes();
    }
    format!("req_{}", to_hex(&bytes))
}

/// Qué pasó al intentar guardar el resultado de una petición.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutcomeResult {
    Recorded,
    /// No hay ninguna decisión reciente con ese id, o la hizo otra clave (no se distingue: no se le
    /// dice a quien pregunta cuál de las dos cosas es).
    UnknownId,
    /// Esa petición ya tiene resultado.
    AlreadyRecorded,
    /// El registro no está activo (no hay fichero): guardar sería un no-hacer-nada silencioso.
    Disabled,
    WriteFailed,
}

/// Lo que se recuerda de una decisión reciente.
struct Remembered {
    key: String,
    has_outcome: bool,
}

#[derive(Default)]
struct Recent {
    order: VecDeque<String>,
    entries: HashMap<String, Remembered>,
}

impl Recent {
    fn register(&mut self, id: &str, key: &str) {
        if self.entries.contains_key(id) {
            return;
        }
        self.order.push_back(id.to_string());
        self.entries.insert(id.to_string(), Remembered { key: key.to_string(), has_outcome: false });
        while self.order.len() > RECENT_CAPACITY {
            if let Some(oldest) = self.order.pop_front() {
                self.entries.remove(&oldest);
            }
        }
    }

    /// Reconstruye lo recordado a partir de una línea ya guardada (al reabrir el fichero).
    fn absorb(&mut self, line: &Value) {
        let Some(id) = line.get("id").and_then(Value::as_str) else { return };
        let key = line.get("key").and_then(Value::as_str).unwrap_or("");
        if line.get("type").and_then(Value::as_str) == Some("outcome") {
            if let Some(entry) = self.entries.get_mut(id) {
                entry.has_outcome = true;
            }
        } else {
            self.register(id, key);
        }
    }
}

pub struct DecisionLog {
    file: Mutex<Option<File>>,
    recent: Mutex<Recent>,
    warned: AtomicBool,
}

impl DecisionLog {
    /// Sin fichero: las decisiones se toman pero no se guardan (los tests y el modo por defecto).
    pub fn disabled() -> Self {
        Self { file: Mutex::new(None), recent: Mutex::new(Recent::default()), warned: AtomicBool::new(false) }
    }

    /// Añade al final del fichero, creándolo si hace falta. Nunca lo trunca. Si ya existe, recupera
    /// de él los ids recientes y cuáles tienen resultado, para que un reinicio de la pasarela no
    /// corte el vínculo entre una decisión y su resultado.
    pub fn to_file(path: &Path) -> io::Result<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let mut recent = Recent::default();
        if let Ok(existing) = File::open(path) {
            for line in BufReader::new(existing).lines().map_while(Result::ok) {
                if let Ok(value) = serde_json::from_str::<Value>(&line) {
                    recent.absorb(&value);
                }
            }
        }
        let file = OpenOptions::new().create(true).append(true).open(path)?;
        Ok(Self { file: Mutex::new(Some(file)), recent: Mutex::new(recent), warned: AtomicBool::new(false) })
    }

    pub fn is_enabled(&self) -> bool {
        self.file.lock().map(|guard| guard.is_some()).unwrap_or(false)
    }

    /// Recuerda una decisión recién tomada, para poder aceptar luego su resultado.
    pub fn register(&self, id: &str, key: &str) {
        if let Ok(mut recent) = self.recent.lock() {
            recent.register(id, key);
        }
    }

    pub fn record(&self, entry: &Value) {
        let Ok(mut guard) = self.file.lock() else { return };
        let Some(file) = guard.as_mut() else { return };
        // Una sola escritura por línea: en modo append, líneas de peticiones distintas no se
        // mezclan a mitad.
        let line = format!("{entry}\n");
        if let Err(error) = file.write_all(line.as_bytes()) {
            if !self.warned.swap(true, Ordering::Relaxed) {
                logging::line(&format!("AVISO: no se pudo escribir el registro de decisiones: {error}"));
            }
        }
    }

    /// Guarda el resultado verificado de la decisión `id`, hecha por la clave `key`. La comprobación
    /// y la escritura van dentro del mismo cerrojo: dos avisos a la vez para el mismo id no pueden
    /// grabar el resultado dos veces.
    pub fn record_outcome(&self, id: &str, key: &str, entry: &Value) -> OutcomeResult {
        if !self.is_enabled() {
            return OutcomeResult::Disabled;
        }
        let Ok(mut recent) = self.recent.lock() else { return OutcomeResult::WriteFailed };
        match recent.entries.get(id) {
            None => return OutcomeResult::UnknownId,
            Some(remembered) if remembered.key != key => return OutcomeResult::UnknownId,
            Some(remembered) if remembered.has_outcome => return OutcomeResult::AlreadyRecorded,
            Some(_) => {}
        }
        let Ok(mut guard) = self.file.lock() else { return OutcomeResult::WriteFailed };
        let Some(file) = guard.as_mut() else { return OutcomeResult::Disabled };
        if file.write_all(format!("{entry}\n").as_bytes()).is_err() {
            return OutcomeResult::WriteFailed;
        }
        if let Some(remembered) = recent.entries.get_mut(id) {
            remembered.has_outcome = true;
        }
        OutcomeResult::Recorded
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn read_lines(path: &Path) -> Vec<Value> {
        std::fs::read_to_string(path)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect()
    }

    #[test]
    fn a_disabled_log_accepts_records_and_does_nothing() {
        let log = DecisionLog::disabled();
        log.record(&json!({ "a": 1 }));
        assert!(!log.is_enabled());
        assert_eq!(log.record_outcome("req_x", "k", &json!({})), OutcomeResult::Disabled);
    }

    #[test]
    fn each_record_is_one_json_line_and_the_file_is_appended() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("decisions.jsonl");

        let first = DecisionLog::to_file(&path).unwrap();
        first.record(&json!({ "n": 1 }));
        drop(first);
        // Reabrir NO debe truncar lo anterior.
        let second = DecisionLog::to_file(&path).unwrap();
        second.record(&json!({ "n": 2 }));

        let lines = read_lines(&path);
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[0]["n"], 1);
        assert_eq!(lines[1]["n"], 2);
    }

    #[test]
    fn request_ids_have_a_fixed_shape_and_do_not_repeat() {
        let first = new_request_id();
        assert!(first.starts_with("req_") && first.len() == 4 + 16, "{first}");
        assert_ne!(first, new_request_id());
    }

    #[test]
    fn an_outcome_is_accepted_once_for_a_known_decision() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("decisions.jsonl");
        let log = DecisionLog::to_file(&path).unwrap();
        log.register("req_a", "nexodeck");

        let outcome = json!({ "type": "outcome", "id": "req_a", "verified": true });
        assert_eq!(log.record_outcome("req_a", "nexodeck", &outcome), OutcomeResult::Recorded);
        assert_eq!(log.record_outcome("req_a", "nexodeck", &outcome), OutcomeResult::AlreadyRecorded);
        assert_eq!(read_lines(&path).len(), 1, "el segundo aviso no debe escribir nada");
    }

    #[test]
    fn an_unknown_id_and_another_keys_id_are_indistinguishable() {
        let directory = tempfile::tempdir().unwrap();
        let log = DecisionLog::to_file(&directory.path().join("decisions.jsonl")).unwrap();
        log.register("req_a", "nexodeck");
        let outcome = json!({ "id": "req_a" });

        assert_eq!(log.record_outcome("req_desconocido", "nexodeck", &outcome), OutcomeResult::UnknownId);
        assert_eq!(log.record_outcome("req_a", "otra-clave", &outcome), OutcomeResult::UnknownId);
        // Y el intento de la otra clave no ha consumido el resultado de la dueña.
        assert_eq!(log.record_outcome("req_a", "nexodeck", &outcome), OutcomeResult::Recorded);
    }

    #[test]
    fn only_the_most_recent_decisions_are_remembered() {
        let directory = tempfile::tempdir().unwrap();
        let log = DecisionLog::to_file(&directory.path().join("decisions.jsonl")).unwrap();
        for index in 0..(RECENT_CAPACITY + 5) {
            log.register(&format!("req_{index}"), "k");
        }
        let outcome = json!({});
        assert_eq!(log.record_outcome("req_0", "k", &outcome), OutcomeResult::UnknownId, "la más antigua se olvidó");
        assert_eq!(
            log.record_outcome(&format!("req_{}", RECENT_CAPACITY + 4), "k", &outcome),
            OutcomeResult::Recorded
        );
    }

    #[test]
    fn reopening_the_file_keeps_the_link_between_decisions_and_outcomes() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("decisions.jsonl");

        let first = DecisionLog::to_file(&path).unwrap();
        first.register("req_con", "k");
        first.register("req_sin", "k");
        first.record(&json!({ "type": "decision", "id": "req_con", "key": "k" }));
        first.record(&json!({ "type": "decision", "id": "req_sin", "key": "k" }));
        first.record_outcome("req_con", "k", &json!({ "type": "outcome", "id": "req_con", "key": "k" }));
        drop(first);

        // Un reinicio de la pasarela: se recuerda cuál ya tiene resultado y cuál no.
        let second = DecisionLog::to_file(&path).unwrap();
        let outcome = json!({ "type": "outcome" });
        assert_eq!(second.record_outcome("req_con", "k", &outcome), OutcomeResult::AlreadyRecorded);
        assert_eq!(second.record_outcome("req_sin", "k", &outcome), OutcomeResult::Recorded);
    }

    #[test]
    fn a_corrupt_line_in_the_file_does_not_stop_the_recovery() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("decisions.jsonl");
        std::fs::write(&path, "esto no es json\n{\"type\":\"decision\",\"id\":\"req_ok\",\"key\":\"k\"}\n").unwrap();

        let log = DecisionLog::to_file(&path).unwrap();
        assert_eq!(log.record_outcome("req_ok", "k", &json!({})), OutcomeResult::Recorded);
    }
}
