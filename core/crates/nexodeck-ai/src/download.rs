//! Descarga reanudable, verificada por SHA256 y con progreso.
//!
//! Es la parte que el usuario ve durante minutos (u horas, en gama alta con una
//! conexion hogarena), asi que las decisiones estan tomadas para que **nunca
//! haya un tramo mudo ni un reinicio silencioso**:
//!
//! - Se baja a un `.part` y se reanuda con `Range`.
//! - Si el server ignora el `Range` y responde `200`, se **descarta el
//!   parcial** en vez de appendear. Un mirror que hace eso produciria un
//!   archivo con el contenido duplicado, hash roto, y ninguna pista de por que.
//! - El SHA256 se calcula al final releyendo el archivo (un hasher incremental
//!   no sobrevive a un resume entre sesiones), en `spawn_blocking` y con su
//!   propio evento `Verifying`: en un GGUF de 18 GB son 30-60 s que si no
//!   parecerian un cuelgue.
//! - Un archivo ya verificado deja un marcador `.ok` con su hash al lado. Sin
//!   eso habria que re-hashear 18 GB en cada arranque de la app.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use futures_util::StreamExt;
use sha2::{Digest, Sha256};
use tokio::io::AsyncWriteExt;
use tokio::sync::mpsc;

use crate::catalog::ArchiveFormat;
use crate::error::{AiError, AiResult};

/// Cada cuanto se emite un evento de progreso. Suficiente para que una barra
/// se vea fluida sin inundar el canal (a 100 MB/s serian miles de eventos por
/// segundo si se emitiera por chunk).
const PROGRESS_INTERVAL: Duration = Duration::from_millis(250);

/// Extension del marcador que dice "este archivo ya se verifico".
const OK_MARKER_EXT: &str = "ok";

#[derive(Debug, Clone)]
pub struct AssetSpec {
    /// Nombre legible, el que se muestra en la UI.
    pub name: String,
    pub url: String,
    pub sha256: String,
    pub expected_bytes: u64,
    /// Donde queda el archivo final. Para un `.gguf` es el archivo mismo; para
    /// un runtime es el archivo comprimido, que despues se extrae.
    pub dest: PathBuf,
    /// Si esta presente, el archivo se descomprime ahi y el comprimido se
    /// borra.
    pub extract_to: Option<PathBuf>,
    pub format: Option<ArchiveFormat>,
}

#[derive(Debug, Clone)]
pub enum DownloadEvent {
    Started {
        asset: String,
        total_bytes: u64,
        /// Bytes que ya estaban en el `.part`. `> 0` significa que se reanudo,
        /// y la UI lo dice explicitamente: si no, parece que la barra arranca
        /// misteriosamente por la mitad.
        resumed_from: u64,
    },
    Progress {
        asset: String,
        downloaded: u64,
        total_bytes: u64,
        bytes_per_sec: u64,
    },
    Verifying {
        asset: String,
    },
    Extracting {
        asset: String,
    },
    Finished {
        asset: String,
        path: PathBuf,
    },
    Failed {
        asset: String,
        detail: String,
    },
}

/// Se asegura de que el asset este en disco, verificado y (si corresponde)
/// descomprimido. Si ya estaba, no baja nada.
pub async fn ensure_asset(
    client: &reqwest::Client,
    spec: &AssetSpec,
    tx: &mpsc::Sender<DownloadEvent>,
    cancel: Arc<AtomicBool>,
) -> AiResult<PathBuf> {
    match ensure_asset_inner(client, spec, tx, cancel).await {
        Ok(path) => {
            let _ = tx
                .send(DownloadEvent::Finished {
                    asset: spec.name.clone(),
                    path: path.clone(),
                })
                .await;
            Ok(path)
        }
        Err(error) => {
            // Ningun fallo puede quedarse sin evento: la UI se queda esperando
            // para siempre una barra que no avanza mas.
            let _ = tx
                .send(DownloadEvent::Failed {
                    asset: spec.name.clone(),
                    detail: error.to_string(),
                })
                .await;
            Err(error)
        }
    }
}

