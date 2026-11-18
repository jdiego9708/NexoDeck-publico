//! Orquesta la instalacion: que hay que bajar, cuanto pesa, y dejarlo listo.
//!
//! Separa dos preguntas que la UI necesita responder por separado:
//!
//! - **¿Que va a pasar si acepto?** ([`SetupPlan`]) — se resuelve sin tocar la
//!   red, para poder mostrar el tamano exacto *antes* de empezar. Bajar 18 GB
//!   sin avisar no es una opcion.
//! - **¿Ya esta listo?** ([`installed_assets`]) — se resuelve sin descargar
//!   nada, para que reabrir la app no vuelva a la pantalla de descarga.

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::AtomicBool;

use nexodeck_hardware::HostOs;
use tokio::sync::mpsc;

use crate::catalog::{self, ArchiveFormat, ModelEntry, RuntimeAsset};
use crate::download::{self, AssetSpec, DownloadEvent};
use crate::error::{AiError, AiResult};
use crate::paths;
use crate::plan::{RuntimePlan, required_disk_mb};

#[derive(Debug, Clone)]
pub struct SetupPlan {
    pub runtime: &'static RuntimeAsset,
    pub model: &'static ModelEntry,
}

impl SetupPlan {
    /// Lo que hay que bajar en total, contando el CUDA runtime cuando aplica.
    /// Este es el numero que el wizard muestra antes de pedir confirmacion.
    pub fn total_download_bytes(&self) -> u64 {
        self.runtime.total_bytes() + self.model.file_bytes
    }

    pub fn total_download_mb(&self) -> u64 {
        self.total_download_bytes() / (1024 * 1024)
    }
}

/// Resuelve que runtime y que modelo corresponden. `model_id` sobreescribe la
/// recomendacion (el usuario puede elegir a mano en el wizard).
pub fn resolve_setup(
    plan: &RuntimePlan,
    os: HostOs,
    model_id: Option<&str>,
) -> AiResult<SetupPlan> {
    let runtime = catalog::runtime_for(plan.backend, os).ok_or_else(|| {
        AiError::NoRuntimeForTarget {
            backend: plan.backend.as_str().to_string(),
            os: os.as_str().to_string(),
        }
    })?;

    let model = match model_id {
        Some(id) => catalog::model_by_id(id).ok_or_else(|| AiError::UnknownModel(id.to_string()))?,
        None => plan.default_model(),
    };

    Ok(SetupPlan { runtime, model })
}

#[derive(Debug, Clone)]
pub struct InstalledAssets {
    pub server_path: PathBuf,
    pub model_path: PathBuf,
}

/// Devuelve las rutas si **ya** esta todo instalado, sin bajar ni verificar
/// nada. `None` significa "hay que correr el setup".
pub fn installed_assets(setup: &SetupPlan) -> Option<InstalledAssets> {
    let runtime_dir = paths::runtime_dir(setup.runtime.id).ok()?;
    let server_path = paths::find_executable(&runtime_dir, setup.runtime.server_file_name)?;
    let model_path = paths::model_path(setup.model.file_name).ok()?;

    if !model_path.exists() {
        return None;
    }

    Some(InstalledAssets {
        server_path,
        model_path,
    })
}

/// Comprueba que el disco alcance antes de empezar.
///
/// Se chequea aca y no solo en `plan_runtime` porque el usuario puede elegir a
/// mano un modelo mas grande que el recomendado, y porque entre que se armo el
/// plan y que apreto "Descargar" puede haber pasado cualquier cosa con el
/// disco.
pub fn check_disk_space(setup: &SetupPlan) -> AiResult<()> {
    let models_dir = paths::models_dir()?;
    let free_mb = nexodeck_hardware::free_disk_mb(&models_dir);
    let needed_mb =
        required_disk_mb(setup.model) + (setup.runtime.total_bytes() / (1024 * 1024)) * 2;

    if needed_mb > free_mb {
        return Err(AiError::NotEnoughDisk {
            needed_mb,
            free_mb,
        });
    }

    Ok(())
}

