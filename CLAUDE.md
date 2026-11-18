# NexoDeck

Streamdeck virtual multiplataforma (Windows, Linux, Android). Core compartido
en Rust (`core/`, workspace de Cargo), UI única en Flutter (`app/`),
comunicados vía `flutter_rust_bridge`. Ver
[`NexoDeck-Arquitectura-y-Plan-de-Fases.md`](./NexoDeck-Arquitectura-y-Plan-de-Fases.md)
para la arquitectura completa y el plan de fases — es la fuente de verdad. Ver
[`docs/ESTADO-DEL-PROYECTO.md`](./docs/ESTADO-DEL-PROYECTO.md) para un
snapshot de qué está hecho, qué falta, y las desviaciones conocidas de la
arquitectura original.

## Comandos canónicos

Melos **debe** ser dev_dependency del workspace raíz (no activarlo global):
desde la v7, Melos usa esa declaración para detectar el workspace — sin ella
falla con "does not appear to be within a Melos workspace" aunque esté
activado globalmente.

```sh
dart pub get                        # resuelve el pub workspace raíz
dart run melos bootstrap            # flutter pub get en app/ (comando built-in de Melos)
dart run melos run setup            # deps del build_tool de cargokit (una vez por máquina)
dart run melos run app:analyze      # flutter analyze sobre app/
dart run melos run rust:build       # cargo build del workspace Rust completo
dart run melos run rust:test        # cargo test del workspace Rust completo
dart run melos run bridge:gen       # regenera los bindings del bridge FFI (app/)
dart run melos run sensors:build    # publica el sidecar de sensores en dist/sensors
```

Correr la app (desde `app/`): `flutter run -d windows` (o `-d linux`, `-d <android-device>`).

## Setup en una máquina nueva (el proyecto se programa en varios equipos)

Nada del repo asume una máquina, un usuario ni una unidad concreta: las rutas
de datos las resuelven `driftDatabase()` (Dart) y `directories::ProjectDirs`
(Rust) por usuario en runtime, y `app/android/local.properties` (rutas del
SDK de Android/Flutter) está gitignoreado y lo regenera Flutter solo. Lo que
sí hay que instalar por máquina:

| Herramienta | Para qué | Verificar |
|---|---|---|
| Flutter 3.41.9 + Dart | app + tooling | `flutter doctor` |
| Rust stable (MSVC en Windows) ≥ 1.90 | los 7 crates del core; **sin esto ni siquiera compila la app de escritorio**, porque cargokit invoca `cargo` durante el build de Flutter | `cargo --version` |
| Targets Android de Rust | `flutter build apk` (cargokit compila el `.so` por ABI) | `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android` |
| JDK 21 + Android SDK + NDK | build de Android | `flutter doctor` |
| .NET SDK 8 | el sidecar de sensores (`sensors/`), que es lo que da la temperatura del CPU en Windows | `dotnet --version` |
| Visual Studio con "Desktop development with C++" | build de Windows y toolchain MSVC de Rust | `flutter doctor` |
| `flutter_rust_bridge_codegen` **en la misma versión que el paquete Dart** (hoy 2.12.0) | solo para `melos run bridge:gen`; si las versiones no coinciden, el codegen se queja | `cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked` |

Orden de arranque tras clonar (o tras cambiar de equipo):

```sh
dart pub get                        # workspace raíz
dart run melos bootstrap            # flutter pub get en app/
dart run melos run setup            # deps del build_tool de cargokit (ver gotcha abajo)
flutter clean                       # desde app/, si el repo viene de otra máquina
```

**Primer gotcha al mover el repo entre máquinas/perfiles:** `flutter analyze`
puede reportar ~185 errores, **todos** dentro de
`app/rust_builder/cargokit/build_tool` (código vendorizado de
flutter_rust_bridge) y ninguno en `lib/`/`test/`. No es código roto: ese
subpaquete tiene su propio `pubspec.yaml` y su `.dart_tool/package_config.json`
queda apuntando al pub cache del perfil de usuario de la máquina anterior, así
que el analizador no resuelve ni `package:http`. Se arregla con el
`dart pub get` de la tercera línea de arriba. Antes de investigar un
`flutter analyze` en rojo, fijate si los errores están en `lib/` o solo en
`cargokit`.

**Segundo gotcha de la misma familia:** si `app/build/` viajó con el repo (está
gitignoreado, pero sobrevive a una copia de carpeta o a un backup),
`flutter build windows` falla con
`error C1083: No se puede abrir el archivo incluir: 'jni.h'` en el plugin
`jni`. La causa no es el JDK: es que `app/build/windows/x64/CMakeCache.txt`
quedó cacheado con las rutas absolutas del JDK de la máquina anterior
(`JAVA_INCLUDE_PATH`, `JAVA_JVM_LIBRARY`), y CMake reusa el caché sin volver a
buscar. `flutter clean` (o borrar `app/build/windows/`) y reconstruir. Por eso
`flutter clean` está en la lista de arranque de arriba: corré eso antes de
diagnosticar cualquier error de compilación nativa en un equipo distinto.

**Tercer gotcha del mismo estilo:** si el repo se copió desde otro perfil de
Windows, `git` corta con "dubious ownership". Se resuelve una vez por equipo
con `git config --global --add safe.directory <ruta-del-repo>`.

## Reglas de arquitectura no negociables

- **Solo `nexodeck-ffi` se expone a Dart.** Ningún otro crate (`nexodeck-hardware`,
  `nexodeck-protocol`, `nexodeck-transport`, `nexodeck-actions`, `nexodeck-vault`,
  `nexodeck-db`) se importa directamente desde `app/`.
- **Nunca JSON en `nexodeck-protocol`.** Se serializa con `postcard`. Ver
  [`docs/architecture-decision-records/0001-postcard-sobre-json.md`](./docs/architecture-decision-records/0001-postcard-sobre-json.md)
  — implica que los enums del protocolo deben ser *externally tagged*
  (default de serde), nunca `#[serde(tag = ..., content = ...)]`.
- Los secretos (tokens, contraseñas) nunca tocan Drift/Dart en texto plano —
  viven cifrados en `nexodeck-vault` (Rust); Drift solo guarda metadatos de
  referencia (`secrets_refs`).

## Riverpod: sin codegen por ahora (deviación conocida)

La arquitectura decide Riverpod 3 con codegen (`@riverpod`). En este SDK de
Flutter (3.41.9 / Dart 3.11.5), `riverpod_generator` no resuelve: el SDK de
Flutter fija `meta` en exactamente `1.17.0`, y **ninguna** versión de
`analyzer` que `riverpod_generator` necesita (en todo su rango de versiones)
es compatible con eso — las versiones viejas de `analyzer` requieren el
paquete `macros`/`_macros` del SDK (removido en este Dart), y las nuevas
requieren `meta ^1.18.0`. Confirmado exhaustivamente por el solver de pub.
Esto es independiente de Melos (no lo agraves quitando Melos del workspace
para "liberar" el lockfile — no ayuda, y rompe la deteccion de workspace de
Melos v7+, ver seccion de arriba).

Mientras esto no se resuelva en el ecosistema, los providers se escriben a
mano con la API clásica de Riverpod (`StreamProvider`, `Provider`, etc. sin
`@riverpod`) — ver `app/lib/features/dashboard/application/`. Antes de
reintentar el codegen en una sesión futura, correr
`flutter pub add dev:riverpod_generator dev:build_runner` de nuevo para ver
si ya resuelve con versiones más nuevas de Flutter/Dart.

## Drift: SÍ funciona con codegen (a diferencia de Riverpod)

`drift_dev` + `build_runner` **sí resuelven** en este SDK de Flutter —a
diferencia de `riverpod_generator`, ver seccion de arriba. La version de
`drift_dev` 2.34.x cae justo en el rango de `analyzer` compatible con el
`meta` que fija este Flutter SDK. No asumas que "codegen no funciona en este
proyecto" en general — es un problema especifico de `riverpod_generator`.

Las 11 tablas del esquema completo (`actions_table`, `action_parameters`,
`macro_steps`, `profiles`, `profile_actions`, `devices`, `alert_rules`,
`hardware_history`, `secrets_refs`, `window_layouts`, `app_settings`) ya
estan creadas de una sola vez en `schemaVersion 1`
(`app/lib/data/local/`), con sus DAOs — decisión del usuario, ya
implementada. Después se sumaron, ya con migración: `action_groups` en
`schemaVersion 2`, `ActionsTable.showTerminalWindow` en `schemaVersion 3`, las
tasas de red de `hardware_history` (`netRxBytesPerSec`/`netTxBytesPerSec`) en
`schemaVersion 4`, el volteo de `show_terminal_window` a `false` en
`schemaVersion 5` —que no agrega nada al esquema: da vuelta las filas
existentes porque el `true` viejo significaba "quiero ver la salida", y ahora
la salida se ve dentro de la app—, `ActionsTable.pasteToActiveWindow` en
`schemaVersion 6` y la dirección manual de una PC
(`Devices.manualHost`/`manualPort`, para alcanzarla fuera de la LAN) en
`schemaVersion 7`. Hoy son **12 tablas con 12 DAOs**, y el esquema va por la
versión 7 (ver `onUpgrade` en `database.dart` y la skill `drift-migration`
antes de tocarlo).

**Los `addColumn` de las migraciones son idempotentes, y no por prolijidad.**
Van todos por `_addColumnIfMissing`, que consulta `PRAGMA table_info` antes de
tocar nada. La base real del equipo principal apareció con
`paste_to_active_window` ya creada y `user_version` todavía en 5 —o sea, a
mitad de la migración a la 6: el PC se apagó mientras corría—. Con el
`m.addColumn` pelado, cada arranque siguiente reintenta el mismo `ALTER` y
muere con `duplicate column name`: **la app no vuelve a abrir nunca**, y el
usuario no tiene ninguna salida. Hay un test que fija las dos mitades
(`test/database_migration_test.dart`).

**Gotcha de nombres:** la tabla de acciones se llama `ActionsTable`, NO
`Actions` — `package:flutter/widgets.dart` ya exporta una clase `Actions`
(el sistema de Actions/Intents de Flutter) y chocaria. Si agregas una tabla
nueva, revisa que su nombre no choque con algo de Flutter/Dart core antes
de escribirla.

**Para inspeccionar la base de datos real durante debugging:** el archivo lo
resuelve Drift solo (`driftDatabase(name: 'nexodeck')` en
`app/lib/data/local/database.dart`), que en desktop/Android cae en el
directorio de documentos/datos de la app **del usuario actual** —
`getApplicationDocumentsDirectory()/nexodeck.sqlite`. Nunca hardcodees esa
ruta: cambia por máquina y por usuario. Para averiguarla en el equipo en el
que estés parado, en Windows:
`[Environment]::GetFolderPath('MyDocuments')` en PowerShell (no asumas
`~/Documents` — la carpeta de Documentos puede estar redirigida a otra
unidad y hasta a otro nombre de usuario distinto del perfil de Windows/Git
Bash, que es exactamente el caso en el equipo principal del proyecto). En
Linux, el equivalente vía `xdg-user-dir DOCUMENTS`.

Puede no haber `sqlite3` CLI instalado; para inspeccionar, un script Dart
chico con `package:sqlite3` corrido con `dart run` **desde dentro de `app/`**
(para que resuelva el `pubspec.yaml` correcto) funciona en cualquier máquina.

## CPU en Windows: un solo `refresh_cpu_*` por snapshot

**Nunca encadenes dos llamadas `refresh_cpu_*` en el mismo `snapshot()`.**
En Windows, `sysinfo` no lee el uso de CPU de contadores de tiempo: lo
calcula como `100 - \Processor(_Total)\% Idle Time` via PDH, y
`refresh_cpu_specifics()` **recalcula ese valor en cada llamada, ignorando
el `CpuRefreshKind` que recibe**. Como `refresh_cpu_usage()` y
`refresh_cpu_frequency()` delegan las dos en ese mismo metodo, llamarlas
seguidas dejaba una ventana de muestreo de ~0 ms para la segunda: el
contador devuelve `PDH_INVALID_DATA`, `Query::get` lo traduce a `0.0` **en
silencio** (`sysinfo/src/windows/cpu.rs`), y el uso quedaba clavado en
`100.0 - 0.0 = 100.0`.

El sintoma es especialmente traicionero porque no hay ningun error: la UI
mostraba 100% de CPU fijo mientras el Administrador de tareas marcaba 60%.
La solucion es la unica llamada
`refresh_cpu_specifics(CpuRefreshKind::everything())` que hay hoy en
`snapshot()` — trae uso y frecuencia con un unico `PdhCollectQueryData`.
Es especifico de Windows: la ruta de Linux protege el recalculo detras de
`MINIMUM_CPU_UPDATE_INTERVAL` (200 ms).

Relacionado: los dos productores del stream de metricas
(`nexodeck-ffi/src/api/hardware.rs` y `nexodeck-transport/src/server.rs`)
usan `tokio::time::interval_at` y no `interval`, porque el primer tick de
`interval` se dispara al instante y ese snapshot se muestrearia sobre una
ventana de ~0 ms contra la linea base de `HardwareMonitor::new()`.

Para verificar el porcentaje contra el Administrador de tareas:
`cargo run -p nexodeck-hardware --example snapshot` (imprime 10 muestras a
1 s). El test de Rust solo comprueba el rango 0-100 a proposito: afirmar
`< 100` seria flaky en una maquina cargada.

### Frecuencia real y cual es "el" porcentaje del Administrador de tareas

**La frecuencia de `sysinfo` en Windows es la nominal fija.** Sale de
`CallNtPowerInformation(...).CurrentMhz`, que en el Ryzen 7 5700X devolvia
**3401 MHz siempre**, con el procesador en turbo a 4.2-4.5 GHz. La actual es
`Processor Frequency` (nominal) por `% Processor Performance` / 100, que es la
cuenta del Administrador de tareas: `cpu_counters.rs` la lee por PDH en una sola
query y `HardwareMonitor::cpu_frequency_mhz` cae a `sysinfo` solo si PDH no da
muestra. La UI la muestra en GHz con dos decimales (`formatCpuFrequency`).

**El porcentaje NO se cambio, y no hay que cambiarlo a `% Processor Utility`.**
Medido el 15-sep-2026 cruzando por marca de tiempo lo que grabo la app instalada
en `hardware_history` contra `cpu_compare`, con el Administrador de tareas al
lado:

| Fuente | Media en la misma ventana |
|---|---|
| App (`sysinfo`, `100 - % Idle Time`) | 41.2% |
| `% Processor Time` | 45.6% |
| `% Processor Utility` | 55.8% |
| Administrador de tareas | ~42% |

`sysinfo` coincide con `% Processor Time`, que es lo que muestra el Administrador
de tareas en este Windows 11 ("metricas estandar"). `% Processor Utility` --el
contador clasico, que pondera por turbo y pasa de 100-- marcaria ~14 puntos de
mas. **Un reporte de "NexoDeck marca mas que el Administrador de tareas" suele ser
un pico**: el valor es instantaneo sobre 1 s, y con carga real salta de 20% a
100% en segundos. Antes de tocar la formula, medir con
`cargo run -p nexodeck-hardware --example cpu_compare -- 20`, que imprime las tres
columnas con su epoch en ms para poder cruzarlas.

## Temperatura del CPU: sidecar propio, ya no LibreHardwareMonitor

`cpu_temp` tiene dos fuentes, en este orden:

1. Los sensores que ya expone el SO via `sysinfo` (`Components`). Es la ruta
   normal en Linux/Android: `k10temp` (AMD) y `coretemp` (Intel) publican ahi
   el Tctl/Tdie y la temperatura del paquete.
