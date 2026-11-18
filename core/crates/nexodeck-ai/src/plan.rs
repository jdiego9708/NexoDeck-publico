//! Decide **que** correr en este equipo: que build de llama.cpp, que gama de
//! modelo, cuantos hilos, cuanto contexto y cuantas capas van a la GPU.
//!
//! Todo el modulo es puro: entra un [`HostCapabilities`] y sale un
//! [`RuntimePlan`]. No toca disco, ni red, ni procesos — por eso se puede
//! testear la matriz completa (NVIDIA grande, NVIDIA chica, AMD con Vulkan,
//! iGPU Intel, CPU con y sin AVX2) sin tener ese hardware a mano, que es
//! justamente el hardware que no tenemos.
//!
//! Cada decision agrega una linea a `reasons`. No es decorado: el wizard las
//! muestra tal cual, porque "te toco la gama baja" sin explicacion es
//! indistinguible de un bug.

use nexodeck_hardware::{GpuVendor, HostCapabilities};

use crate::catalog::{self, ModelEntry};

/// VRAM minima para que valga la pena ofrecer un backend de GPU. Por debajo de
/// esto no entra ni el modelo mas chico del catalogo con su KV cache, y el
/// offload parcial resulta mas lento que quedarse en CPU (cada capa que cruza
/// el bus PCIe por token cuesta mas de lo que ahorra).
const MIN_USABLE_VRAM_MB: u64 = 4096;

/// Fraccion de la VRAM que nos permitimos usar. El resto queda para el
/// escritorio, el compositor y el navegador que el usuario tiene abierto:
/// llenar la VRAM al 100 % hace que Windows empiece a paginar texturas y la
/// maquina entera se arrastra.
const VRAM_SAFETY_FACTOR: f64 = 0.85;

/// Fraccion de la RAM que nos permitimos usar en el camino CPU. La mitad, no
/// mas: el modelo compite con todo lo demas que el usuario tenga abierto.
const RAM_BUDGET_DIVISOR: u64 = 2;

const TIER_BALANCED_MIN_MB: u64 = 6 * 1024;
const TIER_PERFORMANCE_MIN_MB: u64 = 20 * 1024;

/// Margen sobre el tamano del modelo antes de aceptar descargarlo. Un disco al
/// borde de llenarse rompe cosas mucho peores que esta funcion.
const DISK_MARGIN: f64 = 1.20;

/// Compute capability minima que soportan los binarios de CUDA 13.x. Por
/// debajo de esto (Pascal y anteriores: GTX 10xx, Titan X, ...) hay que usar
/// la build de CUDA 12.4.
const CUDA13_MIN_COMPUTE_MAJOR: u32 = 7;
const CUDA13_MIN_COMPUTE_MINOR: u32 = 5;
/// Compute capability a partir de la cual los binarios de CUDA 12.x ya **no**
/// traen codigo: Blackwell (sm_120, las RTX 50xx).
const CUDA12_MAX_COMPUTE_MAJOR: u32 = 11;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Backend {
    /// CUDA 12.4: cubre de Maxwell (sm_50) a Hopper (sm_90). **No** cubre
    /// Blackwell.
    Cuda12,
    /// CUDA 13.3: cubre de Turing (sm_75) a Blackwell (sm_120). **No** cubre
    /// Pascal ni anteriores.
    Cuda13,
    Vulkan,
    CpuAvx2,
    CpuBaseline,
}

impl Backend {
    pub fn is_gpu(&self) -> bool {
        matches!(self, Backend::Cuda12 | Backend::Cuda13 | Backend::Vulkan)
    }

    pub fn is_cuda(&self) -> bool {
        matches!(self, Backend::Cuda12 | Backend::Cuda13)
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Backend::Cuda12 => "cuda-12.4",
            Backend::Cuda13 => "cuda-13.3",
            Backend::Vulkan => "vulkan",
            Backend::CpuAvx2 => "cpu-avx2",
            Backend::CpuBaseline => "cpu-baseline",
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            Backend::Cuda12 | Backend::Cuda13 => "GPU NVIDIA (CUDA)",
            Backend::Vulkan => "GPU (Vulkan)",
            Backend::CpuAvx2 => "CPU (AVX2)",
            Backend::CpuBaseline => "CPU",
        }
    }
}

