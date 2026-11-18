//! Autenticación por clave de API.
//!
//! Decisiones que no son obvias:
//!
//! - **Solo se guarda el hash SHA-256 de cada clave**, nunca la clave. La clave completa se enseña
//!   una única vez, al crearla. Un `keys.json` filtrado no da acceso a nada.
//! - **La comparación es en tiempo constante** y recorre *todas* las claves sin cortar al primer
//!   acierto, para que el tiempo de respuesta no delate si una clave existe ni en qué posición.
//! - **Sin ninguna clave configurada, nadie entra.** El estado por defecto es denegar.
//! - **El fichero se relee cuando cambia** (fecha de modificación), así que crear o revocar una
//!   clave surte efecto sin reiniciar la pasarela.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::RwLock;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// Prefijo legible de las claves, para reconocerlas en un fichero de configuración o un log.
const KEY_PREFIX: &str = "ndk_";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KeyEntry {
    pub name: String,
    /// SHA-256 de la clave, en hexadecimal.
    pub sha256: String,
    /// Segundos desde el epoch en que se creó.
    pub created_unix: u64,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct KeyFile {
    keys: Vec<KeyEntry>,
}

#[derive(Default)]
struct Cache {
    modified: Option<SystemTime>,
    keys: Vec<KeyEntry>,
}

pub struct KeyStore {
    path: PathBuf,
    cache: RwLock<Cache>,
}

pub fn hash_key(key: &str) -> [u8; 32] {
    Sha256::digest(key.as_bytes()).into()
}

pub fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

/// Comparación sin cortocircuito: acumula las diferencias de todos los bytes.
fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    let mut difference = 0u8;
    for (a, b) in left.iter().zip(right) {
        difference |= a ^ b;
    }
    difference == 0
}

/// Genera una clave nueva: `ndk_` + 32 bytes aleatorios del sistema en hexadecimal (256 bits).
pub fn generate_key() -> io::Result<String> {
    let mut bytes = [0u8; 32];
    getrandom::fill(&mut bytes).map_err(|error| io::Error::other(format!("sin fuente de aleatoriedad: {error}")))?;
    Ok(format!("{KEY_PREFIX}{}", to_hex(&bytes)))
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or(0)
}

fn modified_time(path: &Path) -> Option<SystemTime> {
    fs::metadata(path).and_then(|metadata| metadata.modified()).ok()
}

impl KeyStore {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            cache: RwLock::new(Cache::default()),
        }
    }

    fn read_file(&self) -> io::Result<KeyFile> {
        match fs::read_to_string(&self.path) {
            Ok(text) => serde_json::from_str(&text).map_err(|error| {
                io::Error::new(
                    io::ErrorKind::InvalidData,
                    format!("{} no es un JSON válido: {error}", self.path.display()),
                )
            }),
            // Sin fichero no hay claves: se deniega todo, no se falla.
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(KeyFile::default()),
            Err(error) => Err(error),
        }
    }

    /// Escritura atómica (temporal + renombrado): una pasarela que relee el fichero mientras se
    /// escribe no debe ver nunca un JSON a medias.
    fn write_file(&self, file: &KeyFile) -> io::Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        let temporary = self.path.with_extension("json.tmp");
        let text = serde_json::to_string_pretty(file).expect("las claves siempre se serializan");
        fs::write(&temporary, text + "\n")?;
        fs::rename(&temporary, &self.path)
    }

    pub fn list(&self) -> io::Result<Vec<KeyEntry>> {
        Ok(self.read_file()?.keys)
    }

    /// Crea una clave con ese nombre y la devuelve. Es la única vez que existe en claro.
    pub fn add(&self, name: &str) -> io::Result<String> {
        let name = name.trim();
        if name.is_empty() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "el nombre no puede estar vacío"));
        }
        let mut file = self.read_file()?;
        if file.keys.iter().any(|entry| entry.name == name) {
            return Err(io::Error::new(
                io::ErrorKind::AlreadyExists,
                format!("ya existe una clave llamada '{name}'"),
            ));
        }
        let key = generate_key()?;
        file.keys.push(KeyEntry {
            name: name.to_string(),
            sha256: to_hex(&hash_key(&key)),
            created_unix: now_unix(),
        });
        self.write_file(&file)?;
        Ok(key)
    }

    /// Revoca una clave. Devuelve `false` si no existía.
    pub fn remove(&self, name: &str) -> io::Result<bool> {
        let mut file = self.read_file()?;
        let before = file.keys.len();
        file.keys.retain(|entry| entry.name != name);
        if file.keys.len() == before {
            return Ok(false);
        }
        self.write_file(&file)?;
        Ok(true)
    }

    /// Vuelve a leer el fichero solo si ha cambiado desde la última lectura.
    fn refresh(&self) {
        let current = modified_time(&self.path);
        let unchanged = self
            .cache
            .read()
            .map(|cache| cache.modified == current)
            .unwrap_or(false);
        if unchanged {
            return;
        }
        // Si el fichero no se puede leer (o está corrupto) se queda sin claves: denegar.
        let keys = self.read_file().map(|file| file.keys).unwrap_or_default();
        if let Ok(mut cache) = self.cache.write() {
            cache.modified = current;
            cache.keys = keys;
        }
    }

    /// Devuelve el nombre de la clave si `key` es válida.
    pub fn verify(&self, key: &str) -> Option<String> {
        self.refresh();
        let candidate = hash_key(key);
        let cache = self.cache.read().ok()?;

        let mut found: Option<&KeyEntry> = None;
        for entry in &cache.keys {
            // Se comparan todas, sin `break`: el tiempo no depende de cuál coincide.
            let stored = decode_hex(&entry.sha256);
            if constant_time_eq(&candidate, &stored) {
                found = Some(entry);
            }
        }
        found.map(|entry| entry.name.clone())
    }
}