async fn ensure_asset_inner(
    client: &reqwest::Client,
    spec: &AssetSpec,
    tx: &mpsc::Sender<DownloadEvent>,
    cancel: Arc<AtomicBool>,
) -> AiResult<PathBuf> {
    let final_path = spec.extract_to.clone().unwrap_or_else(|| spec.dest.clone());

    if is_already_verified(&final_path, &spec.sha256) {
        return Ok(final_path);
    }

    let part_path = with_extension_appended(&spec.dest, "part");
    if let Some(parent) = part_path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }

    download_with_resume(client, spec, &part_path, tx, cancel.clone()).await?;

    let _ = tx
        .send(DownloadEvent::Verifying {
            asset: spec.name.clone(),
        })
        .await;
    let actual = hash_file(part_path.clone()).await?;
    if !actual.eq_ignore_ascii_case(&spec.sha256) {
        // El parcial esta envenenado: si se deja, el proximo intento lo
        // "reanuda" y vuelve a fallar igual, para siempre.
        let _ = tokio::fs::remove_file(&part_path).await;
        return Err(AiError::ChecksumMismatch {
            asset: spec.name.clone(),
            expected: spec.sha256.clone(),
            actual,
        });
    }

    match (&spec.extract_to, spec.format) {
        (Some(target), Some(format)) => {
            let _ = tx
                .send(DownloadEvent::Extracting {
                    asset: spec.name.clone(),
                })
                .await;
            extract_archive(part_path.clone(), target.clone(), format, spec.name.clone()).await?;
            // El comprimido no se guarda: en CUDA son 500 MB que no sirven
            // para nada una vez extraidos.
            let _ = tokio::fs::remove_file(&part_path).await;
            write_ok_marker(target, &spec.sha256).await?;
            Ok(target.clone())
        }
        _ => {
            tokio::fs::rename(&part_path, &spec.dest).await?;
            write_ok_marker(&spec.dest, &spec.sha256).await?;
            Ok(spec.dest.clone())
        }
    }
}

async fn download_with_resume(
    client: &reqwest::Client,
    spec: &AssetSpec,
    part_path: &Path,
    tx: &mpsc::Sender<DownloadEvent>,
    cancel: Arc<AtomicBool>,
) -> AiResult<()> {
    let existing = tokio::fs::metadata(part_path)
        .await
        .map(|meta| meta.len())
        .unwrap_or(0);

    // Un parcial mas grande que el archivo entero solo puede venir de una
    // interrupcion rara o de un cambio de version del asset: se descarta.
    let resume_from = if spec.expected_bytes > 0 && existing > spec.expected_bytes {
        let _ = tokio::fs::remove_file(part_path).await;
        0
    } else {
        existing
    };

    let mut request = client.get(&spec.url);
    if resume_from > 0 {
        request = request.header(reqwest::header::RANGE, format!("bytes={resume_from}-"));
    }

    let response = request.send().await.map_err(|e| AiError::Download {
        asset: spec.name.clone(),
        detail: e.to_string(),
    })?;

    if !response.status().is_success() {
        return Err(AiError::Download {
            asset: spec.name.clone(),
            detail: format!("el servidor respondio {}", response.status()),
        });
    }

    // ---- El detalle que cuesta encontrar si no se contempla ----
    // Pedimos un rango pero el server devolvio 200 (contenido completo). Si
    // appendearamos, el archivo quedaria con la parte vieja + el archivo
    // entero: hash roto y ninguna pista del motivo. Se empieza de cero.
    let server_honored_range = response.status() == reqwest::StatusCode::PARTIAL_CONTENT;
    let start_offset = if resume_from > 0 && server_honored_range {
        resume_from
    } else {
        0
    };

    let total_bytes = if spec.expected_bytes > 0 {
        spec.expected_bytes
    } else {
        response.content_length().unwrap_or(0) + start_offset
    };

    let _ = tx
        .send(DownloadEvent::Started {
            asset: spec.name.clone(),
            total_bytes,
            resumed_from: start_offset,
        })
        .await;

    let mut file = if start_offset > 0 {
        let mut file = tokio::fs::OpenOptions::new()
            .write(true)
            .open(part_path)
            .await?;
        file.set_len(start_offset).await?;
        file.seek_to_end().await?;
        file
    } else {
        tokio::fs::File::create(part_path).await?
    };

    let mut downloaded = start_offset;
    let mut stream = response.bytes_stream();
    let mut last_emit = Instant::now();
    let mut window_start = Instant::now();
    let mut window_bytes = 0u64;

    while let Some(chunk) = stream.next().await {
        if cancel.load(Ordering::Relaxed) {
            file.flush().await?;
            return Err(AiError::Cancelled);
        }

        let chunk = chunk.map_err(|e| AiError::Download {
            asset: spec.name.clone(),
            detail: e.to_string(),
        })?;
        file.write_all(&chunk).await?;
        downloaded += chunk.len() as u64;
        window_bytes += chunk.len() as u64;

        if last_emit.elapsed() >= PROGRESS_INTERVAL {
            let elapsed = window_start.elapsed().as_secs_f64().max(0.001);
            let _ = tx
                .send(DownloadEvent::Progress {
                    asset: spec.name.clone(),
                    downloaded,
                    total_bytes,
                    bytes_per_sec: (window_bytes as f64 / elapsed) as u64,
                })
                .await;
            last_emit = Instant::now();
            window_start = Instant::now();
            window_bytes = 0;
        }
    }

    file.flush().await?;
    Ok(())
}