2. Solo en Windows, el **sidecar propio** `sensors/NexoDeckSensors` (C#/.NET 8),
   que NexoDeck empaqueta y registra como **servicio de Windows**
   (`NexoDeckSensors`, LocalSystem, arranque automatico). La app no lo lanza:
   solo abre su pipe.

**Esto cambio: antes la fuente 2 era el servidor web de LibreHardwareMonitor**
(`127.0.0.1:8085/data.json`), o sea que la temperatura solo aparecia si el
usuario habia instalado LHM por su cuenta y lo tenia abierto. Hoy el motor
(`LibreHardwareMonitorLib`, MPL-2.0) viaja **dentro** de NexoDeck. Si tocas
esto, no vuelvas a introducir el sondeo HTTP: `reqwest` se saco de
`nexodeck-hardware` justamente por esto, y el crate ya no arrastra una pila
HTTP entera.

**Por que sigue haciendo falta algo asi.** En Windows la temperatura del CPU no
se puede leer desde espacio de usuario, y esto esta **re-verificado en vivo**
en el equipo principal (Ryzen 7 5700X), no heredado de la documentacion vieja:

| Via | Resultado |
|---|---|
| `MSAcpi_ThermalZoneTemperature` (WMI/ACPI) | `Incompatible` |
| Contador PDH `ThermalZoneInformation` | la clase existe, **cero instancias** |
| `Win32_TemperatureProbe` (SMBIOS) | sin instancias |
| Resto de `root\wmi` | solo eventos de politica termica, ninguna lectura |

Los Ryzen la publican en el registro SMN `0x00059800` (espacio de configuracion
PCI) y los Intel en un MSR: los dos, kernel-mode. De ahi el driver, y de ahi
que el sidecar corra como LocalSystem.

Como esta armado, y lo que no es obvio:

- **Hablan por named pipe** (`\\.\pipe\nexodeck-sensors`), no por HTTP: no
  ocupa puerto, no dispara el dialogo del firewall y no queda escuchando para
  cualquiera que pase por localhost.
- **El pipe lleva una ACL explicita, y no es opcional.** Lo crea un proceso
  elevado y lo abre uno sin elevar; con la ACL por defecto el dueño es el
  administrador y NexoDeck recibiria ACCESS_DENIED, con un sintoma identico al
  de "el sidecar no esta corriendo" -- o sea, el diagnostico equivocado. Ver
  `CreatePipe()` en `Program.cs`.
- **Un `0` no es una temperatura, es "el driver no cargo".** Corriendo el
  sidecar SIN elevar, la libreria enumera igual el sensor `Core (Tctl/Tdie)` y
  devuelve exactamente `0`: no lanza, no avisa. Verificado en vivo. Se filtra
  en el sidecar (`MinPlausibleC`) **y** en Rust, porque el que dibuja el badge
  es el lado Rust.
- **El sidecar manda la lista completa de sensores, no el mejor.** Cual gana lo
  decide `cpu_temp::label_priority`, la misma funcion que rankea los sensores
  que llegan por sysfs en Linux. Elegir en los dos lados seria tener la misma
  decision escrita dos veces.
- **Solo habilita `IsCpuEnabled`.** `IsStorageEnabled` **despertaria los discos**
  en cada refresco, y ademas NexoDeck ya lee su temperatura por su cuenta (ver
  la seccion siguiente).
- **Los numeros salen con punto decimal** (`InvariantGlobalization`). El bug de
  la coma decimal de la version anterior (`"58,6 °C"` en un Windows en espanol)
  esta resuelto en el emisor, no en el parser.
- **NativeAOT no sirve** (la libreria carga su driver de un recurso embebido y
  usa reflexion), asi que va autocontenido y comprimido:
  `EnableCompressionInSingleFile` lo baja de 68 MB a 36. **No pongas
  `PublishTrimmed`** sin verificarlo antes contra hardware real.
- **Es un servicio de Windows, no una tarea programada.** La tarea
  (`NexoDeck-Sensors`, disparada con `schtasks /run`) fue la primera version y
  se saco tras pagarla en vivo: solo corria con el usuario conectado, no se
  reiniciaba si el proceso moria, `schtasks` no deja estado que consultar, y
  dependia de que el instalador se hubiera corrido elevado. Hoy el servicio
  arranca con Windows y tiene recuperacion ante fallo (tres reinicios, el
  contador se reinicia al dia). **La app no lo lanza**: `windows_provider.rs`
  solo abre el pipe y reintenta cada 30 s, asi que la temperatura aparece sola
  si el servicio arranca despues.
- **Lo registra el propio `.exe`** con `--install` / `--uninstall` (via
  `sc.exe`, esperando a que el servicio viejo termine de borrarse: `sc delete`
  es asincrono y encadenarlo con `create` fallaba con 1072). Ese mismo camino lo
  usan el instalador y la app, que es lo que evita tener dos formas de
  registrarlo.
- **Sin elevacion no hay servicio, y la app lo dice.** El instalador lo
  registra solo en instalacion para todos los usuarios (la casilla `sensors` se
  oculta por usuario: registrar un servicio es de maquina). Por usuario --el modo
  por defecto--, `sensor_helper.rs` consulta el SCM sin elevar y la UI ofrece
  instalarlo con un UAC unico (menu "Mas" -> "Temperatura del procesador"). Antes
  de eso la temperatura faltaba en silencio.
- El log va a `%ProgramData%\NexoDeck\sensors.log`, no a `LocalAppData`: bajo
  LocalSystem eso resuelve a `System32\config\systemprofile`, donde nadie lo
  buscaria.

Para regenerar el sidecar despues de tocarlo: `dart run melos run sensors:build`
(deja el `.exe` en `dist/sensors`, que es de donde lo toma el instalador). Si
el servicio esta corriendo, `dotnet` no puede sobrescribir el `.exe`: hay que
detenerlo antes desde una consola de administrador (`Stop-Service
NexoDeckSensors`).

**Verificado en vivo en el equipo principal (15-sep-2026):** el servicio esta
instalado desde la instalacion por usuario, corre como LocalSystem con arranque
automatico, publica `\\.\pipe\nexodeck-sensors`, y su log registra "sensores
abiertos; 2 lecturas de CPU" con clientes que conectan y se van. Antes ya se
habia verificado que el filtro del `0` funciona y que el cliente Rust elige
`Core (Tctl/Tdie)` por encima de `Core Max` y descarta `GPU Core`, contra un
servidor de pipe de mentira.

**Lo que NO esta verificado:** que el numero llegue al badge de la ficha de CPU
de la app, mirado en pantalla, y el flujo de instalacion con UAC desde el menu
(necesita un humano que apruebe el dialogo).

## Temperatura por disco (nexodeck-hardware/src/disk_temp.rs)

`DiskUsage.temp_c` trae la temperatura del disco **fisico** que respalda cada
volumen. Dos particiones del mismo disco muestran el mismo numero: hay un solo
sensor.

**Se lee sin privilegios de administrador**, que es lo que la hace viable. La
clave es abrir `\\.\PhysicalDriveN` con `dwDesiredAccess = 0`: sin pedir
`GENERIC_READ` no hace falta elevacion, y los dos IOCTL aceptan igual el
handle. Comparalo con la via "oficial" de PowerShell
(`Get-StorageReliabilityCounter`, o sea `MSFT_StorageReliabilityCounter`), que
**si** exige elevacion -- verificado en vivo: los cuatro discos del equipo
principal contestan "El cliente no tenia acceso disponible a un recurso CIM"
sin elevar, y los cuatro contestan su temperatura por este otro camino.

Dos fuentes segun el bus, porque no hay una sola que sirva para los dos:

- **NVMe**: `IOCTL_STORAGE_QUERY_PROPERTY` con
  `StorageDeviceProtocolSpecificProperty`, pidiendo la log page 0x02 (SMART /
  Health) del estandar NVMe. La temperatura compuesta son los bytes 1-2, en
  Kelvin y little endian.
- **Todo lo demas (SATA, USB, RAID)**: `IOCTL_STORAGE_PREDICT_FAILURE`, que
  devuelve los 512 bytes crudos de `SMART READ DATA`; ahi el atributo 194 es la
  temperatura (y el 190 su respaldo, para los SSD que solo publican ese).
  **Ese IOCTL es `FILE_ANY_ACCESS`**, y eso es exactamente por que funciona con
  el handle abierto sin accesos.

Cosas que no son obvias:

- **No va en la ruta de `snapshot()`, y no es por costo de CPU**: una consulta
  SMART **despierta un disco mecanico**. A 1/s los dos HDD del equipo principal
  no bajarian a reposo nunca. El sondeo vive en un hilo propio cada 30 s, mismo
  patron que `cpu_temp`.
- **Se parte de las letras de unidad, no de enumerar `PhysicalDrive0..N`.** El
  puente es `IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS`, porque las dos mitades
  estan indexadas distinto: la temperatura se pide por disco fisico y la lista
  que dibuja la UI por punto de montaje. Un disco sin letra no tendria donde
  mostrarse, y sondearlo solo lo despertaria para nada.
- **En `VOLUME_DISK_EXTENTS` el array arranca en el byte 8, no en el 4**, por
  el relleno de alineacion: `DISK_EXTENT` contiene un `LARGE_INTEGER`.
- **Los NVMe no contestan `IOCTL_STORAGE_PREDICT_FAILURE`** (dan
  ERROR_INVALID_FUNCTION) y los SATA no entienden la consulta de log page: cada
  bus tiene una sola puerta, no hay que intentar las dos.
- **El umbral de alerta depende del medio** (`metric_thresholds.dart`): 50 °C
  para un plato, 70 para flash, 60 para medio desconocido. Un solo numero seria
  demasiado alto para uno o demasiado bajo para el otro.
- **Un disco dormido no contesta, y eso NO puede borrar su temperatura.** La
  contracara de sondear espaciado es que el disco entra en bajo consumo y la
  consulta SMART falla en vez de despertarlo. Comprobado en vivo: `E:` e `I:`
  dejaron de contestar tras un rato de reposo y volvieron apenas algo los toco.
  Que falle esta bien; lo que estaba mal era que la fila perdiera el dato. Hoy
  `merge_sample` conserva la ultima lectura de un disco que **sigue montado** y
  solo la descarta cuando el disco desaparece del mapa de letras. Si tocas eso,
  el sintoma de la regresion es una temperatura que parpadea sola.

Verificado en vivo en el equipo principal, los seis volumenes:
`cargo run -p nexodeck-hardware --example snapshot` lista la columna de
temperatura al final. `C:` y `D:` comparten numero por ser el mismo NVMe.

Fuera de Windows degrada entero a "sin dato", igual que `disk_io`: en Linux
esto sale de hwmon (`drivetemp`, `nvme`), pero mapear un hwmon a un punto de
montaje es otro problema y no hay maquina Linux para verificarlo.

## Inventario de discos (nexodeck-hardware/src/disks.rs)

`HardwareSnapshot.disks` trae un elemento por volumen fisico montado, y el
agregado `disk_used_mb`/`disk_total_mb` se calcula **sobre esa misma lista**
(`disks::totals`). No es un detalle de implementacion: si el agregado
recorriera `Disks` por su cuenta, el filtro de abajo se aplicaria a la lista
pero no al total, y la suma de las filas que el usuario tiene enfrente no
daria el numero de la barra.

- **`GetDriveType` no alcanza para saber si un volumen es un disco real.**
  Google Drive para escritorio monta sus unidades como `DRIVE_FIXED` con
  FAT32, asi que se hace pasar por disco local: verificado en vivo, dos
  unidades de nube inflaban el agregado en cientos de GB. El tipo de medio de
  `sysinfo` tampoco sirve — devuelve `Unknown` tanto para esas unidades como
  para RAIDs y discos virtuales legitimos.
- **Lo que si los separa es el enlace del espacio de nombres NT**
  (`QueryDosDeviceW`): toda particion de un disco real, incluidos los USB, cae
  en `\Device\HarddiskVolumeN`, mientras que un montaje de nube queda en
  `\Device\Volume{GUID}`, uno de red en `\Device\LanmanRedirector\...` y una
  unidad optica en `\Device\CdRom0`.
- **Un volumen montado en una carpeta (sin letra) se acepta**: no tiene enlace
  en el espacio de nombres DOS que consultar, y perder un disco real es peor
  que colar uno de nube.
- **La lista sale ordenada por punto de montaje.** `sysinfo` no garantiza
  orden estable entre refrescos, y una lista que se reordena sola una vez por
  segundo es ilegible.
- Fuera de Windows no se filtra nada: `sysinfo` ya deja afuera los sistemas de
  archivos pseudo, y el caso de la unidad de nube disfrazada no existe.

Para verificarlo en una maquina concreta,
`cargo run -p nexodeck-hardware --example snapshot` lista al final los discos
que quedaron dentro: si aparece una unidad de Google Drive o un recurso de
red, el filtro no la esta agarrando.

## GPU AMD en Windows (nexodeck-hardware/src/gpu_windows.rs)

No hay crate maduro tipo `nvml-wrapper` para AMD. Combina 3 fuentes,
verificadas en vivo contra una Radeon RX 580 real:

- **Uso %**: PDH, `\GPU Engine(*)\Utilization Percentage`, vendor-agnóstico.
- **VRAM usada**: PDH, `\GPU Adapter Memory(*)\Dedicated Usage`, sumando
  TODAS las instancias. **No uses `IDXGIAdapter3::QueryVideoMemoryInfo`
  para esto** — mide el consumo del proceso que llama, no el total del
  sistema (en este proceso, que no renderiza nada, siempre da 0).
- **VRAM total**: DXGI, `DXGI_ADAPTER_DESC.DedicatedVideoMemory` — esta sí
  es una propiedad estática del hardware, correcta de leer por proceso.
  Más confiable que `Win32_VideoController.AdapterRAM` de WMI (bug de
  overflow conocido en tarjetas con VRAM alta — WMI reportaba ~4GB en esta
  RX 580, que en realidad tiene 8GB, confirmado por DXGI).
- **Temperatura**: shim casero contra `atiadlxx.dll`/`atiadlxy.dll` (ADL),
  cargado con `libloading` en runtime, sin SDK de AMD instalado. Firmas
  verificadas contra el código fuente público de AMD
  (github.com/GPUOpen-LibrariesAndSDKs/display-library).

**Gotcha real encontrado (costó un rato depurar):** el campo `iVendorID`
que devuelve `ADL_Adapter_AdapterInfo_Get` para AMD es el **decimal literal
1002**, NO el hex `0x1002` (que vale 4098) — es una convención propia de
ADL, distinta de `DXGI_ADAPTER_DESC.VendorId` (que sí usa el hex estándar
0x1002). Comparar contra el valor equivocado hace que nunca se encuentre
el adaptador y la temperatura quede siempre en `None` sin ningún error
visible. Ver las dos constantes separadas en `gpu_windows.rs`
(`AMD_VENDOR_ID` para DXGI, `ADL_AMD_VENDOR_ID` para ADL).

**Cuál de las dos rutas corre depende de la máquina:** `gpu_snapshot()`
(`nexodeck-hardware/src/lib.rs`) usa NVML si hay una NVIDIA y solo cae a la
ruta Windows PDH/DXGI/ADL de arriba cuando NVML no inicializa. El equipo
principal cambió de una Radeon RX 580 a una RTX 5060 Ti, así que hoy la ruta
activa ahí es la de NVML (verificada con hardware real: uso 13%, 56°C, VRAM
2534/16311 MB). Consecuencia práctica: **la ruta AMD sigue siendo correcta
pero ya no se puede re-verificar en ese equipo** — si la tocás, probala en
una máquina con Radeon o dejá explícito que no se verificó.

Pendiente: AMD en Linux (`/sys/class/drm/`) e Intel en cualquier
plataforma — no hay máquina Linux ni GPU Intel dedicada para probar.

## USB / AOA (nexodeck-transport/src/usb/, Fase 5)

El transporte USB usa **AOA (Android Open Accessory), nunca ADB** — ver
[`ADR 0002`](./docs/architecture-decision-records/0002-aoa-sobre-adb.md).
Cosas que ya costaron tiempo y no conviene re-descubrir:

- **`nusb` va gateado por plataforma**
  (`[target.'cfg(not(target_os = "android"))'.dependencies]`), igual que
  `arboard`. Ponerlo en `[dependencies]` a secas arrastra la capa nativa de
  USB al `.so` de Android para nada, y ese es exactamente el tipo de cambio
  que en Fase 4 dejó el APK sin `libnexodeck_ffi.so` sin que el build fallara.
- **Los control transfers van por `Interface`, no por `Device`.** En Windows
  `Device::control_in/out` ni siquiera existe (limitación de WinUSB, está
  cfg-eado fuera en el propio crate): hay que reclamar una interfaz primero.
  Cuál da igual — el request va a EP0 con `Recipient::Device`.
- **Los strings del handshake van terminados en NUL.** `f_accessory.c` (AOSP)
  copia hasta el NUL; mandar el `&str` pelado de Rust trunca o lee de más.
- **`AccessoryIdentity::default()` es un contrato con el lado Android**, no un
  detalle cosmético: Android matchea `manufacturer`/`model` contra su
  `accessory_filter.xml`. Si los cambiás (o los hacés depender de la máquina,
  como poner el nombre del equipo), el teléfono entra en accessory mode igual
  pero **ninguna app recibe el intent** y la sesión nunca arranca, sin ningún
  error visible.
- **Que `ACCESSORY_START` devuelva error es normal**: el teléfono se
  desconecta del bus antes de completar el status stage. Quien decide si
  funcionó es la espera de re-enumeración (`18D1:2D00`/`2D01`), no ese
  `Result`.
- **La heurística de a qué dispositivo hablarle tiene que quedar
  conservadora.** El handshake reclama una interfaz, así que apuntarle al
  mouse o al teclado se los saca a su driver mientras dure el intento.
  Verificá cualquier cambio ahí contra un bus real con
  `cargo run -p nexodeck-transport --example usb_scan` (solo lectura: enumera
  y clasifica, no abre nada).
- **Los errores se anuncian una vez por dispositivo, pero el reintento sigue
  en silencio** (`ScanMemory` en `bridge.rs`). El escaneo reintenta cada 2s a
  propósito, para recuperarse solo cuando el usuario instala el driver; si
  cada intento emitiera evento, la UI mostraría el mismo cartel en loop. Ya
  pasó una vez.

- **En `accessory_filter.xml` no pongas `version`.** AAPT lo tipa como
  numero (`"1.0"` se guarda como `1`) y el filtro compilado deja de
  coincidir con el string que manda el handshake, con el mismo sintoma mudo
  de arriba. Los atributos ausentes son comodin: alcanza con
  `manufacturer` + `model`. Si tocas ese archivo, verificalo sobre el APK ya
  construido con `aapt2 dump xmltree <apk> --file res/xml/accessory_filter.xml`
  (en release los recursos se renombran, asi que hay que buscar cual de los
  `res/*.xml` contiene `usb-accessory`).
- **El fd del accessory se cede, no se comparte.** Kotlin hace
  `detachFd()` y se olvida; el dueño pasa a ser Rust, que lo cierra al
  terminar la sesion. Cerrar el `ParcelFileDescriptor` del lado Kotlin (o
  dejar que lo cierre el GC) es un doble close.

Para ver el puente real corriendo sin Flutter de por medio:
`cargo run -p nexodeck-transport --example usb_bridge_watch`.

**Estado hoy en el equipo principal (verificado con el S24 Ultra real):**
el teléfono en modo normal (`04E8:6860`) responde `DriverBlocked` en las 4
interfaces, y el driver atado es **`dg_ssudbus`** (el driver USB de Samsung,
`oem2.inf`), montado sobre el **compuesto entero**, no por interfaz. Detalle
que ahorra tiempo: la interfaz de ADB **ya tiene WinUSB** (`Service: WINUSB`,
`oem51.inf`) y aun asi `nusb` no puede usarla, porque el padre compuesto no
es `usbccgp`. O sea que no alcanza con WinUSB en *alguna* interfaz: hay que
reemplazar el driver del compuesto, que es justo lo que deja al teléfono sin
MTP ni adb en esa PC hasta revertirlo. Ese peaje es inherente al enfoque, no
un detalle de implementación, y es la razón para que el handshake pase a ser
**explícito** (solo al dispositivo ya emparejado o a pedido) en vez de
automático como es hoy.

Aparte, con una tablet Samsung en accessory mode el `DriverBlocked` tenía
otra causa: **`spacedesk`
la tiene tomada**: fue spacedesk quien le hizo el handshake AOA (usa el mismo
mecanismo para su pantalla por cable) y tiene su propio driver de kernel
atado al `18D1:2D00` (`spacedeskAndroidUsb`, `oem44.inf` de datronicsoft).
El canal de accessory es exclusivo, y **cerrar la app o parar el servicio de
usuario no alcanza** — el binding es del driver, no del proceso
(`Get-PnpDeviceProperty -InstanceId "USB\VID_18D1&PID_2D00\..."` lo muestra).
Para probar NexoDeck por cable en este equipo hay que reemplazar ese driver
por WinUSB, lo que deja a spacedesk sin USB hasta restaurarlo.

## Eventos del bridge: NUNCA con `ref.listen`, siempre stream directo

Riverpod **no vuelve a notificar cuando el valor nuevo es `==` al
anterior**, y todo lo que genera flutter_rust_bridge son value types de
freezed. Para un stream de *eventos* eso significa que dos eventos
identicos seguidos se convierten en uno solo, en silencio.

Ya mordio dos veces, las dos encontradas contra hardware real:

- Tocar dos veces el mismo boton del deck desde el celular ejecutaba la
  accion **una sola vez** (dos `ExecuteAction` identicos).
- El telefono quedaba clavado en "Reconectando..." **para siempre** tras el
  segundo rechazo de reconexion: dos `Disconnected` identicos seguidos, y
  el segundo era el unico lugar donde se limpiaba el flag que permite
  reintentar. El sintoma era mudo por partida doble (ver abajo).

Para cualquier efecto que tenga que correr **una vez por evento**, usá
`connectionEventStream(ref)` / `pairingEventStream(ref)` (suscripcion
directa) y cancelá la `StreamSubscription` en `dispose()`. `ref.listen`
sobre `connectionEventsProvider`/`pairingEventsProvider` solo sirve si lo
unico que te importa es el ultimo valor, no la secuencia.

## Fallos de conexion: que no se los trague nadie

Tres lugares donde un fallo del camino WiFi desaparecia sin dejar rastro
(los tres corregidos, no los reintroduzcas):

- `client.rs::connect_first_pairing`/`reconnect` devuelven cuando la
  conexion **quedo establecida**, no cuando termina la sesion — el loop se
  suelta al background con `spawn_session`. Antes esperaban toda la sesion,
  asi que el FFI tenia que spawnearlas y descartar el error con
  `let _ = ...`: un TCP rechazado o un fingerprint que no matchea no
  llegaban nunca a Dart. Si volves a cambiar esto, acordate de que Dart usa
  "la Future resolvio" como sinonimo de "conectado" para decidir si
  reintenta.
- `server.rs` **loguea** el rechazo de una reconexion no autorizada: ese
  camino no emite ningun evento, asi que sin el log el host parece no estar
  recibiendo nada mientras el telefono reintenta cada 4s.
- `main.dart` propaga el fallo de `startTransportHost` a
  `transportHostErrorProvider` (banner en `DevicesScreen`). El caso tipico
  es el puerto 58643 ocupado por otra instancia **o por un ejemplo de
  diagnostico corriendo**; antes el sintoma era solo que emparejar no
  funcionaba.

## Automatizacion de UI: en Android SI hay, via adb

Buena parte de la documentacion vieja dice "no hay herramienta de
automatizacion de UI en este entorno". Eso sigue siendo cierto **solo para
el escritorio**. Con el telefono enchufado por USB (solo como canal de
control; el transporte va por WiFi igual):

```sh
adb install -r app/build/app/outputs/flutter-apk/app-debug.apk
adb shell monkey -p com.nexodeck.nexodeck -c android.intent.category.LAUNCHER 1
adb exec-out screencap -p > captura.png     # y leerla
adb shell input tap <x> <y>                 # coordenadas de la imagen real
adb logcat -d --pid=$(adb shell pidof com.nexodeck.nexodeck)
```

Para inspeccionar la base del telefono (con un APK **debug**, `run-as` no
funciona en release):

```sh
adb exec-out "run-as com.nexodeck.nexodeck cat /data/user/0/com.nexodeck.nexodeck/app_flutter/nexodeck.sqlite" > phone.sqlite
dart run tool/dump_devices.dart phone.sqlite   # desde app/
```

Del lado PC, `cargo run -p nexodeck-transport --example wifi_host_watch --
[--pair] [device_id...]` levanta el host sin Flutter (con `--pair` arma y
acepta el pairing solo), que es lo que permite correr el E2E completo sin
clics en el escritorio. Ojo: mientras corra, **ocupa el puerto 58643** y la
app de escritorio no va a poder levantar su host.

## Sistema de diseno: los tokens mandan

Cuatro archivos en `app/lib/core/theme/`, y **ninguno de esos valores se
escribe a mano en un widget**:

- `app_spacing.dart` — `AppSpacing` (xxs 2 / xs 4 / sm 8 / md 12 / gutter 16
  / lg 20 / xl 32), `AppRadius` (badge 6 / chip 12 / card 20) y `AppSizes`
  (layout responsive).
- `app_motion.dart` — `AppDuration` y `AppCurves`, con nombres **semanticos**
  (`press`, `hover`, `selection`, `state`, `collapse`, `entry`, `chart`...).
  Antes los mismos siete numeros estaban repetidos a mano en 12 archivos y
  dos animaciones que debian sentirse iguales se desincronizaban apenas
  alguien tocaba una.
- `app_surface.dart` — borde, sombra y relleno por estado. `hairline()` (1 px
  a alpha 0.55) es lo que hace que las tarjetas se despeguen del fondo en
  modo claro; `lift()` usa **`spreadRadius: -4`**, que es lo que evita el
  halo gris de las sombras Material clasicas.
- `app_text.dart` — `AppText.numeric()` (cifras tabulares) para **todo numero
  que se actualice solo**. Sin esto el valor de una metrica cambia de ancho
  al pasar de `9%` a `10%` y "baila" una vez por segundo.

**Los valores de `AppSpacing.sm/md/lg`, `AppRadius.card/chip` y las
constantes de `AppSizes` estan congelados**: gobiernan la calibracion del
riel de metricas contra un telefono real. Agregar tokens nuevos es libre;
cambiar los que hay se verifica si o si con una captura del S24 (y ojo:
`metrics_panel_test.dart` deriva su expectativa **de las propias
constantes**, asi que un cambio de valor pasa en verde igual).

### Superficies interactivas: `InteractiveCard`, nunca `Card`

`core/widgets/interactive_card.dart` es la unica fuente de verdad del borde
de una superficie clickeable: hover (borde tenido con el color del
elemento + `lift` + un escalon tonal), foco de teclado con anillo y
`Enter`/`Espacio` para activar, y presionado. **No la envuelvas en un
`Card`**: el `cardTheme` global ya dibuja un hairline y quedarian dos bordes
superpuestos. En touch el hover es inerte, asi que la comparten escritorio y
Android sin costo.

## Fuera de la LAN: dirección manual, no reenvío de puerto

Emparejar y reconectar con la PC **sin mDNS**, escribiendo su dirección a
mano. Es lo que permite usar el deck con datos móviles, con una VPN mesh
(Tailscale) poniendo a las dos puntas en la misma red virtual. La
investigación completa, con las tres alternativas y por qué se eligió esta,
está en [`docs/ideas/conexion-fuera-de-la-lan.md`](./docs/ideas/conexion-fuera-de-la-lan.md).

**El reenvío de puerto no es una alternativa en esta conexión, y está
medido:** el salto siguiente al router del equipo principal es `192.0.2.1`,
o sea que el router **no tiene la IP pública** — Claro hace CGNAT. Reenviar el
58643 expondría una WAN privada que internet no puede alcanzar. No es un
problema de acceso al router; la puerta está un piso más arriba.

Lo que hay del lado de la app:

- **El motor no cambió.** `connect_first_pairing(host, port)` ya aceptaba
  cualquier IP y el pinning funciona igual venga de donde venga: lo único
  atado a la red local era el *descubrimiento*.
- **`parseManualHost`** (`features/pairing/domain/manual_host.dart`) es la
  única definición de qué dirección es válida — la usan el diálogo (para el
  error inline) y quien guarda en Drift. Acepta IP, nombre MagicDNS y puerto
  opcional. Contempla **IPv6**, que Tailscale reparte además de las `100.x`:
  partir por el último `:` rompería `fd7a:115c::1`, así que la sin corchetes
  se trata como dirección entera y sólo la `[...]:puerto` lleva puerto.
- **`resolveReconnectTarget`** (`domain/reconnect_target.dart`, pura y
  testeada) decide a dónde reconectar: **mDNS primero, manual después**. El
  orden no es arbitrario — dentro de la LAN la IP la reparte el DHCP y cambia,
  así que mDNS es la fuente correcta; la manual es el plan B.
- **La manual espera una gracia de 6 s** antes de entrar. Un TCP contra una IP
  que ya no existe no falla rápido: cuelga hasta el timeout y mientras tanto
  bloquea el reintento que sí habría funcionado. **Sin WiFi la gracia se
  saltea**: mDNS es multicast de red local, esperarlo con datos móviles sólo
  retrasa la única vía que puede andar.
- **La dirección manual es sticky.** No se pisa con la de cada conexión
  exitosa: la IP de la LAN cambia, y la que el usuario escribió es justamente
  la que no. Sobrescribirla al volver a casa dejaría el camino de datos
  móviles roto sin ningún aviso.
- **El acceso está donde falla, no en un menú**: el botón "Conectar por IP"
  vive en la banda de "Reconectando...", y en la lista de descubrimiento
  acompaña a **todos** sus estados —buscando, sin resultados y con
  resultados—. Si viviera sólo en "no encontré ninguna PC", quien está con
  datos móviles tendría que esperar los 8 s del cartel para enterarse de que
  la opción existe.

**Lo que NO resuelve esto:** las notificaciones con la app cerrada. Ningún
túnel las arregla —van por FCM— y Android corta el WebSocket en segundo plano
(Doze), lo que pide un foreground service. Las dos cosas siguen pendientes y
son proyectos aparte.

### El relay no puede quedarse con un peer muerto en silencio

`nexodeck-relay` empalma dos conexiones ENTRANTES por token y después solo
copia bytes; nunca termina el TLS ni abre conexiones salientes. Eso lo hace
seguro y simple, pero deja un agujero que costó una tarde entera (2026-09-24):
**el relay no se enteraba de que un peer había muerto en silencio.**

Cuando el teléfono pasa de WiFi a datos móviles, su socket al relay deja de
existir sin FIN ni RST. El kernel del relay no lo sabe, sigue escribiéndole el
tráfico de la PC (un snapshot por segundo), el buffer de envío crece sin freno
y `copy_bidirectional` no termina NUNCA. La PC queda encerrada en esa sesión,
**no vuelve a aparcarse**, y el relay pasa a no tener host: todo intento nuevo
del teléfono recibe `ERR_NO_HOST` ("la PC no está conectada al túnel") hasta
reiniciar el relay. Visto en vivo: dos sockets desde la IP de la PC, uno con
decenas de KB de backlog, y el teléfono sin poder entrar.

Tres cosas lo arreglan, y las tres importan:

- **`configure_dead_peer_detection` (socket2) es la que de verdad lo
  resuelve.** Pone `TCP_USER_TIMEOUT` (20 s) y keepalive en cada socket
  aceptado: con datos en vuelo, el kernel corta el socket en vez de reintentar
  ~15 min (`tcp_retries2`); ocioso, lo corta el keepalive. Comprobado con un
  `DROP` de iptables sobre la 5-tupla del teléfono (muerte SIN RST): el relay
  cierra el socket muerto a los ~15 s y la PC re-aparca sola.
- **`Parked { id }` + `remove_if_mine`.** Antes `park_host` borraba el token del
  mapa incondicionalmente al terminar; el cierre de un park viejo podía borrar
  el de una reconexión nueva con el mismo token y dejar a la PC aparcada pero
  invisible. Ahora solo borra si el park sigue siendo el suyo.
- **`wait_for_client` también LEE el socket del host.** Un host que cierra a
  medias (FIN) sigue leyendo, así que la escritura del keepalive no falla: sin
  leer, su token quedaba tomado para siempre. Ahora el EOF se ve al leer.

**`socket2` rompe la regla de "solo tokio", y es a propósito:** tokio no expone
`TCP_USER_TIMEOUT` ni el keepalive, y sin ellos el relay queda colgado ante una
muerte silenciosa. Es la dependencia mínima que cierra ese agujero.

**Desplegar el relay en el VPS** (`ssh vps-relay`, `203.0.113.10`). El
VPS no tiene Rust; se compila en un contenedor Docker (`rust:1.90`) con un
workspace mínimo que solo contiene el crate. El binario va a
`/opt/nexodeck-relay/nexodeck-relay`, lo levanta una unidad systemd
(`--port 58644 --allow-token <hex64> --max-connections 8`). Para reemplazarlo
**hay que parar el servicio primero** (`systemctl stop nexodeck-relay`):
mientras corre, el fichero está en uso y `cp` falla con "Text file busy".
Respaldo del anterior (`.bak-<fecha>`), copia, `systemctl start` y comprobar que
la PC re-aparca (`ss -tnp | grep 58644`).

## Pairing: es un ritual de DOS pantallas

El PIN existe para que un humano compare dos pantallas. Por eso el widget que
lo dibuja es **uno solo y compartido**
(`features/pairing/presentation/widgets/pin_display.dart`): agrupacion
(`004 821`), cifras tabulares, tracking, pozo tonal y semantica viven ahi, y
las dos puntas lo importan. Si algun dia se dibuja el PIN en un tercer lugar,
usa ese widget: que las cajas midan distinto es exactamente lo que hace
dificil comparar.

Detalles que no son obvios:

- **El PIN necesita tracking POSITIVO.** `AppText.pin()` lo fija explicito
  porque los estilos grandes del tema llevan tracking negativo (`_tighten`),
  y `copyWith(letterSpacing: null)` **no borra** el heredado, lo conserva.
  Hay un test que falla si alguien lo reintroduce
  (`test/pairing_pin_test.dart`).
- **El PIN puede tener ceros a la izquierda** (`format!("{:06}")` en Rust), asi
  que nunca lo pases por `int`.
- **No existe "cancelar" en el protocolo.** El rol cliente solo expone
  `sendPairConfirm()`. El boton Cancelar del telefono es **abandono de UI**: la
  sesion del lado Rust sigue viva hasta el `PAIRING_STEP_TIMEOUT` de 120 s del
  host. Por eso el descarte de un `HostPinReceived` tardio se hace **por fase**
  y no comparando nombres.
- **El nombre de mDNS y el nombre real son strings distintos.**
  `DiscoveredHost.name` es el *fullname* (`MI-PC._nexodeck._tcp.local.`, y
  ademas sanitizado: todo lo no alfanumerico pasa a `-`), mientras que
  `PairPin.hostName` trae el nombre de verdad. Usa `hostDisplayName()`
  (`features/pairing/domain/host_name.dart`) para mostrar el primero, y
  cambia al segundo apenas llega el PIN.
- **Cerrar la hoja de la PC con una solicitud pendiente tiene que responder.**
  `HostPinCard._close()` manda `confirmPairing(false)` antes de popear: sin
  eso el telefono se queda esperando los 120 s completos sin ninguna
  respuesta. Por lo mismo la hoja es `isDismissible: false` + `enableDrag:
  false` — se cierra solo por el boton.
- **`discoveredHostsProvider` nunca emite lista vacia**: hace `await for` y
  solo emite despues del primer host. "No hay ninguna PC" no se puede deducir
  del provider; lo decide un `Timer` propio en `DiscoveredHostsList`
  (`PairingTimings.discoverySearchHint`).

## Ventana de escritorio: validar la posicion guardada

`window_layouts` persiste posicion/tamano por modo, y **restaurarla sin
comprobar que ese monitor siga existiendo deja la app invisible**: arranca
entera fuera del area visible, sin ningun error y sin forma de traerla al
frente. Paso de verdad, con una fila en `pos_x: 2033` de un monitor que se
habia desconectado.

`isWindowRectUsable()` (en `window_mode_controller.dart`) exige un solape
minimo real (160x80 px) contra alguna pantalla conectada **ahora**. Se llama
en los dos lugares que restauran posicion: `main()` y
`WindowModeController.switchTo`. Si agregas un tercero, llamala tambien.

## Capturar la ventana de escritorio

No hay automatizacion de UI de escritorio, pero si se puede ver y tocar la
app por Win32 (los scripts viven en el scratchpad de la sesion, no en el
repo). Tres cosas que no funcionan y conviene no volver a intentar:

- `PrintWindow`, aun con `PW_RENDERFULLCONTENT`: devuelve el marco y el area
  de cliente **en blanco** (Flutter renderiza en su propio swapchain).
- `SetForegroundWindow` solo: Windows bloquea el robo de foco desde otro
  proceso. Hay que subir la ventana con `SetWindowPos` + `HWND_TOPMOST`, o
  usar `AttachThreadInput`.
- `flutter screenshot`: en Flutter 3.41 solo ofrece `device` (no soportado en
  Windows desktop) y `skia` (emite un `.skp`, no una imagen).

Lo que si anda: `SetWindowPos` a topmost + `CopyFromScreen` **del rect de la
ventana**. Nunca de la pantalla completa: se lleva puesto lo que el usuario
tenga abierto.

## UI: pantalla unica (dashboard + deck combinados)

Ya no hay pestañas separadas Dashboard/Acciones -- `main.dart::_HomeShell`
compone todo en una sola pantalla: `MetricsRow` (fila de metricas, 20% del
alto del `body`, medido con `LayoutBuilder` para no contar el AppBar) +
`ActionsDeckGrid` (80% restante). `DashboardScreen`/`ActionsScreen` (los
Scaffolds standalone viejos) se eliminaron. Si necesitas la grilla de
acciones o las metricas en otro lugar, usa `ActionsDeckGrid`/`MetricsRow`
directamente -- ambos ya no tienen `Scaffold`/`AppBar` propios.

Los charts (`fl_chart`) viven en `features/dashboard/presentation/widgets/`
(`mini_line_chart.dart`, `mini_pie_chart.dart`, `mini_bar_chart.dart`).
CPU y Red usan line chart con un historial corto mantenido **en memoria**
dentro de `MetricsRow`. Eso es solo el vistazo de los ultimos segundos: el
historial **persistido** es otra cosa y vive aparte (ver abajo). RAM/GPU usan
donut, Disco usa una barra con `backDrawRodData` (fondo + relleno, no dos
rods separados -- `groupVertically` en `BarChartGroupData` apila valores,
no superpone un track de fondo). Los tres derivan sus radios/anchos del box
que reciben (`LayoutBuilder`): con valores fijos el donut se recortaba en
las tiles chicas del riel de movil.

### Las metricas son UN solo pipeline, compartido PC/Android

No dupliques la construccion de las metricas. Hay exactamente una
definicion de las 5 (CPU/RAM/Disco/GPU/Red) en
`widgets/metric_specs.dart::buildMetricSpecs()`, que devuelve `MetricSpec`s
sobre el **snapshot de dominio** (`features/dashboard/domain/`). El rol
Android convierte el `bridge.HardwareSnapshot` que llega por red con
`HardwareSnapshot.fromBridge` apenas lo recibe, justamente para entrar al
mismo pipeline. Antes habia dos copias (una en `metrics_row.dart` y otra en
`connected_device_screen.dart`) sobre dos tipos distintos, y el telefono
terminaba mostrando menos datos que la PC.

`widgets/metrics_panel.dart` es el unico que decide layout, y lo hace
**midiendo espacio, no preguntando la plataforma**:

- `MetricsPanelAxis.horizontal` = franja; las columnas salen de
  `metricColumnsFor()` (funcion pura, testeada directo) contra
  `AppSizes.minMetricTileWidth`.
- `MetricsPanelAxis.vertical` = riel lateral izquierdo; es el modo de
  movil/tablet en horizontal, donde el recurso escaso es el alto. Si las 5
  tiles no entran a un alto legible el riel **scrollea** en vez de bajar de
  densidad — perder los badges (MHz/°C/VRAM) es peor que scrollear.
- La densidad (`MetricDensity.full/compact/micro` en `metric_tile.dart`) la
  manda el alto por tile, no la orientacion. `compact` pone **titulo y
  valor en la misma linea**: esos ~14 dp por tile son exactamente lo que
  hace que las 5 entren en el riel de un telefono apaisado (~309 dp utiles
  bajo el AppBar) sin scrollear. Verificado en un S24 Ultra real.
- Los badges van en **una sola linea** dentro de un `FittedBox(scaleDown)`,
  no en un `Wrap`. Con `Wrap`, en el telefono los dos badges de la GPU
  (`53°C` + `2.8 GB/15.9 GB`) pasaban a dos lineas, no entraban en el alto
  de la tile y el segundo quedaba cortado por la mitad.
- El valor **no** usa `AnimatedSwitcher`: cambia una vez por segundo y el
  crossfade de 300 ms superponia el numero viejo con el nuevo, asi que casi
  un tercio del tiempo se veia doble. Se ve clarisimo en una captura.

Lo unico que elige el eje es `ConnectedDeviceScreen`, con
`MediaQuery.orientationOf`. Desktop siempre usa franja.

Los numeros que gobiernan todo esto viven juntos en
`core/theme/app_spacing.dart::AppSizes` — son los que hay que tocar para
recalibrar como se reparte la pantalla, no constantes sueltas en los
widgets.

El plegado de las metricas (chevron sutil al borde derecho del panel, en
los tres ejes) se persiste en `app_settings` con la clave
`metrics_collapsed`, via `metrics_visibility_controller.dart` — mismo
patron que `theme_mode_controller.dart`, sin migracion de Drift porque
`app_settings` es clave/valor.

### Dos graficos que no son genericos: los discos y los modulos de RAM

Tres de las cinco metricas usan los charts genericos (linea, donut, barra). Las
otras dos dibujan **la cosa que miden**, y eso las hace legibles de un vistazo
sin leer un numero:

- **Almacenamiento** (`disk_usage_list.dart`): una fila por disco, con su letra
  de unidad, la etiqueta del volumen, una barra propia y `usado/total`. El
  agregado ("2.1 TB de 2.3 TB") solo podia decir cuanto queda **entre todos**,
  que no sirve para saber cual se esta llenando. Un disco por encima del 90% se
  pinta en el color de error.
- **RAM** (`ram_module_chart.dart`): dos modulos DIMM que se llenan **en
  orden**, con el porcentaje de cada uno en su centro. Con la RAM al 74% el
  primero dice 100% y el segundo 48%; el reparto vive en `ramModuleFill()`,
  pura y testeada.

Cosas que no son obvias:

- **La lista de discos se adapta al ancho, no al modo.** Con lugar (la franja,
  el panel maximizado) cada disco entra en una linea; en el riel, donde hay
  ~190 dp, la etiqueta y las cifras van arriba y la barra debajo. Meter las
  tres cosas en una linea a ese ancho dejaba la barra en un hilo y la etiqueta
  sin lugar.
- **El riel tambien expande la tile de disco** (`expanded: density == full`).
  Antes solo lo hacia la franja horizontal, asi que en los layouts de riel
  --que son la mitad de los que hay-- la metrica de Disco se quedaba en el
  agregado.
- **El titulo largo solo se usa si entra** (`AppSizes.expandedTitleMinWidth`):
  en el riel, "Almacenamiento" competia con el valor y los badges y terminaba
  cortado en "Almacenami…", que informa menos que "Disco".
- **El porcentaje de cada modulo de RAM se dibuja DOS veces**, recortado a la
  parte llena y a la vacia, con un color para cada una. Un solo color siempre
  se pierde contra uno de los dos fondos, y este texto cae justo sobre la
  frontera.
- **`MetricSpec.stackedChart` es un pedido, no una garantia.** La RAM pone el
  grafico a lo ancho debajo del titulo, pero solo en densidad completa: en
  `compact` el alto por tile son 48 dp, no entran tres filas, y vuelve al
  reparto lateral como el resto.
- Los dos graficos animan el **valor**, no el widget (`TweenAnimationBuilder`),
  asi el llenado se desliza en vez de saltar una vez por segundo.

### Los graficos dibujan la pieza que miden

Cuatro de las cinco metricas ya no usan un chart generico: dibujan el
componente y meten el dato adentro. Es lo que hace que la tile se reconozca de
un vistazo, sin leer el titulo.

- **CPU** (`cpu_chip_chart.dart`): el encapsulado con sus pines y la muesca del
  pin 1, con el sparkline de siempre adentro. El borde se enciende con la carga.
- **RAM** (`ram_module_chart.dart`): dos modulos DIMM que se llenan **en orden**
  --primero uno, despues el otro-- con el porcentaje de cada uno en su centro.
  El reparto vive en `ramModuleFill()`, pura y testeada.
- **GPU** (`gpu_card_chart.dart`): la placa con su conector PCIe y **dos
  ventiladores que giran mas rapido cuanto mas trabaja**. La VRAM va aparte, en
  una `CapacityBar` con la cifra adentro.
- **Almacenamiento** (`disk_usage_list.dart`): una fila por disco, con letra,
  etiqueta del volumen y barra propia.

Reglas que se repiten en los cuatro y conviene respetar:

- **El texto que cae sobre un relleno parcial se dibuja en dos colores**,
  partidos exactamente donde termina el relleno (`ShaderMask` con los dos
  `stops` juntos, o dos pasadas con `clipRect`). Un solo color siempre se pierde
  contra uno de los dos fondos, y estas cifras caen justo sobre la frontera.
- **Se anima el VALOR, no el widget** (`TweenAnimationBuilder`): el dato llega
  una vez por segundo y sin eso el relleno salta.
- **Nada de reconstruir el hijo en cada frame**: el contenido que va dentro del
  marco se pasa como `child` del `AnimatedBuilder`.

**El layout apilado pide dos cosas, y las dos se miden**
(`MetricSpec.stackedChart`): densidad completa **y**
`AppSizes.minStackedTileHeight`. No alcanza con la densidad: la franja de un
telefono da tiles de ~100 dp que son `full` pero no entran en cuatro filas, y
ahi la tile de GPU **desbordaba 7 dp con banda amarilla**. Verificado en un S24
real; hay dos tests que lo fijan.

**Los nombres de las piezas** (`components.rs` -> `hostComponentsProvider`) se
leen **una sola vez**: no cambian, y WMI y NVML son caros. Van de subtitulo,
chicos y atenuados, y **nunca desplazan al valor** -- ni cuando no hay alto: por
debajo de `AppSizes.minFullMetricTileWithSubtitleHeight` (96) el subtitulo se
**omite**. La franja de un telefono vertical mide justo `minFullMetricTileHeight`
(86), asi que ahi no aparece; en escritorio, con el reparto por defecto (>=96),
si. Sin ese corte, el subtitulo empujaba la fila de valores fuera de la tile de
RAM y de Red y Flutter dibujaba la banda de overflow (verificado en un S24
real). El reloj de GPU es la
excepcion: cambia con la carga, asi que viaja en el snapshot y va de badge.

En la RAM se prioriza **marca y velocidad**: los numeros de parte reales
(`CM4X16GD3600C18K2D`) se comian la linea y dejaban la velocidad en cortada.

### mDNS: la PC anuncia VARIAS IPs y solo una sirve

`discovery.rs` no puede quedarse con la primera IPv4 del anuncio.
`get_addresses()` es un `HashSet` sin orden, y el equipo principal publica
**seis** direcciones: la de la LAN, la del switch virtual de Hyper-V (172.29.x)
y cuatro APIPA (169.254.x) de adaptadores sin red. Quedarse con cualquiera hacia
que el telefono conectara **a veces si y a veces no**, segun el arranque; contra
la de Hyper-V se quedaba en "Reconectando..." para siempre, sin ningun error.

Hoy se descarta lo que nunca puede servir (loopback y link-local), se ordena por
probabilidad (192.168.x y 10.x antes que el resto) y sobre todo **se prueba el
puerto**: gana la primera que acepte un TCP. Una heuristica de rangos sola no
alcanza -- la IP de Hyper-V es una privada perfectamente legitima.

### La tile de almacenamiento pide ancho doble (y a veces no se lo dan)

La metrica de Disco es la unica que declara `MetricSpec.widthUnits = 2`, y solo
cuando hay **mas de un disco**: con uno solo la lista repetiria letra por letra
lo que ya dice el agregado. Cuando consigue ese ancho, la tile cambia de cuerpo
(`MetricSpec.expandedBuilder`) y dibuja `DiskUsageList` — una fila por disco,
con identificador, barra y `usado/total`— en vez del chart.

- **El pedido es un pedido, no una garantia.** `metricStripLayoutFor()` (pura y
  testeada, como `metricColumnsFor()`) lo concede solo si se cumplen las dos
  condiciones: que las unidades entren **todas en una sola fila** — las tiles se
  acomodan con un `Wrap`, y una tile doble que no entra deja un hueco y
  desalinea la siguiente, ademas de agregar una fila que el alto calculado no
  contemplaba— y que sobre alto para `MetricDensity.full`, que es el que
  necesita la lista. Si no, se vuelve al reparto parejo y la tile muestra el
  agregado de siempre. Por eso en un telefono vertical la lista no aparece.
- **El cuerpo expandido reemplaza al chart, no lo acompana**: la lista ya *es*
  el grafico, y dejar los dos partiria el ancho justo cuando se lo dio para
  mostrar mas detalle.
- **La lista scrollea en vez de comprimirse** (mismo criterio que el riel en un
  telefono bajo): con cuatro o cinco discos, achicar las filas dejaria ilegibles
  la barra y la cifra, que es lo unico que la lista venia a mostrar.
- **`formatMbPair()` es distinto de `formatMb()` a proposito**: escribe la
  unidad una sola vez, la fija el **total** (para que las dos cifras sean
  comparables aunque el usado caiga un escalon mas abajo) y en GB no lleva
  decimales — son dos numeros compitiendo por una fila de 20 dp.
- Un disco por encima del 90% se pinta en el color de error. Un disco lleno es
  justo lo que hay que ver de un vistazo y con el color del resto se pierde
  entre las demas barras.

### Tercer eje: `MetricsPanelAxis.microStrip` (ventana compacta)

Ademas de la franja y el riel hay una franja **micro**: una fila de tiles
siempre en `MetricDensity.micro` (chart chico + valor, sin titulo ni badges),
que es lo que dibuja el modo compacto. Ahi el ancho util son ~300 dp: la franja
normal cae a 2 columnas x 3 filas y se come media ventana, y el riel se lleva un
tercio del ancho. A diferencia de los otros dos modos, la densidad **no** se
decide midiendo — este layout *es* la decision de mostrar lo minimo—, y el alto
es fijo (`AppSizes.microMetricStripHeight`) y no proporcional: un 20% de los
~460 dp de la ventana compacta seria mas alto que dos filas de acciones.
`microMetricRowsFor()` decide si las 5 entran en una fila o pasan a dos, y es
pura y testeada por el mismo motivo que las otras dos.

El valor de la tile micro va dentro de un `FittedBox(scaleDown)`: a ~52 dp de
ancho, `1747.1 GB` o `↓19.5 KB/s` no entran, y cortarlos con puntos suspensivos
dejaria el numero sin las unidades, que es justo la parte que hay que leer.

### Cinco layouts de la pantalla principal: `features/home/`

El boton de la barra (`HomeLayoutButton`) rota entre cinco repartos,
persistidos en `app_settings` con la clave `home_layout` —mismo patron que
`theme_mode_controller.dart`, sin migracion de Drift— y leidos en `main()`
antes de `runApp` con `overrideWith`.

**El de por defecto es el centro de control** (ver
[`docs/ideas/centro-de-control.md`](./docs/ideas/centro-de-control.md)):
metricas a la izquierda, el **chat del asistente** al centro y la grilla de
acciones compacta a la derecha. **No sale del par eje + espejo** como los otros
cuatro: es una composicion propia (`_ControlCenterLayout`) con DOS paneles
laterales, cada uno con su divisor y su plegado. Su centro es `AiAssistantPanel`
(el MISMO widget del dialogo del asistente, con `embedded: true`) y el panel
derecho es `ActionsPanel` (icono + etiqueta, 1-2 columnas).

**Los otros cuatro NO son cuatro pantallas.** Salen de combinar dos cosas que el
panel de metricas ya sabia hacer por separado: el eje (`MetricsPanelAxis`,
que el telefono ya elegia por orientacion) y el borde al que queda anclado
(`MetricsPanel.mirrored`, agregado con esto). `HomeLayoutView` solo elige la
combinacion; no hay ningun widget de metricas nuevo.

| Layout | Eje | `mirrored` |
|---|---|---|
| `controlCenter` (por defecto) | `vertical` + 2 paneles | — |
| `metricsTop` | `horizontal` | no |
| `metricsLeft` | `vertical` | no |
| `metricsRight` | `vertical` | si |
| `deckFocus` | `microStrip` | si (franja abajo) |

Cosas que no son obvias:

- **`mirrored` es un bool y no un `enum Side`** porque cada eje solo tiene dos
  posiciones posibles. Lo unico que cambia es de que lado queda el chevron y
  hacia donde apunta: **siempre hacia adentro de la pantalla**, o sea hacia el
  deck. Un chevron contra el borde de la ventana quedaria lejos de la frontera
  que separa.
- **`MetricsRow` lleva una `GlobalKey`** (`_metricsKey` en
  `home_layout_view.dart`). Sin ella, mover el widget de una `Column` a un
  `Row` lo reconstruye desde cero —cambia de padre y de posicion— y el
  historial en memoria de los sparklines de CPU y Red se pierde: las dos
  metricas quedan diciendo "Recolectando..." unos 30 segundos **cada vez que
  se cambia de layout**. Se vio en una captura de la app real antes de
  agregarla. El deck no la necesita: es un `ConsumerWidget` y su estado (el
  grupo elegido) vive en providers.
- **La tile micro pasa a fila cuando le sobra ancho**
  (`AppSizes.microMetricRowMinWidth`). La franja micro nacio para la ventana
  compacta, con ~52 dp por tile; en `deckFocus` cada tile se lleva ~250 dp y
  apilar grafico sobre valor dejaba el donut de RAM/GPU aplastado contra el
  alto de la franja, con su porcentaje interior ilegible.
- **El icono del boton es el del layout ACTUAL**, no el del siguiente: el
  boton es antes que nada un indicador de donde estas. `metricsLeft` y
  `metricsRight` comparten `IconData` y se distinguen por `flipIcon` —sin
  ese volteo el boton se veria identico en los dos y el clic pareceria no
  hacer nada.
- Un valor guardado que ya no exista (bajar de version, renombrar el enum)
  cae al **centro de control** en vez de reventar el arranque
  (`HomeLayout.fromName`).

### Los divisores se arrastran: `PanelSlot` y `ResizeHandle`

Todas las fronteras de la pantalla principal --metricas/contenido y, en el
centro de control, contenido/panel de acciones-- se pueden mover con el mouse.
La regla vive en
`features/home/domain/panel_split.dart` (`PanelSlot`, pura y testeada) y el
widget en `core/widgets/resize_handle.dart`.

**Se guarda la FRACCION del espacio, no un tamano en px.** Con px, achicar la
ventana dejaba al panel comiendose casi todo --o al deck sin nada-- hasta que
el usuario lo volviera a arrastrar. Con fraccion, el reparto que eligio se
mantiene al cambiar de tamano de ventana o de monitor, que es lo que uno
espera de un divisor.

- **Cada slot tiene DOS pares de topes y no es redundante.** `preferredFactor`
  + `preferredMin/Max` son el reparto que se calcula solo, y son exactamente
  los numeros que habia antes de que esto existiera: quien nunca toca un
  divisor no nota que existen. `min`/`max` son los topes del arrastre, mas
  anchos a proposito. Usar los del arrastre tambien para el automatico habria
  cambiado en silencio el aspecto por defecto de la app --el riel habria
  pasado de 220 a 320 px de entrada-- y eso no es lo que se pidio.
- **El techo real no es `max`, es lo que le queda al deck.**
  `extentFor` devuelve `null` cuando al otro lado le quedaria menos de
  `minRemaining` incluso con el panel en su minimo. Que hacer con ese `null`
  lo decide cada llamador, y no coinciden: el panel de procesos no se dibuja
  y el de ejecuciones se maximiza.
- **Se clampea en px y recien despues se pasa a fraccion.** Al reves, una
  fraccion valida puede caer fuera de los topes en px y el panel se va un
  instante mas alla del tope antes de volver.
- **Durante el arrastre NO se escribe en la base.** `drag()` solo mueve el
  estado; `commit()` corre al soltar. Persistir por frame serian decenas de
  escrituras por segundo, y ademas dejaria guardado cualquier punto intermedio
  si la app se cierra a mitad del gesto.
- **El area de agarre son 8 px, la linea sigue siendo 1.** Un divisor de 1 px
  es imposible de agarrar: hay que acertarle al pixel. Lo que cambia al
  activarse es el **color** de la linea, no su grosor -- engordarla moveria el
  contenido de los dos paneles justo cuando el usuario esta apuntando.
- **Doble clic vuelve al reparto automatico**, y las flechas lo mueven con el
  teclado. Sin la primera, un arrastre desafortunado solo se deshace volviendo
  a acertarle al pixel; sin lo segundo, el mouse seria la unica via.
- **Plegado no hay divisor arrastrable**: la barrita del chevron mide lo que
  mide, y una manija ahi prometeria algo que no puede cumplir.
- **El riel dejo de calcular su propio ancho** cuando el padre se lo impone
  (`MetricsPanel.railWidth`). El calculo automatico sale de `MediaQuery` --que
  da el ancho de la ventana entera, no el trozo del riel-- y por eso no podia
  respetar un arrastre. En el telefono sigue en `null` y nada cambia: en touch
  no hay hover, asi que un divisor arrastrable no se podria ni descubrir, y
  `ConnectedDeviceScreen` no usa ninguno.
- `processPanelWidthFor` y `runPanelWidthFor` **se eliminaron**, y los slots
  `PanelSlot.processPanel`/`runPanel` tambien cuando esos paneles pasaron a ser
  **dialogo** (F4): sus reglas viven ahora en `PanelSlot.metricsRail` y
  `PanelSlot.actionsPanel`. Dejar la misma decision escrita en dos lugares es
  justo lo que se desincroniza.

### Panel de procesos: quien esta consumiendo cada metrica

Tocar la tile de CPU, RAM o GPU abre al lado del deck la lista de aplicaciones
que mas usan ese recurso, con su consumo, hace cuanto corren y un boton para
cerrarlas. Rust en `nexodeck-hardware/src/processes/`, UI en
`features/processes/`.

**El colector NO vive en `HardwareMonitor`.** `snapshot()` es la ruta caliente
de 1 s que comparten el stream del FFI y el del servidor (o sea, tambien lo que
ve el telefono); meterle un recorrido de ~370 procesos degradaria las dos por un
dato que el telefono ni siquiera recibe. El colector tiene su propio `System`,
cadencia de 2 s y vive **solo mientras el panel esta abierto**: con el panel
cerrado esto cuesta exactamente cero. Medido en el equipo principal: **~20 ms
por muestra**, 370 procesos, incluida la lectura de GPU.

**Nunca llama `refresh_cpu_*`.** Ver la seccion de arriba sobre por que en
Windows dos refrescos de CPU seguidos dejan el uso clavado en 100. Para
normalizar por nucleos usa `available_parallelism()`, que no consulta a sysinfo.

Decisiones que no son obvias:

- **Un solo stream con las tres listas, no uno por metrica.** El uso de CPU por
  proceso es un delta contra la muestra anterior: re-suscribirse en cada clic
  daria una primera lectura en cero y la lista se vaciaria cada vez que el
  usuario cambia de tile. Calcular las tres cuesta casi lo mismo que una --lo
  caro es el unico `refresh_processes_specifics`--, asi que cambiar de metrica
  es gratis: Dart elige otra lista de la ultima muestra.
- **Se agrupa por nombre de ejecutable**, como la pestana "Procesos" del
  Administrador de tareas. Chrome son 32 procesos y una lista por pid serian 32
  filas identicas. El tiempo que se muestra es el del **mas viejo** del grupo,
  que es el padre: los hijos arrancan despues y darian un numero que no
  significa nada.
- **`run_time == 0` es DESCONOCIDO, no recien arrancado.** Windows no deja leer
  el tiempo de arranque de los procesos del sistema: `start_time()` da 0 y la
  resta devuelve el epoch entero. Se vio en la app real, con `dwm.exe`
  informando **20691 dias** (o sea, desde 1970). Hoy se detecta y la UI dibuja
  `—`.
- **CPU y GPU descartan a los que no llegan a 0.05%**, la memoria no. Con la
  maquina tranquila la lista de CPU se llenaba de filas diciendo "0.0%"
  ordenadas alfabeticamente, y habia que buscar entre ellas los tres procesos
  que consumian algo. En memoria un umbral solo esconderia informacion real.
- **La GPU por proceso sale de PDH y el agregado de la tile sale de NVML.** No
  van a coincidir exactamente, igual que no coinciden en el Administrador de
  tareas. Es inherente a tener dos fuentes; no se "arregla".
- **`Process::memory()` es el working set**, que no es lo que muestra la pestana
  "Procesos". Para comparar, usar **Detalles → Conjunto de trabajo (memoria)**,
  o los numeros van a parecer inflados y se pierde tiempo buscando un bug que no
  existe.

Cerrar procesos, que es la parte irreversible:

- **Se cierra por pid Y nombre.** Windows reutiliza los pids rapido y los de la
  lista son de hasta 2 s atras: actuar solo por pid puede matar un programa que
  el usuario nunca vio. Por lo mismo **no** se buscan procesos nuevos con ese
  nombre — solo se cierra lo que estaba en pantalla.
- **Hay una lista de procesos criticos** (`csrss.exe`, `lsass.exe`,
  `svchost.exe`...) que se rechaza con un mensaje explicando por que. Verificado
  en vivo: `--kill csrss.exe` no toca nada.
- **NexoDeck se muestra en la lista pero no se deja cerrar** desde su propio
  panel (boton deshabilitado, y Rust lo rechaza tambien por si alguien llama la
  API por otro camino). Esconderlo seria deshonesto.
- **La fila no se borra al cerrar**: pasa a "Cerrando…" y desaparece sola en la
  siguiente muestra. Borrarla en el acto mentiria si el cierre fallo por
  permisos. Lo que falla se dice con un `SnackBar`, no en silencio.

Desde **F4** el desglose se abre como **dialogo** (`showProcessPanelDialog`),
no acoplado a un costado: competia por el ancho con el riel de metricas y el
panel de acciones del centro de control. El dialogo se cierra con el boton,
`Esc` o el fondo. `ProcessPanelDock` ya no se persiste ni se elige; solo queda
su variante `maximized`, la que usan el dialogo y la hoja del movil. La
densidad de la tabla la sigue decidiendo el **ancho medido**
(`ProcessRowDensity.forWidth`), no el dock.

**Como queda afuera el modo compacto sin ningun `Platform.is...`:**
`MetricsPanel` recibe `onSelectMetric`, y en `null` **ninguna** tile es
clicable. `CompactDeckView` simplemente no lo pasa (es una franja de ~58 dp,
sin lugar para un panel al costado), asi que no hubo que tocarla.

**Android SI tiene el panel de procesos** (agregado junto con el desglose de
disco, ver mas abajo): `ConnectedDeviceScreen` pasa `onSelectMetric` y
renderiza `ProcessPanel(..., remote: true)` igual que la PC -- la gate es
unicamente `MetricKind.supportsProcessBreakdown`
(`features/dashboard/domain/metric_kind.dart`), asi que agregar una metrica
ahi la habilita en las dos puntas sin tocar `ConnectedDeviceScreen` de nuevo.

**Disco SI se puede desglosar por proceso, a diferencia de lo que decia esta
nota antes.** No hace falta ETW: `sysinfo::Process::disk_usage()` ya usa
`GetProcessIoCounters` en Windows -- la misma fuente que el Administrador de
tareas para su columna de Disco -- y ya era una dependencia del proyecto sin
usar ese dato. Red si sigue afuera: no hay API de usuario que reparta
trafico de red por proceso, eso si necesita ETW de verdad.

Para verlo sin Flutter: `cargo run -p nexodeck-hardware --example processes`
imprime las tres listas cada 2 s con el costo de cada muestra en ms, y
`-- --kill <nombre>` prueba el cierre (busca en toda la tabla, no solo en el
top, porque un notepad de prueba nunca entra en el top).

### Grillas de acciones: `deck_grid_layout.dart`

El calculo vive en `features/actions/presentation/widgets/deck_grid_layout.dart`,
en funciones puras y testeadas (`test/deck_grid_layout_test.dart`):

- `bestColumnCountForAspect()` elige las columnas cuya celda resultante
  queda mas cerca de una proporcion objetivo **llenando todo el espacio**.
  Es lo que usa el deck de escritorio (`actions_deck_grid.dart`), que
  **nunca scrollea**.
- `resolveDeckGrid()` es la version de movil y tiene dos regimenes: si las
  acciones entran a un tamano tocable, se estiran para llenar la pantalla;
  si no, cae a `AppSizes.maxActionTileExtent` y **scrollea**. Seguir
  achicandolas, como hace escritorio, las vuelve intocables en un telefono.

El segundo regimen importa: una grilla de extent fijo dejaba media pantalla
vacia con 4 acciones en un telefono apaisado.

La pantalla de Android **no tiene AppBar**: mostraba el nombre de la PC en
una fila entera (~56 dp) para un dato que no cambia, y en horizontal ese es
justo el espacio que necesitan el riel y el deck. Por eso va envuelta en un
`SafeArea` completo (arriba incluido): sin el, el contenido queda bajo la
barra de estado, la ultima fila de tarjetas bajo la barra de gestos, y en
horizontal el notch se come el riel.

### El catalogo se re-envia con cada cambio, no solo al conectar

`HostRuntime` (`features/host_runtime/application/host_runtime.dart`)
mantiene `connectedDeviceIdsProvider` —el bridge avisa altas y bajas pero no
expone la lista— y re-empuja el catalogo con `_sendCatalogTo()` cuando cambian
`actionsListProvider` o `actionGroupsListProvider`. La primera carga de esos
providers no cuenta como cambio: quien conecta ya recibio el catalogo en
`DeviceConnected`, y sin ese filtro un telefono que conecta mientras Drift
carga lo recibia tres veces.

Antes solo se enviaba en `ConnectionEvent_DeviceConnected`, asi que **crear
un grupo con el telefono ya conectado no llegaba nunca**: del lado Android
seguian sin aparecer las pestañas hasta reconectar, sin ningun error. Mismo
sintoma mudo que el catalogo vacio documentado en `_sendCatalogTo`.

## Perfiles por contexto (Fase 9)

Un **perfil** decide QUE acciones componen el deck (N:N via
`profile_actions`) y puede activarse solo cuando cierta app pasa a primer
plano. Un **grupo** (`action_groups`) es una categoria visual 1:N dentro de
ese conjunto. No son lo mismo y se componen: el filtro de perfil vive en
`visibleActionsProvider` (unica definicion, la usan el deck y el modo
compacto), el de grupo solo en la pantalla completa.

- **Un perfil sin acciones asignadas NO filtra**: muestra el deck completo.
  Activar un perfil recien creado no puede dejar la pantalla vacia sin
  explicacion. El editor lo dice donde se decide.
- **La deteccion del proceso vive en Rust**
  (`nexodeck-hardware/src/foreground.rs`, `GetForegroundWindow` +
  `sysinfo` para resolver el pid), y `watch_foreground_app` emite **solo
  cuando cambia**: filtrar del lado Rust convierte ~3600 mensajes por hora
  en uno por cada Alt+Tab real. Fuera de Windows degrada a `None` (sin
  auto-deteccion; el cambio manual sigue andando).
- **El match del nombre NO esta en Rust**, aunque el dato salga de ahi:
  vive en `features/profiles/domain/profile_matching.dart` porque su unico
  consumidor es la UI. Tolera falta de extension (`obs64` matchea
  `obs64.exe`) pero **no matchea por prefijo** (`obs` no debe activar
  `obs64.exe`), y un valor vacio nunca matchea.

Dos reglas del auto-cambio que parecen detalles y no lo son:

- **La propia ventana de NexoDeck no cuenta como cambio de aplicacion**
  (se distingue por **pid propio**, no por nombre de ejecutable). Para
  elegir un perfil a mano hay que enfocar NexoDeck; si eso contara, el
  override manual se borraria al volver a la app anterior y el selector
  "rebotaria" solo al perfil auto-detectado.
- **Una eleccion manual gana hasta que cambies de verdad de aplicacion.**
  Volver a la misma app no la descarta. Verificado en vivo: elegir
  "Streaming" con warp adelante se mantiene; recien al pasar por otra
  ventana y volver, warp reclama su perfil.
- Que **ninguna** app matchee no desactiva el perfil actual: pasar por el
  explorador entre dos ratos de OBS no tiene por que vaciar el deck.

Para ver el detector solo, sin la app:
`cargo run -p nexodeck-hardware --example foreground` (imprime la app en
foco 1/s y marca los cambios).

## Automatizacion de UI de escritorio: SI hay, por Win32

La documentacion vieja dice que no existe. **Existe**, y con ella se
verificaron los perfiles de punta a punta (menu, editor, filtrado y
auto-cambio) sin tocar el mouse. Los scripts viven en el scratchpad de la
sesion, no en el repo; son tres:

- **capturar**: `SetWindowPos` a topmost + `CopyFromScreen` del rect de la
  ventana (nunca de la pantalla completa: se lleva puesto lo que el usuario
  tenga abierto).
- **clickear**: mover el cursor a `rect.origen + (x,y)` de la captura y
  `mouse_event` down/up. Las coordenadas de la captura mapean 1:1.
- **dar foco a otra app** (para probar la auto-deteccion): topmost +
  `SetForegroundWindow`, y **comprobar despues** con `GetForegroundWindow`
  que el foco realmente quedo ahi.

Dos trampas que costaron tiempo:

- **Una ventana minimizada devuelve un rect en `-32000,-32000` de 160x28**
  (asi la aparca Windows). Si no se detecta con `IsIconic` y se restaura
  con `ShowWindow(SW_RESTORE)`, se captura una tira blanca y los clics
  "relativos" van a cualquier lado. Parece una segunda ventana fantasma y
  no lo es.
- **No dejes dos instancias corriendo**: la segunda falla al levantar el
  host (puerto 58643 ocupado) y ademas el script puede elegir la ventana
  equivocada.

## Exportar/importar el deck: JSON aca SI, y los ids se remapean

El archivo de deck es **JSON**, no postcard. No contradice el
[ADR 0001](./docs/architecture-decision-records/0001-postcard-sobre-json.md):
ese ADR habla del **cable**, y esto es un archivo que el usuario guarda,
comparte y abre meses despues. Ahi conviene lo contrario — poder versionarlo
(`kDeckExportVersion`), leerlo a mano y perdonar campos ausentes.

Tres reglas que no son negociables:

- **Importar AGREGA, nunca reemplaza.** Todo entra con ids nuevos, asi que
  importar dos veces el mismo archivo da dos copias en vez de pisar lo que
  habia. Nadie espera que abrir un deck compartido le borre el suyo.
- **Los ids se remapean al importar.** Los ids son UUID por instalacion: los
  del archivo no existen en la maquina destino. Se genera uno nuevo por
  accion y por grupo, y las referencias (pasos de macro, `groupId`) se
  reescriben contra el mapa. Sin esto una macro importada apunta a la nada.
- **Un paso de macro que apuntaba a una accion que no venia en el archivo se
  descarta, pero se REPORTA** (`ImportResult.droppedSteps`). La macro entra
  igual, mas corta; una macro que pierde pasos en silencio es peor que una
  que no se importa.

## Historial de hardware: muestreo, retencion y bucketing

Dos cosas distintas que es facil confundir: el historial **en memoria** de
`MetricsRow` son los ultimos segundos para el sparkline; el historial
**persistido** (`hardware_history`, `features/dashboard/data/`) es lo que se
mira en el dialogo de Historial.

Los tres numeros que gobiernan todo, y por que:

- **Se persiste 1 muestra cada 15 s**, no 1/s como emite el stream. A 1/s
  serian 86.400 filas por dia para un grafico que nunca dibuja mas de unos
  cientos de puntos. Con 15 s son ~5.760/dia y ~40.000 en la semana de
  retencion.
- **La retencion es de 7 dias** y tiene que cubrir el rango mas largo que
  ofrece el selector. Si se acorta sin tocar `HistoryRange`, el rango de 7
  dias muestra una linea recortada sin decir por que.
- **`bucketSeries()` promedia, no submuestrea.** Saltear muestras pierde los
  picos: en 7 dias, un pico de CPU de 30 s desaparece si cae entre dos
  muestras elegidas. Y los **cubos vacios se omiten en vez de dibujarse como
  0**: si la app estuvo cerrada tres horas, dibujar 0 afirmaria que la CPU
  estuvo en reposo, que es distinto de "no se sabe".

La grabacion vive en `HostRuntime` y no en un widget: sigue escribiendo en
modo compacto (donde la app pasa la mayor parte del tiempo abierta, que es
justo cuando el historial vale) y tambien con la ventana oculta en modo solo
telefono.

## Macros y parametros: la logica pura va afuera del repositorio

El motor de macros (Fase 9) esta partido a proposito en dos:

- **`features/actions/domain/macro_plan.dart`** — `planMacro()` y
  `promptParametersFor()` son **funciones puras**: deciden *que* se ejecuta,
  *en que orden* y *que se le pregunta al usuario*, sin tocar Drift ni el
  bridge. Por eso se testean directo (`test/macro_plan_test.dart`) sin base
  ni FFI. Si agregas logica de macros, va aca, no adentro del repositorio.
- **`ActionsRepository.execute()`** — solo recorre el plan, ejecuta cada
  paso y espera el `delayMsAfter`.

Cosas que no son obvias:

- **A una macro se le pregunta la UNION de los parametros de sus pasos,
  deduplicada por `key`.** Si tres pasos usan `{{rama}}`, se pregunta una
  vez y el valor va a los tres. Preguntar por paso convertiria una macro de
  5 pasos en 5 dialogos seguidos, que es justo lo que la macro venia a
  evitar. Una macro **no declara parametros propios** (no tiene
  `commandTemplate`), y el editor lo dice explicitamente en vez de ofrecer
  una lista que no se usaria.
- **No hay macros anidadas, y se prohibe en DOS lugares.** El repositorio
  lo valida al guardar (`NestedMacroException`), pero hay un camino que se
  le escapa: crear la macro M con el paso A y despues **editar A para
  convertirla en macro**. Por eso `planMacro` tambien filtra los pasos que
  apuntan a una macro — sin ese segundo filtro, ese caso recursa para
  siempre en tiempo de ejecucion. Si tocas uno de los dos, dejá el otro.
- **Un paso que falla aborta el resto**, envuelto en `MacroStepException`
  (que sabe *cual* paso rompio). Una macro es una secuencia, no una bolsa
  de acciones: seguir despues de que fallo "abrir la app" solo produce mas
  errores.
- **La pausa del ultimo paso no se aplica** — no hay nada despues, y solo
  haria que la macro "termine" segundos tarde.
- `watchAll()` hace **dos `leftOuterJoin`** (parametros + pasos), asi que
  las filas vienen en producto cartesiano. Se deduplica por id; no acumules
  a ciegas.

### `run_action.dart` es la unica forma de ejecutar desde la UI de escritorio

Pedir parametros, mostrar el progreso de la macro y reportar el error es
**una sola definicion** (`features/actions/presentation/run_action.dart`),
compartida por el deck y por el modo compacto. Antes estaba duplicada, y la
copia del modo compacto ya habia divergido: **no mostraba ningun error si la
accion fallaba**. No la vuelvas a copiar.

### Los parametros viajan al telefono, y las opciones NO viajan como JSON

`RemoteAction` lleva `parameters` (key, label, tipo, default, opciones),
`kind` y `step_count`, asi que el telefono **dibuja el mismo prompt que la
PC** (`showParameterPromptDialog`, compartido) y manda los valores en
`ExecuteAction`. Detalles:

- Para una macro, la PC manda la union ya resuelta
  (`promptParametersFor`) — Android no tiene los pasos, asi que no podria
  calcularla.
- `ActionParam.options` es **`List<String>`, no el JSON de la columna**: se
  parsea una sola vez en `fromRow`. Por el ADR 0001 el protocolo manda una
  lista de strings; cuando el dominio guardaba JSON crudo habia que
  re-serializarlo para el cable y volver a parsearlo del otro lado.
- Un **valor vacio no es lo mismo que un parametro ausente**: ausente cae
  al default de la accion, vacio es una eleccion explicita del usuario. Lo
  respetan `renderCommand` y los tests de las dos capas.

**Este cambio rompe el cable con binarios viejos**: se le agregaron campos a
`RemoteAction` y a `ExecuteAction` dentro de `V1` (no se abrio un `V2`, ver
el skill `protocol-message`). PC y telefono se compilan del mismo repo, asi
que hay que **reinstalar los dos juntos**; un APK viejo contra una PC nueva
no decodifica el catalogo.

### Correr el E2E de macros y parametros

Del lado PC no hay automatizacion de UI, asi que el escenario se siembra
directo en la base (con la app **cerrada**: Drift no ve escrituras externas):

```sh
# desde app/
dart run tool/seed_macro_e2e.dart "<ruta>/nexodeck.sqlite" seed
# ... levantar la app, tocar desde el telefono ...
dart run tool/seed_macro_e2e.dart "<ruta>/nexodeck.sqlite" clean
```

Siembra una accion con `select` y una macro de dos pasos que **comparten la
variable `rama`** (el prompt debe pedir 2 campos, no 3). Se verifica con
`Get-Clipboard` en la PC y con el archivo testigo del paso 1 — no con
"parece que anduvo".

## Ejecucion capturada de comandos: hay DOS modos, los elige un flag

`ActionsTable.showTerminalWindow` no significa lo que dice su nombre: es el
**selector entre los dos motores de ejecucion**.

- `false` (por defecto desde `schemaVersion 5`) — **modo capturado**,
  `nexodeck-actions/src/runner.rs`. Sin ninguna ventana, con stdout/stderr
  por pipes, codigo de salida y duracion, todo emitido como `RunEvent` por un
  broadcast que Dart escucha con `watchCommandRuns()`.
- `true` — **modo ventana**, `terminal.rs`, el codigo de siempre. Abre una
  consola real y **no captura nada**. Es la unica via para comandos
  interactivos (`ssh`, `npm init`): capturados se cuelgan esperando un input
  que nadie puede escribir, porque su stdin es `Stdio::null()`.

La migracion a `schemaVersion 5` dio vuelta las filas existentes (`true` ->
`false`) a proposito: el `true` viejo queria decir "quiero ver la salida", y
ahora la salida se ve dentro de la app.

Cosas que costaron tiempo y no conviene re-descubrir:

- **No uses `BufReader::lines()` sobre el pipe**, aunque sea lo que hace
  `nexodeck-ai/src/sidecar.rs`. Exige UTF-8 valido y devuelve
  `Err(InvalidData)` en el primer byte que no lo sea; con el
  `while let Ok(Some(..))` de rigor eso **corta la lectura en silencio**. En
  Windows la consola entrega cp850/cp1252, asi que la primera tilde de un
  mensaje en espanol truncaba la salida a la mitad sin ningun error. Por eso
  existe `LineSplitter` (lectura por bytes + `from_utf8_lossy`), y por eso
  los scripts generados llevan `chcp 65001` / el preambulo de
  `[Console]::OutputEncoding`. `llama-server` se salva solo porque emite
  ASCII.
- **`LineSplitter` parte tambien por `\r` suelto.** `flutter analyze` y
  `cargo` dibujan su progreso con retornos de carro; sin eso, 30 segundos de
  comando son *una sola linea* de 200 KB.
- **Nada de `u64` cruzando el puente.** flutter_rust_bridge lo mapea a
  `BigInt` en Dart (se ve en `HardwareSnapshot.netRxBytes`), incomodo como
  clave de `Map`. El `run_id` es `String` y los tiempos son `u32` de ms.
- **`start_captured_command` es `async` por obligacion**, no por gusto: frb
  corre las `async fn` dentro de su propio `Runtime` y adentro se hace
  `tokio::spawn`. Desde una funcion sincrona no hay reactor y el spawn
  panickea.
- **Cancelar usa `taskkill /T`**, no `child.kill()`: matar el `cmd.exe` en
  Windows **no mata a sus nietos**, y cancelar un `flutter analyze` dejaria
  al `dart.exe` real corriendo sin que nada lo muestre. Limitacion aceptada:
  `/T` recorre el arbol de padres vivos, asi que un nieto cuyo padre
  intermedio ya murio sobrevive. La solucion completa es un Job Object, que
  suma la dependencia del crate `windows` y obliga a limpiar
  `KILL_ON_JOB_CLOSE` al detachar (si no, cerrar NexoDeck mata el OBS que el
  usuario acaba de abrir).
- **Los scripts temporales ahora SI se borran**, y recien despues de que el
  proceso murio: `cmd.exe` relee el `.bat` a medida que lo ejecuta, y
  borrarlo mientras corre rompe la ejecucion como si fuera un error de
  sintaxis al azar.

### NO hay heuristica de "app lanzada" por silencio, y es a proposito

El diseno original daba por "app lanzada" a todo proceso que siguiera vivo y
mudo a los 2 s, y cerraba su notificacion. **Se saco despues de medirlo**:
`cd <repo> && flutter analyze`, con la salida a un pipe, tarda **104 segundos
en emitir su primera linea**. O sea que la heuristica marcaba como "lanzado"
—y ocultaba— justo el comando que mas necesita verse, dejando al usuario sin
ninguna senal durante casi dos minutos.

El silencio no distingue "app de ventana" de "comando lento". Lo unico que los
separa de verdad es tener una ventana visible, y eso pide enumerar el arbol de
procesos con la API de Windows. Si alguna vez se implementa, ese es el lugar
para reintroducir `Detached`.

En la practica el caso que la heuristica venia a cubrir casi no existe: las
acciones que abren apps usan `start` (`start obs64.exe`), y con `cmd /C` eso
**retorna en el acto** — el run termina normal en ~100 ms con codigo 0. Solo
quedaria "Ejecutando" un GUI invocado sin `start`, y para eso esta Cancelar.
Hay un test que fija las dos mitades de esto.

`RunStatus::Detached` sobrevive en los tipos porque el protocolo lo transporta
(`RunPhaseWire::Launched`) y porque `RunOutcome::is_ok()` lo trata como exito
— si alguna vez vuelve, esa es la linea que evita que una macro con "Abrir
OBS" se bloquee hasta que el usuario cierre OBS.

**Regresion que costo encontrar, ligada a esto:** `resolve()` soltaba el
`Sender` de cancelacion al resolver el run, y un `oneshot` dentro de un
`select!` **despierta igual por `Err` (sender soltado) que por valor**. Como
detachar tambien resolvia, toda app "lanzada" aparecia en la UI como
**"Cancelada 2.2s"** —con un `taskkill` encima que de verdad la mataba— sin
que nadie hubiera tocado nada. Hoy el supervisor solo trata un `Ok` como
cancelacion, y `resolve()` no suelta el sender.

### El cambio de semantica en macros

Antes un paso "terminaba" cuando el proceso **arrancaba**, asi que
`delayMsAfter` corria en paralelo al comando. Ahora el paso espera a que el
comando **termine de verdad**, y un codigo != 0 aborta la macro
(`CommandFailedException` envuelta en `MacroStepException`). Es lo que uno
espera de una secuencia, pero decks que compensaban con una pausa de 3000 ms
se sienten mas lentos, y decks que "andaban" con un paso que fallaba en
silencio ahora se detienen.

### El camino remoto NO espera

`HostRuntime._handleConnectionEvent` pasa `waitForCompletion: false`: el
`ActionAck` sigue significando "lo recibi y lo lance", igual que antes.
Esperar dejaria al telefono con un spinner 30 segundos por un
`flutter analyze`. El resultado real viaja despues, por
`MessageV1::ActionRunUpdate` (variante nueva **al final** del enum, para no
correr los indices de postcard), y el telefono lo dibuja con **el mismo**
`RunToastHost` que la PC. Solo viajan el arranque y el cierre con ~4 KB del
final de la salida — mandar cada lote de lineas por WiFi no se justifica.

**Rompe el cable con binarios viejos**: hay que reinstalar PC y APK juntos.

### El host de notificaciones vive FUERA del Navigator

`RunToastHost` se instala en `MaterialApp.builder` (`main.dart`), no adentro
de un `Scaffold`: en escritorio hay dos `Scaffold` disjuntos (pantalla
completa y modo compacto) y **ninguno esta vivo** cuando el telefono pide
ejecutar una accion — ese camino corre en `HostRuntime`, que no tiene
`BuildContext`. Colgando de la raiz, una ejecucion remota aparece igual.

**Es solo visual.** Que las ejecuciones se registren no depende de el:
`runCenterProvider` lo lee `main()` al arrancar, porque en modo solo telefono
`RunToastHost` ni siquiera esta montado.

La contracara, que ya mordio una vez: ese subarbol **no tiene `Overlay` ni
`Material` ancestro**. `Tooltip` y `SelectableText` explotan ahi con "No
Overlay widget found" en cada frame (el toast se construye y falla sin que se
vea nada, solo lineas en el log), y los `IconButton` necesitan un `Material`
para su tinta. Por eso `run_toast.dart` no usa tooltips, usa `Text` en vez de
`SelectableText` (para copiar esta el boton) y se envuelve en un
`Material(type: transparency)`. El dialogo de historial si vive dentro del
Navigator y ahi los dos se pueden usar.

