//! Donde viven los binarios y los modelos descargados.
//!
//! Todo cuelga del data dir **por usuario** que resuelve `directories`, con el
//! mismo triplete que ya usa `nexodeck-transport::tls` para el certificado
//! (`dev` / `nexodeck` / `NexoDeck`) — asi la app tiene un solo directorio de
//! datos y no dos.
//!
//! Nunca en `Program Files` ni junto al ejecutable, por dos razones: escribir
//! ahi necesita permisos de administrador, y un `.exe` recien bajado a una
//! carpeta del sistema es exactamente el patron que dispara SmartScreen.

use std::path::PathBuf;

use crate::error::{AiError, AiResult};

fn project_data_dir() -> AiResult<PathBuf> {
    let dirs =
        directories::ProjectDirs::from("dev", "nexodeck", "NexoDeck").ok_or(AiError::NoDataDir)?;
    Ok(dirs.data_dir().to_path_buf())
}

/// Raiz de todo lo que baja el asistente. Borrar esta carpeta deja la funcion
/// como recien instalada, sin tocar nada mas de la app.
pub fn ai_root() -> AiResult<PathBuf> {
    let dir = project_data_dir()?.join("ai");
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}

/// Builds de llama.cpp descomprimidas, una carpeta por `RuntimeAsset::id`.
pub fn runtimes_dir() -> AiResult<PathBuf> {
    let dir = ai_root()?.join("runtimes");
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}

/// Archivos `.gguf`. Se guardan planos (un archivo por modelo) porque tambien
/// tienen que ser faciles de borrar a mano: son los que ocupan los GB.
pub fn models_dir() -> AiResult<PathBuf> {
    let dir = ai_root()?.join("models");
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}

/// Descargas a medio terminar (`.part`). Aparte de los directorios finales
/// para que un parcial nunca se confunda con un archivo listo.
pub fn downloads_dir() -> AiResult<PathBuf> {
    let dir = ai_root()?.join("downloads");
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}

/// Salida de `llama-server` volcada a disco, para poder explicar un fallo que
/// ocurrio en una sesion anterior.
pub fn logs_dir() -> AiResult<PathBuf> {
    let dir = ai_root()?.join("logs");
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}

/// Directorio de instalacion de un runtime concreto.
pub fn runtime_dir(runtime_id: &str) -> AiResult<PathBuf> {
    Ok(runtimes_dir()?.join(runtime_id))
}

/// Ruta final de un `.gguf`.
pub fn model_path(file_name: &str) -> AiResult<PathBuf> {
    Ok(models_dir()?.join(file_name))
}

/// Busca un ejecutable por nombre dentro de un arbol ya descomprimido.
///
/// Se busca en vez de fijar una ruta relativa porque la estructura de los
/// releases de llama.cpp cambio entre versiones (antes `build/bin/`, hoy la
/// raiz del zip). Una ruta fija se rompe sola en la proxima actualizacion y el
/// sintoma seria "no se encontro el binario" sobre un zip perfectamente valido.
pub fn find_executable(root: &std::path::Path, file_name: &str) -> Option<PathBuf> {
    let mut pending = vec![root.to_path_buf()];

    while let Some(dir) = pending.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                pending.push(path);
            } else if path.file_name().and_then(|n| n.to_str()) == Some(file_name) {
                return Some(path);
            }
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn find_executable_encuentra_en_la_raiz_y_anidado() {
        let base = std::env::temp_dir().join(format!(
            "nexodeck-ai-paths-test-{}",
            std::process::id()
        ));
        let nested = base.join("build").join("bin");
        std::fs::create_dir_all(&nested).unwrap();

        // Anidado (estructura vieja de los releases).
        std::fs::write(nested.join("llama-server"), b"x").unwrap();
        assert!(find_executable(&base, "llama-server").is_some());

        // En la raiz (estructura actual).
        std::fs::write(base.join("otro-binario"), b"x").unwrap();
        assert!(find_executable(&base, "otro-binario").is_some());

        assert!(find_executable(&base, "no-esta").is_none());

        let _ = std::fs::remove_dir_all(&base);
    }
}
