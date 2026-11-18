//! Catalogo de runtimes y modelos: **datos, no logica**.
//!
//! Dos tablas de constantes y unos lookups. Se mantiene aparte a proposito
//! porque es la parte que hay que actualizar de vez en cuando (sube un release
//! de llama.cpp, sale un modelo mejor) y no queremos tocar `plan.rs` para eso.
//!
//! ## De donde salen los hashes
//!
//! **Ninguno esta inventado.** Los de los modelos son el `lfs.oid` que expone
//! la API de HuggingFace (`/api/models/{repo}/tree/main`), que para archivos
//! LFS **es** el SHA256 del contenido; los de los binarios son el campo
//! `digest` de la API de releases de GitHub. Los dos se pueden re-verificar sin
//! descargar los GB:
//!
//! ```text
//! curl -s https://huggingface.co/api/models/Qwen/Qwen3-14B-GGUF/tree/main
//! curl -s https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/b10235
//! ```
//!
//! Hay un test que falla si algun campo queda vacio o con un hash de largo
//! equivocado, justamente para que nadie complete la tabla "a ojo".
//!
//! ## Por que estos modelos
//!
//! Los seis son de licencia permisiva (Apache-2.0) y **tool calling nativo**,
//! que no es negociable: toda la salida estructurada del asistente
//! (`propose_action`) viaja como tool call.

use nexodeck_hardware::HostOs;

use crate::plan::{Backend, Tier};

/// Release de llama.cpp contra el que estan tomados los hashes. Subirlo
/// implica volver a leer los `digest` de la API de GitHub.
pub const LLAMA_CPP_BUILD: &str = "b10235";

/// Formato del archivo que se descarga. Los releases de llama.cpp usan `.zip`
/// en Windows y `.tar.gz` en Linux — no es lo mismo y asumir zip para los dos
/// deja la ruta de Linux rota en silencio.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ArchiveFormat {
    Zip,
    TarGz,
}

/// Archivo extra que hay que descomprimir junto al runtime. Solo lo usan las
/// builds de CUDA en Windows: los binarios no traen las DLLs del CUDA runtime
/// y sin ellas `llama-server.exe` no arranca (falla al cargar `cudart64_*.dll`
/// antes de imprimir nada util).
#[derive(Debug, Clone, Copy)]
pub struct ExtraArchive {
    pub file_name: &'static str,
    pub url: &'static str,
    pub sha256: &'static str,
    pub file_bytes: u64,
    pub format: ArchiveFormat,
}

#[derive(Debug, Clone, Copy)]
pub struct RuntimeAsset {
    /// Id estable, tambien usado como nombre del directorio de instalacion.
    pub id: &'static str,
    pub backend: Backend,
    pub os: HostOs,
    pub display_name: &'static str,
    pub file_name: &'static str,
    pub url: &'static str,
    pub sha256: &'static str,
    pub file_bytes: u64,
    pub format: ArchiveFormat,
    /// Nombre del ejecutable a buscar **dentro** de lo descomprimido. Se busca
    /// recursivamente a proposito: la estructura de los zips de llama.cpp
    /// cambio entre releases (antes `build/bin/`, ahora la raiz) y depender de
    /// una ruta fija es exactamente el tipo de suposicion que se rompe sola en
    /// la proxima actualizacion.
    pub server_file_name: &'static str,
    pub extra_archives: &'static [ExtraArchive],
}

impl RuntimeAsset {
    pub fn total_bytes(&self) -> u64 {
        self.file_bytes
            + self
                .extra_archives
                .iter()
                .map(|extra| extra.file_bytes)
                .sum::<u64>()
    }
}