Y como siempre: el controller se suscribe **directo al `Stream`**
(`watchCommandRuns()`), nunca con `ref.listen` — dos `Output` con las mismas
lineas seguidos son perfectamente posibles y Riverpod no re-notifica valores
`==`.

### El panel de ejecuciones: vigilar un comando de horas

El toast y la hoja de historial alcanzan para un comando de segundos. Para uno
de **horas** —una cadena de ODM corre 3-4— no: el toast se cierra o queda
tapado por otra ventana, y la hoja es modal, no tiene cronometro vivo y se
cierra al primer clic afuera. `RunPanel`
(`features/run_center/presentation/run_panel.dart`) muestra lo que corre
**ahora**, su salida en vivo y el boton de detener. **Desde F4 se abre como
dialogo** (`showRunPanelDialog`), lo abre el boton de la barra
(`_RunPanelButton`); la hoja de historial sigue existiendo, movida al menu
"Mas".

**Deuda conocida:** el dialogo es **modal**, y eso va en contra del motivo por
el que este panel existe (vigilar un comando de horas sin que tape el deck).
Convertirlo en un overlay flotante **no modal** es lo que queda pendiente.

- **Lado a lado o apilado lo decide el ancho MEDIDO**
  (`AppSizes.runPanelSideBySideWidth`), no el anclaje — misma filosofia que
  `MetricsPanel` y `ProcessPanel`. Apilado la lista se queda con cuatro filas
  como mucho: de un comando largo lo que hay que mirar es su salida.