/// Elige la build de CUDA segun la compute capability de la tarjeta.
///
/// Ninguna de las dos builds cubre todo el parque de GPUs NVIDIA, y elegir mal
/// **no da un error legible**: da un llama-server que arranca y no acelera, o
/// que muere con un mensaje de CUDA que no le dice nada al usuario. Sin dato de
/// compute capability se toma CUDA 12.4, que cubre mas hardware historico.
fn cuda_backend_for(compute: Option<(u32, u32)>) -> Backend {
    match compute {
        Some((major, _)) if major > CUDA12_MAX_COMPUTE_MAJOR => Backend::Cuda13,
        Some((major, minor))
            if (major, minor) >= (CUDA13_MIN_COMPUTE_MAJOR, CUDA13_MIN_COMPUTE_MINOR) =>
        {
            // Zona de solape (Turing..Hopper): las dos sirven. Se elige 12.4
            // porque exige un driver mas viejo, y un driver desactualizado es
            // muchisimo mas comun que una GPU sin soporte.
            Backend::Cuda12
        }
        _ => Backend::Cuda12,
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Tier {
    Light,
    Balanced,
    Performance,
}

impl Tier {
    pub const ALL: [Tier; 3] = [Tier::Light, Tier::Balanced, Tier::Performance];

    pub fn as_str(&self) -> &'static str {
        match self {
            Tier::Light => "light",
            Tier::Balanced => "balanced",
            Tier::Performance => "performance",
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            Tier::Light => "Gama baja",
            Tier::Balanced => "Gama media",
            Tier::Performance => "Gama alta",
        }
    }

    /// Ventana de contexto por gama. Mas contexto es mas KV cache y por lo
    /// tanto mas VRAM, asi que no se puede subir sin mirar el hardware.
    pub fn context_size(&self) -> u32 {
        match self {
            Tier::Light => 8_192,
            Tier::Balanced => 16_384,
            Tier::Performance => 32_768,
        }
    }

    fn lower(&self) -> Option<Tier> {
        match self {
            Tier::Performance => Some(Tier::Balanced),
            Tier::Balanced => Some(Tier::Light),
            Tier::Light => None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct RuntimePlan {
    pub backend: Backend,
    pub tier: Tier,
    pub threads: u32,
    pub context_size: u32,
    /// VRAM que nos permitimos usar, ya con el factor de seguridad aplicado.
    /// Cero en los backends de CPU.
    pub vram_budget_mb: u64,
    /// Nombre de la GPU elegida, para mostrarlo en el wizard.
    pub gpu_name: Option<String>,
    /// Por que salio este plan, en orden. Se muestran al usuario.
    pub reasons: Vec<String>,
}

impl RuntimePlan {
    /// Modelo recomendado para este plan.
    pub fn default_model(&self) -> &'static ModelEntry {
        catalog::default_model_for(self.tier)
    }
}

/// Elige backend, gama y parametros de arranque a partir del hardware.
pub fn plan_runtime(caps: &HostCapabilities) -> RuntimePlan {
    let mut reasons = Vec::new();

    let (backend, gpu_name, vram_budget_mb) = choose_backend(caps, &mut reasons);
    let tier = choose_tier(caps, backend, vram_budget_mb, &mut reasons);

    RuntimePlan {
        backend,
        tier,
        threads: caps.cpu.recommended_threads(),
        context_size: tier.context_size(),
        vram_budget_mb,
        gpu_name,
        reasons,
    }
}

fn choose_backend(
    caps: &HostCapabilities,
    reasons: &mut Vec<String>,
) -> (Backend, Option<String>, u64) {
    // CUDA primero y por GPU NVIDIA concreta, no por `best_gpu()`: en un
    // portatil con iGPU + NVIDIA, la iGPU puede ganar la comparacion por VRAM
    // reportada y dejarnos eligiendo el backend equivocado.
    let nvidia = caps
        .gpus
        .iter()
        .filter(|gpu| gpu.vendor == GpuVendor::Nvidia)
        .max_by_key(|gpu| gpu.vram_total_mb);

    if let Some(gpu) = nvidia {
        if caps.nvml_available && gpu.vram_total_mb >= MIN_USABLE_VRAM_MB {
            let backend = cuda_backend_for(gpu.cuda_compute_capability);
            reasons.push(format!(
                "Se detecto {} con {} MB de VRAM y el driver NVIDIA cargado: se usa la build {}.",
                gpu.name,
                gpu.vram_total_mb,
                backend.as_str()
            ));
            if let Some((major, minor)) = gpu.cuda_compute_capability {
                reasons.push(format!(
                    "Compute capability {major}.{minor}: es la unica build de CUDA que trae codigo para esta arquitectura."
                ));
            }
            return (
                backend,
                Some(gpu.name.clone()),
                budget_from_vram(gpu.vram_total_mb),
            );
        }
    }

    if caps.vulkan_usable() {
        if let Some(gpu) = caps.best_gpu() {
            if gpu.vram_total_mb >= MIN_USABLE_VRAM_MB {
                reasons.push(format!(
                    "Se detecto {} con {} MB de VRAM y Vulkan disponible: se usa la build Vulkan.",
                    gpu.name, gpu.vram_total_mb
                ));
                return (
                    Backend::Vulkan,
                    Some(gpu.name.clone()),
                    budget_from_vram(gpu.vram_total_mb),
                );
            }
            reasons.push(format!(
                "{} tiene {} MB de VRAM dedicada, menos de los {} MB minimos: no alcanza para acelerar.",
                gpu.name, gpu.vram_total_mb, MIN_USABLE_VRAM_MB
            ));
        }
    } else if caps.best_gpu().is_some() {
        reasons.push(
            "Hay GPU pero Vulkan no esta disponible: sin el no se puede acelerar una GPU que no sea NVIDIA."
                .to_string(),
        );
    } else {
        reasons.push("No se detecto ninguna GPU dedicada.".to_string());
    }

    let backend = if caps.cpu.avx2 {
        reasons.push(format!(
            "La inferencia va por CPU sobre {} ({} hilos), con kernels AVX2.",
            caps.cpu.brand,
            caps.cpu.recommended_threads()
        ));
        Backend::CpuAvx2
    } else {
        reasons.push(format!(
            "La inferencia va por CPU sobre {} ({} hilos). Sin AVX2 se usa la build generica, bastante mas lenta.",
            caps.cpu.brand,
            caps.cpu.recommended_threads()
        ));
        Backend::CpuBaseline
    };

    (backend, None, 0)
}

fn choose_tier(
    caps: &HostCapabilities,
    backend: Backend,
    vram_budget_mb: u64,
    reasons: &mut Vec<String>,
) -> Tier {
    let tier = if backend.is_gpu() {
        tier_for_budget(vram_budget_mb)
    } else {
        // En CPU se topea a la gama baja a proposito. Un modelo de 14B sobre
        // CPU corre a un par de tokens por segundo: tecnicamente "anda", pero
        // una conversacion de aclaracion se vuelve inusable. La gama la puede
        // subir el usuario a mano desde el wizard, viendo la advertencia.
        let by_ram = tier_for_budget(caps.ram_total_mb / RAM_BUDGET_DIVISOR);
        if by_ram > Tier::Light {
            reasons.push(
                "Sin GPU se recomienda la gama baja aunque sobre RAM: en CPU un modelo mas grande tarda minutos por respuesta. Se puede subir a mano."
                    .to_string(),
            );
        }
        Tier::Light
    };

    downgrade_for_disk(tier, caps.free_disk_mb, reasons)
}

fn tier_for_budget(budget_mb: u64) -> Tier {
    if budget_mb >= TIER_PERFORMANCE_MIN_MB {
        Tier::Performance
    } else if budget_mb >= TIER_BALANCED_MIN_MB {
        Tier::Balanced
    } else {
        Tier::Light
    }
}

/// Baja de gama hasta que el modelo por defecto entre en el disco libre.
///
/// Bajar de gama con una explicacion es mejor que bloquear: el usuario obtiene
/// un asistente que funciona hoy, y siempre puede liberar espacio y elegir otro
/// modelo despues.
fn downgrade_for_disk(tier: Tier, free_disk_mb: u64, reasons: &mut Vec<String>) -> Tier {
    let mut current = tier;

    loop {
        let needed_mb = required_disk_mb(catalog::default_model_for(current));
        if needed_mb <= free_disk_mb {
            return current;
        }

        match current.lower() {
            Some(lower) => {
                reasons.push(format!(
                    "{} necesita {} MB libres y solo hay {}: se baja a {}.",
                    current.display_name(),
                    needed_mb,
                    free_disk_mb,
                    lower.display_name()
                ));
                current = lower;
            }
            None => {
                reasons.push(format!(
                    "Ni el modelo mas chico entra: necesita {needed_mb} MB libres y hay {free_disk_mb}. Hay que liberar espacio."
                ));
                return current;
            }
        }
    }
}

/// Disco que hace falta para un modelo, con margen.
pub fn required_disk_mb(model: &ModelEntry) -> u64 {
    ((model.file_bytes as f64 / (1024.0 * 1024.0)) * DISK_MARGIN) as u64
}

fn budget_from_vram(vram_total_mb: u64) -> u64 {
    (vram_total_mb as f64 * VRAM_SAFETY_FACTOR) as u64
}

/// KV cache que va a ocupar un modelo con una ventana de contexto dada.
pub fn kv_cache_mb(model: &ModelEntry, context_size: u32) -> u64 {
    (model.kv_bytes_per_token as u64 * context_size as u64) / (1024 * 1024)
}

/// Cuantas capas del modelo mandar a la GPU (`--n-gpu-layers`).
///
/// - `0` en los backends de CPU.
/// - `999` (todas) cuando el modelo entero mas su KV cache entran en el
///   presupuesto de VRAM. Se usa un numero alto en vez del conteo exacto
///   porque llama.cpp lo satura al total real, y asi no dependemos de que
///   `layer_count` del catalogo este perfecto.
/// - Un valor parcial proporcional cuando no entra entero. Ojo: el offload
///   parcial es bastante mas lento que el total, no linealmente mejor que 0.
pub fn gpu_layers_for(model: &ModelEntry, plan: &RuntimePlan) -> u32 {
    if !plan.backend.is_gpu() || plan.vram_budget_mb == 0 {
        return 0;
    }

    let model_mb = model.file_bytes / (1024 * 1024);
    let kv_mb = kv_cache_mb(model, plan.context_size);

    if model_mb + kv_mb <= plan.vram_budget_mb {
        return 999;
    }

    // El KV cache va entero a la GPU antes que cualquier capa; si ya no entra,
    // no tiene sentido ofrecer offload parcial.
    let Some(for_weights_mb) = plan.vram_budget_mb.checked_sub(kv_mb) else {
        return 0;
    };
    if model_mb == 0 {
        return 0;
    }

    let layers = (model.layer_count as u64 * for_weights_mb) / model_mb;
    layers.min(model.layer_count as u64) as u32
}

#[cfg(test)]
mod tests {
    use super::*;
    use nexodeck_hardware::{CpuInfo, GpuInfo, GpuInfoSource, HostOs};

    fn caps(
        gpus: Vec<GpuInfo>,
        nvml_available: bool,
        vulkan_device_count: Option<u32>,
        ram_total_mb: u64,
        avx2: bool,
    ) -> HostCapabilities {
        HostCapabilities {
            os: HostOs::Windows,
            cpu: CpuInfo {
                brand: "CPU de prueba".into(),
                physical_cores: Some(8),
                logical_cores: 16,
                avx2,
                avx512: false,
            },
            ram_total_mb,
            // Disco de sobra en la mayoria de los casos: el downgrade por
            // disco tiene sus propios tests.
            free_disk_mb: 500_000,
            gpus,
            nvml_available,
            vulkan_device_count,
        }
    }

    fn gpu(vendor: GpuVendor, name: &str, vram_total_mb: u64) -> GpuInfo {
        GpuInfo {
            vendor,
            name: name.into(),
            vram_total_mb,
            cuda_compute_capability: None,
            source: GpuInfoSource::Dxgi,
        }
    }

    fn nvidia(name: &str, vram_total_mb: u64, compute: (u32, u32)) -> GpuInfo {
        GpuInfo {
            vendor: GpuVendor::Nvidia,
            name: name.into(),
            vram_total_mb,
            cuda_compute_capability: Some(compute),
            source: GpuInfoSource::Nvml,
        }
    }

    #[test]
    fn nvidia_grande_usa_cuda_y_gama_alta() {
        let plan = plan_runtime(&caps(
            vec![nvidia("RTX 4090", 24_564, (8, 9))],
            true,
            Some(1),
            65_536,
            true,
        ));

        assert!(plan.backend.is_cuda());
        assert_eq!(plan.tier, Tier::Performance);
        assert_eq!(plan.threads, 8);
        assert!(plan.vram_budget_mb > 20 * 1024);
    }

    /// El equipo principal del proyecto. 16 GB de VRAM no alcanzan para el
    /// modelo por defecto de gama alta, asi que tiene que quedar en media.
    #[test]
    fn nvidia_de_16gb_usa_cuda_y_gama_media() {
        let plan = plan_runtime(&caps(
            vec![nvidia("RTX 5060 Ti", 16_311, (12, 0))],
            true,
            Some(1),
            32_692,
            true,
        ));

        assert!(plan.backend.is_cuda());
        assert_eq!(plan.tier, Tier::Balanced);
    }

    /// Blackwell (sm_120) no tiene codigo en los binarios de CUDA 12.x: si el
    /// plan eligiera 12.4 aca, la GPU no aceleraria y no habria ningun error
    /// que lo explicara.
    #[test]
    fn blackwell_exige_la_build_de_cuda_13() {
        let plan = plan_runtime(&caps(
            vec![nvidia("RTX 5060 Ti", 16_311, (12, 0))],
            true,
            Some(1),
            32_692,
            true,
        ));

        assert_eq!(plan.backend, Backend::Cuda13);
    }

    /// La otra punta: CUDA 13 dejo afuera Pascal, asi que una GTX 10xx tiene
    /// que quedarse en 12.4.
    #[test]
    fn pascal_se_queda_en_la_build_de_cuda_12() {
        let plan = plan_runtime(&caps(
            vec![nvidia("GTX 1080 Ti", 11_264, (6, 1))],
            true,
            Some(1),
            32_768,
            true,
        ));

        assert_eq!(plan.backend, Backend::Cuda12);
    }

    /// Sin compute capability (NVML incompleto) se elige la build que cubre
    /// mas hardware historico en vez de arriesgar.
    #[test]
    fn sin_compute_capability_se_elige_cuda_12() {
        let plan = plan_runtime(&caps(
            vec![GpuInfo {
                cuda_compute_capability: None,
                ..nvidia("RTX 3060", 12_288, (8, 6))
            }],
            true,
            Some(1),
            32_768,
            true,
        ));

        assert_eq!(plan.backend, Backend::Cuda12);
    }

    #[test]
    fn nvidia_chica_cae_a_gama_baja_pero_sigue_en_cuda() {
        let plan = plan_runtime(&caps(
            vec![nvidia("GTX 1650", 4_096, (7, 5))],
            true,
            Some(1),
            16_384,
            true,
        ));

        assert!(plan.backend.is_cuda());
        assert_eq!(plan.tier, Tier::Light);
    }

    /// Sin NVML no hay driver NVIDIA utilizable, aunque DXGI liste la tarjeta.
    #[test]
    fn nvidia_sin_nvml_no_usa_cuda() {
        let plan = plan_runtime(&caps(
            vec![gpu(GpuVendor::Nvidia, "RTX 3060", 12_288)],
            false,
            Some(1),
            32_768,
            true,
        ));

        assert_eq!(plan.backend, Backend::Vulkan);
    }

    #[test]
    fn amd_con_vulkan_usa_vulkan() {
        let plan = plan_runtime(&caps(
            vec![gpu(GpuVendor::Amd, "Radeon RX 580", 8_192)],
            false,
            Some(1),
            16_384,
            true,
        ));

        assert_eq!(plan.backend, Backend::Vulkan);
        assert_eq!(plan.tier, Tier::Balanced);
        assert_eq!(plan.gpu_name.as_deref(), Some("Radeon RX 580"));
    }

    #[test]
    fn amd_sin_vulkan_cae_a_cpu() {
        let plan = plan_runtime(&caps(
            vec![gpu(GpuVendor::Amd, "Radeon RX 580", 8_192)],
            false,
            None,
            16_384,
            true,
        ));

        assert_eq!(plan.backend, Backend::CpuAvx2);
        assert_eq!(plan.vram_budget_mb, 0);
    }

    #[test]
    fn igpu_intel_no_alcanza_y_cae_a_cpu() {
        let plan = plan_runtime(&caps(
            vec![gpu(GpuVendor::Intel, "Intel UHD Graphics 630", 128)],
            false,
            Some(1),
            8_192,
            true,
        ));

        assert_eq!(plan.backend, Backend::CpuAvx2);
        assert_eq!(plan.tier, Tier::Light);
    }

    #[test]
    fn cpu_sin_avx2_usa_la_build_generica() {
        let plan = plan_runtime(&caps(vec![], false, None, 8_192, false));

        assert_eq!(plan.backend, Backend::CpuBaseline);
        assert_eq!(plan.tier, Tier::Light);
    }

    /// Con 128 GB de RAM y sin GPU, la gama por RAM daria alta; el tope de CPU
    /// tiene que ganar igual, y decirlo.
    #[test]
    fn cpu_con_mucha_ram_se_topea_en_gama_baja_y_lo_explica() {
        let plan = plan_runtime(&caps(vec![], false, None, 131_072, true));

        assert_eq!(plan.tier, Tier::Light);
        assert!(
            plan.reasons.iter().any(|r| r.contains("gama baja")),
            "el tope de CPU tiene que quedar explicado: {:?}",
            plan.reasons
        );
    }

    #[test]
    fn el_disco_libre_baja_de_gama_y_lo_explica() {
        let mut c = caps(
            vec![nvidia("RTX 4090", 24_564, (8, 9))],
            true,
            Some(1),
            65_536,
            true,
        );
        // Alcanza para la gama baja, no para la alta.
        c.free_disk_mb = 4_000;

        let plan = plan_runtime(&c);

        assert!(plan.backend.is_cuda(), "el backend no depende del disco");
        assert!(plan.tier < Tier::Performance);
        assert!(
            plan.reasons.iter().any(|r| r.contains("se baja a")),
            "la bajada de gama tiene que quedar explicada: {:?}",
            plan.reasons
        );
    }

    #[test]
    fn gpu_layers_offload_total_cuando_entra() {
        let plan = plan_runtime(&caps(
            vec![nvidia("RTX 4090", 24_564, (8, 9))],
            true,
            Some(1),
            65_536,
            true,
        ));
        let model = catalog::default_model_for(Tier::Light);

        assert_eq!(gpu_layers_for(model, &plan), 999);
    }

    #[test]
    fn gpu_layers_parcial_cuando_no_entra_entero() {
        let plan = plan_runtime(&caps(
            vec![nvidia("RTX 3060", 12_288, (8, 6))],
            true,
            Some(1),
            32_768,
            true,
        ));
        let grande = catalog::default_model_for(Tier::Performance);

        let layers = gpu_layers_for(grande, &plan);
        assert!(
            layers > 0 && layers < 999,
            "se esperaba offload parcial, se obtuvo {layers}"
        );
        assert!(layers <= grande.layer_count);
    }

    #[test]
    fn gpu_layers_es_cero_en_cpu() {
        let plan = plan_runtime(&caps(vec![], false, None, 16_384, true));
        let model = catalog::default_model_for(Tier::Light);

        assert_eq!(gpu_layers_for(model, &plan), 0);
    }

    #[test]
    fn plan_siempre_explica_al_menos_una_decision() {
        for c in [
            caps(
                vec![gpu(GpuVendor::Nvidia, "RTX 4090", 24_564)],
                true,
                Some(1),
                65_536,
                true,
            ),
            caps(vec![], false, None, 8_192, false),
            caps(
                vec![gpu(GpuVendor::Intel, "iGPU", 128)],
                false,
                Some(1),
                8_192,
                true,
            ),
        ] {
            assert!(!plan_runtime(&c).reasons.is_empty());
        }
    }
}