/// Descarga y deja instalado todo lo que falte. Idempotente: lo que ya esta
/// verificado no se vuelve a bajar.
pub async fn ensure_installed(
    setup: &SetupPlan,
    tx: &mpsc::Sender<DownloadEvent>,
    cancel: Arc<AtomicBool>,
) -> AiResult<InstalledAssets> {
    check_disk_space(setup)?;

    let client = download::http_client();
    let downloads = paths::downloads_dir()?;
    let runtime_dir = paths::runtime_dir(setup.runtime.id)?;

    // El CUDA runtime primero: es lo unico sin lo cual el binario principal no
    // sirve de nada, y se descomprime sobre el mismo directorio.
    for extra in setup.runtime.extra_archives {
        let spec = AssetSpec {
            name: extra.file_name.to_string(),
            url: extra.url.to_string(),
            sha256: extra.sha256.to_string(),
            expected_bytes: extra.file_bytes,
            dest: downloads.join(extra.file_name),
            extract_to: Some(runtime_dir.join("cudart")),
            format: Some(extra.format),
        };
        download::ensure_asset(&client, &spec, tx, cancel.clone()).await?;
    }

    let runtime_spec = AssetSpec {
        name: setup.runtime.display_name.to_string(),
        url: setup.runtime.url.to_string(),
        sha256: setup.runtime.sha256.to_string(),
        expected_bytes: setup.runtime.file_bytes,
        dest: downloads.join(setup.runtime.file_name),
        extract_to: Some(runtime_dir.join("bin")),
        format: Some(setup.runtime.format),
    };
    download::ensure_asset(&client, &runtime_spec, tx, cancel.clone()).await?;

    let model_spec = AssetSpec {
        name: setup.model.display_name.to_string(),
        url: setup.model.url.to_string(),
        sha256: setup.model.sha256.to_string(),
        expected_bytes: setup.model.file_bytes,
        dest: paths::model_path(setup.model.file_name)?,
        extract_to: None,
        format: None,
    };
    let model_path = download::ensure_asset(&client, &model_spec, tx, cancel).await?;

    // El CUDA runtime se descarga y verifica en su propio directorio
    // (`cudart/`), pero `ggml-cuda.dll` solo busca sus dependencias en el
    // directorio del binario que las pide (busqueda de DLLs de Windows: no
    // mira directorios hermanos). Sin este paso las DLLs quedan en
    // `cudart/`, CUDA nunca inicializa, y `ggml` cae a CPU **en silencio**
    // (ni error ni warning visible: `llama-server` arranca igual con
    // `--n-gpu-layers 999` en la linea de comandos, solo que no acelera
    // nada). Asi se detecto: comandos de shell con VRAM sin usar y ~4
    // tok/s, tipico de CPU pura sobre un modelo de 14B.
    if !setup.runtime.extra_archives.is_empty() {
        merge_extra_archives_into_bin(runtime_dir.join("cudart"), runtime_dir.join("bin")).await?;
    }

    let server_path = paths::find_executable(&runtime_dir, setup.runtime.server_file_name)
        .ok_or_else(|| AiError::MissingBinary(setup.runtime.server_file_name.to_string()))?;

    #[cfg(unix)]
    make_executable(&server_path)?;

    Ok(InstalledAssets {
        server_path,
        model_path,
    })
}

/// Copia el contenido de `cudart/` a `bin/`, sin repetir la copia si ya esta
/// hecha (compara tamanos). Se llama en cada arranque, no solo en la primera
/// instalacion, para que un directorio de datos que quedo con las DLLs mal
/// ubicadas (versiones de NexoDeck anteriores a este fix) se repare solo.
async fn merge_extra_archives_into_bin(cudart_dir: PathBuf, bin_dir: PathBuf) -> AiResult<()> {
    tokio::task::spawn_blocking(move || -> AiResult<()> {
        if !cudart_dir.is_dir() {
            return Ok(());
        }
        for entry in std::fs::read_dir(&cudart_dir)? {
            let entry = entry?;
            if !entry.file_type()?.is_file() {
                continue;
            }
            let dest = bin_dir.join(entry.file_name());
            let source_len = entry.metadata()?.len();
            let already_copied = std::fs::metadata(&dest)
                .map(|dest_meta| dest_meta.len() == source_len)
                .unwrap_or(false);
            if !already_copied {
                std::fs::copy(entry.path(), &dest)?;
            }
        }
        Ok(())
    })
    .await
    .map_err(|e| AiError::Unzip {
        asset: "cudart".into(),
        detail: e.to_string(),
    })?
}