- **`runPanelMinWidth` (320) es mayor que el del panel de procesos** a
  proposito: lo que muestra son lineas de salida, y mas angosto se parten cada
  tres palabras.
- La salida va con `reverse: true` (lo que importa es la ultima linea) y hay un
  boton para **traer la salida completa** del anillo de Rust: el broadcast tiene
  512 eventos y un Dart atrasado recibe `Lagged` y descarta, pero el anillo del
  lado Rust si las conserva.
- `formatRunElapsed` tiene **escalon de horas**, que no es cosmetico: sin el,
  una cadena de ODM se veria `214:07`, un numero que hay que dividir
  mentalmente para saber que son tres horas y media.

### El grupo ODM: encadenar los scripts de proyecto

un script de siembra interno cubre el caso de uso real que motivo el
panel: la cadena de procesamiento de tandas de vuelos documentada en
`C:\proyecto\scripts\COMO-PROCESAR-UNA-TANDA.md`, partida en tres acciones
independientes (`nueva_tanda.py`, `procesar-tandas.sh`, archivado+limpieza) mas
una macro que las encadena. Existe en vez de cargarlas a mano porque entre las
tres suman seis parametros con sus etiquetas, tipos y opciones.

Lo que no es obvio, y vale para cualquier cadena de scripts que se meta en el
deck:

- **Git Bash va por su ruta corta 8.3** (`C:\PROGRA~1\Git\bin\bash.exe`).
  Con la ruta larga hay que citarla, y las comillas quedarian anidadas con las
  del `-lc` dentro del `.bat` que genera el runner.
- **`TerminalType.bash` de NexoDeck NO sirve aca**: esa variante lanza
  `wsl bash -lc`, y estos scripts invocan `.exe` de Windows, venvs y rutas
  `C:/...` que por WSL no corren. Van como `cmd` con el bash de Git adentro.
- **`-l` (login shell) no es adorno**: fija `HOME`, y sin eso el `ssh` de los
  avisos por WhatsApp no encuentra su `~/.ssh/config`.
- **Dos acciones distintas comparten la key `letra`**, y eso es lo que hace que
  la macro la pregunte **una sola vez** (`promptParametersFor` deduplica por
  key). Es la razon de elegir bien los nombres de los parametros.
- **La pieza irreversible se elige en el dialogo, no en el comando**: el
  `--de-verdad` de `liberar-c.sh` es un `select` con el ensayo por defecto.
- Las acciones van en **modo capturado** (`show_terminal_window = 0`), que es
  lo que hace que su salida entre al panel y el boton de detener funcione.
  Ninguna de las tres es interactiva, asi que no necesitan consola real.
- La macro no lleva pausas entre pasos: cada paso espera a que su comando
  **termine de verdad** y un codigo != 0 aborta el resto. Aca eso es una
  garantia — si el procesado falla, nunca se llega al borrado.
- El seed **reusa el grupo "ODM" por nombre** si el usuario ya lo creo en la
  app, y el `clean` borra sus acciones pero **deja el grupo**: puede tener
  otras cosas dentro.

La app tiene que estar **cerrada** al sembrar: Drift no se entera de
escrituras hechas por fuera de su conexion.

## La IA es opt-in: apagada por defecto

Nada de `nexodeck-ai` corre al arrancar la app, y no es casualidad: el engine
de Rust es un `OnceLock` perezoso (`engine.rs`), `RustLib.init()` solo llama a
`setup_default_user_utils()`, y `llama-server` se levanta unicamente desde
`start_ai_setup`. Aun asi hay un flag explicito, porque el primer contacto con
el asistente descarga varios GB y deja un proceso hijo comiendo VRAM:

- `aiEnabledProvider` (`features/ai_assistant/application/ai_enabled_controller.dart`)
  se persiste en `app_settings` con la clave `ai_enabled` — mismo patron que
  `theme_mode_controller.dart`, sin migracion de Drift. **Ausente = apagado**:
  una instalacion nueva nunca ve la IA.