#[derive(Debug, Clone, Copy)]
pub struct ModelEntry {
    pub id: &'static str,
    pub display_name: &'static str,
    pub tier: Tier,
    /// `true` en el modelo recomendado de cada gama. Hay exactamente uno por
    /// gama (lo verifica un test).
    pub is_default: bool,
    pub license: &'static str,
    pub source_repo: &'static str,
    pub params_b: f32,
    pub quantization: &'static str,
    /// Numero de capas del transformer. Solo alimenta la heuristica de
    /// `--n-gpu-layers`; si esta un poco mal, el peor caso es un offload
    /// parcial subóptimo, no un fallo.
    pub layer_count: u32,
    /// Bytes de KV cache por token (`2 * n_kv_heads * head_dim * n_layers * 2`
    /// con cache en f16). Es una **estimacion** calculada desde la config de
    /// cada modelo, no un valor medido: sirve para no prometer offload total
    /// cuando el contexto no va a entrar.
    pub kv_bytes_per_token: u32,
    pub file_bytes: u64,
    pub file_name: &'static str,
    pub url: &'static str,
    pub sha256: &'static str,
    /// VRAM minima recomendada para correrlo entero en GPU.
    pub min_vram_mb: u64,
    /// El modelo es "hibrido": razona en voz alta salvo que se le apague.
    ///
    /// Determina si se manda `chat_template_kwargs: {enable_thinking: false}`.
    /// Solo se manda a los que lo entienden: para una conversacion de
    /// aclaracion, pensar 30 segundos antes de cada pregunta arruina la
    /// experiencia, pero mandarle la bandera a un modelo que no la conoce es
    /// ruido en su plantilla de chat.
    pub supports_thinking: bool,
    pub notes: &'static str,
}

impl ModelEntry {
    pub fn file_mb(&self) -> u64 {
        self.file_bytes / (1024 * 1024)
    }
}

// ---------------------------------------------------------------------
// Runtimes (llama.cpp b10235)
// ---------------------------------------------------------------------

const CUDART_12_4: ExtraArchive = ExtraArchive {
    file_name: "cudart-llama-bin-win-cuda-12.4-x64.zip",
    url: "https://github.com/ggml-org/llama.cpp/releases/download/b10235/cudart-llama-bin-win-cuda-12.4-x64.zip",
    sha256: "8c79a9b226de4b3cacfd1f83d24f962d0773be79f1e7b75c6af4ded7e32ae1d6",
    file_bytes: 391_443_627,
    format: ArchiveFormat::Zip,
};

const CUDART_13_3: ExtraArchive = ExtraArchive {
    file_name: "cudart-llama-bin-win-cuda-13.3-x64.zip",
    url: "https://github.com/ggml-org/llama.cpp/releases/download/b10235/cudart-llama-bin-win-cuda-13.3-x64.zip",
    sha256: "1462a050eb4c684921ba51dcc4cc488a036674c3e73e9945ee705b854808d03e",
    file_bytes: 390_970_417,
    format: ArchiveFormat::Zip,
};