/// Los tar.gz de llama.cpp conservan el bit de ejecucion, pero un zip no tiene
/// permisos POSIX. Se fuerza para que la ruta de Linux no dependa de con que
/// formato vino el asset.
#[cfg(unix)]
fn make_executable(path: &std::path::Path) -> AiResult<()> {
    use std::os::unix::fs::PermissionsExt;

    let mut permissions = std::fs::metadata(path)?.permissions();
    permissions.set_mode(permissions.mode() | 0o755);
    std::fs::set_permissions(path, permissions)?;
    Ok(())
}

/// Formatea bytes para la UI. Vive aca y no en el lado Dart porque los eventos
/// de descarga ya viajan con los numeros crudos y el texto tiene que ser el
/// mismo en el ejemplo de terminal y en el wizard.
pub fn format_bytes(bytes: u64) -> String {
    const KB: f64 = 1024.0;
    const MB: f64 = KB * 1024.0;
    const GB: f64 = MB * 1024.0;

    let bytes = bytes as f64;
    if bytes >= GB {
        format!("{:.1} GB", bytes / GB)
    } else if bytes >= MB {
        format!("{:.0} MB", bytes / MB)
    } else {
        format!("{:.0} KB", bytes / KB)
    }
}

/// Formato de archivo por extension, para poder resolverlo cuando no viene del
/// catalogo.
pub fn format_from_file_name(file_name: &str) -> Option<ArchiveFormat> {
    if file_name.ends_with(".zip") {
        Some(ArchiveFormat::Zip)
    } else if file_name.ends_with(".tar.gz") || file_name.ends_with(".tgz") {
        Some(ArchiveFormat::TarGz)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Reproduce el bug real: `ggml-cuda.dll` (en `bin/`) no encuentra
    /// `cudart64_13.dll` si queda en un directorio hermano. Sin este merge,
    /// CUDA nunca inicializa y todo cae a CPU sin ningun error.
    #[tokio::test]
    async fn merge_copia_las_dlls_de_cudart_a_bin() {
        let root = std::env::temp_dir().join(format!(
            "nexodeck-ai-merge-test-{}-{}",
            std::process::id(),
            "a"
        ));
        let cudart_dir = root.join("cudart");
        let bin_dir = root.join("bin");
        std::fs::create_dir_all(&cudart_dir).unwrap();
        std::fs::create_dir_all(&bin_dir).unwrap();
        std::fs::write(cudart_dir.join("cudart64_13.dll"), b"contenido-falso").unwrap();

        merge_extra_archives_into_bin(cudart_dir.clone(), bin_dir.clone())
            .await
            .unwrap();

        assert_eq!(
            std::fs::read(bin_dir.join("cudart64_13.dll")).unwrap(),
            b"contenido-falso"
        );

        let _ = std::fs::remove_dir_all(&root);
    }

    /// Sin `extra_archives` (backends de CPU/Vulkan) no hay `cudart/`: el
    /// merge tiene que ser un no-op silencioso, no un error.
    #[tokio::test]
    async fn merge_es_no_op_si_no_hay_directorio_cudart() {
        let root = std::env::temp_dir().join(format!(
            "nexodeck-ai-merge-test-{}-{}",
            std::process::id(),
            "b"
        ));
        let cudart_dir = root.join("cudart");
        let bin_dir = root.join("bin");
        std::fs::create_dir_all(&bin_dir).unwrap();

        merge_extra_archives_into_bin(cudart_dir, bin_dir).await.unwrap();

        let _ = std::fs::remove_dir_all(&root);
    }

    #[tokio::test]
    async fn merge_no_recopia_si_el_tamano_ya_coincide() {
        let root = std::env::temp_dir().join(format!(
            "nexodeck-ai-merge-test-{}-{}",
            std::process::id(),
            "c"
        ));
        let cudart_dir = root.join("cudart");
        let bin_dir = root.join("bin");
        std::fs::create_dir_all(&cudart_dir).unwrap();
        std::fs::create_dir_all(&bin_dir).unwrap();
        std::fs::write(cudart_dir.join("cudart64_13.dll"), b"nuevo-contenido").unwrap();
        // Mismo tamano que el de arriba (15 bytes) pero contenido distinto:
        // el merge lo tiene que dejar como esta, no pisarlo.
        std::fs::write(bin_dir.join("cudart64_13.dll"), b"ya-estaba-aca!!").unwrap();

        merge_extra_archives_into_bin(cudart_dir, bin_dir.clone())
            .await
            .unwrap();

        assert_eq!(
            std::fs::read(bin_dir.join("cudart64_13.dll")).unwrap(),
            b"ya-estaba-aca!!"
        );

        let _ = std::fs::remove_dir_all(&root);
    }

    use crate::plan::{Backend, Tier};

    fn plan_for(backend: Backend, tier: Tier) -> RuntimePlan {
        RuntimePlan {
            backend,
            tier,
            threads: 8,
            context_size: tier.context_size(),
            vram_budget_mb: 13_000,
            gpu_name: Some("GPU de prueba".into()),
            reasons: Vec::new(),
        }
    }

    #[test]
    fn resolve_setup_usa_el_modelo_por_defecto_de_la_gama() {
        let setup = resolve_setup(
            &plan_for(Backend::Cuda13, Tier::Balanced),
            HostOs::Windows,
            None,
        )
        .unwrap();

        assert!(setup.model.is_default);
        assert_eq!(setup.model.tier, Tier::Balanced);
        assert_eq!(setup.runtime.backend, Backend::Cuda13);
    }

    /// El usuario puede elegir a mano un modelo de otra gama: el wizard ofrece
    /// las tres y no tiene por que coincidir con la recomendada.
    #[test]
    fn resolve_setup_respeta_el_modelo_elegido_a_mano() {
        let setup = resolve_setup(
            &plan_for(Backend::Cuda13, Tier::Balanced),
            HostOs::Windows,
            Some("granite-3.3-2b-instruct-q4km"),
        )
        .unwrap();

        assert_eq!(setup.model.tier, Tier::Light);
    }

    #[test]
    fn resolve_setup_falla_con_un_modelo_inexistente() {
        let error = resolve_setup(
            &plan_for(Backend::Cuda13, Tier::Balanced),
            HostOs::Windows,
            Some("no-existe"),
        )
        .unwrap_err();

        assert!(matches!(error, AiError::UnknownModel(_)));
    }

    /// El total tiene que incluir el CUDA runtime: si el wizard promete 9 GB y
    /// terminan siendo 9,5, la barra "se pasa" y queda como un bug.
    #[test]
    fn el_total_a_descargar_incluye_el_cuda_runtime() {
        let setup = resolve_setup(
            &plan_for(Backend::Cuda13, Tier::Balanced),
            HostOs::Windows,
            None,
        )
        .unwrap();

        assert!(
            setup.total_download_bytes()
                > setup.model.file_bytes + setup.runtime.file_bytes,
            "falta sumar el cudart"
        );
    }

    #[test]
    fn format_bytes_usa_la_unidad_legible() {
        assert_eq!(format_bytes(512 * 1024), "512 KB");
        assert_eq!(format_bytes(250 * 1024 * 1024), "250 MB");
        assert_eq!(format_bytes(9_001_752_960), "8.4 GB");
    }

    #[test]
    fn el_formato_sale_de_la_extension() {
        assert_eq!(
            format_from_file_name("llama-b10235-bin-win-cpu-x64.zip"),
            Some(ArchiveFormat::Zip)
        );
        assert_eq!(
            format_from_file_name("llama-b10235-bin-ubuntu-x64.tar.gz"),
            Some(ArchiveFormat::TarGz)
        );
        assert_eq!(format_from_file_name("modelo.gguf"), None);
    }
}
