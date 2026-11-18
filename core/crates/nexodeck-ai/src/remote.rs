//! Proveedores de chat **por internet**: DeepSeek, OpenAI, o cualquier otro
//! que hable el dialecto de OpenAI.
//!
//! No es un rediseno, y el `enum ChatProvider` ya lo habia anticipado: "el modo
//! online futuro seria una tercera variante, no un plugin". Lo unico que cambia
//! respecto del sidecar y de Ollama es de donde sale la direccion base, que
//! modelo se pide, y una cabecera de autorizacion que hasta ahora no hacia
//! falta porque el servidor estaba en loopback.
//!
//! ## Donde vive la clave, y por que en claro
//!
//! En un fichero por proveedor dentro del directorio de datos del usuario, al
//! lado de los modelos y del certificado del host. **En texto plano**, y eso
//! hay que decirlo en voz alta en la UI en vez de dejarlo implicito.
//!
//! La regla del proyecto es que los secretos no tocan Drift en claro, y esto no
//! lo hace. Pero el sitio *correcto* seria `nexodeck-vault`, que sigue siendo un
//! stub (Fase 7). Es la **segunda** vez que el vault aparece como el sitio que
//! deberia existir: la primera fue el token del servidor de control. Cuando la
//! Fase 7 se aborde, estas dos son las que hay que mudar.
//!
//! Un fichero por proveedor y no uno compartido: cambiar de DeepSeek a OpenAI y
//! volver no puede hacer que pierdas la clave de la anterior.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::error::{AiError, AiResult};

/// Un servicio conocido, para que configurarlo sea elegir de una lista en vez
/// de escribir una URL.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemotePreset {
    pub id: String,
    pub label: String,
    pub base_url: String,
    /// Lo que se propone si el usuario no elige otro. No es el "mejor" modelo:
    /// es uno que existe y sirve para conversar, y la lista real se pide con
    /// `/v1/models` cuando ya hay clave.
    pub default_model: String,
    /// Donde saca el usuario su clave. Sin esto, "hace falta una clave" es un
    /// callejon sin salida para quien no sepa de donde sacarla.
    pub api_keys_url: String,
}

/// El identificador reservado para "escribi la direccion a mano". No es un
/// preset con URL fija a proposito: cubre servicios compatibles que no
/// conocemos, incluido un proxy propio.
pub const CUSTOM_PRESET_ID: &str = "custom";

pub fn presets() -> Vec<RemotePreset> {
    vec![
        RemotePreset {
            id: "deepseek".into(),
            label: "DeepSeek".into(),
            base_url: "https://api.deepseek.com".into(),
            default_model: "deepseek-flash".into(),
            api_keys_url: "https://platform.deepseek.com/api_keys".into(),
        },
        RemotePreset {
            id: "openai".into(),
            label: "OpenAI".into(),
            base_url: "https://api.openai.com".into(),
            default_model: "gpt-4o-mini".into(),
            api_keys_url: "https://platform.openai.com/api-keys".into(),
        },
        // El proxy propio. A proposito **sin** direccion, modelo ni pagina de
        // claves fijos: los escribe el usuario. Es la via para un servicio
        // compatible que no conocemos, y en este equipo para la pasarela del
        // stack multiagente (`http://127.0.0.1:8888`, clave `ndk_...`).
        RemotePreset {
            id: CUSTOM_PRESET_ID.into(),
            label: "Otro (proxy propio)".into(),
            base_url: String::new(),
            default_model: String::new(),
            api_keys_url: String::new(),
        },
    ]
}

pub fn preset(id: &str) -> Option<RemotePreset> {
    presets().into_iter().find(|p| p.id == id)
}

fn keys_dir() -> AiResult<PathBuf> {
    let dir = crate::paths::ai_root()?.join("keys");
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}

/// El nombre del fichero sale del id **saneado**, no del id crudo: un id con
/// `..` o con una barra escribiria fuera del directorio. Hoy los ids son
/// nuestros, pero `custom` deja que el usuario elija uno.
fn key_path(provider_id: &str) -> AiResult<PathBuf> {
    let safe: String = provider_id
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
        .collect();
    if safe.is_empty() {
        return Err(AiError::Provider(
            "el identificador del proveedor no puede estar vacio".into(),
        ));
    }
    Ok(keys_dir()?.join(format!("{safe}.key")))
}

/// Ruta del fichero de la clave de un proveedor. La necesita la pasarela del
/// stack para reenviar a un servicio remoto sin duplicar el secreto: en
/// `gateway.json` viaja **la ruta**, nunca la clave.
pub fn api_key_path(provider_id: &str) -> AiResult<PathBuf> {
    key_path(provider_id)
}

pub fn save_api_key(provider_id: &str, api_key: &str) -> AiResult<()> {
    let key = api_key.trim();
    if key.is_empty() {
        return Err(AiError::Provider("la clave de API esta vacia".into()));
    }
    let path = key_path(provider_id)?;
    std::fs::write(&path, key)?;
    restrict_permissions(&path);
    Ok(())
}

/// `None` si no hay clave guardada. Un fichero vacio cuenta como ausente: es un
/// guardado que murio a medias, y devolverlo como clave daria un 401 cuyo
/// motivo no apuntaria a ningun lado.
pub fn load_api_key(provider_id: &str) -> AiResult<Option<String>> {
    let path = key_path(provider_id)?;
    match std::fs::read_to_string(&path) {
        Ok(raw) => {
            let key = raw.trim().to_string();
            Ok(if key.is_empty() { None } else { Some(key) })
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.into()),
    }
}