pub const RUNTIMES: &[RuntimeAsset] = &[
    RuntimeAsset {
        id: "llamacpp-b10235-win-cuda-12.4",
        backend: Backend::Cuda12,
        os: HostOs::Windows,
        display_name: "llama.cpp CUDA 12.4 (Windows x64)",
        file_name: "llama-b10235-bin-win-cuda-12.4-x64.zip",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/b10235/llama-b10235-bin-win-cuda-12.4-x64.zip",
        sha256: "208c192f9c72489c847847339b4c99475a5419ba9813b69eb4f41c245d91b2f8",
        file_bytes: 250_473_605,
        format: ArchiveFormat::Zip,
        server_file_name: "llama-server.exe",
        extra_archives: &[CUDART_12_4],
    },
    RuntimeAsset {
        id: "llamacpp-b10235-win-cuda-13.3",
        backend: Backend::Cuda13,
        os: HostOs::Windows,
        display_name: "llama.cpp CUDA 13.3 (Windows x64)",
        file_name: "llama-b10235-bin-win-cuda-13.3-x64.zip",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/b10235/llama-b10235-bin-win-cuda-13.3-x64.zip",
        sha256: "d1e1993dccf0b144ee0b46a513f4aeca42b31dd78f14e005e422175cf2713c7b",
        file_bytes: 146_533_711,
        format: ArchiveFormat::Zip,
        server_file_name: "llama-server.exe",
        extra_archives: &[CUDART_13_3],
    },
    RuntimeAsset {
        id: "llamacpp-b10235-win-vulkan",
        backend: Backend::Vulkan,
        os: HostOs::Windows,
        display_name: "llama.cpp Vulkan (Windows x64)",
        file_name: "llama-b10235-bin-win-vulkan-x64.zip",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/b10235/llama-b10235-bin-win-vulkan-x64.zip",
        sha256: "f3ab5195a620247e29b10e0eac5efa88beaa6098c9a45743beddc24cec60420f",
        file_bytes: 34_114_173,
        format: ArchiveFormat::Zip,
        server_file_name: "llama-server.exe",
        extra_archives: &[],
    },
    // llama.cpp ya no publica un zip por nivel de SIMD en Windows: el unico
    // `win-cpu-x64` trae varias `ggml-cpu-*.dll` y elige la mejor en runtime.
    // Por eso `CpuAvx2` y `CpuBaseline` apuntan al mismo asset — la distincion
    // sigue importando para explicarle al usuario que velocidad esperar, no
    // para decidir que descargar.
    RuntimeAsset {
        id: "llamacpp-b10235-win-cpu",
        backend: Backend::CpuAvx2,
        os: HostOs::Windows,
        display_name: "llama.cpp CPU (Windows x64)",
        file_name: "llama-b10235-bin-win-cpu-x64.zip",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/b10235/llama-b10235-bin-win-cpu-x64.zip",
        sha256: "ac91678643f4a3e0d5cbeb4575ec5b7f842a1817649ee1e186e5a412ecf17cbe",
        file_bytes: 18_376_611,
        format: ArchiveFormat::Zip,
        server_file_name: "llama-server.exe",
        extra_archives: &[],
    },
    RuntimeAsset {
        id: "llamacpp-b10235-win-cpu-baseline",
        backend: Backend::CpuBaseline,
        os: HostOs::Windows,
        display_name: "llama.cpp CPU (Windows x64)",
        file_name: "llama-b10235-bin-win-cpu-x64.zip",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/b10235/llama-b10235-bin-win-cpu-x64.zip",
        sha256: "ac91678643f4a3e0d5cbeb4575ec5b7f842a1817649ee1e186e5a412ecf17cbe",
        file_bytes: 18_376_611,
        format: ArchiveFormat::Zip,
        server_file_name: "llama-server.exe",
        extra_archives: &[],
    },
    RuntimeAsset {
        id: "llamacpp-b10235-linux-vulkan",
        backend: Backend::Vulkan,
        os: HostOs::Linux,
        display_name: "llama.cpp Vulkan (Ubuntu x64)",
        file_name: "llama-b10235-bin-ubuntu-vulkan-x64.tar.gz",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/b10235/llama-b10235-bin-ubuntu-vulkan-x64.tar.gz",
        sha256: "1b5e93dd0112df791cb1d567b3d8ccad24076bb3c6b36a226db4b6892a796b80",
        file_bytes: 32_446_240,
        format: ArchiveFormat::TarGz,
        server_file_name: "llama-server",
        extra_archives: &[],
    },
    RuntimeAsset {
        id: "llamacpp-b10235-linux-cpu",
        backend: Backend::CpuAvx2,
        os: HostOs::Linux,
        display_name: "llama.cpp CPU (Ubuntu x64)",
        file_name: "llama-b10235-bin-ubuntu-x64.tar.gz",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/b10235/llama-b10235-bin-ubuntu-x64.tar.gz",
        sha256: "928339c5a7be2be44041cb872de48ae8302867053e54e2d3174adf986b8e9abf",
        file_bytes: 16_459_218,
        format: ArchiveFormat::TarGz,
        server_file_name: "llama-server",
        extra_archives: &[],
    },
    RuntimeAsset {
        id: "llamacpp-b10235-linux-cpu-baseline",
        backend: Backend::CpuBaseline,
        os: HostOs::Linux,
        display_name: "llama.cpp CPU (Ubuntu x64)",
        file_name: "llama-b10235-bin-ubuntu-x64.tar.gz",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/b10235/llama-b10235-bin-ubuntu-x64.tar.gz",
        sha256: "928339c5a7be2be44041cb872de48ae8302867053e54e2d3174adf986b8e9abf",
        file_bytes: 16_459_218,
        format: ArchiveFormat::TarGz,
        server_file_name: "llama-server",
        extra_archives: &[],
    },
    // No hay build de CUDA para Linux en los releases oficiales: ahi el camino
    // NVIDIA cae a Vulkan, que anda bien con el driver propietario. Lo resuelve
    // `runtime_for` con un fallback explicito.
];

// ---------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------