/// Hexadecimal a bytes. Una cadena mal formada da un vector vacío, que nunca iguala a un hash de
/// 32 bytes: la entrada corrupta queda inutilizable en vez de romper la comprobación.
fn decode_hex(text: &str) -> Vec<u8> {
    if !text.len().is_multiple_of(2) {
        return Vec::new();
    }
    (0..text.len())
        .step_by(2)
        .map(|index| u8::from_str_radix(&text[index..index + 2], 16))
        .collect::<Result<Vec<u8>, _>>()
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> (tempfile::TempDir, KeyStore) {
        let dir = tempfile::tempdir().unwrap();
        let store = KeyStore::new(dir.path().join("keys.json"));
        (dir, store)
    }

    #[test]
    fn generated_keys_have_prefix_and_256_bits() {
        let key = generate_key().unwrap();
        assert!(key.starts_with("ndk_"));
        assert_eq!(key.len(), 4 + 64);
        assert_ne!(key, generate_key().unwrap(), "dos claves seguidas no pueden coincidir");
    }

    #[test]
    fn a_new_key_verifies_and_returns_its_name() {
        let (_dir, store) = store();
        let key = store.add("nexodeck").unwrap();
        assert_eq!(store.verify(&key).as_deref(), Some("nexodeck"));
    }

    #[test]
    fn a_wrong_key_is_rejected() {
        let (_dir, store) = store();
        store.add("nexodeck").unwrap();
        assert_eq!(store.verify("ndk_incorrecta"), None);
        assert_eq!(store.verify(""), None);
    }

    #[test]
    fn without_any_key_nobody_gets_in() {
        let (_dir, store) = store();
        assert_eq!(store.verify("lo-que-sea"), None);
    }

    #[test]
    fn the_key_is_never_stored_in_clear() {
        let (dir, store) = store();
        let key = store.add("nexodeck").unwrap();
        let on_disk = fs::read_to_string(dir.path().join("keys.json")).unwrap();
        assert!(!on_disk.contains(&key), "la clave en claro no puede estar en el fichero");
        assert!(on_disk.contains(&to_hex(&hash_key(&key))));
    }

    #[test]
    fn a_revoked_key_stops_working_without_restarting() {
        let (_dir, store) = store();
        let key = store.add("temporal").unwrap();
        assert!(store.verify(&key).is_some());
        assert!(store.remove("temporal").unwrap());
        assert_eq!(store.verify(&key), None);
    }

    #[test]
    fn duplicate_and_empty_names_are_refused() {
        let (_dir, store) = store();
        store.add("uno").unwrap();
        assert_eq!(store.add("uno").unwrap_err().kind(), io::ErrorKind::AlreadyExists);
        assert_eq!(store.add("  ").unwrap_err().kind(), io::ErrorKind::InvalidInput);
    }

    #[test]
    fn removing_an_unknown_key_reports_false() {
        let (_dir, store) = store();
        assert!(!store.remove("no-existe").unwrap());
    }

    #[test]
    fn a_corrupt_keys_file_denies_everyone() {
        let (dir, store) = store();
        fs::write(dir.path().join("keys.json"), "esto no es json").unwrap();
        assert_eq!(store.verify("ndk_lo-que-sea"), None);
    }

    #[test]
    fn a_malformed_stored_hash_never_matches() {
        assert!(decode_hex("zz").is_empty());
        assert!(decode_hex("abc").is_empty());
        assert!(!constant_time_eq(&hash_key("x"), &decode_hex("zz")));
    }

    #[test]
    fn constant_time_eq_needs_equal_length_and_content() {
        assert!(constant_time_eq(b"abcd", b"abcd"));
        assert!(!constant_time_eq(b"abcd", b"abce"));
        assert!(!constant_time_eq(b"abcd", b"abc"));
    }
}