/// SHA256 releyendo el archivo entero.
///
/// Va en `spawn_blocking` porque en un GGUF de 18 GB son decenas de segundos de
/// CPU y de I/O: hacerlo en el runtime async bloquearia el mismo executor que
/// mueve el WebSocket del transporte y el USB.
async fn hash_file(path: PathBuf) -> AiResult<String> {
    tokio::task::spawn_blocking(move || -> AiResult<String> {
        use std::io::Read;

        let mut file = std::fs::File::open(&path)?;
        let mut hasher = Sha256::new();
        let mut buffer = vec![0u8; 1024 * 1024];

        loop {
            let read = file.read(&mut buffer)?;
            if read == 0 {
                break;
            }
            hasher.update(&buffer[..read]);
        }

        Ok(hex_lower(&hasher.finalize()))
    })
    .await
    .map_err(|e| AiError::Download {
        asset: "hash".into(),
        detail: e.to_string(),
    })?
}

async fn extract_archive(
    archive: PathBuf,
    target: PathBuf,
    format: ArchiveFormat,
    asset_name: String,
) -> AiResult<()> {
    tokio::task::spawn_blocking(move || -> AiResult<()> {
        // Extraccion limpia: si quedo un intento anterior a medias, un archivo
        // viejo mezclado con uno nuevo produce fallos de carga de DLL
        // imposibles de diagnosticar.
        if target.exists() {
            std::fs::remove_dir_all(&target)?;
        }
        std::fs::create_dir_all(&target)?;

        let file = std::fs::File::open(&archive)?;

        match format {
            ArchiveFormat::Zip => {
                let mut zip = zip::ZipArchive::new(file).map_err(|e| AiError::Unzip {
                    asset: asset_name.clone(),
                    detail: e.to_string(),
                })?;
                zip.extract(&target).map_err(|e| AiError::Unzip {
                    asset: asset_name.clone(),
                    detail: e.to_string(),
                })?;
            }
            ArchiveFormat::TarGz => {
                let decoder = flate2::read::GzDecoder::new(file);
                let mut tar = tar::Archive::new(decoder);
                tar.unpack(&target).map_err(|e| AiError::Unzip {
                    asset: asset_name.clone(),
                    detail: e.to_string(),
                })?;
            }
        }

        Ok(())
    })
    .await
    .map_err(|e| AiError::Unzip {
        asset: "extraccion".into(),
        detail: e.to_string(),
    })?
}

// ---------------------------------------------------------------------
// Marcador de "ya verificado"
// ---------------------------------------------------------------------

fn ok_marker_path(path: &Path) -> PathBuf {
    with_extension_appended(path, OK_MARKER_EXT)
}

/// Un archivo cuenta como listo si existe y su marcador tiene el hash que
/// esperamos. Se confia en el marcador a proposito: re-hashear 18 GB en cada
/// arranque para confirmar algo que ya se confirmo seria absurdo. El marcador
/// se escribe **despues** de verificar, nunca antes.
fn is_already_verified(path: &Path, sha256: &str) -> bool {
    if !path.exists() {
        return false;
    }
    match std::fs::read_to_string(ok_marker_path(path)) {
        Ok(stored) => stored.trim().eq_ignore_ascii_case(sha256),
        Err(_) => false,
    }
}

