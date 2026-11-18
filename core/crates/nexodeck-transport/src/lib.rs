pub mod client;
pub mod discovery;
pub mod error;
pub mod notes;
pub mod pairing;
mod relay;
pub mod server;
mod session;
pub mod tls;
pub mod usb;
mod wire;

pub use error::TransportError;

/// No puede ser un `impl From<...>` -- ambos tipos son de crates externos
/// (regla de orphan rules), asi que es una funcion de conversion simple.
/// Las tres listas de procesos, al formato del cable.
pub fn top_processes_to_wire(
    sample: nexodeck_hardware::TopProcesses,
) -> nexodeck_protocol::TopProcessesWire {
    fn group(g: nexodeck_hardware::ProcessGroup) -> nexodeck_protocol::ProcessGroupWire {
        nexodeck_protocol::ProcessGroupWire {
            name: g.name,
            pids: g.pids,
            cpu_percent: g.cpu_percent,
            memory_mb: g.memory_mb,
            gpu_percent: g.gpu_percent,
            disk_bytes_per_sec: g.disk_bytes_per_sec,
            run_time_secs: g.run_time_secs,
            is_self: g.is_self,
        }
    }

    nexodeck_protocol::TopProcessesWire {
        by_cpu: sample.by_cpu.into_iter().map(group).collect(),
        by_memory: sample.by_memory.into_iter().map(group).collect(),
        by_gpu: sample.by_gpu.into_iter().map(group).collect(),
        by_disk: sample.by_disk.into_iter().map(group).collect(),
        gpu_available: sample.gpu_available,
    }
}

pub fn hardware_snapshot_to_wire(
    s: nexodeck_hardware::HardwareSnapshot,
) -> nexodeck_protocol::HardwareSnapshot {
    nexodeck_protocol::HardwareSnapshot {
        cpu_usage: s.cpu_usage,
        cpu_freq_mhz: s.cpu_freq_mhz,
        cpu_temp: s.cpu_temp,
        ram_used_mb: s.ram_used_mb,
        ram_total_mb: s.ram_total_mb,
        disk_used_mb: s.disk_used_mb,
        disk_total_mb: s.disk_total_mb,
        disks: s
            .disks
            .into_iter()
            .map(|disk| nexodeck_protocol::DiskUsageWire {
                mount_point: disk.mount_point,
                label: disk.label,
                kind: match disk.kind {
                    nexodeck_hardware::DiskMediaKind::Ssd => nexodeck_protocol::DiskKindWire::Ssd,
                    nexodeck_hardware::DiskMediaKind::Hdd => nexodeck_protocol::DiskKindWire::Hdd,
                    nexodeck_hardware::DiskMediaKind::Unknown => {
                        nexodeck_protocol::DiskKindWire::Unknown
                    }
                },
                used_mb: disk.used_mb,
                total_mb: disk.total_mb,
                read_bytes_per_sec: disk.read_bytes_per_sec,
                write_bytes_per_sec: disk.write_bytes_per_sec,
                temp_c: disk.temp_c,
                temp_age_secs: disk.temp_age_secs,
            })
            .collect(),
        net_rx_bytes: s.net_rx_bytes,
        net_tx_bytes: s.net_tx_bytes,
        gpu_usage: s.gpu_usage,
        gpu_temp: s.gpu_temp,
        gpu_vram_used_mb: s.gpu_vram_used_mb,
        gpu_vram_total_mb: s.gpu_vram_total_mb,
        gpu_clock_mhz: s.gpu_clock_mhz,
        cpu_threads_total: s.cpu_threads_total,
        cpu_threads_busy: s.cpu_threads_busy,
        gpu_power_watts: s.gpu_power_watts,
        gpu_power_limit_watts: s.gpu_power_limit_watts,
    }
}