- El valor inicial se lee en `main()` antes de `runApp` y se inyecta con
  `overrideWith`, como el tema y el perfil activo.
- El switch vive en el menu "Mas" del AppBar y **surte efecto en el acto**, sin
  reiniciar. Apagarlo llama a `stopAiAssistant()`: esconder el boton no alcanza
  si el motor ya se levanto en esta sesion.
- Hay **dos** puntos de entrada al asistente y los dos van gateados: el boton
  del AppBar y el del estado vacio del deck. Si agregas un tercero, gatealo
  tambien — la unica forma de que el flag signifique algo es que no quede
  ningun camino que llame al bridge de IA con el flag en `false`, empezando por
  `probeAiCapabilities` (inicializa NVML y crea una instancia de Vulkan).

## Servidor de control: la boca de entrada (MCP en loopback)

NexoDeck escuchaba en un solo sitio, el 58643 del transporte, y ese cable es
para el telefono: postcard sobre TLS con pinning, atado al ritual de
emparejamiento. No sirve para que un programa de la propia maquina le pida
algo. El servidor de control abre el otro lado, para que **Claude Code pueda
pedirle a NexoDeck que avise al usuario** o consultar que comandos corren.

Tres crates nuevos, cada uno con una responsabilidad:

| Crate | Que hace |
|---|---|
| `nexodeck-notify` | Un aviso es **un comando que se ejecuta**. Ni WhatsApp, ni OpenClaw, ni SSH dentro. |
| `nexodeck-control` | Servidor HTTP en loopback que habla MCP. Ocho herramientas: `notify`, `list_runs`, `tail_run`, `reply`, `post_message` y las tres del buzon de documentacion (ver su seccion). |
| `api/notify.rs` + `api/control.rs` | Los DTOs del puente. Solo `nexodeck-ffi` se expone a Dart. |

Despues se sumo `nexodeck-docs`, el buzon de documentacion, que el servidor de
control alimenta con `submit_findings` (ver "Buzon de documentacion" mas abajo).

Puerto **58646**. La familia va seguida a proposito: 58643 host del telefono,
58644 relay, 58646 control -- quien vea uno en un `netstat` reconoce los otros.

### La puerta son TRES guardias, y ninguna sobra (`auth.rs`)

1. **`Host` de la propia maquina.** Contra el reenlace de DNS: una pagina hace
   que `malo.example` resuelva a 127.0.0.1 y habla con el puerto como si fuera
   suyo. El socket ve una conexion de loopback normal, asi que **atar a
   127.0.0.1 no detiene el ataque**; lo unico que lo delata es el `Host`.
2. **Ningun `Origin`.** Lo pone el navegador y no se puede falsificar desde
   JavaScript. Su mera presencia significa "esto lo origino una pagina web", y
   ninguna pagina web tiene que estar pidiendole cosas a NexoDeck. Se rechaza
   **aunque traiga el token correcto**.
3. **Token**, con comparacion sin fuga de tiempo. Loopback **no es** una
   frontera de seguridad: cualquier proceso que corra como el usuario puede
   abrir una conexion a ese puerto.

### El token NO vive en Drift

Es un secreto, y la regla del proyecto es que los secretos no tocan Drift en
texto plano. `nexodeck-vault` sigue siendo un stub (Fase 7), pero ya existe el
sitio correcto **y con precedente**: el directorio de datos del usuario, que es
donde `nexodeck-transport/src/tls.rs` guarda la clave privada del certificado
del host. `control_token.txt` va al lado, por el mismo camino
(`ProjectDirs::from("dev","nexodeck","NexoDeck")`).

Se **persiste** en vez de generarse en cada arranque porque tiene que estar
tambien en la configuracion MCP del cliente: uno nuevo en cada arranque
obligaria a reconfigurar Claude Code cada vez que se abre la app. Mismo
razonamiento que hace persistente al certificado del host.

**No hay una funcion "generar token" separada en el puente, y es a proposito.**
Dart no puede tener un token que el servidor no vaya a usar: la UI lo
enseñaria, el usuario lo copiaria, y las peticiones darian 401 sin que nada
explicara por que. `start_control_server` carga el token el mismo.

### El texto del aviso NUNCA se interpola en una linea de shell

El aviso acaba viajando por `ssh` y por `docker exec`, o sea por dos
interpretes de shell encadenados. `avisar.sh` resuelve su mitad mandando el
texto en base64. La mitad de NexoDeck se resuelve antes y mejor: el texto viaja
**como un elemento de `argv` entero** o **por stdin**, y asi ningun shell lo
llega a parsear. No hay nada que escapar.

La configuracion de esta maquina usa stdin, que no deja lugar a la duda
(`avisar.sh` ya acepta `-`):

```
program: C:\PROGRA~1\Git\bin\bash.exe
args:    ["-lc", 'bash "$0" -', "/d/proyecto/scripts/avisar.sh"]
```

**El timeout por defecto son 45 s, y no sobra.** Medido en el equipo principal:
una entrega real por esta cadena tarda **28,5 s** (el `ssh` de `avisar.sh` ya usa
`ConnectTimeout=25`). Un techo de 30 s cortaria justo el caso lento que todavia
iba a funcionar, y el sintoma seria un aviso "no entregado" que en realidad
llego. Para comprobarlo sin abrir la app:
`cargo run -p nexodeck-notify --example send -- <script> "<texto>" [--seco]`.

Dos detalles que ya costaron tiempo antes y estan fijados por tests: Git Bash
va por su **ruta corta 8.3** (con la larga habria que citarla y las comillas
quedarian anidadas con las del `-lc`), y **`-l` fija `HOME`**, sin lo cual el
`ssh` del script no encuentra su `~/.ssh/config`. Son las mismas dos decisiones
que ya toma un script de siembra interno.

### Un aviso no entregado tiene que ser distinguible de uno entregado

Es la razon de existir de todo esto: las `avisar()` internas del pipeline de ODM
mandaban su salida a `/dev/null`. Consecuencias en el codigo:

- `NotifyOutcome` lleva `delivered`, `exit_code` y `detail`. **Nunca se traga un
  fallo.**
- **Sin ningun canal configurado, `notify` FALLA** (`isError: true`), no se
  calla. Un aviso que no tiene por donde salir es exactamente el fallo mudo que
  esto viene a eliminar.
- Hay **tres** formas de no entregar y solo una es un fallo:
  `is_failure() == !delivered && !skipped && !dry_run`. Un canal saltado no
  llego a intentarlo y un ensayo en seco no queria intentarlo. **Definirlo como
  "no entregado" a secas hacia que comprobar un canal recien configurado
  contestara que estaba roto** -- paso, y lo agarro el test de punta a punta.

### Un provider perezoso sobre un `broadcast` pierde lo de antes

`controlActivityProvider` se suscribe al stream cuando alguien lo observa por
primera vez, y el stream viene de un `broadcast` de tokio: **lo que se emite sin
receptores se pierde**. Montado solo con el panel, el registro decia "todavia no
llego ninguna peticion" habiendo llegado cuatro. Se vio en la verificacion del
9-sep-2026.

Por eso `main()` hace `container.read(controlActivityProvider)` **una sola
vez**, antes de `runApp`. Antes lo hacia un widget en la raiz de `MaterialApp`
(`ControlActivityHost`), pero en modo solo telefono no hay ningun widget
montado. `read` y no `watch`: lo unico que hace falta es que el provider exista.

Es una regla distinta de la de "eventos del bridge nunca con `ref.listen`", pero
de la misma familia: **cuando importa la secuencia y no el ultimo valor, hay que
mirar quien esta escuchando y desde cuando.**

### Donde estan las pruebas

Para repetir la verificacion contra la app corriendo:
`dart run tool/seed_control_e2e.dart <ruta.sqlite> seed <script>` desde `app/`
**con la app cerrada**, y levantarla despues. Enciende el servidor y siembra un
canal, que es lo que permite comprobar que arranca solo sin tocar el panel.

`core/crates/nexodeck-control/tests/e2e.rs` levanta el servidor de verdad y le
habla por HTTP: 401 sin token, 401 con token equivocado, 403 con `Origin`,
`initialize`, `tools/list`, ensayo en seco, entrega real, herramienta inexistente,
el fallo por falta de canales, y que `stop()` cierra el puerto.

**Es un solo test y no varios a proposito**: `control()` es un singleton y varios
`#[tokio::test]` en el mismo binario se pelearian por el, fallando una vez de
cada diez segun el orden del runtime.

### Configurar el cliente

`D:\Repositorios\.mcp.json` apunta al servidor y toma el token de la variable
de entorno `NEXODECK_CONTROL_TOKEN`, para que el secreto no quede escrito en un
fichero del arbol. El panel esta en el menu "Mas" -> "Servidor de control",
con el token, la URL y un boton de ensayo en seco por canal.

**Opt-in, apagado por defecto**, mismo patron exacto que la IA: flag en
`app_settings`, ausente igual a apagado, leido en `main()` antes de `runApp` con
`overrideWith`. Un servidor que acepta ordenes no puede aparecer solo en una
instalacion nueva porque alguien actualizo la app.

## El chat de IA tiene TRES destinos, y no son la misma pieza

En la barra de abajo del chat hay una etiqueta **«Contesta: …» que es de SOLO
LECTURA**: quien contesta lo elige el **perfil del stack** (su slot de
Pensamiento) desde `MODO…`/«Levantar» (`activateProfile`), no un menú aparte.
Antes había un selector desplegable ahí, un **sistema paralelo** al de los
perfiles que podía decir una cosa y contestar otra (el selector decía «la
pasarela» mientras corría el llama.cpp). `activateProfile` además guarda el
destino como **predeterminado** (y la config remota, para los servicios), así que
`restoreDefault` lo reinstala al arrancar. Detrás hay dos caminos muy distintos:

| Destino | Como funciona |
|---|---|
| El sidecar local (Qwen) y Ollama | Bucle de rondas de `nexodeck-ai`, tokens y herramientas, segundos |
| DeepSeek / OpenAI / un proxy | **El mismo bucle**: hablan el mismo dialecto |
| Claude Code | No es un modelo: es un corresponsal. Minutos, y con su propio bucle |

### Los servicios remotos no fueron un rediseno

El comentario de `ChatProvider` ya lo habia anticipado: "el modo online futuro
seria una tercera variante, no un plugin". Y asi salio. Lo unico que cambio:

- `ChatProvider::Remote { base_url, model, api_key, display_name }`.
- `stream_chat` y `list_models` aceptan `Option<&str>` de clave y ponen
  `bearer_auth` **solo si la hay**: el sidecar y Ollama estan en loopback y no
  autentican nada.
- `use_remote` **comprueba la clave antes de instalar el proveedor**. Sin eso,
  una clave mal pegada se descubre al mandar el primer mensaje y el error
  aparece dentro de la conversacion en vez de en el dialogo donde se corrige.
- La clave se guarda **solo si el proveedor arranco bien**. Guardarla antes
  dejaria una invalida en disco que el proximo arranque reusaria en silencio.

**`normalize_base_url` existe por un error concreto**: la documentacion de casi
todos estos servicios enseña la URL completa del endpoint, y pegarla tal cual
daria `/v1/v1/chat/completions` con un 404 que no explica nada. Se quitan el
sufijo `/v1` y el `/chat/completions`, y hay tests que lo fijan.

### Donde vive la clave de API

Un fichero por proveedor en el directorio de datos del usuario, **en texto
plano**, y la UI tiene que decirlo en voz alta. Un fichero por proveedor y no
uno compartido: cambiar de DeepSeek a OpenAI y volver no puede hacerte perder la
clave de la anterior.

**Es la SEGUNDA vez que `nexodeck-vault` aparece como el sitio que deberia
existir**; la primera fue el token del servidor de control. Cuando se aborde la
Fase 7, estas dos son las que hay que mudar.

## El puente con Claude Code: el sentido que el servidor MCP no tiene

El servidor de control solo contesta. Claude Code no expone ningun servidor al
que llamar, asi que un webhook añadiria un salto para nada. La via que si
funciona es la que el usuario ya usa con el puente de WhatsApp: **un proceso que
emite una linea por mensaje**, vigilado con la herramienta Monitor.

- **Ida**: NexoDeck encola en `outbox.rs`. `scripts/nexodeck-listen.sh` consulta
  `GET /outbox?since=N&confirm=M` y escupe una linea por mensaje.
- **Vuelta**: Claude Code llama a la herramienta `reply` con el id que venia en
  la linea, o a `post_message` para hablar sin que le pregunten.

### Las tres reglas son las de `vigilar-cc.sh`

1. **La marca de agua solo avanza tras emitir.** El oyente pide "lo que hay
   despues de N" y decide el mismo cuando avanza. Por eso los mensajes **se
   conservan** despues de entregarse: si el oyente muere a mitad, la vuelta
   siguiente repite en vez de saltarse.
2. **Cada mensaje lleva id.** Sin el, la respuesta no sabria a que pregunta
   pertenece.
3. **El silencio se distingue de la muerte.** Una pregunta sin respuesta vence
   a los quince minutos y emite `TimedOut`. Y `Delivered` existe justamente
   para separar "todavia no contesto" de "no hay nadie escuchando", que desde
   el reloj se ven igual.

### Un solo punto de reparto, y por eso el telefono salio gratis

`sendAiMessageBroadcast` (en `ai_providers.dart`) es por donde pasan **los
tres** caminos: lo que se escribe en la PC, lo que llega del telefono por
`AiMessageRequested`, y los prompts internos. Enrutar ahi significa que elegir
Claude Code vale para todos ellos.

**No hizo falta ninguna variante nueva en el protocolo.** La respuesta del
corresponsal se traduce a los MISMOS eventos del cable
(`AiRemoteChatEvent::AssistantMessage`, `Typing`, `Failed`) en
`main.dart::_handleCorrespondentEvent`, asi que la pantalla de chat del telefono
funciona sin tocarla: para ella, quien contesta da igual.

### Verificado contra la app corriendo (9-sep-2026)

El circulo entero, con NexoDeck en modo depuracion y el oyente lanzado a mano:
escribir en el chat con Claude Code elegido, ver la linea salir por el oyente,
contestar con la herramienta `reply` y ver la respuesta aparecer en su burbuja.
Tambien `post_message` y el rechazo de contestar dos veces.

**Dos fallos aparecieron ahi, y ninguno lo habria pillado un test:**

1. **`python3` en Windows es un señuelo.** El oyente elegia interprete con
   `command -v python3`, y en Windows eso resuelve a
   `WindowsApps/python3`: existe, esta en el PATH, imprime "Python was not
   found" y sale con codigo != 0. El sintoma era "CANAL CAIDO" en bucle con el
   servidor perfectamente vivo. Ahora **cada candidato se prueba de verdad**
   (`python3 -c 'print(1)'`) en vez de darlo por bueno porque exista. Es la
   misma familia que el `0` de temperatura que en realidad significaba "el
   driver no cargo".

2. **El chat exigia un modelo local aunque contestara Claude Code.** El dialogo
   decidia entre chat y wizard con `state.ready`, que solo mira el motor local.
   Con el corresponsal elegido mandaba a descargar varios GB de un modelo que
   no se iba a usar, o sea justo lo contrario de lo que el usuario pidio al
   elegir ese destino.

Y se confirmo el motivo de correlacionar por id: con **dos preguntas encoladas**
y respondiendo solo la primera, la respuesta cae en la burbuja de la primera y
la segunda sigue esperando con su acuse. Correlacionar por "la ultima que
espera" habria puesto la respuesta en el sitio equivocado.

**Como repetirlo:**

```sh
dart run tool/seed_control_e2e.dart <ruta.sqlite> seed <script>   # desde app/, con la app cerrada
bash scripts/nexodeck-listen.sh                                   # el papel de Claude Code
```

### Detalles que no son obvios

- **Con el corresponsal NO se bloquea el campo de texto.** Con un modelo si,
  que contesta en segundos; con Claude Code serian minutos de entrada inerte,
  sin poder encolar otra pregunta ni corregir la primera.
- **La respuesta reemplaza la entrada de espera**, no añade otra. Dos burbujas
  seguidas, una diciendo "esperando" y otra con la respuesta, llenarian el hilo
  de ruido.
- **Una respuesta puede ganarle la carrera al acuse.** Por eso `Delivered` no
  retrocede un turno que ya esta contestado, y `TimedOut` no borra una respuesta
  que ya llego.
- **Contestar dos veces a la misma pregunta se rechaza con motivo**, y el motivo
  dice que use `post_message`. Un evento sin turno donde colocarse no tendria
  donde pintarse.

## Las conversaciones del asistente se guardan (schemaVersion 12)

Antes vivian en el widget del dialogo: cerrarlo las perdia, y lo que se
escribia desde el telefono no aparecia en la PC. Hoy la transcripcion vive en
`chatConversationProvider` y se vuelca a dos tablas de Drift.

**`ChatTranscript` y `ChatConversation` son cosas distintas** y por eso no
comparten nombre: la primera es lo que hay en pantalla, la segunda la fila
guardada que genera Drift.

### Archivar no es borrar

Pasado un mes sin actividad, `archiveStale()` marca `archivedAt` y la
conversacion sale de la lista principal. **Sigue entera.** El interruptor de
"conservar para siempre" (`keepForever`) la salta, y ponerlo tambien la
desarchiva: pedir que algo se guarde y dejarlo escondido seria lo contrario de
lo pedido.

Lo unico que borra es `deleteConversation`, y solo desde el boton con
confirmacion. **Ninguna ruta automatica llega ahi.**

El corte mira `updatedAt`, no `createdAt`: una charla que empezo hace tres
meses pero sigue viva hoy no tiene por que desaparecer. Por eso
`appendMessage` marca la conversacion como viva **en la misma transaccion**;
si eso fallara, quedaria con mensaje nuevo y fecha vieja, y se archivaria
estando activa.

### Tres cosas que costaron tiempo

- **Una columna no se puede llamar `text`.** Es el nombre del constructor de
  columna de Drift (`text()`), y el getter lo tapa. El sintoma es que
  drift_dev **no genera nada para la tabla**, sin ningun error: la tabla
  simplemente no existe. Igual con `delete` como metodo de un DAO, que tapa el
  `delete(tabla)` de Drift y rompe el DAO entero.
- **Dos volcados solapados duplican filas.** Un turno emite
  `AssistantMessage` y enseguida `TurnDone`, y los dos volcaban; como marcar
  una fila como guardada ocurre DESPUES de su `await`, los dos veian el mismo
  mensaje sin guardar. Se vio en la base con la respuesta duplicada. Se
  serializa con un flag y una segunda vuelta encolada. Adelantar la marca al
  antes del `await` tambien lo arreglaria, pero podria **perder** la fila si la
  escritura falla, y aca repetir molesta y perder no se arregla.
- **El volcado se salta lo que se esta escribiendo.** A 39 tokens por segundo,
  guardar por token seria una fila por pulsacion. Se escribe en los puntos
  firmes (fin de turno, mensaje del usuario, respuesta del corresponsal) y lo
  que sigue en streaming entra en la vuelta siguiente.

### El historial vuelve como transcripcion, no como sesion

Un borrador releido se pinta como la nota de lo que se propuso, no como una
tarjeta ejecutable. El estado del equipo cambio desde entonces y ofrecer
correrlo seria ofrecer algo que ya no se verifico. Por lo mismo, el historial
del modelo (que vive en memoria del lado Rust) **no** se restaura: se ve lo
dicho, pero el modelo empieza sin ese contexto.

### El distintivo del telefono

`UserEntry.fromPhone` se guarda en la columna `origin` y se dibuja como un
icono chico **dentro del parrafo**, no como fila aparte: una fila propia
sumaria alto a cada mensaje del telefono y desalinearia la conversacion. No
lleva texto porque "desde el movil" repetido en cada burbuja seria ruido.

De donde vino sale de `exceptDeviceId` en `sendAiMessageBroadcast`, que solo
viene puesto cuando el mensaje llego de un aparato. No hizo falta otro
parametro que dijera lo mismo.

## La logica de host vive fuera del arbol: `HostRuntime` y el modo solo telefono

Todo lo que atiende al telefono en el rol PC vive en
`features/host_runtime/application/host_runtime.dart`, **no en widgets**: los
eventos de conexion (ejecutar acciones, IA remota), el push de catalogo, hubs,
componentes y estado de IA, la sincronizacion de autorizados con Rust, el
historial de hardware, los eventos de hubs y el auto-cambio de perfil. `main()`
crea un `ProviderContainer`, arranca `HostRuntime` y le pasa **el mismo**
container a la UI con `UncontrolledProviderScope`.

Antes vivia en `_HomeShellState` y en cuatro widgets envoltorio, y eso escondia
un bug mudo: **en modo compacto `_HomeShell` no se monta**, asi que el telefono
no recibia el catalogo, sus acciones no corrian y Rust rechazaba toda reconexion
(la cache de autorizados arranca vacia y nadie la llenaba). Si agregas logica de
host, va en `HostRuntime`: un widget solo escucha mientras esta montado.

Cosas que no son obvias:

- **Nada de `addPostFrameCallback` en logica de host.** Con la ventana oculta
  puede no haber ningun frame. `HostRuntime` usa `Timer.run`, con guarda de
  `_started`: el runtime puede haberse desechado antes de que corra.
- **`_listen<T>` existe por la inferencia de tipos, no por comodidad.** Escrito
  como `_listeners.add(container.listen(...))`, Dart toma
  `ProviderSubscription<Object?>` como contexto, infiere `T = Object?` y el
  `next` del listener pierde su tipo. `ProviderListenable` se importa de
  `package:flutter_riverpod/misc.dart`, no del barrel principal.
- **Las funciones que solo leen reciben `ProviderReader`**
  (`core/di/provider_reader.dart`) y no `WidgetRef`: las llaman el dialogo
  (`ref.read`) y `HostRuntime` (`container.read`). Las variantes que necesitan
  `BuildContext` siguen con `WidgetRef`.
- **La primera carga de un provider no es un cambio.** Los reenvios de catalogo
  y de hubs ignoran la transicion desde un `previous` sin valor; los autorizados
  no, porque ahi la primera carga es justo la que tiene que llegar a Rust.
- `controlActivityProvider` y `runCenterProvider` los lee `main()` al arrancar:
  los dos escuchan un `broadcast` que pierde lo que se emite sin receptores.
- Test: `test/host_runtime_test.dart`, sin montar ningun widget. **Toda fuente
  FFI que use `HostRuntime` pasa por un repositorio o provider sustituible**
  (`watchEvents`, `awaitCommandRun`, `sendActionRunUpdate`...). Una llamada
  directa al bridge ahi hace que el test reviente al cargar, sin `RustLib`.

### Modo solo telefono (Windows)

`HostPresentation` (`host_presentation_controller.dart`) vale `window`,
`phoneOnly` o `pairingPopup`. **No se persiste a proposito**: la app arranca
siempre con interfaz, tambien al iniciar Windows. Es decision del usuario.

- **En `phoneOnly`, `MyApp.build` devuelve `SizedBox.shrink()`, sin
  `MaterialApp`.** Ocultar la ventana no alcanza: `NeuralBackground` repinta a
  la tasa de refresco y los charts se reconstruyen cada segundo aunque nadie los
  vea. Sin arbol no hay tickers ni frames que programar.
- **Primero `hide()` y despues desmontar.** Al volver, al reves: montar, forzar
  un frame (`scheduleForcedFrame` + `endOfFrame`, con tope de 300 ms por si el
  engine no rasteriza oculto) y recien ahi `show()`. En el otro orden se ve un
  frame vacio o la superficie vieja.
- **`hide()` y no `setSkipTaskbar`**: `SW_HIDE` ya saca la ventana de la barra
  de tareas y de Alt+Tab, y mezclar las dos cosas puede dejar el boton sin
  volver.
- Las operaciones del controller van **en fila** (`_enqueue`): dos clics
  seguidos en la bandeja intercalarian llamadas asincronas de `window_manager`.
- **`MaterialApp` lleva `key: ValueKey(presentation)`**, y `rootNavigatorKey`
  solo en `window`. Cambiar `home` sobre un Navigator vivo no reemplaza la ruta
  raiz, y una `GlobalKey` compartida haria que Flutter reusara el Navigator
  viejo, con sus rutas.
- Volver a la ventana llama a `WindowModeController.applyGeometry`: la
  emergente de emparejamiento cambia tamano y always-on-top, y `switchTo` no
  hace nada cuando el modo no cambia.
- `enterPhoneOnly` solo guarda la geometria si viene de `window`: guardarla desde
  la emergente dejaria el tamano de la emergente como el de la ventana.

**Bandeja (`tray_controller.dart`), solo Windows.** En Linux `tray_manager` pide
appindicator, y sin bandeja no habria forma de volver; por eso el item "Solo
telefono" del menu "Mas" tambien se ofrece solo en Windows.

- `popUpContextMenu(bringAppToFront: true)`: sin `SetForegroundWindow` el menu
  de la bandeja no se cierra al hacer clic afuera.
- `setPreventClose(true)` y un unico `shutdown()` que llama a
  `trayManager.destroy()` antes de salir: sin eso queda un icono fantasma. La X
  sigue siendo salir.
- El icono es `assets/tray/tray_icon.ico`; el plugin resuelve la ruta contra
  `data/flutter_assets`.

**Instancia unica (`windows/runner/single_instance.h`).** Con la ventana oculta,
abrir el acceso directo lanzaria un segundo proceso que choca en el 58643 sin
que se vea nada. `main.cpp` toma un mutex con nombre; si ya existe, busca la
ventana por la propiedad `NexoDeck.Instance` (`EnumWindows` + `GetPropW`, que si
ven ventanas ocultas), le cede el primer plano con `AllowSetForegroundWindow` y
le postea un mensaje registrado. El runner lo reenvia por el canal
`nexodeck/instance` y Dart muestra la ventana.

- **No se busca por clase**: todas las apps Flutter de Windows usan
  `FLUTTER_RUNNER_WIN32_WINDOW`.
- En debug el mutex lleva `.Debug`, para que `flutter run` no despierte en
  silencio a la app instalada que este en la bandeja.
- La propiedad se quita en `WM_DESTROY` dentro de `MessageHandler`, no en
  `OnDestroy`: cuando se llega ahi, `Win32Window` ya puso el handle en null.
- El runner compila con `/W4 /WX`: el `1` de `SetPropW` pasa por `INT_PTR`
  (C4312, que con `/WX` es error).

### Emparejamiento a demanda

Sin interfaz nadie tiene la hoja de emparejar abierta, asi que un `PairHello`
se rechazaria siempre. Con `TransportHost::set_on_demand_pairing_grace` (el FFI
pone 15 s) Rust **retiene** el hello, emite
`PairingEvent::PairingRequestedWhileDisarmed` y espera a que se arme el PIN.
`HostRuntime` abre la ventana emergente (`PairingPopupView`), su `HostPinCard`
arma, y **el mismo intento** del telefono recibe el PIN sin reintentar.