async fn write_ok_marker(path: &Path, sha256: &str) -> AiResult<()> {
    tokio::fs::write(ok_marker_path(path), sha256).await?;
    Ok(())
}

/// `foo.gguf` + `part` -> `foo.gguf.part`. `Path::set_extension` **reemplaza**
/// la extension y dejaria `foo.part`, que colisionaria entre variantes de
/// cuantizacion del mismo modelo.
fn with_extension_appended(path: &Path, extension: &str) -> PathBuf {
    let mut name = path.as_os_str().to_os_string();
    name.push(".");
    name.push(extension);
    PathBuf::from(name)
}

fn hex_lower(bytes: &[u8]) -> String {
    use std::fmt::Write;
    bytes.iter().fold(String::with_capacity(bytes.len() * 2), |mut acc, byte| {
        let _ = write!(acc, "{byte:02x}");
        acc
    })
}

/// Cliente HTTP compartido para todas las descargas.
pub fn http_client() -> reqwest::Client {
    reqwest::Client::builder()
        // Sin timeout total: una descarga de 18 GB puede tardar horas de forma
        // perfectamente legitima. El timeout que si importa es el de conexion.
        .connect_timeout(Duration::from_secs(30))
        .user_agent(concat!("NexoDeck/", env!("CARGO_PKG_VERSION")))
        .build()
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn el_part_se_agrega_no_reemplaza_la_extension() {
        let path = Path::new("C:/x/Qwen3-14B-Q4_K_M.gguf");
        assert_eq!(
            with_extension_appended(path, "part"),
            PathBuf::from("C:/x/Qwen3-14B-Q4_K_M.gguf.part")
        );

        // Lo que pasaria con `set_extension`, y por que no se usa: dos
        // cuantizaciones distintas del mismo modelo colisionarian en el mismo
        // `.part`.
        let a = with_extension_appended(Path::new("m-Q4_K_M.gguf"), "part");
        let b = with_extension_appended(Path::new("m-Q8_0.gguf"), "part");
        assert_ne!(a, b);
    }

    #[test]
    fn hex_lower_formatea_con_ceros_a_la_izquierda() {
        assert_eq!(hex_lower(&[0x00, 0x0f, 0xff]), "000fff");
    }

    #[tokio::test]
    async fn hash_file_coincide_con_un_sha256_conocido() {
        let path = std::env::temp_dir().join(format!(
            "nexodeck-ai-hash-{}-{}.bin",
            std::process::id(),
            "abc"
        ));
        tokio::fs::write(&path, b"abc").await.unwrap();

        let hash = hash_file(path.clone()).await.unwrap();
        assert_eq!(
            hash,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );

        let _ = tokio::fs::remove_file(&path).await;
    }

    #[tokio::test]
    async fn el_marcador_solo_vale_si_el_hash_coincide() {
        let path = std::env::temp_dir().join(format!(
            "nexodeck-ai-marker-{}.bin",
            std::process::id()
        ));
        tokio::fs::write(&path, b"contenido").await.unwrap();

        assert!(
            !is_already_verified(&path, "aa"),
            "sin marcador no puede darse por verificado"
        );

        write_ok_marker(&path, "aa").await.unwrap();
        assert!(is_already_verified(&path, "aa"));
        assert!(
            !is_already_verified(&path, "bb"),
            "un hash distinto tiene que invalidar el marcador"
        );

        let _ = tokio::fs::remove_file(&path).await;
        assert!(
            !is_already_verified(&path, "aa"),
            "si el archivo no esta, el marcador no alcanza"
        );
        let _ = tokio::fs::remove_file(ok_marker_path(&path)).await;
    }
}

/// `tokio::fs::File` no tiene `seek_to_end`; este helper existe solo para que
/// el camino de reanudacion se lea de corrido arriba.
trait SeekToEnd {
    async fn seek_to_end(&mut self) -> std::io::Result<()>;
}

impl SeekToEnd for tokio::fs::File {
    async fn seek_to_end(&mut self) -> std::io::Result<()> {
        use tokio::io::AsyncSeekExt;
        self.seek(std::io::SeekFrom::End(0)).await?;
        Ok(())
    }
}