pub fn forget_api_key(provider_id: &str) -> AiResult<()> {
    let path = key_path(provider_id)?;
    match std::fs::remove_file(&path) {
        Ok(()) => Ok(()),
        // Borrar algo que no esta no es un error: el resultado pedido ya se
        // cumple.
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.into()),
    }
}

/// En Unix, solo el dueno. En Windows no se hace nada: el fichero hereda la ACL
/// del perfil del usuario, que ya excluye a los demas usuarios, y forzar una ACL
/// propia sin necesidad es como se rompen los perfiles moviles.
#[cfg(unix)]
fn restrict_permissions(path: &std::path::Path) {
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
}

#[cfg(not(unix))]
fn restrict_permissions(_path: &std::path::Path) {}

/// Normaliza lo que escribio el usuario en una direccion base usable.
///
/// Quita la barra final y **el sufijo `/v1`**, que es el error mas facil de
/// cometer: la documentacion de casi todos estos servicios enseña la URL
/// completa del endpoint, y pegarla tal cual daria `/v1/v1/chat/completions`
/// con un 404 que no explica nada.
pub fn normalize_base_url(raw: &str) -> AiResult<String> {
    let trimmed = raw.trim().trim_end_matches('/');
    if trimmed.is_empty() {
        return Err(AiError::Provider("la direccion base esta vacia".into()));
    }
    if !trimmed.starts_with("http://") && !trimmed.starts_with("https://") {
        return Err(AiError::Provider(format!(
            "la direccion base tiene que empezar por http:// o https:// ('{trimmed}')"
        )));
    }
    let without_v1 = trimmed
        .strip_suffix("/chat/completions")
        .unwrap_or(trimmed)
        .trim_end_matches('/');
    let without_v1 = without_v1.strip_suffix("/v1").unwrap_or(without_v1);
    Ok(without_v1.trim_end_matches('/').to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_known_presets_are_well_formed() {
        for preset in presets() {
            assert!(!preset.label.is_empty());
            // "Otro (proxy propio)" no trae direccion, modelo ni pagina de
            // claves a proposito: los escribe el usuario. No sigue las reglas
            // de un servicio publico porque no lo es.
            if preset.id == CUSTOM_PRESET_ID {
                assert!(preset.base_url.is_empty());
                assert!(preset.api_keys_url.is_empty());
                continue;
            }
            assert!(preset.base_url.starts_with("https://"));
            assert!(!preset.default_model.is_empty());
            assert!(preset.api_keys_url.starts_with("https://"));
            // La normalizacion tiene que dejar los presets intactos, o el
            // primer arranque ya cambiaria la URL que mostramos.
            assert_eq!(normalize_base_url(&preset.base_url).unwrap(), preset.base_url);
        }
        // Y "otro" tiene que seguir en la lista: es la unica via para un proxy
        // propio, y sin el la pasarela local no se puede dar de alta.
        assert!(presets().iter().any(|p| p.id == CUSTOM_PRESET_ID));
    }

    /// El error mas facil de cometer: pegar la URL completa del endpoint que
    /// enseña la documentacion del servicio.
    #[test]
    fn pasting_the_full_endpoint_url_still_works() {
        for raw in [
            "https://api.deepseek.com/v1/chat/completions",
            "https://api.deepseek.com/v1/",
            "https://api.deepseek.com/v1",
            "https://api.deepseek.com/",
        ] {
            assert_eq!(
                normalize_base_url(raw).unwrap(),
                "https://api.deepseek.com",
                "fallo con {raw}"
            );
        }
    }

    #[test]
    fn a_base_url_without_scheme_is_refused_with_a_reason() {
        let err = normalize_base_url("api.deepseek.com").unwrap_err();
        assert!(err.to_string().contains("http"));
        assert!(normalize_base_url("   ").is_err());
    }

    /// Un id con separadores no puede escribir fuera del directorio de claves.
    #[test]
    fn a_provider_id_can_never_escape_the_keys_directory() {
        let dir = keys_dir().unwrap();
        for evil in ["../../fuera", "a/b", r"a\b", ".."] {
            let path = key_path(evil).unwrap();
            assert_eq!(
                path.parent().unwrap(),
                dir,
                "'{evil}' se salio del directorio"
            );
        }
    }

    #[test]
    fn a_key_survives_a_round_trip_and_can_be_forgotten() {
        let id = format!("test_{}", std::process::id());
        save_api_key(&id, "  sk-secreta  ").unwrap();
        // Se guarda recortada: un espacio pegado al copiar daria un 401 cuyo
        // motivo no apuntaria a ningun lado.
        assert_eq!(load_api_key(&id).unwrap().as_deref(), Some("sk-secreta"));

        forget_api_key(&id).unwrap();
        assert_eq!(load_api_key(&id).unwrap(), None);
        // Idempotente.
        forget_api_key(&id).unwrap();
    }

    #[test]
    fn an_empty_key_is_refused_and_an_empty_file_reads_as_absent() {
        let id = format!("test_empty_{}", std::process::id());
        assert!(save_api_key(&id, "   ").is_err());

        std::fs::write(key_path(&id).unwrap(), "   ").unwrap();
        assert_eq!(load_api_key(&id).unwrap(), None);
        forget_api_key(&id).unwrap();
    }
}