- **Los 15 s tienen que quedar por debajo de los 20 s del telefono**
  (`PairingTimings.connectHandshake`): pasado eso el telefono ya se rindio y
  descarta el PIN que llegue tarde.
- **Solo `HostPinCard` arma el PIN.** `arm_pairing` lo reemplaza: si
  `HostRuntime` armara tambien, o se abriera una segunda tarjeta, el telefono
  recibiria un PIN distinto del que se ve. `isHostPinCardMounted` (contador
  estatico y no provider, porque se toca en `initState`/`dispose`) impide la
  segunda tarjeta.
- En Rust el `Notified` se habilita **antes** de volver a mirar el estado. Al
  reves, un armado que cae entre mirar y esperar se pierde y la sesion duerme
  hasta que vence la gracia, con el PIN ya en pantalla.
- Frenos contra un dispositivo que reintenta en bucle: una sola espera a la vez;
  60 s de enfriamiento en Rust tras una espera vencida (rechazo inmediato y sin
  aviso); y 30 s en Dart tras cerrar la emergente sin emparejar.
- La emergente no tiene barra de titulo (su X pasaria por `onWindowClose`, que es
  salir); Alt+F4 ahi vuelve al modo sin interfaz. `HostPinCard.dispose` contesta
  `confirmPairing(false)` si queda una solicitud pendiente, para que el telefono
  no espere los 120 s.
- Test: `core/crates/nexodeck-transport/tests/on_demand_pairing.rs`, un solo test
  en su propio binario (los hosts son singletons de proceso).

## Buzon de documentacion: Claude Code manda hallazgos, el usuario aprueba

Claude Code manda hallazgos por MCP (`submit_findings`), un modelo los convierte
en una **propuesta** de cambios a los documentos de un proyecto, y el usuario la
aprueba en la app antes de que se escriba nada. **NexoDeck nunca toca git**: deja
el cambio en el arbol de trabajo. Del lado de Claude Code se usa con la skill
`send-findings` de `D:\Repositorios\.claude\skills`.

| Pieza | Donde |
|---|---|
| Almacen, operaciones, validacion, aplicacion, trabajador | `core/crates/nexodeck-docs` |
| `submit_findings`, `list_doc_projects`, `finding_status` | `nexodeck-control/src/tools.rs` |
| Puente | `nexodeck-ffi/src/api/docs.rs` |
| Bandeja de propuestas | `app/lib/features/docs_inbox/` (boton en la barra, menu "Mas" y bandeja del sistema) |

### Rust es el dueño, en ficheros, y no Drift

`<datos del usuario>/docs_inbox/`: `config.json`, un JSON por hallazgo y una
carpeta por propuesta, todo con escritura atomica (temporal + `sync_all` +
`rename`). Quien produce (MCP) y quien procesa (trabajador) viven en Rust; con
Drift cada hallazgo haria dos saltos y, en modo solo telefono, Dart puede no estar
escuchando. **Dart no guarda nada**: pide una foto y la vuelve a pedir en cada aviso.
La configuracion de proyectos tambien vive ahi y no en `app_settings`, porque la
lee Rust en cada peticion MCP; `config()` relee el fichero cada vez, asi que
editarlo a mano con la app abierta surte efecto en la siguiente vuelta.

### El modelo nunca escribe un fichero entero

El diario de IA pesa 483 KB. Una propuesta son **cuatro operaciones y nada mas**
(`ops.rs`): `insert_section_top`, `set_last_updated`, `replace_exact` (ancla unica,
como Edit) y `append_under_heading`, todas **por ancla y nunca por numero de
linea**, con las posiciones calculadas en Rust. Lo que no es obvio de la
validacion (`validate.rs`):

- **El ancla tiene que estar en lo que se le enseño al modelo** (`context.rs`: del
  diario van la cabecera, el indice de encabezados, las dos secciones mas recientes
  y hasta dos antiguas relacionadas). Un modelo no puede editar lo que no vio. Una
  operacion si puede anclarse en texto que añadio otra anterior de la misma
  propuesta.
- Un documento que no es UTF-8 valido **no se toca**, y se conservan su CRLF y su
  BOM: convertir un CRLF entero por añadir una seccion haria un diff de 8.000 lineas.
- Borrar mas de 40 lineas se marca `destructive` pero no se bloquea: en estos
  documentos lo que deja de ser cierto se borra.
- La fecha de un encabezado de diario tiene que ser la de hoy o la de algun
  hallazgo; al revalidar se usa la del dia en que se genero, para poder aprobar
  hoy una propuesta de ayer.

### Aprobar lleva la revision que se vio

Al aplicar se relee cada documento y se compara su sha256 con el de la propuesta.
Si alguien lo toco **no se escribe nada**: se revalida, y la propuesta sube de
revision y queda `needs_review` (sigue aplicando, hay que volver a enseñarla) o
`stale` (ya no aplica). Aprobar con una revision vieja se rechaza. Se guardan los
originales, se relee lo escrito y, si falla un fichero, se restauran los
anteriores. Deshacer solo funciona si nadie edito despues.

### El trabajador

- **90 s de calma** por `(proyecto, sesion)` antes de pedir nada (tope 10 min), y
  **una sola propuesta pendiente por proyecto**: con dos sobre el mismo diario,
  aprobar la primera invalidaria el hash base de la segunda.
- **Remoto primero, local solo si ya esta levantado.** `Engine::local_endpoint()`
  nunca arranca `llama-server`: una tanda de ODM ocupa la GPU durante horas. Con la
  IA apagada el motor ni se consulta. Sin candidato, o con un fallo pasajero, el
  hallazgo queda `waiting_model` con el motivo concreto y se reintenta a los 5, 15
  y 60 min.
- `stream_chat` es una funcion libre, asi que el trabajador usa su propio proveedor
  **sin tocar la sesion del chat**, que es una sola.
- `submit_findings` **nunca llama al modelo dentro de la peticion**: un cliente MCP
  esperando un minuto acabaria en timeout y reintentando. Un reenvio identico en
  24 h devuelve el id existente.

### Cosas que costaron tiempo

- **El prompt de sistema va en `r####"..."####`.** Trae `"##` (los encabezados de
  ejemplo), que cierra un `r#"..."#` a mitad, y el error del compilador apunta a
  "prefijo desconocido" en palabras sueltas del texto, no a las comillas.
- `jiff` necesita `jiff-tzdb-platform` en Windows para la hora local: el sistema no
  expone la base de zonas en formato IANA. La fecha local importa: pasada la
  medianoche, en UTC el encabezado del diario saldria con otro dia.
- El aviso del stream lleva un contador (`DocsInboxChanged.seq`): dos avisos
  seguidos serian `==` y Riverpod descartaria el segundo.
- El buzon se abre en `main()` **antes** de leer `docsInboxProvider`: el stream de
  Rust termina en el acto si el buzon todavia no existe.
- El e2e de `nexodeck-control` sigue siendo un solo test; la parte del buzon usa un
  `DocsService` con `Backends::Fixed(vec![])` y un repo temporal.

### Configurar un proyecto

En la app, "Buzon de documentacion" -> "Proyectos...", o editando
`docs_inbox/config.json`. Cada documento lleva `path` (relativo al repo), `role`
(`journal`, `plan` o `index`), `answers` (lo que responde, que es lo que lee el
modelo para decidir a donde va cada hallazgo) y `evidence_labels`. Con un modelo
remoto el contenido de esos documentos sale de la maquina, y la UI lo dice.

## Asistente de notas: cinco agentes cruzan tus notas con todo lo demas

Una **boveda** de notas en markdown (compatible con Obsidian) que NexoDeck lee,
relaciona con otras notas, con los hallazgos del buzon y con los commits de los
repositorios, y **completa con propuestas** que el usuario aprueba en el buzon.
Diseño y proximas iteraciones en
[`docs/ideas/asistente-de-notas.md`](./docs/ideas/asistente-de-notas.md).

| Pieza | Donde |
|---|---|
| Indice de la boveda, parser, `git log` | `nexodeck-docs/src/notes/{index,parse,git}.rs` (ADR 0004) |
| Los cinco agentes y la traza | `nexodeck-docs/src/notes/{agents,orchestrator,digest}.rs` |
| El digest dentro del trabajador | `nexodeck-docs/src/notes/runner.rs` + enganches en `service.rs` |
| Roles de boveda, `add_section`, `set_frontmatter_key`, redaccion | `config.rs`, `ops.rs`, `validate.rs`, `redact.rs` |
| `search_notes`, `get_note`, `digest_note` | `nexodeck-control/src/tools.rs` |
| Puente | `nexodeck-ffi/src/api/notes.rs` |
| Dialogo "Notas" | `app/lib/features/notes/` |

### Vive dentro del buzon, no al lado

Las notas usan la cola, los candidatos de modelo, los reintentos, la validacion
de "solo lo que viste" y la aprobacion con revision del buzon. Un sistema
paralelo habria duplicado todo eso y, peor, las dos copias acabarian aceptando
cosas distintas. Por lo mismo **no hay `init` ni stream propios en el puente**:
lo que tiene que estar abierto es el buzon, y sus avisos valen para las notas.

- Una boveda es un `DocProject` con `"kind": "vault"`: vale cualquier `.md` de
  dentro y el rol sale de la carpeta (`diario/` -> `daily`, `proyectos/` ->
  `hub`, el resto `note`). **Nunca** `privado/` (en cualquier nivel) ni
  carpetas ocultas. `InboxConfig.notes` apunta a la boveda y lista los repos.
- `add_section` y `set_frontmatter_key` solo valen en roles de nota: en un
  diario o un plan del buzon romperian su estructura fija. El prompt del buzon
  no las menciona a proposito.
- `Proposal.origin` distingue hallazgos de digests; las propuestas viejas sin el
  campo se leen como hallazgos.

### La cadena de agentes

`nota -> Lector -> (Rust busca) -> Memoria + Codigo (en paralelo) -> Critico ->
(una busqueda mas, como mucho) -> Redactor -> propuesta`. Lo que no es obvio:

- **Rust busca y el modelo razona; los agentes no tienen herramientas.** Cada
  uno recibe candidatos con id (`n:<ruta>#<seccion>`, `f:<hallazgo>`,
  `c:<repo>@<sha>`) y lo que cite fuera de su lista se quita
  (`keep_known_ids`). "Lo citado existe" se comprueba, no se pide.
- **Nada privado ni secreto sale**: una nota con `ai: false` no llega a ningun
  agente, y todo pasa por `redact` antes de cada peticion. Lo mismo en las
  herramientas MCP, porque Claude Code tambien es un modelo remoto.
- Un **error del modelo** a mitad de cadena la para y el trabajador reintenta;
  una **respuesta ilegible** de la memoria o del critico no la para.
- La traza (`docs_inbox/digests/<id>.json`) guarda candidatos, salida de cada
  agente, ids descartados y secretos quitados. La UI la enseña entera.

### El trabajador

- **Bloqueo por nota, no por proyecto**: en una boveda, una propuesta pendiente
  no puede frenar a las otras mil notas.
- **Modo automatico** (`digest_on_idle`, apagado por defecto): notas tocadas en
  las ultimas 24 h que llevan 5 min quietas, 3 por vuelta como mucho, nunca la
  nota de proyecto. Sin el tope de 24 h, encenderlo procesaria la boveda
  entera. `settled_hash` evita que aprobar una propuesta vuelva a encolar la
  nota en bucle.
- El indice vive en memoria (ADR 0004) y se comparte como foto (`Arc`): un
  digest de un minuto no bloquea las busquedas de la app. Los commits se releen
  cada 10 minutos, con `git log` sin consola visible.

### Cosas que costaron tiempo

- **Sin raiz de palabra la busqueda no encontraba lo evidente**: "ortofoto
  deformada" no daba con "deforma las ortofotos". Se comparan las seis primeras
  letras sin tildes; es tosco, pero en español casi todo cambia por el final.
- **`serde_json` ordena las claves** de los objetos: un test que esperaba los ids
  descartados en el orden del JSON escrito fallaba.
- **Tras cambiar un DTO del puente hay que regenerar antes de compilar**:
  `cargo check` de `nexodeck_ffi` falla en `frb_generated.rs` hasta que corre
  `flutter_rust_bridge_codegen generate`, y el error apunta al fichero generado.
- Editar una nota en Obsidian **no avisa a nadie**: el dialogo relee la boveda
  al abrirse, y el detalle se vuelve a pedir cuando cambia la fecha del fichero.

### Configurar

En "Buzon de documentacion" -> "Proyectos...", un proyecto
`{"id": "notas", "name": "Notas", "kind": "vault", "repo_root": "D:\\Notas"}` y
un bloque `"notes": {"vault_project": "notas", "repos": ["D:\\Repositorios\\NexoDeck"]}`.
El dialogo "Notas" enseña el mismo ejemplo cuando no hay boveda.

### Guardar una nota desde Claude Code (`save_note`)

Una sesión puede mandar algo a la bóveda por MCP: el usuario dice "el resumen que
me acabas de dar mándalo a NexoDeck" y la nota aparece al momento.

**Es la única herramienta que escribe en la bóveda sin pasar por el buzón, y la
excepción está acotada a propósito.** La regla de que las notas no se editan
desde una sesión sigue en pie para todo lo demás: procesar una nota, cruzarla y
proponer cambios sigue siendo cosa del buzón y de su aprobación. Lo que cambia
aquí es *quién decide*: no hay ningún modelo reinterpretando la bóveda, es el
usuario pidiendo que se guarde un texto que acaba de leer. Meterlo en el buzón
convertiría una libreta en un trámite.

| Pieza | Dónde |
|---|---|
| Saneado del markdown, título y ruta (puro, con tests) | `nexodeck-docs/src/notes/capture.rs` |
| `DocsService::capture_note`, que escribe sin pisar | `nexodeck-docs/src/notes/editing.rs` |
| La herramienta MCP | `nexodeck-control/src/tools.rs` |

- **El formato lo arregla NexoDeck, no quien llama.** Una herramienta MCP recibe
  lo que le manden; si el markdown dependiera de la buena voluntad del que llama,
  antes o después entraría texto con tres encabezados de nivel uno o con espacios
  al final de cada línea. Se normaliza el espaciado, se separan los encabezados y
  los `#` sobrantes bajan a `##` para que la nota tenga un solo título.
- **Un texto entero envuelto en una cerca de markdown se desenvuelve**, porque es
  exactamente lo que manda una sesión al "pasar el resumen". Solo si la cerca
  abre en la primera línea y cierra en la última y no hay ninguna otra: con más
  cercas el contenido es código de verdad y desenvolverlo lo rompería.
- **El frontmatter que venga en el texto se descarta y lo pone NexoDeck.** Si se
  respetara, una sesión podría marcar la nota `ai: false`, ponerle etiquetas o
  falsear su fecha sin que el usuario lo pidiera. El que se escribe lleva `date`,
  `source: claude-code` y la sesión de origen: dentro de un mes la pregunta es
  "¿esto lo escribí yo o me lo dio una sesión?".
- **El orden es desenvolver y luego quitar el frontmatter, no al revés.** Costó un
  fallo en el e2e: con el texto envuelto, al mirar el frontmatter primero no hay
  nada que quitar —la primera línea es la cerca— y el `ai: false` acababa dentro
  de la nota. Hay un test que lo fija.
- **Dentro de un bloque de código no se toca nada**: ahí una línea en blanco de
  más o un espacio al final pueden ser parte de lo que se guarda.
- **Nunca se pisa una nota.** Sin ruta, cae en `inbox/AAAA-MM-DD-titulo.md`, y si
  ese nombre ya está ocupado se busca el siguiente libre (`(2)`), igual que la
  papelera de `sync.rs`. Con una ruta que ya existe **se añade al final** como
  una sección con su hora, para que dos envíos del mismo día se distingan.
- **Las notas así guardadas son normales**: entran en el índice, en las búsquedas
  y en lo que cruzan los agentes. Es lo que hace que lo guardado sirva luego.
- El nombre del fichero va sin tildes ni ñ: la bóveda se sincroniza con el móvil
  y se abre en Obsidian, y un nombre acentuado viaja distinto según el sistema de
  ficheros.

#### Sin cliente MCP: `scripts/nexodeck-save-note.sh`

Un agente que no hable MCP —o un script de una cadena larga— guarda igual, por
HTTP, con la misma herramienta. Hermano de `nexodeck-listen.sh`, y con su misma
resolución de token (`NEXODECK_CONTROL_TOKEN` o el fichero del directorio de
datos): dos formas distintas de encontrarlo acabarían desincronizándose.

```sh
bash scripts/nexodeck-save-note.sh "Lo que haya que guardar"
comando_largo | bash scripts/nexodeck-save-note.sh --title "Resultado de la tanda"
```

- **Solo funciona en la máquina de NexoDeck.** El servidor de control escucha en
  `127.0.0.1` y nada más (verificado con `netstat`: `TCP 127.0.0.1:58646`). Un
  agente en otra máquina no lo alcanza, y abrirlo a la red sería dejar una puerta
  de escritura en la bóveda del usuario. Por ahí no se pasa: si hiciera falta de
  verdad, es un túnel del usuario, no un cambio de dirección de escucha.
- **El texto viaja por stdin o como un argumento entero, nunca interpolado en una
  línea de shell.** Un resumen lleva comillas, backticks y saltos de línea; el
  JSON se arma con `python`, no con `printf`.
- **Un fallo no se parece a un éxito**: se mira `isError` de la respuesta y se
  sale con código distinto de cero, que es la regla de todo el servidor de
  control.
- La identidad (`from`) se deduce de la carpeta y la rama de quien lo lanza, igual
  que en el vigilante; `--from` la pisa.
- Verificado contra la app corriendo: crea la nota, y con argumentos vacíos
  contesta `Falta 'text'… No se ha guardado nada` sin tocar la bóveda.

### Agrupaciones de notas: cada una es una carpeta

Las notas se agrupan con un nombre y un color sutil, desde la app, desde la ventana
del editor o por MCP (`list_note_groups`, `create_note_group`, `move_note_to_group`,
y `group` en `save_note`). Sin agrupación, una nota vive en `inbox/`.

| Pieza | Dónde |
|---|---|
| Qué carpeta es grupo, validación, listado (puro, con tests) | `nexodeck-docs/src/notes/groups.rs` |
| Mover, crear/editar agrupación | `DocsService::{move_note, upsert_note_group}` en `notes/editing.rs` |
| Reescribir enlaces | `rewrite_wikilinks` en `notes/parse.rs` |
| El catálogo (nombre, color, orden) | `NotesConfig.groups` en `config.rs` |

**Una agrupación ES una carpeta de primer nivel, y fue decisión del usuario sabiendo el
precio.** La alternativa —una clave `group:` en el frontmatter— no movía ficheros ni
rompía nada, pero no se ve como estructura al abrir la bóveda en Obsidian, y se abre
por fuera a menudo. La consecuencia es que **agrupar mueve el fichero**, y la ruta es
la identidad de una nota en siete sitios: digests, propuestas, `settled_hash`,
backlinks, la papelera y el espejo del móvil, donde es clave primaria.

- **El catálogo solo viste; la carpeta manda.** Toda carpeta de primer nivel cuenta
  como grupo aunque no esté en `NotesConfig.groups` (sale con color neutro): así lo
  que se ve y lo que hay en disco no pueden discrepar. Una entrada del catálogo sin
  notas también sale, vacía: borrar la última nota no puede hacer desaparecer el
  grupo sin avisar.
- **`diario`, `proyectos`, `privado` e `inbox` no pueden ser grupos.** Los dos
  primeros cambian el `DocRole` de la nota —y con él su comportamiento: el modo
  automático salta los `hub`—, así que meter una nota en esa "agrupación" le
  cambiaría lo que es. `privado` no lo lee nadie e `inbox` es justo "sin grupo".
- **Los grupos viajan en la misma foto que las notas** (`NotesOverview.groups`),
  sacados del mismo índice, para que las dos listas no puedan desfasarse.
- `NoteGroup` lleva `#[serde(default)]` en `NotesConfig`: toda configuración anterior
  sigue leyéndose. `NotesConfig` **no deriva `Default` a propósito**: un campo nuevo
  rompe la compilación en los cinco sitios que la construyen con literales, y esa
  rotura es la señal de que llegó a todos.

#### Mover sin romper (`DocsService::move_note`)

No existía ninguna operación de mover, ni en Rust ni en el protocolo: hasta ahora
mover era algo que pasaba por fuera y el índice veía como baja + alta.

1. **Se niega si hay una propuesta pendiente sobre la nota.** Guarda el hash de cada
   fichero por ruta: movida la nota, no podría aplicarse. Pedir que se decida antes es
   más robusto que reescribir propuestas por dentro.
2. **Nunca pisa**: si en el grupo ya hay una nota con ese nombre, se aparta a `(2)`.
3. **Reapunta los digests, y solo el campo `note`.** Mover no cambia el contenido, así
   que `note_hash` y `settled_hash` siguen valiendo; sin reapuntar, el modo automático
   reprocesaría la nota como si fuera nueva.
4. **Reescribe los `[[enlaces]]` que la citaban por ruta** en toda la bóveda,
   `privado/` incluido, conservando `#sección`, `|alias` y el `.md`. Los que la citan
   por nombre suelto no se tocan: resuelven solos. **`rewrite_wikilinks` vive en
   `parse.rs` junto a `WIKILINK` y `code_mask` a propósito**: lo que se reescribe al
   mover tiene que ser exactamente lo que el índice cuenta como enlace.

#### Un fallo que casi entra: renombrar creaba otra carpeta

La primera versión de `upsert_note_group` derivaba el id del nombre. Renombrar "Tandas
de ODM" a "Vuelos" desde la interfaz habría creado una carpeta `vuelos` nueva y dejado
las notas en la vieja. Hoy recibe un `id` opcional: **con él se edita la existente y el
nombre es solo lo visible**. El MCP no lo pasa (crea); la interfaz sí (edita). El
diálogo lo dice: "Cambiar el nombre no mueve la carpeta".

#### En la interfaz

- **El color nunca va como relleno ni como color de texto.** En la página se mezcla con
  el tema (`color-mix`) con valor de reserva; en Flutter tiñe el borde de la tarjeta
  (`InteractiveCard(accent:)`), como el deck. Es lo que lo hace sutil y legible en
  claro y oscuro sin calcular contraste. La fila abierta conserva su indicador.
- **El hex se valida antes de usarlo** (`HEX` en `sidebar.ts`, `ColorPalettePicker.parse`
  en Dart): llega de una configuración que se puede editar a mano. Mal escrito se
  pinta gris, no rompe la pantalla.
- **La paleta es la del deck** (`kActionColorPalette`): para el usuario son el mismo
  concepto. El selector, que estaba triplicado, se extrajo a
  `core/widgets/color_palette_picker.dart`; los tres anteriores siguen con su copia.
- **Una nota nueva desde la ventana va a `inbox/`** sin agrupación, igual que
  `save_note`. Antes sugería la raíz: dos reglas para "dónde cae una nota nueva"
  habrían confundido. Cambiar de grupo una ruta escrita a mano solo toca la carpeta si
  era la bandeja o un grupo conocido (`regroupPath`): un `privado/` no se mueve solo.
- **Mover desde la app no interrumpe si sale bien** (el usuario pidió que los enlaces
  se arreglen solos, no que se lo cuenten) **y lo dice en un diálogo si falla**: dentro
  del diálogo de Notas un `SnackBar` saldría tapado detrás, o sea mudo.

**Lo que falta:** mover una nota **desde la ventana del editor** (hoy se mueve desde el
diálogo de la app o por MCP) y **el móvil**. En el móvil no se tocó el protocolo: un
movimiento se ve como borrado + alta en el espejo, y si esa copia tenía cambios sin
sincronizar no se borra, así que puede quedar duplicada.

**Lección de la tanda:** al añadir `save_note` quedó roto
`every_tool_declares_a_name_and_a_schema` y no se vio, porque se corrió el e2e de
`nexodeck-control` por separado y luego el workspace excluyendo ese crate. Tras tocar
las herramientas MCP: **`cargo test -p nexodeck-control` entero**.

### Notas locales: carpetas del usuario leídas en su sitio

Además de la bóveda, el usuario puede añadir **carpetas suyas con `.md` ya ordenados**
(apuntes, docs de trabajo). NexoDeck las lee, las edita, las agrupa y las mueve **en su
ruta, sin copiarlas nunca** en la PC, con todas sus subcarpetas, y las enseña en árbol
con una etiqueta sutil **"Notas locales"**. Al móvil sí van copiadas, como la bóveda,
para usarlas sin conexión. Se añaden y se quitan desde el menú "Más" → **"Carpetas de
notas…"**. Quitar una **no borra nada del disco**.

**Ese acceso existe porque el primero no se veía nunca**: el diálogo de la bóveda solo
se abría con el "Cambiar…" del diálogo de Flutter, y con WebView2 el botón "Notas" abre
la ventana del editor, que no tiene configuración. Lo encontró el usuario al buscarlo.

#### Desde la propia ventana de notas: menú ⋮ junto al buscador

Petición del usuario: que las carpetas se gestionen **en la misma ventana**. El menú
tiene "Importar notas locales…", "Importar espacio de NexoDeck…" (cambiar la carpeta
principal) y "Exportar notas…"; una carpeta local se quita con **clic derecho** sobre
ella en el árbol.

| Pieza | Dónde |
|---|---|
| Elegir bóveda, añadir y quitar carpetas (sobre la config validada) | `nexodeck-docs/src/notes/folders.rs` |
| Exportar a zip | `nexodeck-docs/src/notes/export.rs` |
| Diálogos nativos modales (`rfd`) | `pick_path` en `nexodeck-editor/src/host.rs` |
| `Effect::Pick` → `Session::picked` → `Job` | `session.rs` |
| El menú | `web/src/menu.ts`, `sidebar.ts` |

- **La página nunca manda una ruta.** Pide "elige una carpeta" y la ruta la trae el
  diálogo nativo que abre Rust. Si la página pudiera mandar `{ path }`, cualquier
  cosa que se colara en ella podría apuntar NexoDeck a cualquier carpeta del disco.
  Además, un `<input type=file>` de WebView2 no da la ruta de una carpeta.
- **El diálogo corre en otro hilo**, con la ventana como padre para que sea modal:
  en el hilo del event loop bloquearía los avisos del buzón y las búsquedas mientras
  el usuario elige. Lo elegido vuelve como `Command::Picked`; cancelar no avisa de
  nada.
- **Un rechazo va a la página como error y no se avisa a Dart**: que la carpeta pise
  documentación del buzón es algo que el usuario tiene que leer, no un fallo de la
  app.
