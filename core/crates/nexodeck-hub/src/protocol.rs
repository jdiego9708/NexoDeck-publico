//! Framing del protocolo JSON Hub de SignalR -- funciones puras, sin red,
//! para poder testearlas sin levantar un servidor real.
//!
//! Referencia: SignalR separa cada mensaje con el caracter Record Separator
//! (`\x1e`, `U+001E`), tanto en el handshake inicial como en los mensajes
//! posteriores. El handshake es un caso especial: la respuesta es `{}` (o
//! `{"error":"..."}`), sin el campo `type` que sí llevan el resto.

pub const RECORD_SEPARATOR: char = '\u{1e}';

/// El mensaje de handshake que el cliente manda primero, siempre. `version:1`
/// es el protocolo JSON (el binario MessagePack queda fuera de alcance, ver
/// el plan -- JSON alcanza y es mucho mas facil de debuggear a mano).
pub fn handshake_message() -> String {
    format!("{{\"protocol\":\"json\",\"version\":1}}{RECORD_SEPARATOR}")
}

/// Un mensaje `Invocation` (type 1): lo que usa el cliente para llamar un
/// metodo del hub (`SubscribeToJob`) -- serde_json arma el JSON, asi que un
/// argumento con comillas o un jobId numerico se serializan bien solos, sin
/// que este modulo tenga que saber de que tipo son.
pub fn invocation_message(target: &str, arguments: &[serde_json::Value]) -> String {
    let payload = serde_json::json!({
        "type": 1,
        "target": target,
        "arguments": arguments,
    });
    format!("{payload}{RECORD_SEPARATOR}")
}

/// Parte un frame de texto (que puede traer varios mensajes SignalR
/// pegados, o ninguno si el frame esta vacio) en los registros individuales,
/// ya sin el separador.
pub fn split_records(frame: &str) -> Vec<&str> {
    frame
        .split(RECORD_SEPARATOR)
        .filter(|s| !s.is_empty())
        .collect()
}

#[derive(Debug, Clone, PartialEq)]
pub enum HubMessage {
    HandshakeAck,
    HandshakeError(String),
    /// Server -> client: invoco un metodo nuestro (`ReceivePlantTrainingProgress`).
    /// `arguments_json` queda tal cual vino (un array JSON serializado) --
    /// quien llama decide como mostrarlo, este modulo no interpreta el
    /// contenido de la app.
    Invocation {
        target: String,
        arguments_json: String,
    },
    /// Keep-alive del servidor. Se ignora: no hace falta responder para que
    /// la conexion siga viva del lado del cliente.
    Ping,
    Close {
        error: Option<String>,
    },
    /// StreamItem/Completion/StreamInvocation/CancelInvocation -- ningun uso
    /// hoy (no invocamos streams ni mandamos cancelaciones), pero se
    /// reconocen para no confundirlos con basura.
    Other(String),
}

/// Interpreta un registro ya separado. `expecting_handshake` es `true`
/// unicamente para el PRIMER registro que llega despues de mandar el
/// handshake -- ese no lleva `type`, todo lo que sigue si.
pub fn parse_record(record: &str, expecting_handshake: bool) -> HubMessage {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(record) else {
        return if expecting_handshake {
            HubMessage::HandshakeError(format!("respuesta invalida: {record}"))
        } else {
            HubMessage::Other(record.to_string())
        };
    };

    if expecting_handshake {
        return match value.get("error").and_then(|e| e.as_str()) {
            Some(err) => HubMessage::HandshakeError(err.to_string()),
            None => HubMessage::HandshakeAck,
        };
    }

    match value.get("type").and_then(|t| t.as_i64()) {
        Some(1) => {
            let target = value
                .get("target")
                .and_then(|t| t.as_str())
                .unwrap_or_default()
                .to_string();
            let arguments_json = value
                .get("arguments")
                .map(|a| a.to_string())
                .unwrap_or_else(|| "[]".to_string());
            HubMessage::Invocation {
                target,
                arguments_json,
            }
        }
        Some(6) => HubMessage::Ping,
        Some(7) => {
            let error = value
                .get("error")
                .and_then(|e| e.as_str())
                .map(String::from);
            HubMessage::Close { error }
        }
        _ => HubMessage::Other(record.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handshake_message_termina_en_record_separator() {
        let msg = handshake_message();
        assert!(msg.ends_with(RECORD_SEPARATOR));
        assert_eq!(&msg[..msg.len() - RECORD_SEPARATOR.len_utf8()], r#"{"protocol":"json","version":1}"#);
    }

    #[test]
    fn invocation_message_arma_target_y_argumentos() {
        let msg = invocation_message("SubscribeToJob", &[serde_json::json!("job-123")]);
        assert!(msg.starts_with(r#"{"arguments":["job-123"],"type":1,"target":"SubscribeToJob"}"#) || msg.contains("\"target\":\"SubscribeToJob\""));
        assert!(msg.contains("job-123"));
        assert!(msg.ends_with(RECORD_SEPARATOR));
    }

    #[test]
    fn split_records_separa_varios_mensajes_pegados() {
        let frame = format!("{{\"a\":1}}{RECORD_SEPARATOR}{{\"b\":2}}{RECORD_SEPARATOR}");
        assert_eq!(split_records(&frame), vec![r#"{"a":1}"#, r#"{"b":2}"#]);
    }

    #[test]
    fn split_records_ignora_registros_vacios() {
        assert_eq!(split_records(""), Vec::<&str>::new());
        assert_eq!(split_records(&RECORD_SEPARATOR.to_string()), Vec::<&str>::new());
    }

    #[test]
    fn handshake_ack_vacio_es_exito() {
        assert_eq!(parse_record("{}", true), HubMessage::HandshakeAck);
    }

    #[test]
    fn handshake_con_error_se_reporta() {
        assert_eq!(
            parse_record(r#"{"error":"protocolo no soportado"}"#, true),
            HubMessage::HandshakeError("protocolo no soportado".to_string())
        );
    }

    #[test]
    fn invocation_entrante_se_reconoce() {
        let record = r#"{"type":1,"target":"ReceivePlantTrainingProgress","arguments":[{"pct":50}]}"#;
        assert_eq!(
            parse_record(record, false),
            HubMessage::Invocation {
                target: "ReceivePlantTrainingProgress".to_string(),
                arguments_json: r#"[{"pct":50}]"#.to_string(),
            }
        );
    }

    #[test]
    fn ping_se_reconoce() {
        assert_eq!(parse_record(r#"{"type":6}"#, false), HubMessage::Ping);
    }

    #[test]
    fn close_con_error_se_reconoce() {
        assert_eq!(
            parse_record(r#"{"type":7,"error":"conexion perdida"}"#, false),
            HubMessage::Close {
                error: Some("conexion perdida".to_string())
            }
        );
    }
}
