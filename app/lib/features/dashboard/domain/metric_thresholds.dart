/// A partir de cuanto una metrica se pinta en el color de alerta en vez del
/// color normal de su tile.
///
/// Son umbrales calculados, no medidos contra un equipo puntual -- el
/// proyecto corre en maquinas distintas (ver "Setup en una maquina nueva" en
/// `CLAUDE.md`), asi que no hay un numero "correcto" para todo hardware.
/// Cada uno deja margen real antes del limite fisico de la pieza:
///
/// - **CPU 80°C**: mismo umbral que ya usaba `ThermometerChart` (`warnC`,
///   agregado antes que esto) para virar su color -- no es el limite fisico
///   del silicio (los Ryzen modernos aguantan 90-95°C de `Tctl`/`Tdie` antes
///   de empezar a limitar), es "donde vale la pena mirar". Se reusa el mismo
///   numero en vez de inventar uno nuevo para que el chip, el termometro, el
///   numero de grados y el badge de hilos viren todos juntos.
/// - **GPU 80°C**: las GPUs de escritorio actuales (NVIDIA y AMD) suelen
///   empezar a limitar entre 83-88°C segun el modelo; 80 es conservador
///   pero generico, sin depender de la tarjeta puntual.
/// - **GPU 2400 MHz**: los relojes boost de las GPUs de gama media/alta
///   actuales rondan 2400-2700 MHz bajo carga; por debajo de eso el reloj
///   sube y baja con normalidad, no es indicio de nada.
/// - **80% de uso** (RAM por modulo, GPU): mismo criterio en los dos --
///   cerca del limite pero con margen antes de quedarse sin recurso.
/// - **Potencia de GPU, relativa a su propio techo**: como con la red, no hay
///   un numero de watts que separe "normal" de "mucho" -- una tarjeta de gama
///   media tira 180 W a full y una de gama alta 450 W en reposo relativo. Se
///   compara contra el techo que el driver informa
///   (`nvmlDeviceGetEnforcedPowerLimit`), que es exactamente cuando la GPU
///   empieza a recortarse sola.
/// - **Disco, distinto segun el medio**: un plato y una memoria flash no
///   sufren a la misma temperatura, asi que un solo numero seria demasiado
///   alto para uno o demasiado bajo para el otro. Un HDD trabaja comodo hasta
///   ~45 °C y los fabricantes ponen su maximo de operacion en 55-60; un SSD o
///   un NVMe recien empiezan a limitarse cerca de los 75-80. De ahi los 50 y
///   los 70 de abajo, cada uno con margen antes de su propio limite.
/// - **Red, relativo al pico reciente**: a diferencia de temperatura o
///   porcentaje, no hay un numero de KB/s que separe "normal" de "mucho": una
///   fibra satura a cientos de MB/s y un WiFi viejo a un par de MB/s. Se
///   compara contra el propio historial reciente (`netMaxY`, el mismo pico
///   que ya usa el grafico para autoescalarse) en vez de un umbral fijo.
library;

import 'hardware_snapshot.dart';

/// CPU: temperatura de alerta, en °C. Mismo valor que
/// `ThermometerChart.warnC` -- ver el porque en el comentario de arriba.
const double kCpuHotTempC = 80.0;

/// GPU: temperatura de alerta, en °C.
const double kGpuHotTempC = 80.0;

/// GPU: reloj de alerta, en MHz.
const int kGpuFastClockMhz = 2400;

/// GPU: fraccion de uso (0.0-1.0) a partir de la cual se considera "trabajando".
const double kGpuBusyFraction = 0.80;

/// RAM: fraccion de un modulo (0.0-1.0) a partir de la cual se pinta de alerta.
const double kRamModuleHotFraction = 0.80;

/// GPU: fraccion de VRAM ocupada (0.0-1.0) a partir de la cual la barra de
/// capacidad se pinta de alerta. Mismo numero que [kRamModuleHotFraction]
/// -- es la misma pregunta ("memoria casi llena") sobre otra memoria --,
/// pero con nombre propio: es independiente del uso de computo de la GPU
/// (`kGpuBusyFraction`), no la misma cosa medida dos veces.
const double kGpuVramHotFraction = 0.80;

/// GPU: fraccion del techo de potencia (0.0-1.0) a partir de la cual el
/// consumo se pinta de alerta. Mas alto que el 80% del resto a proposito: a
/// diferencia de la memoria, tocar el techo de potencia no rompe nada --la
/// tarjeta baja el reloj y sigue--, asi que solo interesa saberlo cuando ya
/// esta ahi.
const double kGpuPowerHotFraction = 0.90;

/// Disco mecanico: temperatura de alerta, en °C.
const double kHddHotTempC = 50.0;

/// Disco de estado solido (SSD SATA o NVMe): temperatura de alerta, en °C.
const double kSsdHotTempC = 70.0;

/// Disco de medio desconocido: a mitad de camino entre los dos de arriba. Es
/// la unica opcion honesta -- usar el umbral del SSD podria callar un plato a
/// 65 °C, y usar el del HDD pintaria de rojo un NVMe que esta perfecto.
const double kUnknownDiskHotTempC = 60.0;

/// Red: fraccion del pico reciente (`netMaxY`) a partir de la cual una
/// direccion (bajada o subida) se considera cargada.
const double kNetworkBusyFractionOfPeak = 0.70;

bool isCpuHot(double? tempC) => tempC != null && tempC >= kCpuHotTempC;

bool isGpuHot(double? tempC) => tempC != null && tempC >= kGpuHotTempC;

bool isGpuFast(int? clockMhz) => clockMhz != null && clockMhz >= kGpuFastClockMhz;

bool isGpuBusy(double? usagePercent) =>
    usagePercent != null && usagePercent / 100 >= kGpuBusyFraction;

bool isRamModuleHot(double moduleFill) => moduleFill >= kRamModuleHotFraction;

bool isGpuVramHot(double? vramFraction) =>
    vramFraction != null && vramFraction >= kGpuVramHotFraction;

/// Una GPU sin techo informado nunca da "alta": no hay contra que comparar
/// los watts, igual que la red sin pico reciente.
bool isGpuPowerHigh(double? powerFraction) =>
    powerFraction != null && powerFraction >= kGpuPowerHotFraction;

/// Umbral que le corresponde a un disco segun su medio.
double diskHotTempC(DiskMediaKind kind) => switch (kind) {
  DiskMediaKind.hdd => kHddHotTempC,
  DiskMediaKind.ssd => kSsdHotTempC,
  DiskMediaKind.unknown => kUnknownDiskHotTempC,
};

bool isDiskHot(DiskMediaKind kind, double? tempC) =>
    tempC != null && tempC >= diskHotTempC(kind);

/// `currentKb` cargado respecto de `recentPeakKb`. `recentPeakKb` en 0 (sin
/// historial todavia) nunca da "cargado": no hay pico contra el que comparar.
bool isNetworkBusy(double currentKb, double recentPeakKb) =>
    recentPeakKb > 0 && currentKb / recentPeakKb >= kNetworkBusyFractionOfPeak;