- **"Importar espacio" no copia nada**: cambia `repo_root` del proyecto de la bóveda y
  conserva repos, agrupaciones y carpetas locales. Si no había bóveda, la crea con el
  id `notas`.
- **La exportación es solo la bóveda principal** (decisión del usuario: las locales ya
  viven en su ruta). Dentro del zip, una carpeta raíz con el nombre de la bóveda y el
  **orden del árbol** (carpetas primero, natural). Solo `.md`; fuera lo oculto y los
  `@` de primer nivel, igual que el índice. **`privado/` entra**: es la copia de su
  propia bóveda. **Las carpetas vacías entran**, porque una agrupación recién creada
  es eso. Se escribe a `.zip.partial` y se renombra al final: un zip a medias con el
  nombre bueno parece una copia válida.
- **La regla del id de carpeta está dos veces**, en `folders.rs::folder_id` y en
  `vault_config.dart::folderId` (el diálogo de la app edita el JSON). Hay un test a
  cada lado con los mismos casos; si cambias una, cambia la otra.
- **Cambiar la bóveda con una nota abierta** no la cierra. No se pierde nada: al
  guardar, el hash ya no coincide y sale la banda de conflicto en vez de escribir.
- La copia de la página del móvil también lleva el menú, pero allí todavía no hay
  quien atienda esos mensajes: la pantalla de notas del móvil es un paso pendiente.

#### Filas que no caben: flecha, no barra de desplazamiento (`web/src/scrollStrip.ts`)

Las pestañas (Notas, Tareas, Asistente) y la barra de agrupaciones, cuando no caben,
**no se recortan ni sacan barra de scroll**: sale una flecha en el borde por donde se
corta, y la contraria cuando ya se avanzó. Petición del usuario: el número de una
pestaña cortado no decía que había más.

- Las pestañas son `flex: 1 0 auto`: reparten el ancho pero **nunca encogen por debajo
  de su contenido**. Con el `grid` de tres columnas iguales de antes, el contador se
  recortaba sin avisar.
- La barra de agrupaciones se redibuja con cada foto de la bóveda, así que su
  desplazamiento se guarda en la clase (`groupScroll`) y se restaura; si no, elegir un
  chip de la derecha lo volvía a esconder.
- **Verificado con capturas de Edge sin interfaz** sobre la página con datos de muestra
  y la barra lateral estrecha: flecha derecha al inicio, y al final la izquierda sin la
  derecha, con el contador entero. Ojo al repetirlo: en ese modo el desplazamiento
  **suave** no llega a terminar y la captura sale a medias; por eso, además del evento
  `scroll`, `step` recalcula a los 400 ms.

| Pieza | Dónde |
|---|---|
| Raíces, identidad, `locate`, `link_form`, reglas de solapamiento (puro, con tests) | `nexodeck-docs/src/notes/roots.rs` |
| Índice sobre varias raíces, `resolve_link_from` | `notes/index.rs` |
| Mover entre carpetas (`copy_verified`), agrupaciones por carpeta | `notes/editing.rs` |
| Añadir y quitar en el JSON sin tocar lo demás | `app/lib/features/notes/domain/vault_config.dart` |
| Árbol (orden del Explorador) | `domain/note_tree.dart` + `presentation/note_tree_view.dart`, `web/src/noteTree.ts` |

**Una carpeta local ES un proyecto `vault` más**, listado en `NotesConfig.local_folders`
(`#[serde(default)]`). Es la costura más barata: propuestas, validación y aprobación ya
iban por proyecto, así que un digest de una nota local se aprueba sin tocar nada de eso.

**Identidad: `@<id>/<ruta>`.** Las notas de la bóveda principal conservan su ruta de
siempre (nada de lo que ya existía cambia: espejo del móvil, digests, enlaces). Las de
una carpeta local llevan su prefijo (`@apuntes/clientes/acme.md`), y sus agrupaciones
también (`@apuntes/clientes`).

- **`@` es el único prefijo que pasa por todos los validadores sin tocarlos**
  (Rust, `notePaths.ts`, `note_editor.dart`) y no altera la detección de `privado/`.
  `:` es inválido en NTFS y lo rechazan los diálogos; un `_ext/` sería indistinguible
  de una carpeta real.
- **`locate(ruta virtual)` es la costura central**: sustituyó a la raíz única en unas
  veinte funciones. Todo lo que recibe una ruta pasa por ahí, y por eso las
  herramientas MCP con `path` aceptan `@id/…` sin cambios.
- En la bóveda principal, **una carpeta de primer nivel que empiece por `@` se salta**
  al recorrer, igual que las ocultas: chocaría con el prefijo.
- `vault_role` y `group_of` miran el primer segmento, así que reciben la ruta **sin**
  prefijo; si no, `@apuntes/diario/x.md` perdería su rol de diario.

**Enlaces, la parte fina.** Dentro de una carpeta se escriben **relativos a ella**
(`[[clientes/acme]]`), para que esa carpeta se siga abriendo bien en Obsidian; entre
carpetas, con el prefijo. `link_form` (Rust) y `linkForm` (página) deciden la forma, y
la usan el orquestador, el autocompletado y la reescritura al mover.
`resolve_link_from(target, source)` resuelve **desde la nota que enlaza**: primero su
propia carpeta, después la principal por ruta exacta; un nombre suelto sigue la regla de
Obsidian (único en todo, o no resuelve). Por eso el trait `EditorBackend::resolve_link`
recibe la nota de origen, y un enlace a una nota que no existe la crea **en la carpeta
de quien enlaza** (`in_folder_of` en `session.rs`). El orquestador busca la nota de
proyecto (`hub_for`) **dentro de la carpeta de la nota**.

**Mover entre carpetas no puede ser un `rename`**: pueden estar en discos distintos, y
entre volúmenes no funciona. Se copia, se relee, se compara el sha256 y **solo entonces
se borra el original**; si no coincide, se borra la copia y el original no se toca. Sin
agrupación, entre carpetas **conserva su ruta**: quien lleva una nota a otra carpeta
quiere llevarla tal cual, no que caiga en un `inbox/` que esa carpeta quizá ni tenía. La
papelera va dentro de cada carpeta (`<carpeta>/.trash`), y la regla de "propuesta
pendiente" filtra por proyecto.

**La regla del buzón y los solapamientos** (`folder_problems`, dentro de
`InboxConfig::problems()`, así que vale también para quien edite el JSON a mano). Una
carpeta local se rechaza si **es** la raíz de un proyecto de documentación, **la
contiene**, o **contiene alguno de sus documentos** (decisión del usuario: no dejarla
añadir). Una carpeta de notas dentro del repo que no pisa ningún documento sí vale.
Ninguna carpeta de notas puede estar dentro de otra, principal incluida: las notas
saldrían dos veces.

- **Se compara por componentes y nunca por prefijo de texto**: si no,
  `ExampleApi2` pasaría por hija de `ExampleApi`.
- **Se canonicaliza antes**, por los junctions.
- **Dart no valida nada de esto**: añade la carpeta al JSON y es Rust quien la
  rechaza al guardar, con el motivo. Dos criterios acabarían discrepando.

**En la interfaz:**

- **El árbol va sin filtro; con un filtro de agrupación, la lista plana**: una
  agrupación ya es una sola carpeta. Carpetas primero, orden natural sin distinguir
  mayúsculas, **ordenado a propósito en cada nivel**: el índice ordena por fecha y el
  disco no garantiza orden. La rama que contiene la nota abierta se abre sola.
- En la página lo abierto se guarda en la clase (`openFolders`, `closedRoots`) y no en
  el DOM, porque `render` redibuja con `replaceChildren` en cada foto de la bóveda.
- **"Abrir en Obsidian" y "Abrir el fichero" usan la ruta real** que da Rust
  (`NoteDetails.realPath`): componer la raíz principal con una ruta virtual apuntaba a
  un fichero que no existe.
- Una carpeta **no disponible** (disco desconectado) sale con su etiqueta y sin notas; no
  tumba nada. No se ofrece como destino de "Mover a…".
- **Fallo que casi entra:** `readVaultSettings` y `writeVaultFolder` tomaban "el primer
  proyecto `vault`" como bóveda, y una carpeta local también lo es. Cambiar la bóveda
  habría acabado moviendo una carpeta local. Hay un test que lo fija.

**Móvil: sin cambios de protocolo.** El cable no interpreta la ruta: el espejo la usa
como clave. `vault_manifest` recorre todas las raíces con rutas virtuales, y quitar una
carpeta la saca del manifiesto: el móvil borra sus copias limpias y conserva las que
tenían cambios sin mandar (regla ya existente de `planNoteSync`).

**MCP.** `list_note_groups` enseña también las carpetas (solo si hay alguna local),
`create_note_group` y `move_note_to_group` aceptan `folder`, y un `group` con prefijo
(`@apuntes/clientes`, tal como lo da el listado) se parte en carpeta y agrupación.
**Añadir o quitar carpetas NO está en el MCP, a propósito**: sería darle a un agente la
capacidad de convertir cualquier carpeta del disco en notas que lee, sincroniza al móvil
y reescribe.

## Ventana de notas: CodeMirror 6 en una ventana WebView2 propia

Las notas de la bóveda se leen, se buscan y se escriben en **una ventana nativa
aparte**, que se maximiza y minimiza sin tocar la de NexoDeck:

- **A la izquierda:** búsqueda en notas, hallazgos y commits, y las pestañas
  Notas, Tareas y Asistente.
- **En el centro:** el editor, o una bienvenida si no hay nota abierta.
- **A la derecha:** el panel de la nota, con su esquema, quién la enlaza, qué se le
  parece y lo que hizo el asistente con ella.

El botón "Notas" de la barra (y "Más" → "Notas…") abre esa ventana con
`openNotes` (`notes_dialog.dart`). **El diálogo de Flutter queda solo como plan
B**, sin WebView2: Linux, o Windows 10 sin runtime.

**Editar no pasa por la IA ni por el buzón**: es el usuario escribiendo, y por eso
también se editan las de `privado/`. Procesar una nota sí pasa por el buzón, como
siempre.

| Pieza | Dónde |
|---|---|
| Abrir, guardar con hash base, crear, nota del día | `nexodeck-docs/src/notes/editing.rs` |
| La página (TypeScript, CodeMirror 6, iconos Lucide) | `core/crates/nexodeck-editor/web/` |
| Barra lateral, panel de la nota, bienvenida, traza de un digest | `web/src/{sidebar,contextPanel,welcome,digestView}.ts` |
| El bundle embebido (commiteado) | `core/crates/nexodeck-editor/assets/` |
| El protocolo JSON, gemelo de `web/src/protocol.ts` | `nexodeck-editor/src/protocol.rs` |
| Qué hacer con cada mensaje, sin ventana | `nexodeck-editor/src/session.rs` |
| El hilo de tao, la ventana y el WebView | `nexodeck-editor/src/host.rs` |
| Puente y backend sobre `nexodeck-docs` | `nexodeck-ffi/src/api/editor.rs` |

### Si tocas `web/`, reconstruye y commitea `assets/`

`dart run melos run editor:build` (hace `npm ci` y esbuild). El binario embebe
`assets/` con `include_bytes!`, así que `flutter build` no necesita Node. La
contracara es que **un cambio en `web/` sin reconstruir no llega a la app**, y no
falla nada. `node_modules/` está en `.gitignore`. Tests de la página:

**Y son DOS pasos, no uno.** `editor:build` corre `build.mjs`, que deja el bundle
en `nexodeck-editor/assets/` — el de la **ventana de escritorio**. La copia en
línea que usa el **móvil** (`app/assets/editor/editor.html`, un solo fichero con
todo incrustado) la genera `node web/inline.mjs`, y `editor:build` **no la toca**.
Olvidarlo tiene el mismo síntoma mudo que lo anterior, un escalón más abajo: el
cambio llega al escritorio, no llega a Android, y nada falla. Pasó al cambiar el
texto de la bienvenida: `editor.js` traía el texto nuevo y `editor.html` seguía
con el de la víspera. Para comprobarlo, `grep` del texto en los dos ficheros.
- `npm test` (vitest);
- `npm run typecheck`.

### Por qué wry y no un plugin de Flutter

- **Los plugins de WebView de Flutter para Windows pintan la web como textura y
  reenvían el teclado**, que es donde se rompen las tildes, las teclas muertas, el
  IME y el corrector.
- **Con `wry` el WebView2 va en una ventana nativa real** y todo eso funciona como
  en Edge.
- **Está verificado dentro de la app** (paso 0): se abre desde un hilo de frb y se
  escribe "ñandú acción ¿qué pasó?" con teclas muertas reales.

### Cosas que no son obvias

- **El event loop de tao se crea una vez y no termina nunca.**
  - tao no deja recrear el event loop en un proceso, y en Windows que `run`
    termine **cierra el proceso entero**, o sea NexoDeck.
  - Vive en su propio hilo (`with_any_thread`), se arranca la primera vez que se
    abre la ventana, y cerrar la ventana solo destruye la ventana.
- **Nunca se pisa lo que cambió por fuera.**
  - Cada guardado lleva el hash con el que se abrió. Si en disco hay otra cosa
    (Obsidian, una propuesta aprobada), no se escribe: la página enseña una banda
    para elegir, y el guardado automático se para hasta que el usuario decide.
  - Una nota borrada por fuera también es conflicto: guardar a ciegas la
    resucitaría.
- **Cerrar o cambiar de nota con cambios pendientes** manda `requestClose`. La
  página guarda y contesta `closeReady`, y solo entonces se destruye la ventana o
  se carga la otra nota.
  - Una segunda X pasados 5 s cierra igual: una página colgada no puede dejar la
    ventana abierta para siempre.
- **La lógica vive en `session.rs` y devuelve efectos**, que `host.rs` aplica.
  Es lo que permite probar guardado, conflicto y cierre con un backend falso: la
  ventana no se puede probar sin escritorio.
- **Lo lento va en otro hilo** (`Effect::Fetch` con un `Job`): la foto de la
  bóveda, la búsqueda, el detalle de una nota y mandarla al asistente.
  - Recorren el índice, y cada 10 minutos corren `git log`: en el hilo de la
    ventana la congelarían.
  - Abrir, guardar y crear sí van en el hilo de la ventana: son un fichero.
  - Los destinos de `[[` salen de la misma foto de la bóveda; no hay una lectura
    aparte.
- **Las lecturas de la bóveda no se amontonan.**
  - Cada guardado avisa de un cambio. Con una lectura en marcha, solo se apunta que
    hace falta otra, y se hace una sola al terminar (`overview_busy` /
    `overview_again`).
  - Sin esto, escribir seguido lanzaba una lectura entera de la bóveda por segundo.
- **El detalle que llega tarde se tira.** Si mientras se leía el detalle de una nota
  ya se abrió otra, no se enseña.
  - Una nota privada no está en el índice y su detalle falla: el panel se vacía en
    vez de seguir con el de la anterior.
- **La lista no se redibuja si la foto no cambió** (compara el JSON). Cuando sí
  cambia, conserva el scroll y no repite la animación de entrada: la foto llega con
  cada guardado, y la lista bailaría mientras se escribe.
- **Los atajos del navegador están apagados** (`with_browser_accelerator_keys(false)`):
  - Ctrl+P es la paleta, no imprimir;
  - Ctrl+F busca con CodeMirror;
  - F5 no recarga la página a mitad de una nota.
- **Solo la página propia habla con Rust.**
  - La navegación a cualquier otro origen se bloquea, y el IPC comprueba el
    origen.
  - Los enlaces web salen por `explorer.exe` (nunca `cmd /c start`: un `&` sería
    otro comando).
  - Un `file:` o `javascript:` escrito en una nota no abre nada.
- **La carpeta de datos de WebView2 va a `data_local_dir`**, no junto al exe (en
  una instalación para todos los usuarios no se puede escribir) ni a la itinerante
  (es caché del navegador).
- **La ventana se refresca con los avisos del buzón.**
  - `api/editor.rs::watch_docs` tiene un hilo con `blocking_recv` sobre
    `DocsService::subscribe`, y cada aviso llama a `Editor::changed`. Así llegan
    una nota guardada, un digest que avanza o una propuesta aprobada en la app.
  - Un hilo propio y no tokio: el editor no vive dentro de un runtime.
  - Al volver el foco a la ventana también se relee, si pasaron 20 s. Una nota
    creada en Obsidian no avisa a nadie.
- **Las propuestas se aprueban en la app, no en la ventana.**
  - "Ver la propuesta en el buzón" manda `showInbox`, que llega a Dart como evento
    `show_inbox`.
  - `notesInboxOpenerProvider`, que pone `main()`, trae al frente la ventana
    principal y abre el buzón con `rootNavigatorKey`.
  - El controlador no puede abrir diálogos: no tiene `BuildContext`.
- **La ventana recuerda tamaño, posición y si estaba maximizada**, pero solo
  mientras NexoDeck siga abierta: se guarda en memoria al cerrarla.
  - La posición se descarta si no cae al menos 160×80 px en un monitor conectado,
    el mismo criterio que `isWindowRectUsable`.
  - La primera vez ocupa el 86 % del monitor principal, con tope de 1480×940.
- **El crate solo compila con ventana en Windows**
  (`[target.'cfg(windows)'.dependencies]` en `nexodeck_ffi`, mismo gotcha que
  `nusb`). `protocol.rs`, `assets.rs` y `session.rs` compilan en todas partes
  para que sus tests corran.
- **WebView2 Runtime viene con Windows 11 y el instalador no lo trae.** Sin
  runtime, `editor_availability` da el motivo y el diálogo cambia los botones por
  un aviso.

Tres fallos que no pilló ningún test y sí la prueba con la app. Si tocas algo de
esto, vuelve a mirarlo en pantalla:

- **Cada zona del grid de `.app` lleva su `grid-row` fijo.** La banda de conflicto
  se oculta con `hidden`, que es `display: none` y la saca del grid. Sin el
  `grid-row`, todo sube una fila y la barra de estado se queda con el `1fr`: el
  editor acaba a media ventana.
- **Los botones de la banda devuelven el foco al editor** (`view.focus()`). Al
  elegir, la banda se esconde y el botón con el foco desaparece, así que lo que se
  escribía después no llegaba a CodeMirror, sin ningún aviso.
- **Lezer no sabe de frontmatter.** `date: 2026-09-15` seguido del `---` de cierre
  es para él un encabezado Setext H2. Todo lo que recorra el árbol buscando
  encabezados salta lo que quede antes de `frontmatterEnd`: la vista previa y el
  esquema.

Para ver la ventana sin Flutter:
`cargo run -p nexodeck-editor --example open_note -- <carpeta> [nota]`. Usa un
backend de juguete sobre la carpeta: sin asistente, y con búsqueda por texto
literal. Por stdin acepta `open <nota>`, `show`, `changed`, `close` y `quit`.

Fuera de WebView2 (sin `window.ipc`) la página carga datos de muestra (`demo()` en
`main.ts`), lo que sirve para trabajar el diseño en un navegador.

## Notas en el móvil (en curso)

El objetivo, decidido con el usuario: en Android la sección de notas es **la misma
página** en un WebView, **la PC sigue siendo el motor** (dueña de la bóveda, del
índice y de los agentes), y el móvil funciona **entero sin conexión** —ver, editar,
crear y borrar— sincronizando solo al reconectar. Da igual el camino: WiFi,
dirección manual por Tailscale o túnel por relay; una vez hay sesión, mandar es lo
mismo.

**Dos decisiones que ya están tomadas y condicionan el resto:**

- **La página del móvil lee y escribe SIEMPRE contra la copia local**, y un motor
  aparte sincroniza. Con conexión el cambio sale hacia la PC en el acto; sin ella
  espera en la cola. Así hay un solo camino, en vez de uno con red y otro sin ella
  que se prueba la mitad.
- **La copia del móvil es la bóveda entera, `privado/` incluido**, y un choque
  **nunca pisa nada**: si la nota cambió en los dos sitios, se conservan las dos y
  elige el usuario.

### La bóveda para un cliente que guarda copia (`notes/sync.rs`)

- **No es el índice, y no puede serlo.** El índice es lo que ven los agentes y
  salta `privado/` a propósito (`notes/index.rs`). La sincronización lleva las
  privadas, así que tiene su propio recorrido; lo que sigue fuera son las carpetas
  ocultas (`.obsidian`, `.git`, `.trash`) y los enlaces simbólicos.
- **El manifiesto va aparte del texto.** `vault_manifest()` devuelve ruta, hash y
  fecha de cada nota: es pequeño, se pide seguido, y el texto solo se pide de lo
  que de verdad cambió.
- **Borrar es mover a `.trash/`** (`delete_note`), no borrar de verdad. Empieza por
  punto, así que lo borrado desaparece del índice, de las búsquedas y del propio
  manifiesto, pero se recupera a mano. Un borrado que llega de un móvil que estuvo
  sin cobertura no puede ser irreversible.
- **Borrar dos veces no falla**: la segunda vez contesta `Missing`, y si ya había
  algo con ese nombre en la papelera, la nueva entra como `nota (2).md`. Un cliente
  que reintenta tras quedarse sin señal tiene que poder terminar.
- **Borrar respeta el hash**, igual que guardar: con `base_hash`, si alguien editó
  la nota mientras tanto, se contesta `Conflict` y no se toca el disco.

### El contrato con el móvil (`nexodeck-protocol`)

Tres variantes al final de `MessageV1`, con sus enums internos
(`NotesRequestWire`, `NotesResponseWire`, `NoteOpWire`, `NoteOpResultWire`),
mismo criterio que `AiChatEventWire`: lo que crece es el enum interno, no
`MessageV1`.

- **`NotesRequest` lleva `request_id`, y es el primer sitio del protocolo que lo
  necesita.** El resto se apaña con ids de dominio (`action_id`, `run_id`) o son
  empujes sin respuesta. Aquí no: el teléfono puede tener varias peticiones en
  vuelo a la vez —el manifiesto, el texto de unas notas, y la tanda que tenía
  encolada sin cobertura—. El id lo genera quien espera, que es el teléfono.
- **`NotesResponse` llega siempre, también cuando falla** (`Failed`). Un teléfono
  esperando sin respuesta no distingue "todavía no" de "nunca", que es la misma
  lección que ya dejó escrita `nexodeck-control/src/outbox.rs`.
- **`NotesChanged` no lleva el cambio, solo el aviso.** Mandar el contenido
  obligaría a la PC a saber qué tiene ya cada teléfono y a los dos a acordar el
  orden de los avisos; con el manifiesto, quien compara es siempre el que tiene
  la copia.
- **Los cambios viajan en tanda y en orden** (`Apply { ops }`), porque es lo que
  el teléfono tenía encolado: aplicar la mitad dejaría su copia diciendo algo
  distinto de la bóveda. Y se piden varios textos juntos (`Fetch { paths }`)
  porque una petición por nota multiplicaría las idas y vueltas justo en el
  enlace más lento, que son los datos móviles.
- **Un choque nunca escribe**: `NoteOpResultWire::Conflict` viaja con el texto y
  el hash que hay en disco, para que el teléfono conserve las dos versiones.

### La PC atiende al teléfono (`nexodeck-transport/src/notes.rs`)

- **El transporte NO puede depender de `nexodeck-docs`**, porque también se
  compila para el `.so` de Android y ese crate arrastra `nexodeck-ai` (pila HTTP
  y sidecar del modelo). Mismo gotcha que `nusb` y `arboard`.
- Por eso la bóveda **se engancha en tiempo de ejecución**: el transporte define
  el trait `NotesVault`, y la FFI —que sí es de escritorio— registra su
  implementación con `set_notes_vault`. Mismo patrón que
  `nexodeck_control::control().set_docs(...)`.
- **Se registra en dos sitios a propósito** (`docs_inbox_init` y
  `start_transport_host`): cuál de los dos arranca antes no está garantizado, y
  sin eso el teléfono podría pedir notas a un host sin bóveda.
- **Sin bóveda enganchada se contesta `Failed`, nunca silencio.** Un teléfono
  esperando sin respuesta no distingue "todavía no" de "nunca".
- **Las lecturas van a `spawn_blocking`.** Recorrer la bóveda o guardar una tanda
  es lento y síncrono; dentro del `select!` de la sesión dejaría al teléfono sin
  snapshots ni acks mientras dura. La respuesta sale por el canal de salida de la
  sesión, que es quien serializa los envíos.
- **`notify_notes_changed()` recorre las sesiones vivas.** Los teléfonos que no
  estén conectados se enteran al reconectar, que es cuando piden el manifiesto de
  todos modos.

### La copia local del móvil (`note_mirror`, `note_outbox`, schemaVersion 13)

Dos tablas de Drift y un motor que las sincroniza. El espejo es lo que el
teléfono tiene de cada nota; la cola, lo que escribió y la PC todavía no sabe.

- **Guardar escribe en las dos, en la misma transacción.** Solo lo primero y el
  teléfono enseñaría algo que la PC nunca va a saber; solo lo segundo y la
  pantalla no reflejaría lo que el usuario acaba de escribir.
- **Nada se da por entregado hasta que la PC lo confirma.** La fila sale de la
  cola al recibir el resultado, no al mandarlo: si la sesión se cae en medio, el
  cambio sigue ahí y se reintenta. Repetir un guardado idéntico no hace daño,
  perderlo sí. Es la regla de `nexodeck-control/src/outbox.rs`.
- **El `localHash` del espejo NO es el hash de la PC, y no puede serlo.** Allí es
  el sha256 del fichero tal como está en disco, con su BOM y sus CRLF
  (`notes/editing.rs`); el teléfono solo tiene el texto con `\n`. El de aquí
  (`localNoteHash`, FNV-1a) solo sirve para una cosa: saber si lo que hay en el
  espejo es lo que llegó de la PC o algo que escribió el usuario. Los dos campos
  se llaman "hash" y viven en la misma fila, así que es fácil creer que son
  comparables. No lo son, y por eso tampoco se añadió `crypto` como dependencia.

El orden de una vuelta de `NotesSyncEngine` no es casual:

1. **Primero se vacía la cola.** Así el manifiesto que llega después ya incluye
   esos guardados y no se piden de vuelta para nada.
2. **Después el manifiesto**, que se compara con el espejo (`planNoteSync`, pura
   y testeada).
3. **Al final los textos** de lo que de verdad cambió, en lotes de 40: la bóveda
   entera en una petición sería un mensaje de megabytes por datos móviles, y de
   una en una serían mil idas y vueltas.

- **El motor vive fuera del árbol de widgets**, arrancado en `main()` como
  `HostRuntime`. Lo que se escribió sin cobertura tiene que salir en cuanto haya
  sesión, esté o no montada la pantalla de notas.
- **Cada petición se correlaciona por `request_id`**, con espera propia y tope de
  30 s. Al desconectar se fallan las que estaban en vuelo: dejarlas colgadas
  hasta el tope retrasaría la vuelta siguiente justo cuando vuelve la conexión.
