use nexodeck_ai::catalog;
use nexodeck_ai::plan::{Tier, gpu_layers_for, kv_cache_mb, plan_runtime, required_disk_mb};
use nexodeck_hardware::probe_host_capabilities;

/// Corre el probe de hardware real y muestra que decidiria el asistente:
/// backend, gama, modelo, hilos, contexto y cuantas capas irian a la GPU.
///
/// Hito verificable del paso 2: esto tiene que imprimir un plan coherente con
/// el hardware de la maquina **sin descargar nada**.
fn main() {
    let models_dir = nexodeck_ai::paths::models_dir()
        .unwrap_or_else(|_| std::env::temp_dir());
    let caps = probe_host_capabilities(&models_dir);
    let plan = plan_runtime(&caps);

    println!("=== Hardware detectado ===");
    println!("  {} / {}", caps.os.as_str(), caps.cpu.brand);
    println!(
        "  {} MB de RAM, {} MB libres en {}",
        caps.ram_total_mb,
        caps.free_disk_mb,
        models_dir.display()
    );
    match plan.gpu_name.as_deref() {
        Some(name) => println!("  GPU: {name}"),
        None => println!("  GPU: ninguna utilizable"),
    }
    println!();

    println!("=== Plan ===");
    println!("  backend      {}", plan.backend.as_str());
    println!("  gama         {}", plan.tier.display_name());
    println!("  --threads    {}", plan.threads);
    println!("  --ctx-size   {}", plan.context_size);
    println!("  VRAM usable  {} MB", plan.vram_budget_mb);
    println!();

    println!("=== Por que ===");
    for reason in &plan.reasons {
        println!("  - {reason}");
    }
    println!();

    let runtime = catalog::runtime_for(plan.backend, caps.os);
    println!("=== Runtime a descargar ===");
    match runtime {
        Some(runtime) => println!(
            "  {} ({:.0} MB{})",
            runtime.display_name,
            runtime.total_bytes() as f64 / (1024.0 * 1024.0),
            if runtime.extra_archives.is_empty() {
                ""
            } else {
                ", incluye el CUDA runtime"
            }
        ),
        None => println!("  (ninguno disponible para esta plataforma)"),
    }
    println!();

    println!("=== Modelos ofrecidos para {} ===", plan.tier.display_name());
    for model in catalog::models_for(plan.tier) {
        let layers = gpu_layers_for(model, &plan);
        let offload = if !plan.backend.is_gpu() {
            "CPU".to_string()
        } else if layers >= 999 {
            "GPU (todas las capas)".to_string()
        } else if layers == 0 {
            "GPU (no entra: iria por CPU)".to_string()
        } else {
            format!("GPU parcial ({layers}/{} capas)", model.layer_count)
        };

        println!(
            "  [{}] {:<38} {:>6} MB  KV {:>5} MB  ->  {}",
            if model.is_default { "*" } else { " " },
            model.display_name,
            model.file_mb(),
            kv_cache_mb(model, plan.context_size),
            offload
        );
        println!("       {} · {}", model.license, model.notes);
    }
    println!();

    println!("=== Todas las gamas (para el selector manual del wizard) ===");
    for tier in Tier::ALL {
        let model = catalog::default_model_for(tier);
        println!(
            "  {:<10} {:<38} descarga {:>6} MB (con margen)",
            tier.display_name(),
            model.display_name,
            required_disk_mb(model)
        );
    }
}
