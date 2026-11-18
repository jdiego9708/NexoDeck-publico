use nexodeck_hardware::{GpuInfoSource, probe_host_capabilities};

/// Imprime el probe estatico del equipo, que es lo que despues decide que
/// modelo de IA y que build de llama.cpp se descargan.
///
/// Verificacion manual: el nombre y la VRAM de la GPU tienen que coincidir con
/// el Administrador de tareas → Rendimiento → GPU. Es el unico chequeo que
/// importa: un test automatico no puede afirmar nada sobre hardware que no
/// conoce.
fn main() {
    let caps = probe_host_capabilities(&std::env::temp_dir());

    println!("SO: {}", caps.os.as_str());
    println!();

    println!("CPU");
    println!("  {}", caps.cpu.brand);
    println!(
        "  nucleos: {} fisicos / {} logicos  ->  --threads {}",
        caps.cpu
            .physical_cores
            .map_or_else(|| "?".to_owned(), |c| c.to_string()),
        caps.cpu.logical_cores,
        caps.cpu.recommended_threads(),
    );
    println!(
        "  AVX2: {}   AVX-512: {}",
        si_no(caps.cpu.avx2),
        si_no(caps.cpu.avx512)
    );
    println!();

    println!("Memoria y disco");
    println!(
        "  RAM total: {} MB ({:.1} GB)",
        caps.ram_total_mb,
        caps.ram_total_mb as f64 / 1024.0
    );
    println!(
        "  disco libre en {}: {} MB ({:.1} GB)",
        std::env::temp_dir().display(),
        caps.free_disk_mb,
        caps.free_disk_mb as f64 / 1024.0
    );
    println!();

    println!("GPU");
    if caps.gpus.is_empty() {
        println!("  (ninguna detectada)");
    }
    for gpu in &caps.gpus {
        let source = match gpu.source {
            GpuInfoSource::Nvml => "NVML",
            GpuInfoSource::Dxgi => "DXGI",
        };
        let compute = gpu
            .cuda_compute_capability
            .map_or_else(String::new, |(major, minor)| {
                format!("  compute {major}.{minor}")
            });
        println!(
            "  [{source}] {:<8} {:<40} {:>6} MB VRAM{compute}",
            gpu.vendor.as_str(),
            gpu.name,
            gpu.vram_total_mb
        );
    }
    println!("  NVML disponible: {}", si_no(caps.nvml_available));
    println!(
        "  Vulkan: {}",
        match caps.vulkan_device_count {
            None => "no disponible (sin loader o sin ICD)".to_owned(),
            Some(0) => "loader presente, 0 dispositivos".to_owned(),
            Some(n) => format!("{n} dispositivo(s)"),
        }
    );
    println!();

    match caps.best_gpu() {
        Some(gpu) => println!(
            "GPU elegida para acelerar: {} ({} MB)",
            gpu.name, gpu.vram_total_mb
        ),
        None => println!("Sin GPU utilizable: la inferencia iria por CPU."),
    }
}

fn si_no(value: bool) -> &'static str {
    if value { "si" } else { "no" }
}