- **Una nota sucia que desapareció de la PC no se borra del espejo.** Borrarla
  tiraría lo que el usuario acaba de escribir; su guardado pendiente la recrea.
- **Una nota cambiada en los dos sitios se pide igual.** Es el choque, y para
  conservar las dos versiones —lo que pidió el usuario— hace falta tener delante
  la de la PC. Quién gana lo decide él, con `keepMine` / `takeHost`.
- **Un choque al borrar no enseña nada al momento**: la fila del espejo ya no
  existe, así que `recordConflict` no tiene dónde escribir. La nota vuelve sola
  en el `_pullChanges` de esa misma vuelta, porque sigue en el manifiesto y no en
  la copia.
- **Los `switch` sobre `ConnectionEvent` de `host_runtime.dart` y
  `connected_device_screen.dart` hubo que ampliarlos.** Son exhaustivos, así que
  añadir variantes al enum los rompe en tiempo de compilación — que es
  justamente lo que uno quiere: nadie se traga un evento nuevo en silencio.

### Paso 0: CodeMirror dentro del WebView de Android (verificado en un Armor X12)

Se probó con la app real en un teléfono de 32 bits con Android 13, y **funciona**:
la página se dibuja, ejecuta JavaScript y el teclado llega. Lo que costó llegar:

- **El plugin es `webview_flutter`, el oficial.** El otro candidato lleva casi dos
  años sin versión estable. Pide `minSdk 24`, que es justo el de Flutter por
  defecto (`FlutterExtension.kt`), así que no hubo que subir nada.
- **La página va en un solo fichero** (`web/inline.mjs` → `app/assets/editor/editor.html`),
  con estilos y bundle incrustados. 841 KB en una sola cadena no son problema para
  `loadHtmlString`, que era la duda principal.
- **Ese fichero se genera entero, nunca parcheando `index.html` con expresiones
  regulares.** El primer intento lo hizo así y falló en silencio: el `<meta>` de la
  CSP y el `<link>` están repartidos en varias líneas, no casaron, y quedó una
  página con el bundle incrustado, sin estilos y con un `<link>` roto. El WebView
  la pintó **como texto**, con el JavaScript a la vista.
- **La CSP por `<meta>` no se aplica por este camino.** Android avisa de que llegó
  "fuera del `<head>`" y la ignora; el documento queda en `about:blank`, sin
  contexto seguro. Si esto va a producción, la página debería servirse por un
  origen propio (como hace la ventana de escritorio) en vez de incrustarse.
- **`process is bad` en los procesos aislados del WebView era arrastre, no la
  causa.** Android marca así un proceso tras varios arranques fallidos, y el aviso
  siguió apareciendo incluso desinstalando; desapareció solo cuando el HTML dejó de
  estar roto. Antes de investigar eso, comprobá que la página en sí es válida.
- **Los `SandboxedProcessService` no se declaran en el manifiesto de la app**: los
  aporta el paquete del WebView. Que no aparezcan en el APK es normal.
- **Sin verificar todavía**, porque necesita dedos humanos: tildes con teclas
  muertas, el corrector, colocar el cursor y seleccionar tocando.

### La pantalla de Notas del móvil (`MobileNotesScreen`)

Botón "Notas" en la barra de `ConnectedDeviceScreen`. Petición del usuario: **lo
básico en el móvil**. Se puede ver la lista en árbol, buscar, abrir, editar, crear,
abrir la nota del día, ver las tareas y seguir `[[enlaces]]`. **Quedan fuera
importar, exportar, las carpetas y el asistente**, que son de la PC. La página ni
los enseña.

| Pieza | Dónde |
|---|---|
| Pantalla con el WebView, tema, atrás de Android, franja de sincronización | `app/lib/features/notes/presentation/mobile_notes_screen.dart` |
| Quien contesta a la página (el `session.rs` del móvil) | `application/mobile_notes_host.dart` |
| Foto, búsqueda, enlaces entrantes, resolver enlaces (puro, testeado) | `domain/mobile_notes_page.dart` |
| Leer del espejo y escribir por el motor | `data/drift_mobile_notes_store.dart` |
| Modo táctil de la página | `data-mobile` en `web/src/main.ts`, `styles.css` (sección "móvil") |

- **La página es la misma; quien contesta cambia.** En la PC contesta Rust sobre la
  bóveda. En el teléfono contesta Dart **contra la copia local** (`MobileNotesHost`),
  con el mismo JSON de `protocol.ts`. Así se cumple la decisión de funcionar entera
  sin conexión: la página nunca espera a la PC.
- **El canal es `window.nexodeckIpc`**, un `JavaScriptChannel` que Android pone en la
  página antes de sus scripts. `bridge.ts` lo usa si no hay `window.ipc` (wry), y
  eso mismo activa el modo móvil (`isMobileHost`). `?mobile` en la URL lo fuerza en
  un navegador para trabajar el diseño.
- **Una cosa a la vez.** La lista va a pantalla completa y, al abrir una nota, la
  nota. El botón de la lista y el **atrás de Android** vuelven: la página expone
  `window.nexodeck.back()`, que la pantalla consulta en `PopScope`. Desde la lista,
  atrás sale de Notas.
- **Al abrir una nota no se enfoca el editor**: el teclado taparía media nota que se
  venía a leer.
- **Lo que el móvil hace más simple que la PC, a propósito:**
  - la búsqueda es por texto, sin tildes ni mayúsculas, y solo en notas (hallazgos y
    commits viven en la PC);
  - las agrupaciones salen con el color neutro, porque el catálogo de nombre y color
    está en la configuración de la PC y no viaja;
  - una carpeta local se enseña con su id, porque su nombre tampoco viaja.
- **Conflictos, con la misma banda.** Una nota con choque en el espejo carga con la
  banda "quedarme con lo mío / recargar". Mientras no se resuelva no se escribe
  nada, ni con el guardado automático. "Quedarme con lo mío" llega como guardado
  `overwrite` (→ `keepMine`); "recargar" manda `conflictResolved` (→ `takeHost`).
  Ese mensaje es nuevo en el protocolo, y **la PC lo ignora**: allí "recargar del
  disco" ya es lo que hay en disco.
- **Si la PC cambia la nota abierta** y aquí no hay nada sin guardar, se recarga
  sola con un aviso. Con cambios sin guardar no se toca: al guardar, el motor
  reconcilia o marca el choque.
- **La franja de arriba** dice si hay conexión con la PC y cuántos cambios esperan.
  Sin ella, escribir sin cobertura se vería igual que con cobertura, y el usuario
  no sabría si la PC ya lo tiene.
- **Un solo motor.** `main()` guarda el `NotesSyncEngine` en
  `notesSyncEngineProvider` y la pantalla escribe por él: dos colas mandarían lo
  mismo dos veces.
- **Un fallo que salió en la captura:** la fila de herramientas de formato mide
  ~810 px y ensanchaba la rejilla de `.app`, así que la nota entera quedaba más
  ancha que el teléfono y el texto se cortaba. `.app[data-mobile]` fija la columna
  a `minmax(0, 1fr)`, y las herramientas se deslizan dentro de su fila.
- **Para verlo sin teléfono:** Edge sin interfaz sobre
  `core/crates/nexodeck-editor/assets/index.html?mobile` con `--window-size=412,860`.
  Ojo, la captura sale recortada: en ese modo el viewport mide ~492 px aunque la
  ventana diga 412. Se comprueba midiendo con `getBoundingClientRect`, no a ojo.
- **Sin verificar en un teléfono**, y los enlaces web de una nota todavía no abren
  nada en el móvil: la navegación del WebView se bloquea a propósito y no hay
  `url_launcher`.

## «Configura tus perfiles»: la config del asistente es un manifiesto del stack

La config del asistente tiene **una sola seccion** en vez de dos. Antes eran
«Quien puede contestar» (`destinations_section.dart`) y «Elegi el modelo»
(catalogo de llama.cpp por gamas). Hoy es `profiles_section.dart`, que reemplaza
a las dos dentro de `ai_setup_wizard.dart::_Chooser`.

**PERFIL A y PERFIL B** son los del stack vLLM (`features/stack/`), no un
concepto nuevo. Cada perfil tiene dos slots:

- **Router** (liviano) y **Pensamiento** (pesado).
- Cada slot sale de un motor, y el catalogo es **por motor**: un rol del stack
  (`models.json`), un modelo de llama.cpp (los `AiModelOption` de siempre), uno
  de Ollama, la sesion de Claude Code, o un servicio por internet.

### Piezas (que toca cada archivo)

Lo que se creo en esta sesion, para no re-descubrir donde vive nada:

| Pieza | Donde | Que hace |
|---|---|---|
| Config del dialogo | `presentation/profiles_section.dart` | La seccion; reemplaza a `destinations_section.dart` (**borrado**) |
| Selector por motor | `presentation/widgets/model_picker_sheet.dart` | Bottom sheet con catalogo por motor + descarga inline de llama.cpp |
| Tira de motores | `presentation/widgets/engine_strip.dart` | llama.cpp / Ollama / vLLM y su estado |
| Servicio por rol | `presentation/profile_remote_dialog.dart` | Hermano de `remote_provider_dialog.dart`, con clave por slot |
| Dominio | `domain/ai_profile.dart` | `ProfileSlot`, `AiProfileConfig`, `AiProfilesConfig` (encode/decode tolerante) |
| Repositorio | `data/stack_catalog_repository.dart` | Lee/escribe `models.json`/`profiles.json`; detecta `~/models` en WSL |
| Controlador | `application/ai_profiles_controller.dart` | Estado + guardar + detectar; `aiProfilesProvider` |
| Activacion | `profiles_section.dart::activateProfile` | Levanta el rol de pensamiento (stack/llama.cpp/Ollama/remoto/Claude Code) |
| Wizard | `presentation/ai_setup_wizard.dart` | Reescribio `_Chooser`: `HardwareSummaryCard` + `ProfilesSection` + pie de llama.cpp |
| Distro | `features/stack/application/stack_controller.dart` | `stackDistroProvider` (default `Ubuntu`), persistido y leido en `main()` |
| Test | `test/ai_profile_test.dart` | Encode/decode + repositorio con ficheros temporales |
| Rust | `nexodeck-ai/src/engine.rs` | `Engine::download_model` (descarga sin arrancar `llama-server`; `prepare_installed` compartido) |
| Rust | `nexodeck-ai/src/remote.rs` | `api_key_path()` publico |
| FFI | `nexodeck-ffi/src/api/ai.rs` | `download_ai_model`, `ai_remote_key_path` (bridge regenerado) |
| Pasarela | `llm-stack/gateway/src/config.rs` | `BackendConfig`/`BackendDetails` (cadena u objeto) |
| Pasarela | `llm-stack/gateway/src/proxy.rs` | Config tras `RwLock` + `maybe_reload`, swap de `Authorization`, `upstream_model`, externos sin sondear |

`model_choice_card.dart` quedo **sin uso** al reescribir el wizard; se dejo por
si se reutiliza, no lo importa nadie.

### `profiles.json` es la fuente de verdad

`StackCatalogRepository` (`features/ai_assistant/data/`) lee y escribe
`profiles.json` en la carpeta del stack (`stackScriptsDirProvider`), y
`serve-profile.sh` lo lee por `profile-roles.py`. **Sin el fichero vale el mapeo
historico** (A: router+fast, B: router+complex), asi que una instalacion vieja
arranca igual. Un slot con `source` distinto de `stack` no lo sirve vLLM.

`models.json` se enriquecio con `display_name`, `notes`, `size_gb`, `vram_gb` y
`context`:
son lo que muestra la tarjeta de cada modelo. La estructura `models` +
`alternatives` no se toco (`list-models.py` y `download-models.sh` la usan).

Cosas que no son obvias:

- **La deteccion corre sola al entrar, pero NO arranca WSL2.** El usuario lo
  tiene configurado para que arranque solo con funciones de IA. La tira de
  motores lee llama.cpp (nativo), Ollama (HTTP en loopback) y vLLM
  (`stackHealthProvider`, `:8888`). Los descargados en `~/models` se consultan
  al montar `ProfilesSection` (`initState` → `detectInstalled`), **sin boton**:
  si la distro esta apagada se dice sin levantarla, que es lo que hace barato
  mirar de entrada.
- **Descarga inline solo en llama.cpp** (`downloadAiModel`, que descarga **sin**
  arrancar `llama-server`). Ollama (`ollama pull`) y vLLM (`download-models.sh`
  en WSL) van por el runner capturado y su progreso sale en el panel de
  Ejecuciones.
- **Claude Code es un slot, no un modelo.** Sale por el puente de siempre
  (`kClaudeCodeBackendId`); la pasarela no puede enrutarle.
- **El servicio por internet se puede elegir en cualquiera de los dos slots, y
  lo detectado usa la clave GLOBAL del preset.** Históricamente la clave se
  guardaba por slot (`providerId` = `remote:<perfil>.<slot>`), y eso hacía que la
  `deepseek.key` que el usuario ya tenía **no apareciera**: el diálogo buscaba
  `remote_A_router.key`. Ahora el selector lista los servicios con clave
  guardada y, al elegirlos, el `ProfileSlot` usa el id **global** del preset
  (`deepseek`), así que la misma clave sirve para el router y el pensamiento sin
  copiarla. La detección no necesita una función nueva en el puente: se prueba
  `aiRemoteKeyPath` por preset y se mira si el fichero existe
  (`AiRepository.remoteKeyIdsWithSavedKey`). El diálogo por slot, si el slot no
  tiene clave propia, **reusa la del preset** en vez de pedirla de nuevo.
- **Cada modelo del stack dice para qué slot es ideal** (`stackRoleFitsSlot`,
  pura): el rol `router` es el liviano, y `fast`/`complex`/`writer` son
  trabajadores. El apto para el slot que se está eligiendo se resalta; el que no,
  sigue siendo elegible pero queda neutro.
- **La VRAM se valida al configurar, no al arrancar.** Cada rol del stack trae su
  huella (`vram_gb` en `models.json`, calibrada para que las sumas den los totales
  medidos de los perfiles: A 15.5, B 14.9, C ~12 GiB). `stackRolesVramGb` la suma
  contando cada rol **distinto** una sola vez (el perfil C es `writer` en los dos
  slots y se sirve una vez), y `stackSelectionFitsVram` **bloquea en el selector**
  el modelo que no cabe junto al del otro slot. El presupuesto es la VRAM de la
  GPU que detecta `aiVramBudgetProvider`; sin GPU o sin probe (`budgetGb == 0`) no
  se bloquea nada, que es mejor que inventar un límite. La tarjeta del perfil
  muestra la suma (`VRAM estimada: 15.5 / 15.9 GiB`).
- **Un perfil sin ningún rol local para el stack.** Si los dos slots del perfil
  son de otro motor (nube, Ollama, llama.cpp, Claude), `activateProfile` no
  arranca vLLM: **para el stack** (`StackProfile.apagado`). Sin eso, los modelos
  que ya estuvieran cargados se quedan en la GPU —pasó: pasar el perfil C a
  DeepSeek dejó un `vllm-writer` ocupando 13 GiB y la pregunta «si elegí la nube,
  por qué usa mi VRAM»—, porque el «Levantar» solo tocaba el stack cuando el slot
  de Pensamiento era `stack`.
- **El menú de modo dice «Perfil A/B/C» y los modelos elegidos, en vivo.** El
  `label` de `StackProfile` es «Perfil A/B/C» (el enum conserva
  `rapido`/`contextoLargo`/`texto` porque se persisten: renombrarlos dejaría una
  selección guardada apuntando a la nada). El renglón de cada perfil **no** lleva
  los modelos de la receta: `ai_chat_view` le pasa a `ProfileSwitch` un `describe`
  que saca de `aiProfilesProvider` los modelos **elegidos** de cada slot (locales
  o de la nube, p. ej. «Router: DeepSeek · Pensamiento: DeepSeek»), así que se
  actualiza al cambiar un slot. El acoplamiento va de `ai_assistant` → `stack`
  (por el callback), nunca al revés.
- **El `MODO…` aplica el perfil ENTERO, no solo el stack.** `ai_chat_view` le pasa
  a `ProfileSwitch` un `onSelect` que llama a `activateProfile`: arranca/para
  vLLM **y** pone a contestar el motor del slot de Pensamiento (instalar un motor
  reemplaza el anterior, así que un perfil de nube **apaga el llama.cpp local** y
  libera su VRAM). Antes el switch solo hacía `stackController.select`, y elegir
  un perfil de nube dejaba el `llama-server` del motor local ocupando ~11 GiB —
  la confusión «si elegí la nube, por qué usa mi GPU». `activateProfile` también
  fija `chatBackendProvider` (`local:`/`ollama:`/`remote:`) para que la etiqueta
  del chat y el enrutado de `sendAiMessageBroadcast` coincidan. Son **dos
  sistemas**: los perfiles A/B/C (stack vLLM) y el **destino del chat** (quién
  contesta); `activateProfile` los sincroniza, el `MODO…` por sí solo no.
- **Al arrancar NO se levanta el motor local salvo que el destino sea local.**
  `_AiAssistantPanelState._autoStart` mira el **destino** del chat
  (`chatDestinationsProvider` + `chatBackendProvider`): si es nube/Ollama/Claude
  llama a `restoreDefault` y **no** arranca el `llama-server`; solo arranca el
  motor local (con el modelo del destino) cuando el destino es un modelo local.
  Antes era un `startSetup()` pelado: con un destino de nube cargaba el llama.cpp
  igual —11 GiB de VRAM de más— y encima reemplazaba el proveedor que el destino
  había puesto (el selector decía «la pasarela» pero el que corría era llama.cpp).
  Se espera a que el registro cargue (`registry.loading`) para no decidir con la
  lista vacía.
- **La distro de WSL es configurable** (`stackDistroProvider`, default `Ubuntu`):
  la deteccion y `serve-profile.sh` la usan por nombre. Se persiste en
  `app_settings` (`stack_distro`) y se lee en `main()` con `overrideWith`, mismo
  patron que la carpeta del stack.
- **Sin detectar, los slots dicen «Sin comprobar», no «Falta descargar».** El
  estado tiene un flag `detected`: afirmar que falta algo que no se miro es
  mentir. Aparecio en el E2E y se corrigio en las dos vistas (tarjeta y picker).
- **Un perfil cuyos modelos del stack no estan descargados no se muestra, y no
  se deja arrancar.** `AiProfilesState.isProfileRunnable` lo decide (todos sus
  slots `stack` con el dir instalado; un slot de otro motor no bloquea) y
  `profiles_section.dart` lo oculta — pero **solo con `detected`**: sin mirar
  WSL2 esconder los tres perfiles seria peor que mostrarlos «Sin comprobar».
- **El guard del lado del stack es `serve-model.sh`, no el perfil.** Antes de
  tocar Docker comprueba que `$MODELS_DIR/$MODEL_DIR` exista y no este vacio. Sin
  eso, un perfil sin bajar **arranca el contenedor igual** y muere a los 2-6 min
  con un `HFValidationError: Repo id must be in the form ...` criptico (vLLM
  trata la ruta inexistente como un repo de Hugging Face). El selector del stack
  trae un «Comprobar descargados» porque «Descargar» solo sale con
  `detected && falta`: sin ese boton, el camino para bajar el modelo no se veia.

### La pasarela reenvia a un remoto y recarga en caliente

Un backend de `gateway.json` acepta hoy una **cadena** (vLLM local, como
siempre) o un **objeto** `{url, api_key_file, upstream_model}`. Con
`api_key_file`, la pasarela lee la clave del fichero que Rust ya administra
(`ai_remote_key_path`, nunca la clave en `gateway.json`), **reemplaza** la
cabecera `Authorization` y reescribe el campo `model` con `upstream_model`. Un
backend externo **no se sondea** (puede no tener `/health` y gastaria cuota).
`build_app_with_reload` vigila el fichero y recarga, porque cambiar de perfil no
reinicia la pasarela.

### Verificacion

`flutter analyze` limpio (los 9 `info` de siempre), `flutter test` en verde
(490), y en la pasarela `cargo test` (53 unitarias + 37 de integracion, con una
que comprueba el cambio de clave y de modelo hacia un remoto de mentira).

**E2E contra el stack real (2026-09-25).** «Levantar» arranca WSL2 + vLLM y la
tira pasa a «cargados: Router · Gemma»; cambiar el Pensamiento del Perfil A a
`complex` por la UI y volver a levantar carga **Router + Complejo y no arranca
Gemma**. El reenvio por rol se probo contra DeepSeek con la clave que ya estaba
guardada (`ai/keys/deepseek.key`).

**Bug de TLS en la pasarela, corregido.** `reqwest` iba con
`default-features = false` y **sin** feature TLS, asi que un backend `https://`
(DeepSeek) daba 503 `backend_unavailable` al no poder abrir la conexion. Se
añadio `rustls` en `llm-stack/gateway/Cargo.toml`. Los backends locales son `http://` y no
la necesitan, pero cualquier servicio por internet si: no quitar esa feature.

### Lo que falta (no lo des por hecho)

**La app NO genera `gateway.json` a partir del perfil.** Es el unico hueco entre
la UI ya hecha y el reenvio real. Hoy «Levantar» escribe `profiles.json` y arranca
el stack, pero si un slot es un servicio por internet, la pasarela **no se entera**
de que ese rol va al remoto: el reenvio se verifico **escribiendo `gateway.json` a
mano**. Lo que falta es que la activacion escriba `gateway.json` mapeando cada slot
remoto a su rol:

- `backends[rol] = { url, api_key_file: ai_remote_key_path(providerId),
  upstream_model: remoteModel }` para un slot `source: remote`;
- los slots del stack siguen a los puertos locales (`8002` router, `8001` fast,
  `8000` complex);
- hay que decidir el directorio del gateway (`%LOCALAPPDATA%\nexodeck\LlmGateway\
  data`, o `NEXODECK_GATEWAY_DIR`, o `llm-gateway paths`).

La pasarela por su lado ya lo soporta y esta probada (`cargo test`), y la recarga
en caliente (`maybe_reload`) ya existe: al escribir el fichero, surte efecto sin
reiniciar la pasarela.

## Estado del proyecto

- **Fase 0 ("Cimientos")** completada: monorepo con Melos/pub workspaces,
  Cargo workspace de 7 crates, proyecto Flutter multiplataforma, bridge FFI
  mínimo (función `greet`), protocolo v1 esqueleto con test de round-trip,
  CI en Windows/Linux.
- **Fase 1 ("Lectura de hardware")** completada: `nexodeck-hardware`
  (snapshot de CPU/RAM/disco/red con `sysinfo`, GPU NVIDIA opcional con
  `nvml-wrapper`, degradación a `None` sin GPU/sensores), `watch_hardware_metrics()`
  expuesto como `Stream` vía `StreamSink` desde `nexodeck-ffi`, y la
  feature `dashboard` (`app/lib/features/dashboard/`) mostrando las
  métricas en vivo. **GPU AMD en Windows agregada despues, en una sesión
  posterior**, cuando el equipo principal tenía una Radeon RX 580 — ver
  sección "GPU AMD en Windows" más arriba, incluida la nota de que hoy ese
  equipo tiene una NVIDIA y la ruta activa pasó a ser la de NVML.
- **Fase 2 ("Motor de acciones")** completada, junto con el esquema Drift
  completo (ver arriba): `nexodeck-actions` (portapapeles vía `arboard`,
  terminal nueva vía script temporal + `CREATE_NEW_CONSOLE`, elevación
  admin vía trampolín de PowerShell `Start-Process -Verb RunAs` en
  Windows — **la ruta de elevación no se pudo probar de punta a punta**,
  requiere que un humano confirme el UAC), expuesto vía `nexodeck-ffi`
  (`execute_clipboard_action`, `execute_terminal_action`), y la feature
  `actions` (`app/lib/features/actions/`) con CRUD completo, editor con
  parámetros dinámicos `{{variable}}`, y ejecución real. Verificado
  inspeccionando la base de datos real (perfiles/acciones semilla
  correctos) — **la ejecución desde la UI (clic en una tarjeta) no se
  probó de forma interactiva**, no hay herramienta de automatización de UI
  de escritorio disponible en el entorno de desarrollo.
- **Fase 3 ("Modo compacto / pantalla completa")** completada, solo
  desktop (Windows/Linux; Android usa un mecanismo de overlay distinto,
  fuera de alcance): `window_manager` (una sola ventana que cambia de
  tamaño/decoración/always-on-top, NO `desktop_multi_window` — evita la
  complejidad de multiples engines de Flutter para lo que es, en la
  práctica, alternar el layout de una ventana) + `screen_retriever` para
  el id del monitor. Persistencia en `window_layouts` (posición/tamaño por
  modo) y `app_settings` (qué modo estaba activo — dato de preferencia,
  no de layout, por eso vive en una tabla distinta). Feature
  `compact_overlay/`. Gotcha real encontrado: `window_manager` usa un
  `MethodChannel` antes de `runApp()`, así que `main()` necesita
  `WidgetsFlutterBinding.ensureInitialized()` explícito al principio o
  truena con un assert de binding no inicializado.
  **Verificado con un test real** (`test/window_layout_repository_test.dart`,
  contra SQLite en memoria) de que el upsert por modo no duplica filas, y
  confirmando por Win32 API (`GetWindowRect`) que la ventana abre con el
  tamaño/centrado esperado — **el toggle de modo desde la UI (clic en el
  botón) no se probó interactivamente**, misma limitación de automatización
  de UI que Fase 2.
- **Fase 4 ("Transporte WiFi + protocolo end-to-end")** completada:
  WebSocket sobre TLS con certificado autofirmado persistido, mDNS con
  descubrimiento automático (incluido el `MulticastLock` nativo en Android),
  pairing con PIN y certificate pinning desde el primer emparejamiento,
  `ActionsCatalog` para que los ids de acción de la PC signifiquen algo del
  lado Android, y la feature `pairing/` en Flutter. **El flujo E2E con el
  Android físico todavía no se corrió** (sí hay un test de integración en
  loopback que cubre pairing, reconexión, revocación y los relays).
- **Fase 5 ("Transporte USB por AOA")** en curso: el lado PC está hecho
  (framing sobre canal crudo, `SessionTransport`, handshake AOA sobre
  `nusb`, puente bulk) — ver la sección "USB / AOA" más arriba para los
  gotchas. Faltan el lado Android, `libwdi` y la UI.

El detalle completo de cada fase, con qué quedó verificado y qué no, vive en
[`docs/ESTADO-DEL-PROYECTO.md`](./docs/ESTADO-DEL-PROYECTO.md) (mantenerlo
ahí, no duplicarlo acá). Las fases que faltan están descritas en
`NexoDeck-Arquitectura-y-Plan-de-Fases.md`.
