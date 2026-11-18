//! Quitar secretos de lo que sale hacia un modelo.
//!
//! Las notas de trabajo traen de todo: una cadena de conexion copiada de un
//! `appsettings.json`, una clave de API pegada para no perderla. Nada de eso
//! tiene que viajar a un servicio remoto, y el usuario no va a acordarse de
//! limpiarlo antes de pulsar "Procesar nota". Se redacta **siempre**, antes de
//! cualquier peticion, y no solo cuando el modelo es remoto: un prompt local
//! tambien acaba en logs.
//!
//! Es una red de seguridad por patrones, no una garantia. Lo que no tiene forma
//! reconocible (una contraseña suelta en una frase) no se detecta; para eso
//! estan `privado/` y `ai: false`.

use std::sync::LazyLock;

use regex::Regex;

pub const REDACTED: &str = "[REDACTADO]";

/// Patrones cuyo texto entero es el secreto.
static WHOLE: LazyLock<Vec<Regex>> = LazyLock::new(|| {
    [
        // Bloques de clave privada PEM, con saltos de linea dentro.
        r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----",
        // OpenAI, DeepSeek, Anthropic y compañia.
        r"\bsk-[A-Za-z0-9_\-]{16,}",
        // Claves de acceso de AWS.
        r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b",
        // Tokens de GitHub y de Slack.
        r"\bgh[pousr]_[A-Za-z0-9]{30,}",
        r"\bxox[abprs]-[A-Za-z0-9\-]{10,}",
        // JWT: tres bloques base64url separados por puntos.
        r"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}",
    ]
    .iter()
    .map(|p| Regex::new(p).expect("patron de redaccion valido"))
    .collect()
});

/// `clave = valor`: se conserva la clave, que da contexto al modelo, y se
/// redacta solo el valor. Cubre `Password=...;` de las cadenas de conexion.
static KEY_VALUE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r#"(?i)\b(password|passwd|pwd|contraseña|secret|client_secret|api[_\-]?key|access[_\-]?key|secret[_\-]?key|token|auth[_\-]?token)(\s*["']?\s*[:=]\s*)("[^"\n]*"|'[^'\n]*'|[^\s;,"'\n]+)"#,
    )
    .expect("patron de redaccion valido")
});

/// Credenciales dentro de una URL: `postgres://usuario:clave@host`.
static URL_CREDENTIALS: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b([a-z][a-z0-9+.\-]*://[^:/\s@]+:)([^@\s/]+)(@)")
        .expect("patron de redaccion valido")
});

/// El texto con los secretos reemplazados, y cuantos se reemplazaron.
pub fn redact(text: &str) -> (String, usize) {
    let mut count = 0;
    let mut out = text.to_string();

    for pattern in WHOLE.iter() {
        let hits = pattern.find_iter(&out).count();
        if hits > 0 {
            count += hits;
            out = pattern.replace_all(&out, REDACTED).into_owned();
        }
    }

    let hits = KEY_VALUE
        .captures_iter(&out)
        .filter(|c| c.get(3).is_some_and(|v| !v.as_str().contains(REDACTED)))
        .count();
    if hits > 0 {
        count += hits;
        out = KEY_VALUE
            .replace_all(&out, |c: &regex::Captures| {
                if c[3].contains(REDACTED) {
                    c[0].to_string()
                } else {
                    format!("{}{}{REDACTED}", &c[1], &c[2])
                }
            })
            .into_owned();
    }

    let hits = URL_CREDENTIALS.find_iter(&out).count();
    if hits > 0 {
        count += hits;
        out = URL_CREDENTIALS
            .replace_all(&out, format!("${{1}}{REDACTED}${{3}}").as_str())
            .into_owned();
    }

    (out, count)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn clean(text: &str) -> String {
        redact(text).0
    }

    #[test]
    fn api_keys_and_tokens_are_removed() {
        let samples = [
            "la clave es sk-abcdefghijklmnop1234567890 no la pierdas",
            "AKIAIOSFODNN7EXAMPLE en la cuenta",
            "ghp_abcdefghijklmnopqrstuvwxyz0123456789",
            "xoxb-1234567890-abcdefghij",
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N",
        ];
        for sample in samples {
            let out = clean(sample);
            assert!(out.contains(REDACTED), "{sample} -> {out}");
            assert!(!out.contains("abcdefghij") || !out.contains("sk-"), "{out}");
        }
        assert!(!clean(samples[0]).contains("sk-abc"));
        assert!(!clean(samples[1]).contains("AKIAIOSFODNN7EXAMPLE"));
    }

    #[test]
    fn a_connection_string_keeps_its_shape_but_not_the_password() {
        let text = "Server=10.0.0.5;Port=5434;User Id=proyecto;Password=Sup3r$ecreta;Database=prod";
        let out = clean(text);
        assert!(out.contains("Server=10.0.0.5"), "{out}");
        assert!(out.contains(&format!("Password={REDACTED}")), "{out}");
        assert!(!out.contains("Sup3r$ecreta"), "{out}");
    }

    #[test]
    fn key_value_pairs_in_json_and_yaml_are_redacted() {
        let json = r#"{"ApiKey": "abc123secreto", "Region": "us-east-1"}"#;
        let out = clean(json);
        assert!(!out.contains("abc123secreto"), "{out}");
        assert!(out.contains("us-east-1"));

        let yaml = "token: 9f8e7d6c5b4a\nnombre: prueba";
        let out = clean(yaml);
        assert!(!out.contains("9f8e7d6c5b4a"), "{out}");
        assert!(out.contains("nombre: prueba"));
    }

    #[test]
    fn credentials_inside_a_url_are_redacted() {
        let out = clean("psql postgres://admin:clave-muy-secreta@vps.example:5435/db");
        assert!(!out.contains("clave-muy-secreta"), "{out}");
        assert!(out.contains("postgres://admin:"), "{out}");
        assert!(out.contains("@vps.example:5435/db"), "{out}");
    }

    #[test]
    fn a_private_key_block_disappears_entirely() {
        let text = "antes\n-----BEGIN RSA PRIVATE KEY-----\nMIIEow\nIBAAK\n-----END RSA PRIVATE KEY-----\ndespues";
        let out = clean(text);
        assert!(!out.contains("MIIEow"), "{out}");
        assert!(out.starts_with("antes\n") && out.ends_with("\ndespues"), "{out}");
    }

    #[test]
    fn ordinary_notes_are_left_alone() {
        let text = "## 15-sep: la deteccion va 3,5 veces mas rapida\n\n- [ ] revisar el token de la tanda R con Juan";
        let (out, count) = redact(text);
        assert_eq!(out, text);
        assert_eq!(count, 0);
    }

    #[test]
    fn redacting_twice_changes_nothing_more() {
        let once = clean("password=abc123 y sk-abcdefghijklmnop1234567890");
        let (twice, count) = redact(&once);
        assert_eq!(once, twice);
        assert_eq!(count, 0);
    }
}
