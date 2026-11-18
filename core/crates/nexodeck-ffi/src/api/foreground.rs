use std::time::Duration;

use crate::frb_generated::StreamSink;

/// Aplicacion en primer plano en la PC. Espejo de
/// `nexodeck_hardware::ForegroundApp` -- ver el comentario de
/// `HardwareSnapshot` sobre por que el DTO se duplica aca.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ForegroundApp {
    pub process_name: String,
    pub pid: u32,
}

/// Empuja hacia Dart la aplicacion en primer plano, **solo cuando cambia**.
///
/// El polling (1/s) se hace de este lado y no en Dart por dos razones: es
/// una llamada nativa por plataforma que no tiene por que cruzar el bridge,
/// y filtrar aca los valores repetidos convierte ~3600 mensajes por hora en
/// uno por cada Alt+Tab real.
///
/// `None` (que llega a Dart como `null`) significa "no se puede saber":
/// ninguna ventana en foco, el proceso murio entre leer el pid y resolver
/// el nombre, o la plataforma no lo soporta (todo lo que no sea Windows,
/// por ahora). El consumidor trata `null` igual que "ningun perfil
/// matchea": no cambia nada.
pub async fn watch_foreground_app(sink: StreamSink<Option<ForegroundApp>>) {
    let mut watcher = nexodeck_hardware::ForegroundWatcher::new();
    let mut ticker = tokio::time::interval(Duration::from_secs(1));
    // El primer tick de `interval` es inmediato, y aca eso es lo que
    // queremos (a diferencia de las metricas, que necesitan una ventana de
    // muestreo): la UI tiene que saber el foco actual sin esperar un
    // segundo. Ademas `last` arranca sin valor, asi que el primer estado
    // siempre se emite.
    let mut last: Option<Option<ForegroundApp>> = None;

    loop {
        ticker.tick().await;
        let current = watcher.current().map(|app| ForegroundApp {
            process_name: app.process_name,
            pid: app.pid,
        });

        // Comparar por el valor entero (incluido el `None`) y no solo por
        // el nombre: pasar de "OBS" a "sin foco" tambien es un cambio que
        // la UI tiene que ver.
        if last.as_ref() == Some(&current) {
            continue;
        }
        last = Some(current.clone());

        if sink.add(current).is_err() {
            break; // Dart cerro el stream
        }
    }
}