pub const MODELS: &[ModelEntry] = &[
    // ---- Gama baja ----
    ModelEntry {
        id: "qwen3-4b-instruct-2507-q4km",
        display_name: "Qwen3 4B Instruct 2507",
        tier: Tier::Light,
        is_default: true,
        license: "Apache-2.0",
        source_repo: "unsloth/Qwen3-4B-Instruct-2507-GGUF",
        params_b: 4.0,
        quantization: "Q4_K_M",
        layer_count: 36,
        kv_bytes_per_token: 147_456,
        file_bytes: 2_497_281_120,
        file_name: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
        url: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
        sha256: "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597",
        min_vram_mb: 6_144,
        supports_thinking: false,
        notes: "Variante sin modo de razonamiento: responde directo, que es lo que conviene para una conversacion de aclaracion. Es el piso usable del asistente.",
    },
    ModelEntry {
        id: "granite-3.3-2b-instruct-q4km",
        display_name: "IBM Granite 3.3 2B Instruct",
        tier: Tier::Light,
        is_default: false,
        license: "Apache-2.0",
        source_repo: "ibm-granite/granite-3.3-2b-instruct-GGUF",
        params_b: 2.5,
        quantization: "Q4_K_M",
        layer_count: 40,
        kv_bytes_per_token: 81_920,
        file_bytes: 1_545_303_328,
        file_name: "granite-3.3-2b-instruct-Q4_K_M.gguf",
        url: "https://huggingface.co/ibm-granite/granite-3.3-2b-instruct-GGUF/resolve/main/granite-3.3-2b-instruct-Q4_K_M.gguf",
        sha256: "ac71e9e32c0bea919b409c5918f69ca74339854b0319c5065e4e9fb6d95c4852",
        min_vram_mb: 4_096,
        supports_thinking: false,
        notes: "Rescate para equipos muy flacos: 1,5 GB. Menos preciso escribiendo comandos, pero arranca donde el resto no entra.",
    },
    // ---- Gama media ----
    ModelEntry {
        id: "qwen3-14b-q4km",
        display_name: "Qwen3 14B",
        tier: Tier::Balanced,
        is_default: true,
        license: "Apache-2.0",
        source_repo: "Qwen/Qwen3-14B-GGUF",
        params_b: 14.8,
        quantization: "Q4_K_M",
        layer_count: 40,
        kv_bytes_per_token: 163_840,
        file_bytes: 9_001_752_960,
        file_name: "Qwen3-14B-Q4_K_M.gguf",
        url: "https://huggingface.co/Qwen/Qwen3-14B-GGUF/resolve/main/Qwen3-14B-Q4_K_M.gguf",
        sha256: "500a8806e85ee9c83f3ae08420295592451379b4f8cf2d0f41c15dffeb6b81f0",
        min_vram_mb: 12_288,
        supports_thinking: true,
        notes: "El equilibrio bueno: entra entero en 12-16 GB de VRAM y acierta con comandos de shell y rutas mucho mas que los de 4B.",
    },
    ModelEntry {
        id: "gpt-oss-20b-mxfp4",
        display_name: "gpt-oss 20B (MoE)",
        tier: Tier::Balanced,
        is_default: false,
        license: "Apache-2.0",
        source_repo: "ggml-org/gpt-oss-20b-GGUF",
        params_b: 20.9,
        quantization: "MXFP4",
        layer_count: 24,
        kv_bytes_per_token: 49_152,
        file_bytes: 12_109_566_624,
        file_name: "gpt-oss-20b-MXFP4.gguf",
        url: "https://huggingface.co/ggml-org/gpt-oss-20b-GGUF/resolve/main/gpt-oss-20b-MXFP4.gguf",
        sha256: "27cd6c432c7672cb812a92f611cf3ba7bbc35928262bb1e1253ff4ee6ae35901",
        min_vram_mb: 14_336,
        supports_thinking: true,
        notes: "Mixture-of-experts: pesa 12 GB pero solo activa ~3,6B por token, asi que responde bastante mas rapido que un denso del mismo tamano.",
    },
    // ---- Gama alta ----
    ModelEntry {
        id: "qwen3-coder-30b-a3b-q4km",
        display_name: "Qwen3 Coder 30B A3B Instruct (MoE)",
        tier: Tier::Performance,
        is_default: true,
        license: "Apache-2.0",
        source_repo: "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF",
        params_b: 30.5,
        quantization: "Q4_K_M",
        layer_count: 48,
        kv_bytes_per_token: 98_304,
        file_bytes: 18_556_689_568,
        file_name: "Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf",
        url: "https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf",
        sha256: "fadc3e5f8d42bf7e894a785b05082e47daee4df26680389817e2093056f088ad",
        min_vram_mb: 24_576,
        supports_thinking: false,
        notes: "El mejor del catalogo para escribir comandos y encadenar herramientas. MoE de 3,3B activos: pesa 18 GB pero corre rapido.",
    },
    ModelEntry {
        id: "devstral-small-2507-q4km",
        display_name: "Devstral Small 2507 (24B)",
        tier: Tier::Performance,
        is_default: false,
        license: "Apache-2.0",
        source_repo: "mistralai/Devstral-Small-2507_gguf",
        params_b: 23.6,
        quantization: "Q4_K_M",
        layer_count: 40,
        kv_bytes_per_token: 163_840,
        file_bytes: 14_333_915_904,
        file_name: "Devstral-Small-2507-Q4_K_M.gguf",
        url: "https://huggingface.co/mistralai/Devstral-Small-2507_gguf/resolve/main/Devstral-Small-2507-Q4_K_M.gguf",
        sha256: "1bcc2b1b7b7ea3168ba2dbe782432c464f2240598bd193930122c41b117c1796",
        min_vram_mb: 20_480,
        supports_thinking: false,
        notes: "Denso, entrenado especificamente para uso agentico de herramientas. Pesa menos que el de 30B y entra en 20 GB.",
    },
];

// ---------------------------------------------------------------------
// Lookups
// ---------------------------------------------------------------------

pub fn models_for(tier: Tier) -> impl Iterator<Item = &'static ModelEntry> {
    MODELS.iter().filter(move |model| model.tier == tier)
}

/// Modelo recomendado de una gama. Nunca entra en panico: el test
/// `cada_gama_tiene_exactamente_un_default` garantiza que existe.
pub fn default_model_for(tier: Tier) -> &'static ModelEntry {
    MODELS
        .iter()
        .find(|model| model.tier == tier && model.is_default)
        .or_else(|| MODELS.iter().find(|model| model.tier == tier))
        .unwrap_or(&MODELS[0])
}

pub fn model_by_id(id: &str) -> Option<&'static ModelEntry> {
    MODELS.iter().find(|model| model.id == id)
}

pub fn runtime_by_id(id: &str) -> Option<&'static RuntimeAsset> {
    RUNTIMES.iter().find(|runtime| runtime.id == id)
}

/// Runtime para un par (backend, SO).
///
/// Fallback explicito: en Linux no hay build oficial de CUDA en los releases,
/// asi que una NVIDIA cae a Vulkan (que funciona bien con el driver
/// propietario) en vez de quedarse sin runtime.
pub fn runtime_for(backend: Backend, os: HostOs) -> Option<&'static RuntimeAsset> {
    if let Some(runtime) = RUNTIMES
        .iter()
        .find(|runtime| runtime.backend == backend && runtime.os == os)
    {
        return Some(runtime);
    }

    if backend.is_cuda() {
        return RUNTIMES
            .iter()
            .find(|runtime| runtime.backend == Backend::Vulkan && runtime.os == os);
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn is_sha256(value: &str) -> bool {
        value.len() == 64 && value.chars().all(|c| c.is_ascii_hexdigit())
    }

    /// El test que existe para que nadie complete la tabla "a ojo": si alguien
    /// agrega un modelo con el hash en blanco o con un placeholder, esto se
    /// pone rojo antes de que nadie descargue 18 GB para nada.
    #[test]
    fn todos_los_modelos_tienen_url_y_sha256_reales() {
        for model in MODELS {
            assert!(!model.id.is_empty());
            assert!(
                model.url.starts_with("https://"),
                "{}: url invalida",
                model.id
            );
            assert!(
                is_sha256(model.sha256),
                "{}: el sha256 no parece un sha256 ('{}')",
                model.id,
                model.sha256
            );
            assert!(model.file_bytes > 0, "{}: file_bytes en 0", model.id);
            assert!(model.layer_count > 0, "{}: layer_count en 0", model.id);
            assert!(
                model.kv_bytes_per_token > 0,
                "{}: kv_bytes_per_token en 0",
                model.id
            );
            assert!(!model.notes.is_empty(), "{}: sin notas para la UI", model.id);
        }
    }

    #[test]
    fn todos_los_runtimes_tienen_url_y_sha256_reales() {
        for runtime in RUNTIMES {
            assert!(
                runtime.url.starts_with("https://"),
                "{}: url invalida",
                runtime.id
            );
            assert!(
                is_sha256(runtime.sha256),
                "{}: el sha256 no parece un sha256",
                runtime.id
            );
            assert!(runtime.file_bytes > 0, "{}: file_bytes en 0", runtime.id);
            assert!(!runtime.server_file_name.is_empty());

            for extra in runtime.extra_archives {
                assert!(extra.url.starts_with("https://"), "{}: extra sin url", runtime.id);
                assert!(is_sha256(extra.sha256), "{}: extra sin sha256", runtime.id);
                assert!(extra.file_bytes > 0);
            }
        }
    }

    #[test]
    fn los_ids_no_se_repiten() {
        for (index, model) in MODELS.iter().enumerate() {
            assert!(
                !MODELS[..index].iter().any(|other| other.id == model.id),
                "id de modelo duplicado: {}",
                model.id
            );
        }
        for (index, runtime) in RUNTIMES.iter().enumerate() {
            assert!(
                !RUNTIMES[..index].iter().any(|other| other.id == runtime.id),
                "id de runtime duplicado: {}",
                runtime.id
            );
        }
    }

    #[test]
    fn cada_gama_tiene_dos_modelos_y_exactamente_un_default() {
        for tier in Tier::ALL {
            let count = models_for(tier).count();
            assert!(
                count >= 2,
                "{:?} tiene {count} modelos, se esperaban al menos 2",
                tier
            );

            let defaults = models_for(tier).filter(|model| model.is_default).count();
            assert_eq!(defaults, 1, "{:?} tiene {defaults} modelos por defecto", tier);

            assert_eq!(default_model_for(tier).tier, tier);
        }
    }

    /// Los modelos tienen que crecer con la gama. Si esto se rompe, el
    /// downgrade por disco de `plan.rs` (que asume que bajar de gama libera
    /// espacio) deja de tener sentido.
    #[test]
    fn el_modelo_por_defecto_crece_con_la_gama() {
        let light = default_model_for(Tier::Light).file_bytes;
        let balanced = default_model_for(Tier::Balanced).file_bytes;
        let performance = default_model_for(Tier::Performance).file_bytes;

        assert!(light < balanced, "light {light} no es menor que balanced {balanced}");
        assert!(
            balanced < performance,
            "balanced {balanced} no es menor que performance {performance}"
        );
    }

    /// Cada backend que `plan_runtime` puede devolver tiene que tener un
    /// runtime resoluble en Windows y en Linux — si no, el wizard llega a un
    /// callejon sin salida despues de haber prometido acelerar.
    #[test]
    fn todo_backend_resuelve_a_un_runtime_en_windows_y_linux() {
        let backends = [
            Backend::Cuda12,
            Backend::Cuda13,
            Backend::Vulkan,
            Backend::CpuAvx2,
            Backend::CpuBaseline,
        ];

        for os in [HostOs::Windows, HostOs::Linux] {
            for backend in backends {
                assert!(
                    runtime_for(backend, os).is_some(),
                    "sin runtime para {backend:?} en {os:?}"
                );
            }
        }
    }

    #[test]
    fn en_linux_cuda_cae_a_vulkan() {
        let runtime = runtime_for(Backend::Cuda13, HostOs::Linux).unwrap();
        assert_eq!(runtime.backend, Backend::Vulkan);
        assert_eq!(runtime.format, ArchiveFormat::TarGz);
    }

    #[test]
    fn las_builds_de_cuda_en_windows_traen_el_cuda_runtime() {
        for backend in [Backend::Cuda12, Backend::Cuda13] {
            let runtime = runtime_for(backend, HostOs::Windows).unwrap();
            assert!(
                !runtime.extra_archives.is_empty(),
                "{}: sin el zip de cudart, llama-server.exe no arranca",
                runtime.id
            );
            assert!(runtime.total_bytes() > runtime.file_bytes);
        }
    }

    #[test]
    fn model_by_id_encuentra_todos_los_del_catalogo() {
        for model in MODELS {
            assert_eq!(model_by_id(model.id).unwrap().id, model.id);
        }
        assert!(model_by_id("no-existe").is_none());
    }
}
