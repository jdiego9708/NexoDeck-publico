# NexoDeck — Estado del proyecto

Snapshot del progreso real, para retomar el trabajo sin tener que reconstruir el contexto desde cero. Ver [`NexoDeck-Arquitectura-y-Plan-de-Fases.md`](../NexoDeck-Arquitectura-y-Plan-de-Fases.md) para la arquitectura completa y el plan de fases original, y [`CLAUDE.md`](../CLAUDE.md) para las reglas operativas del día a día (incluida la sección "Setup en una máquina nueva", que el proyecto se programa en varios equipos).

---

## Salud del build (2026-07-30)

Se retomó el proyecto tras un parate, en un equipo con el perfil de Windows recreado, y se dejó todo compilando y en verde de nuevo:

| Comprobación | Resultado |
|---|---|
| `cargo test --workspace` | 23 tests en verde (16 de protocolo, 4 de `FramedUsb`, 1 de hardware contra la máquina real, 1 de loopback de pairing, 1 del stub de vault) |
| `flutter analyze` | sin problemas |
| `flutter test` | 7 tests en verde |
| `flutter build windows` | `nexodeck.exe` + `nexodeck_ffi.dll` |
| `flutter build apk --debug` | OK, con `libnexodeck_ffi.so` **verificado dentro del APK** en `arm64-v8a`, `armeabi-v7a` y `x86_64` (la regresión de Fase 4) |

Lo que hubo que reinstalar/arreglar en el equipo (todo documentado como gotchas de portabilidad en `CLAUDE.md`): toolchain de Rust completo (no estaba: sin él ni siquiera compila la app de escritorio, porque cargokit invoca `cargo` durante el build de Flutter) con los targets de Android, `flutter_rust_bridge_codegen` 2.12.0 (misma versión que el paquete Dart, para `melos run bridge:gen`), `dart pub get` del `build_tool` de cargokit, y `flutter clean` para tirar un `CMakeCache.txt` que apuntaba al JDK de la máquina anterior. Se agregó el script `melos run setup` para el paso de cargokit.

---

## Completado

### Fase 0 — Cimientos (`338a2d3`)

Monorepo con pub workspace + Melos (dev_dependency local, obligatoria desde Melos v7 para que detecte el workspace — no se puede activar global), workspace de Cargo con 7 crates, proyecto Flutter multiplataforma (Windows/Linux/Android), bridge FFI mínimo (`greet()`) integrado con `flutter_rust_bridge` 2.12.0 apuntando directo a `core/crates/nexodeck-ffi` (sin necesidad de reubicar el crate, gracias al flag `--rust-crate-dir`), protocolo v1 esqueleto (`nexodeck-protocol`) con test de round-trip en `postcard`, CI en GitHub Actions (Windows + Linux).

Verificado: `cargo build`/`test` en verde, `flutter run -d windows` mostrando el saludo real de Rust, `flutter build apk --debug` compilando para Android.

### Fase 1 — Lectura de hardware (`3c532cd`)

`nexodeck-hardware`: snapshot de CPU/RAM/disco/red vía `sysinfo` 0.38, GPU NVIDIA opcional vía `nvml-wrapper` 0.12 (degradación a `None` sin GPU/driver). `watch_hardware_metrics()` expuesto como `Stream<HardwareSnapshot>` desde `nexodeck-ffi` vía `StreamSink` (no `impl Stream` — ver gotcha abajo). Feature `dashboard` en Flutter mostrando las métricas en vivo con Riverpod.

Verificado: test de Rust real (`snapshot_reports_plausible_ram`, contra el hardware real de la máquina), app corriendo en Windows sin excepciones. **GPU siempre `None` en esta máquina** (sin NVIDIA) — se resuelve en esta misma sesión, ver sección de GPU AMD más abajo.

### Fase 2 — Motor de acciones + esquema Drift completo (`672337a`)

Se adelantó el esquema de base de datos completo (decisión ya tomada: las 11 tablas de una sola vez, no incremental por fase) junto con el Fase 2 original:

- **Drift**: `actions_table`, `action_parameters`, `macro_steps`, `profiles`, `profile_actions`, `devices`, `alert_rules`, `hardware_history`, `secrets_refs`, `window_layouts`, `app_settings` en `schemaVersion 1`, con sus 11 DAOs. `PRAGMA foreign_keys = ON` en `beforeOpen` (si no, los `onDelete: cascade` no hacen nada).
- **`nexodeck-actions`**: portapapeles vía `arboard`, terminal nueva vía script temporal + `CREATE_NEW_CONSOLE` (evita el escaping de `cmd.exe`), admin vía trampolín de PowerShell `Start-Process -Verb RunAs` en Windows.
- Feature `actions`: CRUD completo, editor con parámetros dinámicos `{{variable}}`, ejecución real conectada al bridge.

Verificado: `cargo build`/`test`, app corriendo sin excepciones, **inspección directa del SQLite real** (perfiles y acciones semilla correctos, no solo logs).

### Fase 3 — Modo compacto / pantalla completa (`d3ee45d`)

Solo desktop (Windows/Linux). `window_manager` (una sola ventana que cambia de tamaño/decoración/always-on-top) en vez de `desktop_multi_window` — evita múltiples engines de Flutter para algo que en la práctica es alternar el layout de una ventana. `screen_retriever` para el id del monitor. Persistencia dividida: `window_layouts` (posición/tamaño *por modo*) vs `app_settings` (*qué modo* estaba activo, es una preferencia, no un dato de layout). Feature `compact_overlay/`.

Verificado: test real contra SQLite en memoria (`test/window_layout_repository_test.dart`, confirma que el upsert por modo no duplica filas), tamaño/posición de ventana confirmados por Win32 API (`GetWindowRect`). De paso se resolvió `test/widget_test.dart`, que probaba el contador default de Flutter y llevaba roto desde Fase 1 (nunca se había corrido `flutter test`): se **eliminó** y se reemplazó por el test de repositorio de arriba — no existe más un `widget_test.dart` en el proyecto. CI pasó a correr `flutter test` además de `flutter analyze`.

### GPU AMD en Windows

`nexodeck-hardware` solo leía GPU vía NVML (NVIDIA); esta máquina tiene una Radeon RX 580, así que `gpu_usage`/`gpu_temp`/`gpu_vram_*` siempre daban `None`. Se agregó `gpu_windows.rs` (solo Windows por ahora), combinando 3 fuentes: PDH (`\GPU Engine(*)\Utilization Percentage` para uso, `\GPU Adapter Memory(*)\Dedicated Usage` para VRAM usada — ambas vendor-agnósticas), DXGI (`DXGI_ADAPTER_DESC.DedicatedVideoMemory` para VRAM total), y un shim casero contra `atiadlxx.dll` (ADL, vía `libloading`) para temperatura, sin SDK de AMD instalado.

Verificado con datos reales de esa GPU, corriendo el ejemplo (`cargo run -p nexodeck-hardware --example snapshot`) varias veces y viendo los números variar de forma plausible: uso 5-28%, temperatura 57-66°C, VRAM total ~8.1GB (corrigiendo de paso un dato erróneo — WMI reportaba ~4GB por un bug de overflow conocido), VRAM usada ~2.8GB. Encontró y corrigió en el camino un gotcha real: el `iVendorID` de ADL usa el decimal literal `1002`, no el hex `0x1002` — comparar contra el valor equivocado hacía que nunca se encontrara el adaptador, sin ningún error visible (ver detalle en `CLAUDE.md`).

**Actualización (2026-07-30): la ruta NVML quedó verificada, la ruta AMD ya no es re-testeable en esta máquina.** El equipo de desarrollo cambió de GPU (ahora una NVIDIA RTX 5060 Ti). Como `gpu_snapshot()` prioriza NVML y solo cae a la ruta Windows PDH/DXGI/ADL cuando no hay NVIDIA, ahora la ruta activa es la de NVML — que hasta ahora **nunca se había podido ejercitar contra hardware real** (en Fase 1 daba siempre `None` por falta de tarjeta NVIDIA). Corriendo el mismo ejemplo se confirmó que funciona de punta a punta: uso 13%, temperatura 56°C, VRAM 2534MB usada de 16311MB total (coherente con los 16GB reales de la tarjeta). El código de la ruta AMD queda tal cual — es correcto y estuvo verificado en su momento —, pero cualquier cambio futuro ahí no se puede volver a comprobar con hardware en este equipo.

### UI: dashboard y deck combinados en una sola pantalla (`6f5f0b4`)

Mejora visual pedida antes de seguir con Fase 4: métricas y controles del deck ya no viven en pestañas separadas. `main.dart::_HomeShell` compone `MetricsRow` (fila de métricas, 20% del alto disponible del `body`, medido con `LayoutBuilder` para no contar el `AppBar`) + `ActionsDeckGrid` (80% restante) en un solo `Scaffold`. `DashboardScreen`/`ActionsScreen` (los `Scaffold` standalone viejos) se eliminaron.

`MetricsRow` combina, vía `fl_chart`: gráficos de torta (RAM, GPU), de barras (Disco, con `backDrawRodData` — fondo + relleno en un solo rod) y de líneas (CPU, Red — historial corto mantenido **en memoria** dentro del widget, no persistido en `hardware_history`), todos con porcentajes y datos extra (frecuencia/temperatura de CPU, temperatura/VRAM de GPU).

Verificado con `flutter analyze`/`test` en verde y **capturas de pantalla reales** de la app corriendo en Windows (dos capturas separadas por unos segundos, confirmando que el panel respeta el 20%, los 3 tipos de gráfico renderizan correctamente, y los valores actualizan en vivo entre capturas — RAM 73%→71%, GPU 4%→5%). El usuario también revisó la app corriendo interactivamente en su propia sesión de terminal.

### Fase 4 — Transporte WiFi + protocolo end-to-end

Implementación completa según la arquitectura original (el usuario eligió explícitamente no recortar alcance): WebSocket+TLS, mDNS con descubrimiento automático (incluyendo el `MulticastLock` nativo en Android), y certificate pinning desde el primer pairing.

- **`nexodeck-protocol`**: nuevas variantes de `MessageV1` para el handshake de pairing (`PairHello`/`PairPin`/`PairConfirm`/`PairAccepted`/`PairRejected`), reconexión (`Reconnect`/`ReconnectAccepted`/`ReconnectRejected`), sesión post-pairing (`HardwareSnapshot`, `ActionsCatalog`, `ExecuteAction`, `ActionAck`) — todas externally-tagged, 16 tests de round-trip.
- **`nexodeck-transport`** (antes un stub vacío): crate nuevo con `tls.rs` (certificado autofirmado vía `rcgen`, persistido en disco para que el fingerprint sea estable entre reinicios; verificadores custom de `rustls` para trust-on-first-use y pinning), `discovery.rs` (`mdns-sd`, servicio `_nexodeck._tcp.local.`), `pairing.rs`, `server.rs` (`TransportHost`, rol PC — WebSocket sobre TLS manual con `tokio-rustls` + `tokio-tungstenite`, nunca un backend TLS de tungstenite ni `native-tls`/`openssl`, para no arrastrar `openssl-sys` en la cross-compilación a Android), `client.rs` (`TransportClient`, rol Android). Probado con un test de integración en loopback (`tests/loopback_pairing.rs`) que cubre pairing completo, reconexión con fingerprint correcto/incorrecto, revocación, y los dos relays de sesión — todo en un solo proceso jugando ambos roles a la vez.
- **`nexodeck-ffi`**: `api/pairing.rs` y `api/connection.rs`, siguiendo los 3 patrones ya establecidos del skill `rust-ffi-bridge`. Los eventos de host y cliente se multiplexan hacia un único stream por función (`watch_pairing_events`/`watch_connection_events`) para que Dart no necesite saber en qué rol está corriendo.
- **Catálogo de acciones (gap encontrado durante la implementación, no estaba en el plan original)**: cada dispositivo siembra su propia base Drift con ids aleatorios propios (`uuid.v4()` independiente por instalación) — un `action_id` generado en Android no significa nada para la PC. Se agregó `MessageV1::ActionsCatalog { actions: Vec<RemoteAction> }`: la PC empuja su catálogo real al conectar un dispositivo, Android reenvía esos mismos ids en `ExecuteAction`. Sin esto, "tocar una acción en Android" no podía funcionar por construcción.
- **Flutter**: `features/pairing/` (4 capas, mismo patrón que `features/actions/`). `devices` (tabla+DAO) ya existía del esquema completo de Fase 2, solo faltaba el repositorio/provider. UI: `DevicesScreen`+`HostPinCard` (PC), `AndroidPairingScreen`+`ConnectedDeviceScreen` (Android, vía `AndroidShell` en el branch de plataforma de `_ModeAwareHome`). `main.dart::_HomeShell` gana dos `ref.listen`: sincroniza autorizados hacia Rust, y despacha `ActionExecutionRequested`/`DeviceConnected` (ejecuta localmente con el motor de Fase 2 y responde `ActionAck`, o empuja el catálogo).
- **Android nativo**: primer código Kotlin real del proyecto (`MainActivity.kt`), un `MethodChannel` puntual para adquirir/liberar un `WifiManager.MulticastLock` — necesario porque el descubrimiento corre sobre un socket UDP multicast crudo (`mdns-sd`), no la API `NsdManager` de Android, y Android descarta paquetes multicast por defecto sin el lock. El skill `kotlin-android-plugin` (antes un stub) se completó con este patrón como plantilla. Permisos nuevos en `AndroidManifest.xml`: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`.
- **Bug preexistente encontrado y corregido de paso**: `nexodeck-actions` dependía de `arboard` sin gating de plataforma desde Fase 2, y `arboard` no tiene backend de Android — `flutter build apk` nunca había vuelto a correrse después de que Fase 2 agregara esa dependencia a `nexodeck-ffi`, así que el `.apk` llevaba meses generándose "exitosamente" sin `libnexodeck_ffi.so` adentro (Gradle no falla el build aunque cargokit no logre producir la librería para ningún ABI). Se resolvió con `arboard` como dependencia condicional (`[target.'cfg(not(target_os = "android"))'.dependencies]`) y `paste_to_clipboard` devolviendo `UnsupportedPlatform` en Android — no hace falta clipboard local ahí, las acciones se disparan siempre hacia la PC.

Verificado: `cargo test` en todo el workspace (incluye el loopback de pairing), `flutter analyze`/`flutter test` en verde, `flutter build windows` y `flutter build apk --debug` compilando (con `libnexodeck_ffi.so` confirmado presente en las 3 arquitecturas del APK, no solo "el build no falló"), la app de Windows corriendo sin excepciones con el host de transporte arrancando. **Pendiente de verificación**: el flujo E2E completo (pairing real PIN-a-PIN, hardware en vivo, ejecutar una acción de punta a punta) requiere el Android físico del usuario — no hay automatización de UI disponible en este entorno, misma limitación que fases anteriores. Guion de prueba manual completo en el plan de la sesión.

**Simplificaciones deliberadas de esta primera versión** (documentadas, no bugs):
- Un solo dispositivo emparejado activo a la vez del lado Android (`AndroidShell` usa `list.first`); la PC sí soporta múltiples dispositivos.
- La reconexión en Android resuelve el host actual re-navegando mDNS y haciendo match por nombre de instancia sanitizado contra `device.name` guardado — heurístico razonable para esta fase (un solo PC real en la red durante las pruebas), no un identificador persistido explícito.
- `ActionsCatalog` no lleva parámetros dinámicos (`{{variable}}`) ni macros — ejecutar una acción parametrizada desde Android usa valores por defecto/vacíos. Un prompt de parámetros de punta a punta queda para una fase posterior.
- El PIN de pairing es una confirmación visual (SAS-style, dos humanos comparando pantallas), no está criptográficamente atado a la sesión TLS — suficiente para el requisito de "confirmación explícita en ambos dispositivos", pero no es una defensa contra un atacante activo durante la primera conexión (TOFU). Documentado como limitación conocida, no como pendiente de esta fase.

### Fase 4 — verificación E2E real y arreglos que salieron de ahí (2026-08-01)

**El E2E de Fase 4 dejó de estar pendiente**: se corrió de punta a punta
contra el Samsung Galaxy S24 Ultra real (SM-S928B), usando adb como
automatización de UI del lado Android (ver la sección nueva de `CLAUDE.md`)
y `examples/wifi_host_watch` como host sin Flutter del lado PC. Verificado
con capturas y logs, no solo "compila":

- descubrimiento mDNS, reconexión TLS con el fingerprint pinneado, y sesión;
- las **5 métricas en vivo** de la PC en el teléfono (CPU 6% @3401 MHz, RAM
  12.2/31.9 GB, Disco 1518/2553 GB, GPU 4% 48°C 1.4/15.9 GB por la ruta
  NVML, Red ↓6.2/↑93.4 KB/s);
- el catálogo de acciones llegando y renderizando;
- **ejecución remota**: un tap en la tarjeta del teléfono produjo
  `ActionExecutionRequested { action_id: "diagnostico-1" }` en la PC.

Lo que **no** quedó cubierto en esta corrida: el primer pairing PIN-a-PIN
(el teléfono ya estaba emparejado de antes — se confirmó leyendo su base
real: el fingerprint guardado coincide con el del host) y el `ActionAck` de
vuelta (el ejemplo de diagnóstico relaya pero no ejecuta ni responde).

Correr esto destapó **tres bugs reales, todos con el mismo patrón: fallar
en silencio**. Los tres corregidos y re-verificados contra el teléfono:

1. **El teléfono se trababa para siempre en "Reconectando..."**. Causa raíz:
   Riverpod no re-notifica cuando el valor nuevo es `==` al anterior y los
   eventos del bridge son value types de freezed, así que de dos
   `Disconnected` seguidos el segundo se perdía — y ese era el único lugar
   donde se limpiaba el flag que habilita el reintento. El lado PC ya había
   tropezado con esto (`main.dart`) y estaba documentado; el lado Android
   había quedado con `ref.listen`. Se pasaron los 4 sitios a suscripción
   directa (`connectionEventStream`/`pairingEventStream`, este último
   nuevo). Medido: antes se clavaba en 2 intentos, ahora hace 11 en 45 s y
   se recupera solo cuando la PC vuelve a autorizar, sin reiniciar la app.
2. **Los fallos de conexión no llegaban nunca a Dart**: el FFI spawneaba
   `connect_first_pairing`/`reconnect` y descartaba el error con
   `let _ = ...`. Ahora esas funciones devuelven cuando la conexión quedó
   *establecida* (el loop se suelta con `spawn_session`) y el error se
   propaga. De paso, esto habilitó que la UI muestre el motivo.
3. **El rechazo de reconexión era invisible en los dos lados**: la PC no
   emitía ningún evento (ahora loguea) y el teléfono lo recibía como evento
   de *pairing*, que `ConnectedDeviceScreen` no escuchaba. Ahora lo muestra
   ("La PC rechazó la conexión: dispositivo no autorizado") con un botón
   **"Olvidar esta PC"** — antes no había ninguna salida salvo reinstalar.

Otros dos arreglos del mismo camino: el reintento de reconexión ya no
depende de que mDNS re-emita (timer propio cada 4 s, porque el stream solo
emite al *resolver* un servicio nuevo y podía no volver a hacerlo nunca), y
el fallo de `startTransportHost` dejó de tragarse en silencio
(`transportHostErrorProvider` + banner en `DevicesScreen`; el caso típico es
el puerto 58643 ocupado).

Herramientas nuevas: `examples/wifi_host_watch --pair` (arma y acepta el
pairing solo, para correr el E2E sin clics en el escritorio), logger
inicializado en los dos ejemplos de diagnóstico, y `app/tool/dump_devices.dart`
para inspeccionar la base de un teléfono.

### UI: experiencia de emparejamiento (2026-08-02)

**El primer pairing PIN a PIN dejó de estar pendiente**: se corrió de punta a
punta con el S24 Ultra real, desemparejando primero (`adb shell pm clear`) —
era el último ítem sin verificar de la Fase 4. Verificado con capturas de las
dos pantallas.

Lo que se arregló, en orden de impacto:

- **El PIN ahora tiene tratamiento y es el mismo widget en las dos puntas**
  (`widgets/pin_display.dart`): agrupado `315 116`, cifras tabulares, pozo
  tonal con hairline. Antes cada lado hacía `Text(pin, displaySmall)` — y
  `displaySmall` tiene `letterSpacing: -0.6`, o sea tracking **negativo** sobre
  un número que hay que comparar dígito por dígito. `AppText.pin()` lo revierte
  explícitamente, y hay un test que falla si alguien lo reintroduce.
- **La lista de PCs mostraba el nombre mDNS crudo**: `discovery.rs` usa
  `get_fullname()`, así que se veía `JUANDIEGO-PC._nexodeck._tcp.local.` como
  nombre de la computadora. `hostDisplayName()` lo limpia.
- **El spinner desnudo del teléfono** entre el tap y el diálogo del PIN pasó a
  un panel con el nombre de la PC, el estado por fase, y **Cancelar**. Más dos
  timeouts con mensajes distintos (20 s hasta el PIN, 125 s hasta la decisión
  humana, alineado a `PAIRING_STEP_TIMEOUT`).
- **"Buscando dispositivos" giraba para siempre.** Y no donde parecía:
  `discoveredHostsProvider` solo emite después del primer host, así que la rama
  `isEmpty` era código muerto y el culpable era el `loading:`. Ahora un `Timer`
  propio decide, a los 8 s, mostrar "No encontramos ninguna PC" con reintento.
- **Bug real, no cosmético**: cerrar la hoja de la PC con una solicitud
  pendiente dejaba al teléfono esperando los 120 s completos sin respuesta.
  Ahora `_close()` manda `confirmPairing(false)`, y la hoja no es descartable
  por accidente.
- La solicitud entrante pasó a tener superficie y jerarquía propias; se sumó un
  momento de éxito en ambas puntas; y `_DeviceTile`, los banners y la lista de
  hosts pasaron a los tokens y a `InteractiveCard`/`EmptyState`.

**Primeros tests de pairing del repo** (`test/pairing_pin_test.dart`, 9 casos):
agrupación con ceros a la izquierda, deletreo para lectores de pantalla,
limpieza del nombre mDNS, y el que más vale — que el tracking resuelto contra
`AppTheme` sea positivo y las cifras tabulares.

**Verificado con capturas reales**: PIN idéntico en PC y teléfono, lista con el
nombre limpio, panel de conexión, cancelar volviendo a la lista, "no
encontramos ninguna PC" + reintento funcionando, y el pairing completo
terminando con el teléfono en `ConnectedDeviceScreen`. **No verificado**: el
momento de éxito de la PC (dura 900 ms y el pipeline de captura tarda ~2,8 s en
levantar la ventana) y los dos timeouts, que requieren esperar 20 s / 125 s.

**Dos límites del protocolo que quedaron documentados, no resueltos** (piden
mensaje nuevo, skill `protocol-message`): no existe un "cancelar" del lado
cliente — el botón es abandono de UI y la sesión de Rust sigue viva hasta el
timeout del host —, y `DiscoveredHost` no trae plataforma, así que el ícono de
la lista es neutral en vez de mentir con uno de Windows.

### UI: pulido visual del escritorio + sistema de tokens (2026-08-02)

Auditoría visual real del escritorio (la primera del proyecto: hasta ahora la
UI de Windows nunca se había mirado con capturas). Se hizo puliendo sobre la
identidad existente —seed violeta `#6C5CE7`, Plus Jakarta Sans, superficies
tonales planas—, sin cambiar paleta ni tipografía.

**Bug encontrado y corregido en el camino, sin relación con el diseño**: la
app arrancaba **invisible**. `window_layouts` tenía `pos_x: 2033` y un
`monitor_id` de un monitor AOC ya desconectado, y `main.dart` restauraba esa
posición sin validarla, así que la ventana se abría entera fuera del área
visible — sin error, y sin forma de traerla al frente. Se agregó
`isWindowRectUsable()`, que exige un solape mínimo de 160×80 px contra alguna
pantalla conectada *hoy*, aplicada en los dos puntos que restauran posición.

**Sistema de tokens** (`app/lib/core/theme/`): `app_motion.dart` (duraciones y
curvas semánticas — los mismos 7 números estaban repetidos a mano en 12
archivos), `app_surface.dart` (hairline/lift/focusRing/cardDecoration),
`app_text.dart` (cifras tabulares) y `AppSpacing`/`AppRadius` ampliados. Los
valores calibrados contra el S24 quedaron congelados; los nuevos solo se
agregaron.

**Lo que cambió visualmente**:
- **Hover, foco y teclado**: `InteractiveCard` nuevo — borde teñido con el
  color de la acción, sombra sin halo (`spreadRadius: -4`), anillo de foco y
  **`Enter` para ejecutar**; el deck no era navegable por teclado en absoluto.
  Más click derecho como menú contextual.
- **Bordes**: hairline de 1 px en `cardTheme`. En modo claro las tarjetas
  antes casi no se despegaban del fondo.
- **Tarjeta de acción**: fuera la franja de 3 px (leía "Material 2015"), entra
  un wash de esquina; chip de icono con degradado y borde; y el texto pasó al
  pie, porque el contenido ocupaba solo los primeros ~90 px de una tarjeta de
  ~205 y el resto era espacio muerto.
- **Se eliminó el FAB**: tapaba la descripción de la última tarjeta del deck,
  y además es un patrón de móvil. "Nueva acción" vive ahora en la barra.
- **Marca**: lockup en el AppBar (degradado `primary`→`tertiary`, derivado del
  mismo seed — ningún hex nuevo), reusado en la barra del modo compacto.
- **Estados vacíos** (`EmptyState`) reusando el lenguaje del diálogo de error,
  con variante compacta automática para el teléfono apaisado.
- **Cromo de escritorio**: scrollbar fina que engorda al hover, tooltips y
  snackbars tematizados, AppBar transparente para que el fondo neuronal
  respire detrás, chips con borde reactivo, hover rojo en el botón de cerrar
  del modo compacto, fade de scroll en la barra de grupos.
- **Cifras tabulares** en los valores de métricas y en el `%` del donut.

Verificado: `flutter analyze` limpio, 25/25 tests, y **capturas reales antes y
después** en Windows (claro y oscuro) más el **S24 Ultra en vertical y
horizontal** — las 5 tiles siguen entrando en el riel apaisado sin scrollear y
los badges (`3401 MHz`, `47°C`, `1.3 GB/15.9 GB`) siguen completos, que era el
riesgo concreto de tocar `MetricTile`.

### Fase 9 (cont.) — perfiles por contexto (2026-08-02)

Los perfiles existían en el esquema desde Fase 2 (`profiles` +
`profile_actions`, con la columna `auto_detect_process` ya prevista) pero no
tenían ni UI ni motor. Ahora el deck cambia solo según la aplicación que
tengas adelante.

- **`nexodeck-hardware/src/foreground.rs`**: `GetForegroundWindow` +
  `GetWindowThreadProcessId`, y `sysinfo` refrescando **solo ese pid** para
  resolver el nombre (un `refresh_processes` completo recorre cientos de
  procesos y esto corre 1/s). Fuera de Windows degrada a `None`.
  `watch_foreground_app` (FFI) emite **solo cuando cambia**.
- **`features/profiles/`**: repositorio, providers, selector en la barra,
  editor (nombre, ícono, color, ejecutable disparador y checkboxes de
  acciones) y `ProfileAutoSwitcher`.
- **`visibleActionsProvider`**: única definición del filtro por perfil, la
  usan el deck de pantalla completa y el modo compacto.

Tres decisiones que costaron pensar y quedaron documentadas en `CLAUDE.md`:
la propia ventana de NexoDeck **no cuenta como cambio de aplicación** (se
distingue por pid, no por nombre) porque para elegir un perfil a mano hay
que enfocarla; una elección manual **gana hasta que cambies de verdad de
app**; y un perfil sin acciones asignadas **no filtra nada**, para que
activarlo no vacíe la pantalla sin explicación.

De paso, el editor de acciones ahora **avisa si usás `{{variable}}` en el
comando sin declarar el parámetro** (con un botón para declararlos de una).
El caso salió de mirar la app real: la acción semilla "Copiar plantilla de
título" tiene `{{tema}}` y ningún parámetro, así que se ejecutaba con ese
texto literal y nada lo decía.

**Verificado con la app real corriendo en Windows**, con clics y capturas
(ver la sección nueva de `CLAUDE.md` sobre automatización por Win32): el
menú lista los perfiles con sus colores, el editor abre con los datos
correctos y sugiere `warp.exe` —la última app externa, no `nexodeck.exe`,
que es lo que valida la comparación por pid—, seleccionar "Streaming"
filtra el deck de 6 acciones a las 2 del perfil, y **al enfocar warp el
perfil cambió solo a "Desarrollo"** con sus 3 acciones. La base del usuario
quedó restaurada a su estado previo después de la prueba.

**No verificado**: Linux (no hay implementación de foreground ahí, degrada
a manual) y el comportamiento con varios monitores/escritorios virtuales.

### Fase 9 (parcial) — historial de hardware persistido (2026-08-02)

`hardware_history` existía en el esquema desde Fase 2 pero nadie escribía en ella: los sparklines de `MetricsRow` eran un buffer en memoria de los últimos segundos, y al cerrar la app no quedaba nada.

- **Drift `schemaVersion 4`**: la tabla original no preveía las tasas de red, así que gana `netRxBytesPerSec`/`netTxBytesPerSec` con su `onUpgrade` real (no un `createAll` nuevo).
- `HardwareHistoryRecorder` persiste **una muestra cada 15 s** (no 1/s como emite el stream: serían 86.400 filas diarias para un gráfico de unos cientos de puntos) y envuelve a los dos modos de ventana, porque en compacto es cuando la app pasa más tiempo abierta.
- Retención de 7 días, que es exactamente el rango más largo del selector.
- `bucketSeries()` (puro, testeado en `test/history_series_test.dart`) promedia por cubos en vez de submuestrear: saltear muestras haría desaparecer un pico de 30 s en un rango de 7 días. Los cubos vacíos se omiten en vez de dibujarse como cero — "la app estuvo cerrada" no es lo mismo que "la CPU estuvo en reposo".
- Diálogo de Historial (`history_screen.dart`) con selector de rango, en el mismo patrón "pantalla dentro de un `Dialog`" del resto del proyecto.

**No verificado**: el comportamiento con una semana de datos reales acumulados — se probó con datos sembrados, no con una semana de uso.

### Fase 9 (parcial) — motor de macros + parámetros end-to-end (2026-08-02)

Dos huecos que se arrastraban desde Fase 2 y Fase 4 respectivamente: el tipo
de acción `macro` existía en el esquema y en el enum pero **no se podía ni
crear ni ejecutar**, y el `ActionsCatalog` no llevaba los parámetros
dinámicos, así que tocar una acción parametrizada desde Android la corría
con los valores por defecto **sin avisarle a nadie**.

**Motor de macros** (la parte de Fase 9 que faltaba para que el tipo dejara
de ser decorativo; perfiles por contexto, historial y export/import siguen
pendientes):

- `domain/macro_plan.dart` con `planMacro()` y `promptParametersFor()`
  **puras** — deciden qué corre, en qué orden y qué se pregunta, sin Drift
  ni bridge. `ActionsRepository.execute()` solo recorre el plan.
- A una macro se le pide la **unión de los parámetros de sus pasos,
  deduplicada por `key`**: tres pasos que usan `{{rama}}` preguntan una vez.
- Prohibición de macros anidadas en **dos** lugares (validación al guardar y
  filtro en `planMacro`), porque editar una acción ya usada como paso para
  convertirla en macro se le escapa a la validación y recursaría para
  siempre.
- Un paso que falla aborta el resto, envuelto en `MacroStepException`, que
  sabe cuál paso rompió; el diálogo de error lo dice.
- Editor de pasos en `action_editor_sheet.dart` (lista reordenable, pausa
  por paso, selector que sólo ofrece acciones no-macro), y la fila de
  parámetros ganó **valor por defecto, tipo de input y opciones** — antes el
  editor sólo guardaba key y label, así que `select` y defaults existían en
  el esquema pero eran inalcanzables desde la UI.

**Parámetros hacia Android**: `RemoteAction` lleva `parameters` (key, label,
tipo, default, opciones), `kind` y `step_count`; `ExecuteAction` lleva los
valores. El teléfono dibuja el **mismo widget de prompt que la PC** y la PC
aplica los valores con el mismo `renderCommand` del deck local.

De paso salieron dos limpiezas que no eran del alcance pedido pero estaban
en el camino: se unificó la ejecución desde la UI de escritorio en
`presentation/run_action.dart` (estaba duplicada entre el deck y el modo
compacto, y **la copia del compacto se tragaba los errores en silencio**), y
`ActionParam.options` pasó de JSON crudo a `List<String>` parseada una sola
vez en `fromRow` — el dominio cargando JSON obligaba a re-serializarlo para
el cable y volver a parsearlo del otro lado.

**Verificado contra el S24 Ultra real** (adb como automatización de UI del
lado Android, app de escritorio real del lado PC, escenario sembrado con
`tool/seed_macro_e2e.dart`):

- el catálogo llega con los parámetros completos y la tarjeta de una macro
  muestra sus dos distintivos (parámetros + cantidad de pasos);
- tocar una acción parametrizada **abre el prompt en el teléfono** con la
  etiqueta real, el default precargado y el desplegable con sus opciones
  (`staging`/`produccion`) — o sea que las opciones viajaron desde el JSON
  de Drift, por el protocolo como lista de strings, hasta el widget;
- al ejecutar, el portapapeles de la PC pasó de un centinela a
  `msg=[hola-desde-tel] env=[produccion]`, con los valores cargados en el
  teléfono, y el ack volvió al teléfono.

**Pendiente de verificación**: la corrida de la **macro** desde el teléfono
(prompt con `rama`+`tag` deduplicados, orden de pasos, pausa de 1.5 s). El
escenario y el script están listos; quedó sin correr porque el teléfono dejó
de estar disponible. La lógica de esa parte sí está cubierta por tests (11
del plan puro + 6 de persistencia contra SQLite real).

**Ojo, cambio incompatible en el cable**: se agregaron campos a
`RemoteAction` y `ExecuteAction` dentro de `V1`, sin abrir un `V2` (PC y
Android se compilan del mismo repo). Hay que **reinstalar las dos puntas
juntas**: un APK viejo contra una PC nueva no decodifica el catálogo.

### Exportar/importar el deck (2026-08-02)

Compartir un deck (o llevárselo a otra máquina) no requería nada del backlog: es puro Dart sobre lo que ya existía. `file_selector` para elegir el archivo, `deck_export.dart` para el formato y `DeckTransferRepository` para la lógica.

- El archivo es **JSON**, no postcard, y eso no contradice el ADR 0001: ese ADR es sobre el *cable*. Un archivo que el usuario guarda y abre meses después quiere justo lo contrario — versionable (`kDeckExportVersion`), legible a mano y tolerante a campos ausentes.
- **Importar agrega, nunca reemplaza**: todo entra con ids nuevos. Importar dos veces el mismo archivo da dos copias en vez de pisar lo que había.
- **Los ids se remapean.** Son UUID por instalación, así que los del archivo no existen en el destino: se genera uno nuevo por acción y por grupo y se reescriben las referencias (pasos de macro, `groupId`). Sin esto una macro importada apunta a la nada.
- Un paso de macro cuya acción no venía en el archivo se descarta pero **se reporta** (`ImportResult.droppedSteps`): una macro que pierde pasos en silencio es peor que una que no se importa.

Verificado con `test/deck_transfer_test.dart` (round-trip y remapeo de ids). **No verificado**: el diálogo de archivos en Linux.

### CI: job de Android que verifica el `.so` (2026-08-02)

`.github/workflows/ci.yml` gana un job `android` que compila el APK y
**comprueba que `libnexodeck_ffi.so` esté adentro en las 3 ABIs**. Era el
cabo suelto más caro de la lista: Gradle empaqueta el APK "exitosamente"
aunque cargokit no produzca la librería para ningún ABI, que es exactamente
el bug que dejó meses de APKs vacíos en Fase 4 y no tenía ninguna guardia de
regresión.

### UI: grupos de acciones y tema claro/oscuro (`bbf0aa4`)

Mejoras de UI hechas junto con Fase 4, no parte de ninguna fase numerada del plan original:

- **Grupos de acciones**: tabla nueva `action_groups` (nombre, ícono, color hex, orden) con su DAO; `ActionsTable` gana `groupId` nullable (`onDelete: setNull` — borrar el grupo no borra las acciones, las deja sin categorizar). Feature completa en `features/actions/` (repositorio/provider/editor `ActionGroupEditorDialog` para crear/renombrar/cambiar color/eliminar, y `ActionGroupFilterBar` — chips horizontales encima de la grilla, "Todas" + uno por grupo + botón para crear, long-press abre el editor). Es una categoría simple 1:N (una acción, a lo sumo un grupo), a diferencia de `Profiles`/`ProfileActions` que ya existían (N:N, perfiles exclusivos con auto-detección de proceso) — no se reemplaza ese modelo, es un filtro visual adicional.
  - Los grupos también viajan al `ActionsCatalog` de Fase 4 (`RemoteAction.group_id/group_name/group_color_hex` en `nexodeck-protocol`, resueltos en `ConnectionRepository.sendActionsCatalog` vía el parámetro `groups`) — Android ve los mismos grupos/colores que la PC, no hace falta re-implementar el filtro del lado cliente.
- **Tema claro/oscuro**: `features/theme/` (`ThemeModeController`, persistido en `app_settings` bajo la key `theme_mode`, mismo patrón que `WindowModeController` de Fase 3 — se lee `readInitialThemeMode()` antes de `runApp` para no mostrar un flash del tema equivocado en el primer frame). `AppTheme` (`core/theme/app_theme.dart`) define un tema Material 3 propio (seed violeta/indigo `#6C5CE7`, tipografía `google_fonts` Plus Jakarta Sans, superficies tonales planas sin blur — look "enterprise" tipo Linear/Vercel/Stripe) para `light`/`dark`, con `ThemeModeToggleButton` en el `AppBar`.
- **Rediseño visual del home**: `NeuralBackground` (fondo animado de nodos con deriva sinusoidal y líneas entre nodos cercanos, muy baja opacidad) montado solo en desktop detrás del contenido vía el `builder:` de `MaterialApp`. `AppBar` gana accesos directos a dispositivos (`DevicesButton`, de Fase 4) y tema, además del toggle de modo compacto ya existente.
- **Ícono de la app regenerado**: `flutter_launcher_icons` configurado en `pubspec.yaml` (Android adaptativo + Windows, `assets/icon/`), reemplaza el ícono placeholder default de Flutter en ambas plataformas.
- **Ejecución de terminal sin ventana visible**: `ActionsTable.showTerminalWindow` (default `true`) permite acciones que corren un comando en segundo plano sin abrir consola; del lado Rust es el parámetro `show_window` de `nexodeck-actions::terminal`.

**El esquema de Drift ya no está en la versión 1**: `action_groups` entró en `schemaVersion 2` y `showTerminalWindow` en `schemaVersion 3`, ambas con su `onUpgrade` real en `database.dart` (no un `createAll` nuevo). Son 12 tablas con 12 DAOs, no las 11 originales de Fase 2.

Verificado: `flutter analyze`/`flutter test` en verde (incluye `test/action_groups_repository_test.dart`, nuevo). **Pendiente de verificación interactiva**: el editor de grupos y el toggle de tema no se probaron con clics reales, misma limitación de automatización de UI que el resto del proyecto (ver sección de cabos sueltos más abajo).

---

### Ejecución capturada de comandos + centro de notificaciones (2026-08-04)

Hasta acá una acción de terminal era **dispará y olvidate**: `run_in_terminal()` escribía un script temporal, hacía `spawn()` con `CREATE_NEW_CONSOLE` y descartaba el `Child` en el acto. La salida solo existía en una consola aparte, y `execute_terminal_action` devolvía `Ok(())` apenas arrancaba el proceso — o sea que una acción reportaba éxito aunque el comando fallara. Una acción disparada desde el celular, además, no mostraba absolutamente nada en la PC.

- **`nexodeck-actions/src/runner.rs`** (nuevo): motor de ejecución capturada. `tokio::process` con pipes, agrupado de líneas cada 120 ms, anillo de 2000 líneas/256 KB con conteo de descartadas, cancelación con `taskkill /T`, limpieza de los scripts temporales (que hasta hoy no se borraban nunca), y ruta elevada best-effort vía redirección a archivo + trampolín con `-Wait -PassThru`. Singleton con `broadcast`, calcado de `nexodeck-ai/src/engine.rs`.
  - **La heurística de "app lanzada" por silencio se diseñó, se implementó y se sacó tras medirla**: `flutter analyze` con la salida a un pipe tarda **104 s en emitir su primera línea**, así que marcar como "lanzado" a todo proceso mudo a los 2 s ocultaba justo el comando que más necesita verse. Detalle completo en `CLAUDE.md`.
- **`showTerminalWindow` pasa a ser el selector entre los dos motores** (`false` = capturado, `true` = ventana real para comandos interactivos). `schemaVersion 5` da vuelta las filas existentes: el `true` viejo significaba "quiero ver la salida", y ahora la salida se ve dentro de la app.
- **FFI**: `start_captured_command` / `await_command_run` / `cancel_command_run` / `command_run_output` / `watch_command_runs`, con DTOs espejo. Ningún `u64` cruza el puente (frb los mapea a `BigInt`): el `run_id` es `String` y los tiempos `u32` de ms.
- **`features/run_center/`** (nuevo): dominio `CommandRun`, controller suscrito **directo al stream**, `RunToastHost` montado en `MaterialApp.builder` (cubre las dos ventanas de escritorio *y* Android, y por eso una ejecución remota aparece sin depender de ningún `BuildContext`), `RunToast` con cronómetro en vivo, estado "tardando" a los 10 s, salida expandible, copiar y cancelar, y panel de historial de la sesión.
- **Protocolo**: `MessageV1::ActionRunUpdate` + `RunPhaseWire` (variante nueva **al final** del enum, para no correr los índices de postcard), con round-trip tests. La PC manda arranque y cierre con ~4 KB del final de la salida; el teléfono lo dibuja con el mismo `RunToastHost`. **Rompe el cable con binarios viejos**: hay que reinstalar PC y APK juntos.
- **Bug adyacente corregido**: `main.dart::_handleConnectionEvent` descartaba los `params` del `ActionExecutionRequested`, así que una acción parametrizada disparada desde el celular corría con los valores por defecto en silencio.

Dos cambios de comportamiento deliberados, ambos documentados en `CLAUDE.md`: **un paso de macro ahora espera a que el comando termine de verdad** (antes `delayMsAfter` corría en paralelo al comando) y **un código != 0 aborta la macro**; y **el camino remoto no espera** (`waitForCompletion: false`), porque el ack sigue significando "lo lancé" y bloquearlo 30 s por un `flutter analyze` dejaría al teléfono con un spinner.

Verificado: 15 tests nuevos en `nexodeck-actions` (éxito, código != 0, stderr etiquetado, detach, cancelación con muerte real del árbol, agrupado, anillo, y las unidades puras de `LineSplitter` — incluido el caso de UTF-8 inválido que con `BufReader::lines()` truncaba la salida en silencio), 21 en `nexodeck-protocol`, `flutter analyze` limpio y 114 tests de Dart en verde.

**No verificable en este entorno**: la ruta elevada (UAC) necesita que un humano apruebe el diálogo, y la ruta Linux (`pkexec`, `process_group`) no tiene máquina donde probarse.

---

### Métricas: temperatura de CPU real y lista de discos (2026-08-25)

Dos huecos de la métrica de hardware, los dos con el mismo síntoma: el dato se mostraba, pero no era el que decía ser.

- **La temperatura del CPU se tomaba del primer sensor que apareciera** (`components.list().iter().find_map(...)`), así que en una máquina que solo expone el sensor del NVMe la métrica "CPU" mostraba la temperatura del disco sin ninguna señal. Y en el equipo principal (Ryzen 7 5700X, Windows) no había ningún sensor: quedaba siempre en `None`.
- **El agregado de disco sumaba todo lo montado**, incluidas dos unidades de Google Drive — que se montan como `DRIVE_FIXED` con FAT32 y por eso pasaban por disco local—, inflando el total en cientos de GB. Además era un solo número para todo: no había forma de ver qué disco estaba lleno.

Qué se hizo:

- **`nexodeck-hardware/src/cpu_temp.rs`** (nuevo): elección del sensor por prioridad (Tctl/Tdie > package > k10temp/coretemp > cpu > core > genérico) con descarte explícito de lo que seguro no es el CPU (`nvme`, `gpu`, `battery`...), evaluado **antes** del ranking genérico para que "GPU Core" no se cuele por contener `core`. Es la parte testeable sin hardware y es la que decide si el número es el correcto.
- **`cpu_temp/windows_provider.rs`** (nuevo): segunda fuente solo en Windows, el proveedor WMI de LibreHardwareMonitor/OpenHardwareMonitor, sondeado desde un hilo propio (`WMIConnection` es `!Send` por los apartamentos COM, y una consulta WQL por segundo no se paga por un dato que cambia despacio). Filtra por `Identifier` (`/amdcpu/0/temperature/0`), no por `Name`, que CPU y GPU comparten. **En Windows no hay forma de leer esto desde espacio de usuario** — SMN/MSR son kernel-mode y el desktop del proyecto no implementa zonas térmicas ACPI (`MSAcpi_ThermalZoneTemperature` responde "Incompatible")—, así que sin esas herramientas degrada a `None` y la UI no dibuja el badge. Detalle completo en `CLAUDE.md`.
- **`nexodeck-hardware/src/disks.rs`** (nuevo): inventario por volumen, con el filtro de volúmenes que no son discos reales vía `QueryDosDeviceW` (un disco real cae en `\Device\HarddiskVolumeN`; nube, red y ópticas no). El agregado `disk_used_mb`/`disk_total_mb` pasa a calcularse **sobre esa misma lista**, para que la suma de las filas que el usuario ve dé exactamente el número de la barra.
- **Bridge y protocolo**: `HardwareSnapshot.disks` (`DiskUsage`/`DiskUsageWire` + tipo de medio) en el DTO del FFI y en el mensaje de red, así que el teléfono ve la misma lista que la PC. `HardwareSnapshot` deja de ser `Copy` en los tres lugares (se mueve en todos sus usos, no obliga a clonar en ninguna ruta caliente). **Rompe el cable con binarios viejos**: campo agregado dentro de `V1`, hay que reinstalar PC y APK juntos.
- **UI**: la tile de Disco pide ancho doble (`MetricSpec.widthUnits`) cuando hay más de un disco y, si la franja se lo concede, cambia de cuerpo a `DiskUsageList` — una fila por disco con identificador, barra de progreso y `usado/total`, ordenadas, con el disco por encima del 90% en color de error. El reparto lo decide `metricStripLayoutFor()`, función pura y testeada: solo concede el ancho si todo entra en **una sola fila** (un `Wrap` con una tile doble que no entra deja hueco y desalinea) y si sobra alto para `MetricDensity.full`. En un teléfono vertical no se concede y la tile vuelve al agregado.
- De paso, `formatMb()` gana el escalón de TB (con varios discos los totales daban cuatro cifras en GB) y aparece `formatMbPair()` para la fila de disco, que escribe la unidad una sola vez y la fija el total.

Verificado: `cargo test` en verde en los tres crates tocados (16 de hardware — incluidos los de prioridad de sensor y coherencia de la lista real de la máquina—, 21 de protocolo con el round-trip del snapshot con discos, 12 de transporte), `cargo check -p nexodeck_ffi` limpio, `flutter analyze` limpio y **137 tests de Dart en verde**, con 11 nuevos entre `metric_strip_layout`/`microMetricRowsFor`, el formato de cifras y los cuatro casos de la tile de disco (escritorio ancho, un solo disco, teléfono vertical, riel que scrollea).

**Verificado en vivo en el equipo principal** con `cargo run -p nexodeck-hardware --example snapshot`: los 3 discos reales (C: 399/476 GB SSD, D: 913/931 GB HDD, E: 837/931 GB SSD), total 2149.5/2338.9 GB, **sin las unidades de Google Drive** que antes inflaban el agregado.

**No verificado**: la ruta WMI de la temperatura. En este equipo no hay ningún proveedor corriendo (los dos namespaces responden "no disponible"), así que la temperatura queda en `None` y el badge de °C no aparece — que es el comportamiento correcto, pero significa que la consulta contra LibreHardwareMonitor **nunca se ejercitó contra un proveedor real**. La ruta 1 (sensores del SO vía `sysinfo`) tampoco tiene sensores que leer en este Windows; su lógica de elección sí está cubierta por tests puros.

---

### UI: cuatro layouts para la pantalla principal (2026-08-26)

Un botón en la barra rota entre cuatro repartos de métricas y deck, persistidos en `app_settings` (`home_layout`). Feature nueva `features/home/` (dominio + controller + vista + botón).

Lo importante del diseño: **no son cuatro pantallas**. Salen de combinar el eje del panel de métricas (`MetricsPanelAxis`, que ya existía para el teléfono) con un `mirrored` nuevo que lo ancla al borde opuesto. `metricsTop` (el de siempre), `metricsLeft`, `metricsRight` y `deckFocus` (franja mínima abajo, todo el resto para botones). No hay ningún widget de métricas nuevo.

Dos cosas que salieron de verificarlo en la app real, no de leer el código:

- **El historial de los sparklines se perdía en cada cambio de layout.** Mover `MetricsRow` de una `Column` a un `Row` lo reconstruye desde cero, así que CPU y Red quedaban en "Recolectando..." ~30 s cada vez. Se veía en la primera captura; se arregló con una `GlobalKey`.
- **La tile micro se veía mal con ancho de sobra.** Esa franja nació para la ventana compacta (~52 dp por tile); en `deckFocus` cada tile se lleva ~250 dp y apilar gráfico sobre valor dejaba el donut de RAM/GPU aplastado y su porcentaje ilegible. Ahora pasa a fila por encima de `AppSizes.microMetricRowMinWidth`.

Verificado por Win32 (captura + clic, sin tocar el mouse) sobre el binario release: los cuatro layouts, el ciclado completo volviendo al primero, el tooltip, la preferencia sobreviviendo a un reinicio de la app, y el historial de sparklines intacto al cambiar. Más `flutter analyze` limpio y **143 tests de Dart en verde** (6 nuevos: el ciclado, el valor guardado inválido, el volteo del ícono, y el chevron del panel espejado —posición real y dirección—).

---

### Panel de procesos por métrica (2026-08-26)

Tocar la tile de CPU, RAM o GPU abre al lado del deck la lista de aplicaciones que más usan ese recurso, con su consumo, hace cuánto corren y un botón para cerrarlas. Crate: `nexodeck-hardware/src/processes/` + `pdh.rs`; bridge: `api/processes.rs`; UI: `features/processes/`.

**El colector no vive en `HardwareMonitor`**: `snapshot()` es la ruta de 1 s que comparten el FFI y el servidor (lo que ve el teléfono), y meterle ~370 procesos degradaría las dos por un dato que el teléfono no recibe. Tiene su propio `System`, cadencia de 2 s, y **solo existe mientras el panel está abierto**. Medido: **~20 ms por muestra** incluyendo la lectura de GPU — el miedo inicial (una medición de 850 ms con `Get-Counter`) resultó ser overhead de PowerShell, no de PDH.

Un solo stream con las **tres** listas, no uno por métrica: el uso de CPU por proceso es un delta contra la muestra anterior, así que re-suscribirse en cada clic vaciaría la lista cada vez que el usuario cambia de tile.

Tres cosas que salieron de verificar en vivo, no de leer el código:

- **`dwm.exe` informaba 20691 días corriendo** (o sea, desde 1970). Windows no deja leer el tiempo de arranque de los procesos del sistema: `start_time()` da 0 y la resta devuelve el epoch entero. Ahora eso es "desconocido" y se dibuja `—`.
- **La lista de CPU se llenaba de filas en "0.0%"** ordenadas alfabéticamente, y había que buscar entre ellas los tres procesos que consumían algo. Ahora CPU y GPU descartan lo que no llega a 0.05%; la memoria no lleva umbral porque ahí todo proceso ocupa algo.
- **El botón de cerrar de cada fila quedaba cortado** contra el borde de la ventana con el panel maximizado o anclado a la derecha.

Cerrar procesos exige **pid y nombre** (Windows reutiliza pids rápido y los de la lista son de hasta 2 s atrás), rechaza una lista de procesos críticos y no deja cerrar NexoDeck desde su propio panel. La fila no se borra al cerrar: pasa a "Cerrando…" y desaparece en la siguiente muestra, porque borrarla en el acto mentiría si el cierre falló por permisos.

**Bug preexistente corregido de paso** (`gpu_windows.rs`): el agregado de GPU por PDH filtraba `engtype_3D` con D mayúscula, que no matchea ninguna de las 620 instancias reales, y además tomaba el **máximo** entre instancias 3D —que son una por proceso, no una por adaptador como decía su comentario—, o sea que devolvía el uso del proceso más pesado en vez del de la GPU. Verificado con `Get-Counter`: el máximo por instancia daba 3.5% mientras la suma del motor 3D (y el Administrador de tareas) marcaban 5.5%. Los helpers de PDH se extrajeron a `pdh.rs` con el parseo en funciones puras y testeadas.

Verificado: **38 tests de Rust** y **172 de Dart** en verde, `flutter analyze` limpio, y en la app real por Win32 — los tres anclajes (izquierda, derecha, maximizado), el cambio de métrica sin que se reinicien los valores, la preferencia de anclaje sobreviviendo a un reinicio, el botón deshabilitado en la fila de NexoDeck, y el cierre real de un `notepad.exe` de descarte (1 → 0 procesos) más el rechazo de `csrss.exe` sin tocarlo.

**No verificable en este entorno**: el fallo por permisos al cerrar un proceso elevado (necesita un humano en el UAC) y la corrección del `engtype_3D` de punta a punta (con la NVIDIA presente, el agregado sale de NVML y esa ruta no corre).

---

### Métricas: los gráficos dibujan la pieza, y aparecen los nombres de los componentes (2026-08-26)

Las cinco tiles pasan de "un gráfico genérico y un número" a mostrar el componente real: **CPU** como encapsulado con el sparkline adentro, **RAM** como dos módulos DIMM que se llenan en orden con su porcentaje en el centro, **GPU** como la placa con dos ventiladores que giran al ritmo del uso, y **Disco** ya listaba cada unidad. La VRAM sale de los badges y pasa a una barra con la cifra adentro.

Además, cada tile dice **qué pieza es**: `components.rs` (nuevo) lee el modelo del procesador, la marca y velocidad de la memoria (WMI `Win32_PhysicalMemory`, prefiriendo `ConfiguredClockSpeed` sobre `Speed` para no mentir cuando el XMP no está activo), el nombre de la GPU y **el adaptador por el que sale el tráfico** — elegido por bytes acumulados, porque el primero de la lista suele ser un adaptador virtual. Se lee una sola vez por sesión: no cambia y las consultas son caras.

El **reloj de GPU** sí es dato vivo y viaja en el snapshot (campo nuevo al final del struct: **rompe el cable con binarios viejos**, hay que reinstalar PC y APK juntos).

**Bug de red corregido**: `discovery.rs` tomaba la primera IPv4 de un `HashSet` sin orden. La PC anuncia **seis** direcciones (la LAN, la del switch de Hyper-V y cuatro APIPA), así que el teléfono conectaba o no según con cuál se quedara ese arranque — y contra la de Hyper-V se quedaba reintentando para siempre, sin error visible. Verificado: el teléfono alcanza 192.168.1.8 y no 172.29.160.1. Ahora se descarta lo que nunca sirve, se ordena por probabilidad y **se prueba el puerto**: gana la que responde.

**Overflow encontrado en el S24**: la franja del móvil da tiles de ~100 dp, que entran en densidad completa pero no en las cuatro filas del layout apilado; la de GPU se pasaba 7 px con banda amarilla. Ahora el apilado exige alto suficiente y si no lo hay vuelve al reparto lateral.

Verificado: `flutter analyze` limpio, **181 tests de Dart** en verde, y en la app real por Win32 más captura del S24. Instalado en Windows (`C:\\Program Files\\NexoDeck`) y en el teléfono, ambos hablándose con el protocolo nuevo.

### Actividad de disco: señal de vida por unidad + desglose por proceso (2026-08-28)

La ficha de Almacenamiento pasa de mostrar solo capacidad a mostrar tambien
**actividad**: cada fila de `DiskUsageList` gana un `DiskHeartbeat` —una
linea base con puntas finas hacia abajo (lectura) o hacia arriba (escritura),
altura proporcional a los bytes de esa muestra, estilo señal de vida—. Tocar
la tile abre el panel de procesos con una 4ª columna "Disco", igual que ya
pasaba con CPU/RAM/GPU.

**Corrige una suposicion vieja** (`MetricKind.supportsProcessBreakdown`
decia que Disco necesitaba ETW): `sysinfo::Process::disk_usage()` ya usa
`GetProcessIoCounters` en Windows, la misma fuente que el Administrador de
tareas — sin ETW de por medio. El agregado *del sistema* (para la señal de
vida) sale de PDH `\LogicalDisk(*)\Disk Read/Write Bytes/sec` —por letra de
unidad, no por disco fisico, para matchear directo contra
`DiskUsage.mount_point` sin mapear disco↔volumen—, reusando
`pdh::read_counter_array` que ya existia para el contador de GPU.

Como `MetricSpec`/`buildMetricSpecs` es la unica definicion que comparten
`MetricsRow` (PC) y `ConnectedDeviceScreen` (Android), y esta ultima **ya**
pasaba `onSelectMetric` a `MetricsPanel` (dato que esta seccion tenia
desactualizado, ver mas abajo), el telefono gano la señal de vida y el panel
de procesos por Disco sin tocar mas que el historial en memoria — mismo
patron que `_cpuHistory`.

**Rompe el cable con binarios viejos** (campos nuevos en `DiskUsageWire` y
`ProcessGroupWire`/`TopProcessesWire` dentro de `V1`): hay que reinstalar PC
y APK juntos.

Verificado: `cargo test --workspace` (nuevos tests puros de
`disk_io`/`pdh::parse_logical_disk_instance` y de `processes::mod` con
disco) y `flutter test` (240 tests) en verde. **Pendiente de verificar con
clics reales**: la señal de vida contra actividad de disco real (copiar un
archivo grande) y que la 4ª columna del panel no quede apretada a 4
columnas — las alturas de fila (`AppSizes.diskRowExtent`/
`diskRowStackedExtent`) se calcularon a mano sin poder correr la app en esta
sesion.

Queda anotado para más adelante, investigado y sin implementar: [limitar CPU/RAM/GPU por aplicación](ideas/limitar-recursos-por-proceso.md).

De la [conexión fuera de la LAN](ideas/conexion-fuera-de-la-lan.md) ya está hecha la mitad interactiva: se puede emparejar y reconectar escribiendo la dirección de la PC a mano (`schemaVersion 7`), que con Tailscale en las dos puntas es todo lo que el deck necesita para andar con datos móviles. **Verificado sólo en tests**: falta ejercitarlo contra el teléfono real fuera de la red. Siguen sin empezar las notificaciones con la app cerrada (FCM) y el foreground service que evita que Doze corte el WebSocket.

---

### Servidor de control MCP + canal de avisos (2026-09-09)

**Cimiento de la Fase 8, y la primera boca de entrada de NexoDeck.** Hasta ahora
la app solo escuchaba en el 58643 del transporte, que es el cable del telefono
(postcard sobre TLS con pinning). Un programa de la propia maquina no tenia
forma de pedirle nada. El caso de uso que lo motiva: que **Claude Code le pida a
NexoDeck que avise al usuario por WhatsApp** durante una tanda de ODM de horas,
en vez de escribir un vigilante nuevo en bash cada vez.

Tres crates nuevos:

- **`nexodeck-notify`** — un aviso es un comando que se ejecuta. Sin WhatsApp,
  sin OpenClaw y sin SSH dentro: el pegamento de cada maquina vive en
  configuracion. Dos niveles (`Milestone` / `Always`), replicando los dos que
  `odm-watch.sh` aprendio a distinguir.
- **`nexodeck-control`** — servidor HTTP en `127.0.0.1:58646` que habla MCP
  (JSON-RPC sobre un unico POST, sin SSE ni sesiones: este servidor solo
  contesta). Tres herramientas: `notify`, `list_runs` y `tail_run`.
- Puente en `api/notify.rs` y `api/control.rs`, con las funciones presentes en
  los tres targets y el cuerpo cfg-gateado (Android no lleva el servidor).

Del lado Dart, la feature `features/control/` con el panel del menu "Mas":
encender el servidor, ver el token y la URL, gestionar canales, probarlos en
seco y ver el registro de lo que han pedido.

Se agrego tambien `CommandRunner::list()` a `nexodeck-actions`, que no existia:
la UI se entera de cada ejecucion por `RunEvent::Started` y se arma su lista,
pero el servidor de control responde a preguntas puntuales y nunca vio pasar
esos eventos.

**Decisiones que no son obvias** (el detalle esta en `CLAUDE.md`, seccion
"Servidor de control"):

- **Tres guardias en la puerta, ninguna redundante**: `Host` de la propia
  maquina (contra reenlace de DNS, que atar a 127.0.0.1 **no** detiene),
  rechazo de cualquier `Origin` (ningun navegador entra, ni con el token
  correcto) y token con comparacion sin fuga de tiempo.
- **El token no vive en Drift.** Es un secreto; va al directorio de datos del
  usuario, al lado de la clave privada del certificado del host
  (`nexodeck-transport/src/tls.rs`). Se persiste porque tiene que estar tambien
  en la configuracion del cliente.
- **El texto del aviso nunca se interpola en una linea de shell**: viaja por
  stdin o como un elemento de `argv` entero, asi que no hay nada que escapar.
- **Un ensayo en seco no es un fallo.** Definir el fallo como "no entregado" a
  secas hacia que comprobar un canal recien configurado contestara que estaba
  roto. Lo agarro el test de punta a punta.
- **Sin ningun canal configurado, `notify` falla en voz alta** en vez de
  callarse.

**Verificado**: `core/crates/nexodeck-control/tests/e2e.rs` levanta el servidor
y le habla por HTTP de verdad (401 sin token, 401 con token equivocado, 403 con
`Origin`, `initialize`, `tools/list`, ensayo en seco, entrega real, herramienta
inexistente, fallo por falta de canales, y que `stop()` cierra el puerto). Los
376 tests de Rust y los 354 de Flutter en verde, y `flutter build windows`
compila con la libreria nativa nueva. La invocacion real de Git Bash se
comprobo a mano con un script postizo: el mensaje llega intacto con comillas,
`$`, `;` y acentos, y `-l` fija `HOME`.

**Verificado despues, contra la app corriendo en debug** (automatizacion Win32,
la que describe CLAUDE.md): el servidor **arranca solo** al abrir la app con la
preferencia sembrada, sin tocar el panel; las cuatro guardias contestan lo que
deben (401 sin token, 401 con token equivocado, 403 con `Origin`, 403 con un
`Host` ajeno y el token bueno); `initialize`, `tools/list` y las tres
herramientas responden; y el panel se dibuja bien, con el ensayo en seco
funcionando desde el boton.

**Un fallo encontrado ahi y corregido**: el registro de actividad decia
"todavia no llego ninguna peticion" **habiendo llegado cuatro**. El stream de
eventos es un `broadcast` de tokio y lo que se emite sin receptores se pierde;
`controlActivityProvider` se suscribia al construirse, o sea al abrir el panel
por primera vez. Se monto `ControlActivityHost` en la raiz de `MaterialApp`,
junto a `RunToastHost` y por el mismo motivo. Sin eso, los rechazos --que son
justo lo que hay que poder mirar despues-- solo se veian si el panel ya estaba
abierto en ese momento.

Se agrego `app/tool/seed_control_e2e.dart` para poder repetir todo esto:
enciende el servidor y siembra un canal directo en la base, con la app cerrada.

**Lo que sigue sin verificar**: mover el interruptor del panel con un clic real
(se verifico el estado que muestra, no el toque), y que el token que quedo en la
variable de entorno del usuario funcione desde un cliente MCP de verdad -- eso
necesita reiniciar el cliente para que herede la variable.

### Modo solo teléfono + lógica de host fuera de la interfaz (2026-09-15)

**Qué es.** Un modo, solo en Windows, en el que NexoDeck sigue atendiendo al
teléfono sin ventana ni render, para no gastar CPU/GPU en una interfaz que
nadie mira. Se entra y se sale desde el icono de la bandeja del sistema, o desde
el menú "Más" → "Solo teléfono". La app **arranca siempre con interfaz**, también
al iniciar Windows: fue decisión explícita del usuario. El detalle y los gotchas
están en la sección "La logica de host vive fuera del arbol" de `CLAUDE.md`.

**Qué cambió:**

- **`HostRuntime`** (`features/host_runtime/`) concentra todo lo que atiende al
  teléfono, que antes vivía en `_HomeShellState` y en cuatro widgets envoltorio.
  `main()` crea el `ProviderContainer` y la UI lo recibe con
  `UncontrolledProviderScope`.
- **Bug corregido de paso:** en modo compacto `_HomeShell` no se montaba, así que
  el teléfono no recibía el catálogo, sus acciones no se ejecutaban y Rust
  rechazaba las reconexiones.
- En modo solo teléfono `MyApp` no construye nada (ni `MaterialApp`): sin árbol no
  hay `NeuralBackground` ni charts repintando.
- Bandeja (`tray_manager`), salida ordenada sin icono fantasma, e instancia única
  en el runner de Windows (mutex + mensaje registrado + canal `nexodeck/instance`).
- **Emparejamiento a demanda:** sin interfaz, Rust retiene el `PairHello` 15 s
  (`set_on_demand_pairing_grace`), la PC abre una ventana emergente con el PIN y el
  mismo intento del teléfono sigue adelante. Evento local nuevo
  `PairingRequestedWhileDisarmed`; **no cambia el protocolo del cable**, así que no
  obliga a reinstalar el APK.

**Verificado:**

- 390 tests de Flutter en verde, incluido `test/host_runtime_test.dart` (7 casos
  sin montar ningún widget: push al conectar, dos `ExecuteAction` idénticos corren
  dos veces, acción inexistente, reenvío del catálogo, sincronización de
  autorizados).
- Todos los tests de `nexodeck-transport`, incluido el nuevo
  `tests/on_demand_pairing.rs`: el PIN llega al mismo intento, el rechazo espera
  la gracia y el enfriamiento rechaza al instante y sin aviso.
- `cargo check` de `nexodeck_ffi`, `bridge:gen`, `flutter analyze` sin avisos
  nuevos, y `flutter build windows --debug` compila el runner con `/W4 /WX`.

**Lo que sigue sin verificar** (requiere la app corriendo y el S24):

- E2E real: con la PC en modo compacto y en solo teléfono, reconectar, recibir el
  catálogo, ejecutar acciones y usar el chat de IA.
- El emparejamiento a demanda contra el teléfono real (la emergente, el PIN que
  llega sin reintentar, aceptar y rechazar).
- La bandeja en vivo: el menú, que se cierre al hacer clic afuera, que el icono
  vuelva tras reiniciar `explorer.exe` y que no quede fantasma al salir.
- La instancia única con la app oculta (abrir el acceso directo muestra la
  ventana y queda un solo proceso).
- **La medición del ahorro**: CPU y GPU del proceso en pantalla completa,
  compacto y solo teléfono. Tampoco está verificado que el engine de Windows deje
  de hacer vsync con la ventana oculta; el desmontaje del árbol elimina los
  tickers igual.

### Buzón de documentación (2026-09-15, rama `feat/docs-inbox`)

**Qué es.** Claude Code manda hallazgos a NexoDeck por MCP ("manda los hallazgos a
NexoDeck", "actualiza la documentación del proyecto de IA") y un modelo prepara
una **propuesta** de cambios a los documentos del proyecto; el usuario la aprueba
en la app antes de que se escriba nada, y NexoDeck no toca git. Es la primera
mitad de una idea más grande: la segunda son los vigilantes de tareas largas
(ODM) con avisos por WhatsApp, que queda como iteración 2. Detalle y gotchas en
la sección "Buzon de documentacion" de `CLAUDE.md`.

**Qué entró:**

- `nexodeck-docs`: almacén en ficheros propiedad de Rust, cuatro operaciones por
  ancla sobre Markdown, validación, aplicación con hash y deshacer, y el
  trabajador (calma de 90 s, remoto primero y local solo si ya está levantado,
  reintentos, reparación del JSON del modelo).
- `nexodeck-ai`: `response_format` y `local_endpoint()`, sin tocar el chat.
- `nexodeck-control`: `submit_findings`, `list_doc_projects` y `finding_status`.
- `api/docs.rs` y la feature `docs_inbox` (botón con contador, menú "Más" y
  bandeja del sistema).
- Fuera del repo: la skill `send-findings` y una sección en el `CLAUDE.md` de
  `D:\Repositorios`, el MCP `nexodeck` activado en su `settings.local.json`, la
  carpeta `ExampleMaps/docs` con índice y diario (sin commitear, a propósito) y
  la configuración de esta máquina con los proyectos `ia` y `mapas`.

**Verificado:**

- `nexodeck-docs`: 62 tests (diario sintético de 8.000 líneas, CRLF y BOM,
  rollback, y el trabajador con un modelo de mentira: calma, reparación, reintento,
  paso al local, clave inválida, revisión tras edición a mano, `stale`, cola
  retenida, deshacer).
- `nexodeck-control`: 33 unitarios + el e2e contra el servidor de verdad, con la
  sección del buzón.
- `nexodeck-ai`: 178 tests. `cargo clippy` sin avisos en lo nuevo.
- `bridge:gen`, `flutter analyze` sin avisos nuevos y `test/docs_inbox_test.dart`.
- La suite completa de Flutter (394 tests) y `flutter build windows --debug`.

**Lo que sigue sin verificar:**

- Una propuesta real contra DeepSeek sobre el diario de IA de verdad (483 KB), y si
  el presupuesto de contexto de 120.000 caracteres le sienta bien.
- El respaldo local contra el sidecar de verdad.
- La app corriendo: el diálogo, aprobar y ver el `git diff` en ExampleApi, el
  contador en la bandeja.
- `submit_findings` desde una sesión de Claude Code real (el MCP recién activado
  entra en vigor en la siguiente sesión).

### Asistente de notas (2026-09-15, rama `feat/notes-assistant`)

**Qué es.** Una bóveda de notas en markdown, compatible con Obsidian, que NexoDeck
lee y relaciona con otras notas, con los hallazgos del buzón y con los commits de
los repositorios. Cinco agentes en cadena (lector, memoria, código, crítico y
redactor) proponen cómo completar una nota: resumen, relacionados, tareas y
preguntas abiertas. El usuario aprueba en el buzón, como cualquier otra propuesta.
Detalle en la sección "Asistente de notas" de `CLAUDE.md` y en
[`ideas/asistente-de-notas.md`](ideas/asistente-de-notas.md).

**Qué entró:**

- `nexodeck-docs`:
  - bóvedas como proyectos `vault`, con roles por carpeta, y nada de `privado/`
    ni de notas con `ai: false`;
  - `add_section` y `set_frontmatter_key`;
  - redacción de secretos;
  - índice en memoria con búsqueda BM25 sobre notas, hallazgos y commits
    (ADR 0004);
  - la cadena de agentes con su traza;
  - el digest dentro del trabajador, con bloqueo por nota y modo automático.
- `nexodeck-control`: `search_notes`, `get_note` y `digest_note`.
- `api/notes.rs` y la feature `notes` (diálogo, botón en la barra, entrada en
  "Más"); el buzón distingue las propuestas que vienen de una nota.

**Verificado:**

- `nexodeck-docs`: 110 tests, con un modelo de mentira que recorre la cadena
  entera. Cubren:
  - la ronda extra del crítico, que no se repite;
  - el id inventado que se descarta;
  - el secreto que no sale;
  - la nota con `ai: false` sin ninguna llamada;
  - el fallo de red a mitad;
  - digest manual hasta aprobar;
  - bloqueo por nota;
  - modo automático que procesa una sola vez;
  - regenerar.
- `nexodeck-control`: unitarios y el e2e con una bóveda de prueba (ni la nota
  privada, ni la de `ai: false`, ni un `Password=` salen por MCP).
- `bridge:gen`, `cargo clippy` sin avisos en lo nuevo, `flutter analyze` sin
  avisos nuevos y la suite completa de Flutter.

**Lo que sigue sin verificar:**

- Un digest real contra DeepSeek sobre notas de verdad: si los prompts dan
  relaciones útiles y si el presupuesto de contexto alcanza.
- La app corriendo: el diálogo, "Abrir en Obsidian", aprobar desde el buzón.
- `search_notes` y `digest_note` desde una sesión real de Claude Code.
- La bóveda misma: todavía no existe; la migración desde OneNote está descrita en
  la idea.

### Guardar una nota desde Claude Code (2026-09-16, rama `feat/note-editor`)

**Qué es.** Una herramienta MCP (`save_note`) para que una sesión de Claude Code
guarde en la bóveda un texto que el usuario acaba de pedirle: "el resumen que me
acabas de dar mándalo a NexoDeck", y la nota aparece al momento.

**Decisiones del usuario:** nota nueva en `inbox/`, escritura directa sin pasar por
el buzón, visible para los agentes como cualquier otra, y **el markdown lo sanea
NexoDeck**, sin fiarse de que el que llama lo mande bien.

- `notes/capture.rs` (nuevo): saneado del markdown, título y ruta, todo puro y
  testeado. Desenvuelve una respuesta citada entre cercas, descarta el frontmatter
  que venga en el texto, deja un solo título, normaliza el espaciado y **no toca el
  interior de un bloque de código**.
- `DocsService::capture_note`: escribe sin pisar nunca. Sin ruta busca nombre libre
  (`(2)`); con una ruta que ya existe, añade al final una sección con su hora.
- `nexodeck-control/src/tools.rs`: la herramienta, con su descripción diciendo
  cuándo usarla y cuándo no (para documentar un proyecto sigue siendo
  `submit_findings`).
- Es la **única** vía que escribe en la bóveda sin aprobación, y la excepción queda
  acotada en `CLAUDE.md`: lo que cambia no es la seguridad, es quién decide.

**Verificado:** 10 tests del saneado, el e2e de `nexodeck-control` ampliado (guarda
contra una bóveda de verdad, comprueba el frontmatter escrito, que el que venía en
el texto no entra, que la cerca se desenvuelve, que un segundo envío a una nota
existente **no pisa** lo que había, y que sin buzón lo dice en vez de fallar raro),
`cargo clippy` sin avisos en lo nuevo.

**Un fallo que solo apareció en el e2e:** el texto llega envuelto en una cerca **y**
con frontmatter dentro. Quitando el frontmatter antes de desenvolver no hay nada que
quitar, y el `ai: false` acababa en la nota. Hay un test unitario que fija el orden.

**Lo que sigue sin verificar:**

- El uso real desde una sesión de Claude Code contra NexoDeck abierto (hasta ahora,
  tests).
- Cómo queda una nota larga de verdad en el editor y en Obsidian.

### Agrupaciones de notas (2026-09-16, rama `feat/note-editor`)

**Qué es.** Agrupar notas con un nombre y un color sutil, desde la app, la ventana del
editor o el MCP. Sin agrupación, una nota vive en `inbox/`.

**Decisiones del usuario:** cada agrupación es **una carpeta de verdad** de la bóveda
(no una clave de frontmatter); una nota está en **una sola**; **PC primero**; toda
carpeta existente cuenta como grupo; y al mover **se arreglan solos los enlaces**.

- `notes/groups.rs` (nuevo, puro): qué carpeta es grupo, reservadas, validación y
  listado. El catálogo de nombre y color va en `NotesConfig.groups`.
- **`move_note`, que no existía en ninguna capa**: se niega con una propuesta
  pendiente, nunca pisa, reapunta los digests y reescribe los `[[enlaces]]` por ruta
  en toda la bóveda.
- MCP: `list_note_groups`, `create_note_group`, `move_note_to_group` y `group` en
  `save_note`.
- App: barra de agrupaciones con su color, borde teñido en cada nota, diálogo de
  crear/editar con la paleta del deck, y "Mover a…" en la cabecera de la nota.
- Ventana del editor: color por fila y filtro por agrupación en la barra lateral y la
  bienvenida, y selector de agrupación al crear una nota.

**Verificado:**
- Rust: 151 tests de `nexodeck-docs` (10 del módulo de grupos, 4 de reescritura de
  enlaces y 3 de mover sobre bóveda real), 33 unitarios y el e2e de
  `nexodeck-control` (crea un grupo, guarda dentro, rechaza `Diario`, y mueve una
  nota comprobando en disco que el enlace de otra se reescribió), 26 de
  `nexodeck-editor`. `clippy` limpio en los cuatro crates.
- Flutter: `flutter analyze` sin avisos nuevos y **430 tests en verde**. Los 4 que
  fallan son de `metrics_panel_test.dart`, de otra sesión.
- Página: `typecheck` y 28 tests de vitest. Construida en los dos pasos: la ventana
  y la copia del móvil llevan las agrupaciones.
- Se arregló un test que había quedado roto en la tanda de `save_note` (la cuenta de
  herramientas MCP) y no se había visto.

**Lo que sigue sin verificar:**
- **Con la app corriendo**: el diálogo, la barra, el color en claro y oscuro, y mover
  una nota enlazada mirándolo en pantalla. La app abierta tiene el binario anterior.

### Notas locales (2026-09-16, rama `feat/note-editor`)

**Qué es.** Añadir carpetas propias con `.md` ya ordenados. NexoDeck las lee y las
actualiza **en su ruta, sin copiarlas**, en árbol y con una etiqueta sutil "Notas
locales". Detalle y decisiones en `CLAUDE.md` → "Notas locales".

**Decisiones del usuario:** se puede hacer todo, como en la bóveda (editar, agrupar,
mover); se ven en árbol de carpetas; también van al móvil; y una carpeta que ya es
proyecto del buzón no se deja añadir.

- `notes/roots.rs` (nuevo): identidad `@<id>/<ruta>`, `locate`, `link_form` y las
  reglas de solapamiento. El índice, los digests, el orquestador, la edición, el
  manifiesto del móvil y la papelera pasan por `locate`.
- Mover entre carpetas con copia verificada por sha256; agrupaciones por carpeta.
- App: árbol en la pestaña Notas, "Carpetas locales" en el diálogo de la bóveda,
  Obsidian por la ruta real, "Mover a…" con carpetas, carpeta al crear una agrupación.
- Ventana del editor: árbol con `<details>` y etiqueta, carpeta al crear una nota,
  enlaces relativos dentro de la carpeta, y `resolve_link` desde la nota de origen.
- MCP: `folder` en `create_note_group` y `move_note_to_group`; `list_note_groups`
  enseña las carpetas. Añadir carpetas **no** está en el MCP, a propósito.

**Verificado:**
- Rust: 169 tests de `nexodeck-docs` (roots, índice con dos raíces, mover entre dos
  directorios temporales, regla del buzón con los casos reales), 27 de
  `nexodeck-editor`, y los 33 unitarios más el e2e de `nexodeck-control` con una
  segunda carpeta: `get_note` sobre `@apuntes/…`, crear una agrupación dentro, y
  moverla a la bóveda comprobando en disco que el original se fue.
- Todos los tests previos de una sola raíz pasan sin tocarlos: es la prueba de que
  la bóveda principal no se movió.
- Flutter: sin avisos en `features/notes`, y 443 tests en verde (los 4 de
  `metrics_panel_test.dart` que fallan son de otra sesión).
- Página: `typecheck` y 34 tests de vitest; construida en los dos pasos.

**Lo que sigue sin verificar:**
- **Con la app corriendo**: añadir una carpeta real con subcarpetas, verla en árbol en
  la app y en la ventana, editar una nota y comprobar el fichero en su ruta, e intentar
  añadir `ExampleApi\docs` para ver el rechazo.
- Un móvil real con una carpeta local, y quitarla después.

**Añadido el mismo día, a petición del usuario:** gestionar las carpetas desde la
propia ventana de notas. Menú ⋮ junto al buscador (importar notas locales, importar
espacio de NexoDeck, exportar a zip) y clic derecho para quitar una carpeta local.
Diálogos nativos con `rfd`, abiertos por Rust. Verificado: 7 tests nuevos en
`nexodeck-docs` (176 en total), 3 de sesión en `nexodeck-editor` (30), 35 de vitest,
`typecheck` y clippy limpios, y los dos bundles construidos. **Sin verificar con la app
corriendo**: los diálogos nativos, el menú y abrir el zip exportado.
- Mover **desde la ventana del editor**, que todavía no existe.
- **El móvil**: no se tocó el protocolo. Un movimiento llega como borrado + alta, y
  una copia con cambios sin sincronizar puede quedar duplicada.

### Editor de notas (2026-09-15, rama `feat/note-editor`)

**Qué es.** Escribir las notas desde NexoDeck, sin salir a Obsidian:
- una **ventana nativa con WebView2** (`wry` + `tao`) y **CodeMirror 6** dentro;
- vista previa en vivo: las marcas se ocultan fuera de la línea del cursor;
- casillas de tarea que se marcan con un clic;
- `[[` con autocompletado contra el índice;
- paleta de comandos, esquema lateral y modo concentración;
- guardado automático a 1 s y conflictos que nunca pisan lo que cambió por fuera;
- las notas de `privado/` también se editan.

Detalle en la sección "Editor de notas" de `CLAUDE.md`.

**Qué entró:**

- `nexodeck-docs` (`notes/editing.rs`): abrir, guardar con hash base, crear, nota
  del día y destinos de enlace. Conserva CRLF y BOM, y es anti-junction.
- `nexodeck-editor`:
  - `web/` (TypeScript, esbuild, vitest) construido a `assets/`, que va commiteado
    y embebido;
  - `protocol.rs`;
  - `session.rs`, la lógica sin ventana;
  - `host.rs`, el hilo de tao con la ventana;
  - el ejemplo `open_note`.
- `api/editor.rs`.
- En el diálogo "Notas": "Editar", "Nota de hoy" y "Nota nueva…".
- El script de Melos `editor:build`.

**Verificado:**

- La prueba de viabilidad del paso 0, dentro de la app real:
  - la ventana se abre desde un hilo de frb;
  - se escribe "ñandú acción ¿qué pasó?" con teclas muertas;
  - cerrar y reabrir reutiliza el event loop;
  - la ventana de Flutter sigue bien.
- **Tests:**
  - los de `nexodeck-docs/notes/editing.rs`;
  - los 17 de vitest y el typecheck de la página;
  - los 18 de `nexodeck-editor`, entre ellos los 10 de `session.rs` contra un
    backend falso;
  - los de `notes_test.dart`.
- **Compilación:** `clippy -D warnings` de `nexodeck-editor`, `bridge:gen` y
  `cargo check` de `nexodeck_ffi`, más `flutter analyze` sin avisos nuevos y
  `flutter build windows --debug`. `wry` no aparece en el árbol de Android.
- **La prueba real, el 15-sep-2026, con NexoDeck debug y una bóveda de prueba**
  (manejada por Win32: capturas, clics y teclado real):
  - "Editar" desde el diálogo abre la ventana con la nota renderizada;
  - escribir "ñandú, acción, ¿qué pasó?" guarda solo a 1 s y conserva el BOM y el
    CRLF del fichero;
  - la casilla deja `- [x]` en disco;
  - `[[pro` autocompleta a `[[proyectos/NexoDeck]]`;
  - Ctrl+clic en un wikilink abre esa nota;
  - una edición por fuera da la banda de conflicto y el disco no se pisa;
    "Quedarme con lo mío" sobrescribe;
  - cerrar con cambios pendientes los guarda antes;
  - "Nota de hoy" crea `diario/2026-09-15.md` con su encabezado;
  - "Nota nueva…" en `privado/` crea la nota con candado, y no sale en la lista.
- **Tres fallos que solo se vieron en la prueba real, corregidos y vueltos a
  verificar:**
  - con la banda de conflicto oculta, la barra de estado se quedaba con la fila
    flexible y el editor acababa a media ventana;
  - tras resolver el conflicto, el foco se perdía y lo que se escribía no llegaba
    al editor;
  - el frontmatter salía en el esquema como encabezado.

  Además, con un título largo la barra de herramientas se partía en dos filas.

**Lo que sigue sin verificar:**

- El instalador no trae WebView2: Windows 11 lo incluye, y en Windows 10 sin
  runtime el diálogo dice por qué no hay botón de editar. No se probó una máquina
  sin runtime.
- **Detalles vistos y no corregidos**, que son del diálogo de notas y no del
  editor:
  - la vista de solo lectura del diálogo enseña el frontmatter como texto con una
    regla;
  - la ruta larga de la bóveda se parte en tres líneas en la cabecera;
  - el recuento de palabras del editor cuenta el frontmatter.

### Ventana de notas (2026-09-15, rama `feat/note-editor`)

**Qué es.** El usuario probó el editor y pidió que las notas no fueran un diálogo en
medio de NexoDeck, sino una ventana independiente que se pueda maximizar y
minimizar. La ventana del editor pasó a ser la app de notas completa:

- **Izquierda:**
  - una búsqueda en notas, hallazgos y commits;
  - la pestaña **Notas**;
  - la pestaña **Tareas**, con las vencidas primero; pulsar una abre la nota en
    esa línea;
  - la pestaña **Asistente**, con los digests y su traza;
  - los botones "Nota de hoy" y "Nota nueva".
- **Centro:** el editor, o una bienvenida con las recientes.
- **Derecha:** el esquema, quién enlaza la nota, las notas parecidas, y sus
  digests con "Procesar nota".

El botón "Notas" de NexoDeck abre esa ventana. El diálogo de Flutter queda para
cuando no hay WebView2.

**Qué entró:**

- **`nexodeck-editor`:**
  - DTOs y mensajes nuevos: foto de la bóveda, búsqueda, detalle, digest, aviso,
    abrir, crear, nota de hoy, buzón y refrescar;
  - la ventana se abre sin nota (`Editor::show`);
  - trabajos lentos en otro hilo (`Job` / `Fetched`), con lecturas de la bóveda que
    no se amontonan;
  - `Editor::changed`;
  - tamaño y posición recordados en la sesión.
- **`api/editor.rs`:**
  - `open_notes_window`;
  - `watch_docs`, que refresca la ventana con cada aviso del buzón;
  - el backend lee `notes_overview`, `search_notes`, `note_details` y
    `digest_note`.
- **Página:**
  - `sidebar.ts`, `contextPanel.ts`, `welcome.ts`, `digestView.ts` y
    `newNoteDialog.ts`;
  - `labels.ts` y `notePaths.ts`, puros y con tests;
  - atajos Ctrl+Shift+E (lista), Ctrl+J (panel) y Ctrl+Shift+F (buscar en la
    bóveda);
  - "Ir a…" de todas las notas en la paleta.
- **Flutter:**
  - `openNotes`;
  - el evento `show_inbox` con `notesInboxOpenerProvider`, que trae la ventana
    principal y abre el buzón.

**Verificado:**

- **Página:** typecheck y 25 tests de vitest.
- **Rust:** 26 tests de `nexodeck-editor` y `clippy -D warnings`. Los tests nuevos
  de la sesión cubren:
  - la ventana sin nota;
  - lecturas que no se amontonan;
  - destinos de `[[` que aparecen con notas nuevas;
  - detalle tardío o de una nota privada;
  - digest que avisa y refresca;
  - búsqueda vacía sin backend;
  - buzón.
- **FFI y Flutter:** `bridge:gen` y `cargo check` de `nexodeck_ffi`, `flutter
  analyze` sin avisos nuevos y los 10 tests de `notes_test.dart`.

**Lo que sigue sin verificar:**

- **La ventana nueva en pantalla**, con la app recompilada. La prueba real anterior
  fue del editor solo, antes de este cambio, y el exe no se recompiló porque la app
  de prueba estaba abierta. Falta comprobar:
  - maximizar y minimizar;
  - que recuerde el tamaño;
  - la lista y la búsqueda;
  - tareas que abren en su línea;
  - "Procesar nota" contra DeepSeek;
  - "Ver la propuesta en el buzón", que tiene que traer la ventana principal;
  - que la lista se actualice al guardar.
- La traza de un digest real en la pestaña Asistente: hasta ahora solo se vio con
  datos de muestra.

### Notas en el móvil (2026-09-15, en curso, rama `feat/note-editor`)

**Qué se busca.** Que el teléfono tenga las notas: la misma página del editor en un
WebView, la PC como motor, y el móvil **funcionando entero sin conexión** (ver,
editar, crear, borrar) con sincronización automática al reconectar. Decisiones del
usuario: la copia del móvil lleva la bóveda entera, privadas incluidas, y un choque
conserva las dos versiones. Detalle en la sección "Notas en el móvil" de
`CLAUDE.md`.

**Paso 0 — viabilidad del WebView, verificado en un Armor X12 (Android 13, 32 bits):**

- la página del editor se dibuja dentro del APK y ejecuta JavaScript;
- el teclado llega a la página (cada pulsación se vio en el log);
- 841 KB en una sola cadena cargan sin problema;
- el plugin elegido es `webview_flutter`, el oficial, y su `minSdk 24` coincide con
  el de Flutter por defecto: no hubo que subir nada ni dejar teléfonos fuera.

**Paso 1 — la bóveda para un cliente con copia (`nexodeck-docs/src/notes/sync.rs`):**

- `vault_manifest()`: todas las notas con hash y fecha, `privado/` incluido, sin
  carpetas ocultas ni enlaces simbólicos;
- `delete_note()`: mueve a `.trash/`, respeta el hash (conflicto sin tocar el
  disco), no falla al repetir y no pisa lo ya borrado;
- 6 tests nuevos; 124 en el crate, todos en verde.

**Paso 2 — el contrato con el móvil (`nexodeck-protocol`):**

- tres variantes al final de `MessageV1`: `NotesRequest`, `NotesResponse` y
  `NotesChanged`, con sus enums internos;
- `request_id` propio, el primero del protocolo: el teléfono puede tener varias
  peticiones en vuelo (manifiesto, textos, la tanda encolada sin cobertura);
- la respuesta llega siempre, también al fallar; el aviso de cambio no lleva el
  cambio; los cambios viajan en tanda y en orden; un choque nunca escribe y
  devuelve lo que hay en disco;
- 8 tests de ida y vuelta nuevos (50 en el crate), clippy limpio, y el transporte,
  la FFI y el relay siguen compilando: ningún `match` sobre `MessageV1` se quedó
  corto.

**Paso 3 — la PC atiende al teléfono (`nexodeck-transport`, `nexodeck-ffi`):**

- `notes.rs` en el transporte: el trait `NotesVault` y la resolución de cada
  petición, con 3 tests;
- la bóveda se engancha en tiempo de ejecución (`set_notes_vault`), porque el
  transporte va también al `.so` de Android y no puede depender de
  `nexodeck-docs`; se registra al abrir el buzón y al arrancar el transporte,
  para cubrir los dos órdenes posibles;
- las lecturas van a `spawn_blocking` y la respuesta sale por el canal de la
  sesión: el teléfono no se queda sin snapshots mientras la PC lee la bóveda;
- `notify_notes_changed()` avisa a las sesiones vivas con cada cambio del buzón;
- `api/notes_vault.rs` traduce entre los tipos de la bóveda y los del cable, y
  convierte "borrar lo que ya no está" en éxito, para que un teléfono que
  reintenta pueda terminar.

**Verificado:** 27 tests del transporte (3 nuevos), la FFI compila, clippy no
señala ninguna línea de lo nuevo, y el árbol de dependencias del transporte para
Android sigue trayendo solo `protocol`, `hardware` y `relay`: ni `nexodeck-docs`
ni `nexodeck-ai`.

**Paso 4 — la base local del móvil (Drift, `features/notes/`):**

- dos tablas nuevas en `schemaVersion 13`: `note_mirror` (la copia de la bóveda,
  privadas incluidas) y `note_outbox` (lo escrito que la PC todavía no sabe);
  guardar toca las dos en la misma transacción;
- `NotesMirrorDao` no deja que lo que llega de la PC pise una nota con cambios
  sin mandar: guarda la versión de la PC al lado y elige el usuario;
- `planNoteSync` y `localNoteHash` (`domain/note_sync.dart`) son puros y
  testeados: qué pedir, qué borrar y qué conservar;
- `NotesSyncEngine` arranca en `main()` **fuera del árbol de widgets**, como
  `HostRuntime`: vacía la cola, pide el manifiesto, compara y trae los textos en
  lotes, correlacionando cada petición por su `request_id`;
- el `localHash` del espejo **no es comparable con el hash de la PC** (allí es el
  sha256 del fichero con BOM y CRLF); solo marca si la copia está sucia.

**Pasos 5 y 6 — la página en modo táctil y la pantalla de Notas (2026-09-16):**

Petición del usuario: lo básico de Notas en el móvil, sin importar, exportar,
carpetas ni asistente.

- Botón "Notas" en `ConnectedDeviceScreen` → `MobileNotesScreen`: la página del
  editor en un WebView, con el tema de la app, el atrás de Android y una franja que
  dice si hay conexión y cuánto falta por mandar.
- `MobileNotesHost` contesta a la página **contra la copia local**: foto de la
  bóveda, abrir, guardar, crear, nota del día, buscar, enlaces entrantes y resolver
  `[[enlaces]]`, con las mismas reglas de carpeta local que la PC.
- La página en modo móvil (`data-mobile`): lista y nota a pantalla completa, una cada
  vez; sin panel de la nota, sin pestaña del asistente, sin menú de carpetas;
  herramientas de formato en una fila que se desliza.
- Conflictos con la misma banda que en la PC; mensaje nuevo `conflictResolved`, que
  Rust ignora.

**Verificado:**
- 12 tests de Dart (`test/mobile_notes_test.dart`): la foto como la da la PC,
  búsqueda sin tildes, resolver enlaces (carpeta, ruta exacta, nombre único),
  enlaces entrantes, guardar, nota del día sin duplicar, el conflicto que bloquea el
  guardado y se resuelve, y que lo de la PC se ignora sin romper.
- `flutter analyze` sin avisos en lo nuevo; 30 tests de `nexodeck-editor`; typecheck
  y 35 de vitest; los dos bundles construidos.
- Capturas de Edge sin interfaz a tamaño de teléfono. Sirvieron para encontrar y
  arreglar que la nota salía más ancha que la pantalla.

**Sin verificar:** nada en un teléfono real todavía (escribir, el atrás, la
sincronización de lo escrito sin cobertura). Los enlaces web de una nota no abren en
el móvil.

**Verificado:** 10 tests nuevos (`note_sync_test.dart`) —el plan puro, el hash y
cinco vueltas del motor contra SQLite en memoria—, `flutter analyze` sin ningún
aviso de lo nuevo, y la suite entera en 414 pasados. Los 4 fallos que quedan son
de `metrics_panel_test.dart` y vienen de otra sesión (el cambio de MHz a GHz sin
actualizar la expectativa), no de esto.

**Lo que sigue sin verificar:**

- **El camino entero contra un teléfono real**: pedir manifiesto, textos y aplicar
  cambios por el cable. Hasta ahora solo hay tests de las piezas, con una PC de
  mentira al otro lado.
- **Cortar el WiFi, editar y volver**: es el caso que justifica toda la cola, y
  solo se puede comprobar con el teléfono en la mano.
- `cargo check` del transporte para Android **no se pudo correr** en este equipo:
  falta el compilador del NDK (`aarch64-linux-android-clang`) y `ring` no
  construye. La comprobación se hizo con el árbol de dependencias.
- **Lo que necesita dedos humanos en el teléfono**: tildes con teclas muertas, el
  corrector, colocar el cursor y seleccionar tocando, y marcar una casilla.
- La barra de herramientas sale cortada a lo ancho en el móvil: hay que rehacerla
  para pantalla táctil (probablemente una fila deslizable sobre el teclado).
- **La CSP por `<meta>` no se aplica** con la página incrustada: Android la ignora
  y el documento queda sin contexto seguro. Antes de dar esto por bueno hay que
  decidir si la página se sirve por un origen propio.
- Lo que queda del plan: **la página en modo táctil** (paneles como cajones y la
  barra de formato sobre el teclado) y **la pantalla de Notas en Android**, con su
  aviso de sin conexión y su lista de conflictos.

## En curso

### Pantalla principal como centro de control (2026-09-23)

Rediseño de la pantalla de **escritorio** para que el chat del asistente sea lo
principal: métricas a la izquierda, chat al centro (el mismo chat de siempre,
no uno nuevo) y panel de acciones compacto a la derecha, todos ocultables y con
divisores. Un switch **Perfil A / Perfil B / Perfil C / Apagado** (que muestra
los modelos elegidos de cada perfil) arranca o cambia el perfil del stack
multiagente por el runner de comandos. Plan
y fases en [`docs/ideas/centro-de-control.md`](./ideas/centro-de-control.md).

**F1-F5 hechas (2026-09-23).** El centro de control es el `HomeLayout` por
defecto (`controlCenter`); el chat se reutiliza como `AiAssistantPanel`
(`embedded: true`) y su estado vacío es `ChatWelcome`. Métricas y acciones se
reparten con dos divisores (`PanelSlot.metricsRail` / `PanelSlot.actionsPanel`)
y los dos se pliegan. El panel de procesos y el de ejecuciones dejaron de
acoplarse al costado y se abren como **diálogo** (`showProcessPanelDialog`,
`showRunPanelDialog`), así que `PanelSlot.processPanel`/`runPanel` ya no
existen. `flutter analyze` limpio (9 `info` preexistentes) y 58 tests en verde.
**Falta:** el panel de ejecuciones es modal y su motivo original era vigilar un
comando de horas sin que tape el deck; convertirlo en overlay no modal queda
pendiente.

### «Configura tus perfiles» en el asistente (2026-09-25)

La configuración del asistente (`ai_setup_wizard.dart`) pasó de tener dos
secciones («Quién puede contestar» + «Elegí el modelo») a una sola:
**«Configura tus perfiles»** (`profiles_section.dart`). Muestra el **motor
configurado** (llama.cpp integrado, Ollama, pasarela vLLM) y los dos perfiles del
stack (A/B), cada uno con un slot **Router** y otro **Pensamiento** elegibles
entre un catálogo **por motor** (rol del stack, llama.cpp, Ollama, Claude Code o
servicio por internet). Cada modelo dice si está descargado; los de llama.cpp se
descargan con barra inline (`downloadAiModel`, sin arrancar el motor), y Ollama y
vLLM por el runner capturado (panel de Ejecuciones). La detección de descargados
corre sola al abrir la pantalla y **no levanta WSL2**.

La elección se guarda en `llm-stack/scripts/profiles.json`, que `serve-profile.sh` lee por
`profile-roles.py` (con fallback al mapeo histórico). La pasarela
(`llm-stack/gateway/`) acepta backends remotos
(`{url, api_key_file, upstream_model}`), cambia la cabecera `Authorization` por la
del servicio y recarga `gateway.json` en caliente. Verificado: `flutter analyze`
limpio (9 `info` preexistentes), `flutter test` 490 en verde, y en la pasarela
`cargo test` (53 unitarias + 37 de integración).

**E2E con el stack real (2026-09-25).** «Levantar» el Perfil A arrancó WSL2 + vLLM
y la tira pasó a «cargados: Router · Gemma»; la detección marcó los
tres modelos como descargados; y al cambiar el Pensamiento del Perfil A de
`fast` a `complex` (por la UI, sin tocar el shell) y volver a levantar, el stack
cargó **Router + Complejo y no arrancó Gemma** (`no existe: vllm-fast`), que es
la prueba de que `profiles.json` manda. El reenvío por rol se probó contra
DeepSeek con la clave guardada: `fast` → respuesta real. **Bug encontrado y
corregido:** `reqwest` iba sin feature TLS (`default-features = false`), así que
un destino `https://` daba 503 `backend_unavailable`; se añadió `rustls`.

**Falta (hueco conocido, 2026-09-25):** hoy la app **no genera `gateway.json` a
partir del perfil**. El reenvío por rol se verificó escribiendo ese fichero a
mano: `backends.fast = {url: api.deepseek.com, api_key_file: <ai/keys/deepseek.key>,
upstream_model: deepseek-flash}`. Si se elige un servicio por internet en un slot,
NexoDeck guarda la clave y lo registra en `profiles.json`, pero la pasarela no se
entera de que ese rol va al remoto. Lo que falta es que **«Levantar» escriba
`gateway.json`** mapeando cada slot remoto a su rol (`url` + `api_key_file` vía
`ai_remote_key_path` + `upstream_model`), y que los slots del stack sigan
apuntando a los puertos locales (`8002` router, `8001` fast, `8000` complex). Es
la única pieza que separa la UI ya hecha del reenvío real; la pasarela por su
lado ya lo soporta y está probada.

### Túnel por relay para fuera de la LAN (2026-08-28, en curso — parate a mitad de camino)

Complemento de la [dirección manual](ideas/conexion-fuera-de-la-lan.md) (ya
hecha, ver más arriba): un relay de encuentro en un VPS con IP pública para
cuando ni mDNS ni Tailscale/dirección manual alcanzan — la PC y el teléfono
están cada uno detrás de su propio CGNAT y no hay forma de que se encuentren
solos sin un tercero. Surgió al preguntar por seguridad de extremo a extremo;
la respuesta (ya resuelta: TLS con pinning, el relay nunca lo termina) quedó
anotada en [seguridad del túnel](ideas/seguridad-del-tunel.md), junto con lo
que falta después de esto: mTLS para autenticar al teléfono, que hoy solo
prueba su identidad con un UUID.

**El core en Rust está completo y probado de punta a punta — esto NO es lo
que falta:**

- **`nexodeck-relay`** (crate nuevo, binario propio): el servidor del relay.
  `hello.rs` es el saludo de 38 bytes (magic+versión+rol+token de 32 bytes),
  código puro sin async para que `nexodeck-transport` lo reuse tal cual.
  `server.rs` empareja dos conexiones ENTRANTES por token y después solo
  copia bytes (`copy_bidirectional`) — nunca termina TLS, nunca abre una
  conexión saliente. Semáforo de conexiones simultáneas, lista blanca de
  tokens opcional, keepalive cada 30s mientras el host espera (un TCP inactivo
  por NAT se cae solo). 8 tests unitarios + 1 de integración
  (`tests/splice.rs`).
- **`nexodeck-protocol`**: `MessageV1::RelayOffer { host, port, token_hex }`
  (variante nueva al final del enum, no rompe índices de postcard). La PC se
  lo manda a Android en **cada** sesión (también las de la LAN) — es cómo el
  teléfono se entera de por dónde volver a encontrarla desde afuera.
- **`nexodeck-transport`**: `relay.rs` (cliente del saludo del relay, 6 tests),
  `server.rs` gana `RelayEndpoint`/`serve_via_relay()`/`stop_relay()` — el
  túnel es un camino ADICIONAL, el listener de la LAN no se toca — con reintento
  de backoff creciente (2s→60s) si el VPS no contesta. `client.rs` gana
  `reconnect_via_relay()`/`connect_first_pairing_via_relay()`, y
  `server_name_for()` ahora acepta nombres DNS además de IPs (necesario para
  el SNI del túnel, y de paso arregla el pinning contra un nombre MagicDNS de
  Tailscale, que antes moría con "host inválido"). Test de integración nuevo:
  `tests/relay_pairing.rs`, pairing completo a través de un relay real
  levantado en el mismo test.
- **`nexodeck-ffi`**: `api/relay.rs` — `generate_relay_token`,
  `start_relay_tunnel`/`stop_relay_tunnel`, `watch_relay_status`
  (`RelayStatus`: Parked/Matched/Failed/Stopped, para que la UI pueda
  distinguir "aparcado y esperando" de "el VPS no contesta" — se ven igual
  desde la pantalla si no hay este dato), `reconnect_via_relay`.

`cargo test --workspace` en verde (incluye los 8+6+1 tests nuevos), `cargo
check --workspace --all-targets` limpio.

**Lo que falta es TODO el lado Flutter — nada de esto existe todavía:**

- Migración Drift `schemaVersion 8`: columnas `relayHost`/`relayPort`/
  `relayTokenHex` en `Devices`, mismo patrón que `manualHost`/`manualPort` de
  la `schemaVersion 7`.
- Persistir `ConnectionEvent.RelayOfferReceived` ahí (Android, rol cliente).
- Tercer nivel en `resolveReconnectTarget`/`_resolveTarget`
  (`connected_device_screen.dart`): mDNS → manual → relay, llamando a
  `reconnectViaRelay`.
- UI del lado PC para prender/apagar el túnel: host/puerto del VPS propio
  (el relay no tiene dirección pública fija, cada quien corre el suyo — ver
  `nexodeck-relay/src/main.rs`, `--port`/`--allow-token`/`--max-connections`),
  generar y mostrar el token, y pintar `RelayStatus` en vivo.

**Estado exacto en el que se retomó esta sesión (documentado porque costó
diagnosticarlo):** `bridge:gen` ya había corrido —agregó
`ConnectionEvent_RelayOfferReceived` al enum sellado de Dart— pero ningún
código de aplicación lo manejaba todavía, así que `flutter analyze` cortaba
con `non_exhaustive_switch_statement` en dos lugares (`main.dart` y
`connected_device_screen.dart`). Se agregó el `case` faltante en los dos como
no-op explícito (con TODO apuntando acá) solo para volver a tener un build
verde — **la persistencia y el tercer nivel de reconexión siguen sin
implementarse**, es lo primero para retomar.

---

### Suscripciones en vivo (SignalR/WebSocket) + auto-suscripción + panel remoto (2026-08-28/29, en curso — falta TODO el lado Dart del relay al teléfono)

Surgió al preguntar si NexoDeck podía suscribirse a un webhook (no solo
llamarlo) para seguir en vivo el progreso de los entrenamientos de
ExampleApi (`pt-start` y las demás acciones `training/*` ya creadas esta
misma sesión, ver más abajo el estado de esas 15 acciones). Se resolvió como
**cliente SignalR de salida** (no un receptor de webhooks entrante — evita
abrir puerto nuevo y el problema de CGNAT ya documentado en
[conexión fuera de la LAN](ideas/conexion-fuera-de-la-lan.md)), con soporte
también para WebSocket crudo (sin el protocolo SignalR encima) porque el
mecanismo es genérico, no específico de ExampleApi.

**Hecho y verificado EN VIVO en la máquina real (escritorio), no solo
compilado:**

- **`nexodeck-hub`** (crate nuevo): cliente SignalR minimo (negotiate HTTP
  vía `reqwest` + handshake + invocación del método del hub, protocolo JSON
  con mensajes separados por `\x1e`) y WebSocket crudo, ambos sobre
  `tokio-tungstenite`. `protocol.rs` es puro y tiene 9 tests. Mismo esqueleto
  que `nexodeck_actions::runner::CommandRunner` (singleton + broadcast).
  `tls.rs` tiene el verificador que acepta certificados inválidos, para el
  toggle homónimo del formulario (apagado por defecto).
- **`nexodeck-ffi/src/api/hub.rs`**: `start_hub_subscription` (el id lo
  elige Dart, no Rust — tiene que coincidir con la fila que ya existe en
  Drift), `stop_hub_subscription`, `restart_hub_subscription`,
  `remove_hub_subscription`, `watch_hub_events`.
- **Drift `schemaVersion` 7→8**: tablas nuevas `hub_subscriptions` +
  `hub_messages` (cascade de borrado), DAOs, repositorio
  (`features/hub_subscriptions/`), listener global `HubEventsRecorder`
  (suscripción directa al stream, nunca `ref.listen` — misma regla que
  `RunCenterController`).
- **UI de escritorio**: panel de suscripciones (lista + detalle + historial
  con `reverse: true` + Detener/Reiniciar/Eliminar), formulario "Nueva
  suscripción" (SignalR con atajos a los dos hubs de ExampleApi, o
  WebSocket crudo), botón nuevo en la barra junto al de Ejecuciones.
- **`schemaVersion` 8→9**: 5 columnas nuevas en `actions_table`
  (`autoSubscribeBaseUrl/HubPath/InvokeMethod/JsonField/AllowInvalidCert`).
  Sección nueva en el editor de acciones ("Suscribirse al terminar", solo
  visible en modo capturado) para configurarlo a mano.
- **Auto-suscripción** (`ActionsRepository._tryAutoSubscribe`): al terminar
  bien un comando capturado, si la acción tiene auto-suscripción
  configurada, interpreta `outputTail` como JSON, saca el campo configurado
  (ej. `job_id`) y arranca la suscripción sola, sin que el usuario copie
  nada a mano. Silencioso si el JSON no trae el campo (no cuenta como fallo
  de la acción, que ya terminó bien) — queda en el log.
- **`pt-start`** (una de las 15 acciones ya creadas para ExampleApi) tiene
  la auto-suscripción configurada apuntando a
  `/hubs/plant-training-progress` + `SubscribeToJob` + campo `job_id` —
  confirmado contra el propio JSON que devuelve ese endpoint
  (`PlantDetectionController.StartTraining`, que hasta repite
  `signalr.hub_url`/`subscribe_method` en la respuesta).
- **Verificación real, con capturas**: suscripción manual creada a mano
  (conecta, falla contra `localhost:5242` sin servidor arriba, pasa a
  "Desconectada", Detener/Eliminar con cascada — todo correcto). Cadena de
  auto-suscripción probada con una acción temporal (`echo` que imita la
  respuesta de `pt-start`, borrada después de probar): terminó bien, se leyó
  `job_id` de la salida, se creó la suscripción sola con el nombre y los
  argumentos correctos. `cargo test --workspace` (Rust) y `flutter test`
  (280 tests Dart) en verde en el punto donde se probó esto.

**En curso — el relay al teléfono, HECHO del lado Rust pero SIN NADA del
lado Dart todavía:**

El pedido explícito fue "verificá que desde la app móvil también tengamos el
panel" — la suscripción vive en la PC (la acción que la dispara puede correr
ahí aunque el botón se toque desde el teléfono, "el camino remoto" ya
documentado), así que verla desde Android necesita relayarla por el mismo
canal que ya usan el catálogo de acciones y el resultado de una ejecución
remota.

Hecho y compilando (`cargo build -p nexodeck_ffi` y
`cargo test --workspace` verdes con todo esto):

- **`nexodeck-protocol`**: `MessageV1::HubSubscriptionsSnapshot { subscriptions: Vec<HubSubscriptionWire> }`,
  agregado al FINAL del enum (no corre los índices de postcard, mismo
  criterio que `ActionRunUpdate`/`RelayOffer`). `HubSubscriptionWire` /
  `HubSubscriptionStatusWire` son el resumen: id, nombre, `target` (URL ya
  resuelta), estado, y un `last_event_summary` corto (no el JSON completo —
  el pedido fue "eventos resumidos"). 2 tests de roundtrip nuevos.
- **`nexodeck-transport`**: `TransportHost::send_hub_subscriptions_snapshot(device_id, subscriptions)`
  del lado servidor (rol PC), mismo patrón exacto que
  `send_actions_catalog`. `client::ConnectionEvent::HubSubscriptionsSnapshotReceived`
  + el `match` que lo despacha, del lado cliente (rol Android).
- **`nexodeck-ffi`**: `HubSubscriptionSummary`/`HubSubscriptionSummaryStatus`
  (espejo del wire — nombrado distinto de `api::hub::HubSubscriptionKind`
  para no chocar: ese es sobre ARRANCAR una suscripción, esto es el RESUMEN
  de una que ya existe), `send_hub_subscriptions_snapshot` (función que
  llama Dart del lado PC), el variant nuevo en el `ConnectionEvent` de FFI +
  sus dos `impl From`. `bridge:gen` ya corrido con todo esto.

**Lo que falta es TODO el lado Dart — nada de esto existe todavía, es lo
primero para retomar:**

- `main.dart`: un `ref.listen(hubSubscriptionsListProvider, ...)` que llame
  a `sendHubSubscriptionsSnapshot(deviceId, ...)` por cada dispositivo
  conectado — mismo patrón EXACTO que `_sendCatalogTo` (que ya hace esto
  para el catálogo de acciones), más la llamada inicial en
  `DeviceConnected`. Falta decidir cómo se arma `lastEventSummary` (¿un
  provider nuevo que traiga "última suscripción + su último mensaje" en una
  sola pasada, en vez de un stream por suscripción?).
- **`ConnectedDeviceScreen` va a cortar `flutter analyze` con
  `non_exhaustive_switch_statement`** apenas se toque cualquier otro `case`
  de su switch, porque `ConnectionEvent_HubSubscriptionsSnapshotReceived` ya
  existe en el enum sellado (por el `bridge:gen` de esta sesión) pero
  ningún `case` lo maneja — **exactamente el mismo síntoma ya documentado
  arriba para `RelayOfferReceived`**. Agregar el `case`, guardar el estado
  (provider nuevo, ej. `remoteHubSubscriptionsProvider`), y un panel de
  **solo lectura** (nombre/target/estado/último evento) — crear/detener/
  reiniciar sigue siendo exclusivo de la PC, igual que hoy el panel de
  ejecuciones no se controla desde el teléfono.
- Botón de entrada al panel en la UI de Android, análogo a
  `_HubSubscriptionsButton` de escritorio.
- Nada de esto se probó — ni compiló del lado Dart — todavía.

**Estado exacto en el que se dejó la sesión, confirmado con
`flutter analyze` corrido a mano:** el `bridge:gen` que agregó
`ConnectionEvent_HubSubscriptionsSnapshotReceived` al enum sellado de Dart
ya corrió, así que **`flutter analyze` está en rojo ahora mismo**, con
exactamente dos errores `non_exhaustive_switch_statement`:
`lib/main.dart:621` y
`lib/features/pairing/presentation/connected_device_screen.dart:801`. El
lado Rust (`cargo build -p nexodeck_ffi`, `cargo test --workspace`) está
verde. Se dejó así a propósito, sin el `case` no-op de relleno que se usó
para el túnel relay (ver más arriba) — arreglarlo de verdad con el `case`
real (guardar el estado + pintar el panel) es literalmente el primer paso
para retomar, no un no-op de relleno.

---

### Fase 5 — Transporte USB por AOA (parcial, `7326b3f`)

> **El test `pairing_completo_sobre_un_canal_de_bytes_crudo` es flaky con la máquina cargada** (descubierto el 2026-08-25, no es una regresión: falla igual en un worktree de `HEAD` limpio). Sus `recv` tienen timeout de 5 s y con la CPU al 100% se pasan; con la máquina descargada el test entero corre en ~1.9 s. Si aparece en rojo, volvé a correrlo antes de investigarlo.

Ya arrancada, aunque hasta ahora no estaba registrada en este documento. Es **AOA (Android Open Accessory), no el túnel ADB** que planteaba el borrador original del plan — ver [`ADR 0002`](architecture-decision-records/0002-aoa-sobre-adb.md). El "Hito 0" (spike de viabilidad contra un Samsung Galaxy S928B real en Windows 11) ya se corrió y confirmó el escenario más pesimista de los contemplados: hay que instalar el driver WinUSB con `libwdi` en **dos** momentos distintos del primer uso, no en uno solo, y hay que asumirlo como el caso normal.

Lo que ya está en el repo:

- **`nexodeck-transport/src/session.rs`** — trait `SessionTransport` ("un `MessageV1` adentro, un `MessageV1` afuera") que abstrae el canal. `server.rs` pasó a ser genérico sobre él (`dispatch_first_message`, `handle_pairing`, `handle_reconnect`, `run_session`), así que todo el loop de sesión de Fase 4 se reusa tal cual sobre USB en vez de duplicarse. Se usa siempre monomorfizado, nunca como `dyn`, así que el `async fn` del trait no necesita boxing (RPITIT; el workspace fija `rust-version = "1.90"`).
- **`nexodeck-transport/src/usb/framing.rs`** (`FramedUsb`) — framing propio para un canal de bytes crudo (length-prefix de 4 bytes LE + postcard). Hace falta porque `wire.rs` depende del framing que ya trae WebSocket; USB es solo un flujo de bytes. Sirve igual para el puente bulk del lado PC y para el `File` que envolverá el fd crudo del lado Android. Cota defensiva de 16 MB contra un length-prefix corrupto u hostil.
- **`nexodeck-transport/src/usb/session.rs`** (`UsbSession`) — implementación de `SessionTransport` sobre `FramedUsb`. Todo el módulo `usb` está gateado con `#[cfg(not(target_os = "android"))]`: es el rol PC/host.

Verificado: 4 tests unitarios de `FramedUsb` (roundtrip simple; roundtrip fragmentado forzando chunks de 8 bytes, que emula el tamaño máximo de un bulk transfer real; EOF limpio → `Ok(None)`; length-prefix sobredimensionado → error sin alocar el buffer) más el resto del workspace en verde, incluido el loopback de pairing de Fase 4 que sigue pasando después de generalizar `server.rs`.

#### Fase 5-C — handshake AOA + puente bulk del lado PC (hecho)

`nusb` 0.2.5 entró como dependencia **solo para las plataformas que no son Android** (`[target.'cfg(not(target_os = "android"))'.dependencies]`, mismo patrón que `arboard`): el rol PC enumera USB, el rol Android recibe el fd del accessory desde Kotlin y no necesita la capa nativa.

- **`usb/aoa.rs`** — los 3 control transfers vendor-specific (`ACCESSORY_GET_PROTOCOL` 0x33, `ACCESSORY_SEND_STRING` 0x34 × N, `ACCESSORY_START` 0x35) y la clasificación de los PIDs de accessory mode. Detalles que importan: los strings van **terminados en NUL** (`f_accessory.c` copia hasta el NUL); `manufacturer`/`model` (`AccessoryIdentity`) son la clave que Android matchea contra su `accessory_filter.xml`, por eso son constantes y no llevan el nombre del equipo; y un error en `ACCESSORY_START` **no** es un fallo (el teléfono se desconecta del bus antes de completar el status stage), decide la espera de re-enumeración.
- **`usb/stream.rs`** (`UsbStream`) — une los dos endpoints bulk (`nusb` los expone por separado, uno por dirección) en un único `AsyncRead + AsyncWrite`, que es lo que `FramedUsb` espera. Sin lógica propia: `nusb` ya trae los impls de `tokio::io` con la feature `tokio`.
- **`usb/bridge.rs`** — el loop: escanea el bus cada 2s, decide a qué dispositivos vale la pena hablarles, hace el handshake, espera la re-enumeración (hasta 10s), abre el canal bulk y entrega la sesión a `server::dispatch_first_message` — el mismo `TransportHost`, el mismo pairing, las mismas autorizaciones y los mismos `ConnectionEvent` que WiFi. Lo propio de USB son los `UsbEvent` (estado del *cable*: `PhoneDetected`, `DriverBlocked`, `AccessoryConnected`…).
  - **La heurística de a quién tocarle es deliberadamente conservadora**: el handshake reclama una interfaz, y reclamar la del mouse o el teclado se la sacaría a su driver mientras dure el intento. Se descartan HID, audio, video, almacenamiento, hubs e impresoras, y se aceptan MTP/PTP y vendor-specific (incluida la firma de ADB) o los dispositivos sin interfaces en cache (modo "solo carga").
  - **Los errores se reportan una vez por dispositivo, pero el reintento sigue en silencio**: así el puente se recupera solo cuando el usuario instala el driver, sin desenchufar nada, y la UI no recibe el mismo cartel cada 2 segundos.
- **Arranque**: `start_transport_host` (FFI) levanta el puente junto con el host de WiFi, así que en desktop está vivo desde el inicio de la app sin ningún paso extra.
- **Diagnósticos**: `cargo run -p nexodeck-transport --example usb_scan` (solo lectura: enumera y clasifica, nunca abre nada — sirve para auditar la heurística contra un bus real) y `--example usb_bridge_watch` (corre el puente de verdad e imprime sus eventos, sin Flutter de por medio).

Verificado: 12 tests unitarios del crate (los 4 de framing más los de clasificación de PIDs, encoding de strings AOA y la heurística de candidatos) **más un pairing completo sobre un canal de bytes crudo** (`tokio::io::duplex` en lugar del cable: ejercita framing → `SessionTransport` → `dispatch_first_message` → sesión con `HardwareSnapshot` real). Y **contra hardware real** (el mismo Samsung del spike del ADR 0002, conectado y ya en accessory mode): el escaneo lista los 9 dispositivos del bus y marca como candidato **solo** el teléfono —mouse, teclado, headset, webcam, hubs y un dongle WiFi con interfaz vendor-specific quedan correctamente afuera—, detecta el `18D1:2D00`, y al intentar abrir su canal bulk reporta `DriverBlocked` exactamente una vez. Eso último **es** el segundo momento del ADR 0002 confirmado en vivo: el driver de accessory mode no trae Microsoft OS Descriptors, así que sin WinUSB instalado el claim falla — el camino queda cerrado hasta que exista la Fase 5-E.

Correr el puente real destapó y corrigió un bug propio de esa vuelta: la rama de accessory emitía un `Failed` genérico (en vez de `DriverBlocked`) y lo repetía cada 2s, porque decidía el evento adentro en vez de dejárselo al loop, que es quien tiene la memoria de qué ya se reportó.

#### Fase 5-D — lado Android (hecho)

El teléfono no enumera USB: Android le entrega el canal ya abierto como un `ParcelFileDescriptor`, y de ahí en adelante todo es el mismo flujo que WiFi.

- **`AndroidManifest.xml`**: `<uses-feature android.hardware.usb.accessory required="false">` (sin accessory la app sigue sirviendo por WiFi, no hay razón para bloquear la instalación), intent-filter `USB_ACCESSORY_ATTACHED` en `MainActivity` y el `meta-data` que apunta a `res/xml/accessory_filter.xml`.
- **`accessory_filter.xml`**: matchea `manufacturer`/`model` contra `AccessoryIdentity::default()`. **El atributo `version` se dejó afuera a propósito**: AAPT tipa `"1.0"` como número y lo guarda como `1`, así que el filtro compilado nunca coincidiría con el string `"1.0"` del handshake — verificado con `aapt2 dump xmltree` sobre el APK ya construido. Los atributos ausentes actúan como comodín, así que fabricante + modelo alcanzan.
- **`MainActivity.kt`**: segundo `MethodChannel` (`/usb_accessory`) que abre el accessory, pide el permiso de USB si falta, y devuelve **solo el número del fd** (`ParcelFileDescriptor.detachFd()`, que cede la propiedad — cerrarlo del lado Kotlin sería un doble close). Además un `BroadcastReceiver` para ATTACHED/DETACHED/permiso y `onNewIntent`, porque con `launchMode="singleTop"` el intent llega por ahí si la app ya estaba abierta.
- **`nexodeck-transport::usb::android`**: envuelve el fd en un `tokio::fs::File` (char device `/dev/usb_accessory`, no un socket: no se puede registrar en el reactor ni tratar como pipe) y corre `TransportClient::run_over_session`, que es el mismo loop de mensajes de WiFi — por eso el flujo de PIN, el catálogo y la ejecución de acciones andan sin tocar nada más. Sobre USB no hay TLS: el "canal" es un cable entre dos aparatos que el usuario tiene enfrente, no una red compartida; el PIN se sigue pidiendo igual.
- **Dart**: `UsbAccessoryService` + `usbAccessoryServiceProvider`, montado desde `AndroidShell`. **Los bytes del protocolo nunca pasan por Dart**: transporta el fd una vez y de ahí lo lee Rust.

Verificado: `flutter build apk --release` con el filtro y el intent-filter **confirmados dentro del APK** (`aapt2 dump xmltree`, no solo "compiló"), `libnexodeck_ffi.so` en las 3 ABIs, `flutter analyze`/`test` y `cargo test` en verde.

#### `UsbEvent` en la UI (hecho)

`api/usb.rs` en el FFI (firma única con cuerpo cfg-gateado, como `paste_to_clipboard`: cfg-ear la función entera rompe el link del lado que falta, porque frb genera el glue para todos los targets), `usbEventsProvider` y `UsbStatusBanner` en `DevicesScreen`. Solo aparece cuando hay algo que decir; el caso que importa es `DriverBlocked`, el único que necesita una acción del usuario.

#### Lo que falta de la Fase 5

- **Fase 5-E — WinUSB con `libwdi`**: sigue siendo **el bloqueante real**. Se intentó integrarlo: existen los crates `wdi`/`libwdi-sys` 0.1.5 y compilan hasta el final del vendorizado, pero el build script falla en dos puntos en esta máquina: (1) construye `installer_arm64.exe` aunque la feature `enable-arm64` esté apagada (el crate `wdi` declara `libwdi-sys` sin `default-features = false`, así que la unificación de features de Cargo la vuelve a prender — se evita dependiendo de `libwdi-sys` directo), y (2) el embedder exige `WdfCoInstaller01011.dll` del redist de **WDK 8.0**, que no está instalado y que ni siquiera hace falta para WinUSB (es de libusbK/libusb0). Queda pendiente: o se instala ese redist, o se parchea el `config.h` vendorizado. Mientras tanto, el equivalente manual es Zadig (que es libwdi con GUI).
- **Confirmado contra el S24 Ultra en modo normal (2026-08-01)**: el handshake ni siquiera puede empezar porque `dg_ssudbus` (driver USB de Samsung, `oem2.inf`) está atado al **compuesto entero**; las 4 interfaces dan `DriverBlocked`, incluida la de ADB, que **ya tiene WinUSB** pero es inalcanzable para `nusb` porque el padre compuesto no es `usbccgp`. Consecuencia de producto, no de implementación: instalar WinUSB deja al teléfono **sin MTP ni adb en esa PC** hasta revertirlo. Eso refuerza que el handshake automático de hoy tiene que volverse explícito, y que USB debería ser opt-in con WiFi como camino principal.
- **Handshake AOA contra hardware**: todavía sin ejercitar, y no por falta de teléfono. El único disponible ya estaba en accessory mode **porque lo puso ahí `spacedesk`**, que además tiene su propio driver de kernel (`spacedeskAndroidUsb`, `oem44.inf` de datronicsoft) atado al `18D1:2D00`. El canal de accessory es exclusivo: mientras ese driver esté atado, NexoDeck no puede abrirlo, y cerrar la app o parar el servicio de usuario no alcanza (el binding es del driver, no del proceso). Probarlo implica reemplazar ese driver por WinUSB, lo que deja a spacedesk sin pantalla por cable hasta restaurarlo.
- **Decisión de diseño pendiente para 5-E**: hoy el puente le hace el handshake automáticamente a cualquier Android que vea. Con el driver instalado eso podría arrancarle el teléfono a una transferencia MTP en curso, o pelearse con otro host AOA como spacedesk. Debería volverse explícito (solo al dispositivo ya emparejado, o a pedido del usuario).
- **Linux**: regla de udev (`SUBSYSTEM=="usb", ATTRS{idVendor}=="18d1", MODE="0666"`), que se empaqueta en Fase 10 pero ya sirve en desarrollo.

---

## Desviaciones de la arquitectura original (y por qué)

| Decisión original | Qué se hizo en su lugar | Por qué |
|---|---|---|
| Riverpod 3 con codegen (`@riverpod`) | Providers escritos a mano con la API clásica | `riverpod_generator` no resuelve en este SDK de Flutter (conflicto real e irresoluble entre `analyzer` y el `meta` que fija Flutter 3.41.9 — confirmado exhaustivamente por el solver de pub). `drift_dev` sí funciona, es un problema específico de `riverpod_generator`. |
| Melos como parte del monorepo | Sigue siendo dev_dependency local (no se cambió) | Se intentó sacarlo para "liberar" el lockfile pensando que ayudaría con lo de Riverpod — no era la causa real, y además Melos v7+ requiere la dev_dependency para detectar el workspace. Revertido. |
| Tabla `Actions` (como en el borrador de esquema original) | `ActionsTable` | `package:flutter/widgets.dart` ya exporta una clase `Actions` (el sistema de Actions/Intents) — chocaría. |
| `window_manager`/`desktop_multi_window` (el doc dejaba ambos como opción) | Solo `window_manager` | Una sola ventana que cambia de estado es suficiente para alternar compacto/pantalla-completa; `desktop_multi_window` añade complejidad de múltiples engines sin necesidad real todavía. |
| Snippet de protocolo con `#[serde(tag=..., content=...)]` | Enums *externally tagged* (default de serde) | postcard/bincode no soportan `deserialize_any`, que ese atributo requiere. Documentado en el ADR 0001. |

---

## Pendiente

### Fases del plan original (`NexoDeck-Arquitectura-y-Plan-de-Fases.md`, sección 7)

- **Fase 5 — Transporte USB**: **en curso**, ver la sección de arriba. Es AOA nativo, no el túnel ADB del borrador original (ADR 0002). Ya están el lado PC (5-A/5-B cimientos, 5-C handshake AOA + puente bulk), el lado Android (5-D) y los `UsbEvent` en la UI. Falta `libwdi` (5-E), que sigue siendo el bloqueante real.
- **Fase 6 — Transporte Bluetooth**: BLE con `btleplug` + plugin Kotlin del lado Android.
- **Fase 7 — Vault de secretos y variables dinámicas**: cifrado con `age`/`chacha20poly1305` + `argon2`, variables como rama git activa, fecha, escena activa en OBS, etc.
- **Fase 8 — Alertas bidireccionales**: mensajes `Alert` en ambas direcciones, reglas configurables de umbral (la tabla `alert_rules` ya existe, falta la lógica y la UI). **El camino de salida ya está**: `nexodeck-notify` sabe mandar un aviso fuera de la máquina y el servidor de control expone `notify`. Lo que falta de esta fase es quién decide **cuándo** avisar: evaluar `alert_rules` contra el stream de métricas, y el mensaje `Alert` en el protocolo (variante al final del enum, ver la skill `protocol-message`).
- **Fase 9 — Perfiles por contexto y macros**: detección automática de perfil por proceso activo, ejecución real de macros (la tabla `macro_steps` ya existe, falta la UI de edición y el motor de ejecución), historial con gráficas (`fl_chart`), export/import de "decks".
- **Fase 10 — Empaquetado y distribución**: instaladores, firma de código, congelar `docs/protocol-spec.md` como v1 estable.

### Cabos sueltos dentro de fases ya "completas"

- **Tipo de acción `macro`** existe en el esquema y en el enum `ActionType`, pero el editor de acciones (`action_editor_sheet.dart`) solo ofrece Portapapeles/Terminal — falta la UI y el motor de ejecución de macros (Fase 9).
- **Modo compacto en Android**: Fase 3 se limitó a desktop. Android necesita su propio mecanismo (overlay tipo bubble, `SYSTEM_ALERT_WINDOW`), que requiere una pieza nativa Kotlin — ver skill `kotlin-android-plugin` (ya tiene contenido real desde Fase 4, usar como plantilla).
- **Verificación interactiva de UI pendiente en general**: no hay automatización de UI **de escritorio** en este entorno. Del lado **Android sí la hay**, vía adb (`input tap`, `screencap`, `uiautomator`, `logcat`) — ver `CLAUDE.md`; con eso se cerró el E2E de Fase 4. Lo que sigue sin probarse con clics reales:
  - Ejecutar una acción desde la tarjeta en la UI (Fase 2).
  - La ruta de elevación UAC en Windows (Fase 2) — requiere que un humano confirme el diálogo.
  - El botón de alternar modo compacto/pantalla completa (Fase 3).
  - Spawn de terminal en Linux (Fase 2) — sin máquina Linux disponible para probar en absoluto.
  - **De Fase 4 solo queda el primer pairing PIN-a-PIN** contra el teléfono físico (hardware en vivo, ejecución remota, reconexión y rechazo ya se verificaron — ver la sección de Fase 4 más arriba). El teléfono de pruebas ya estaba emparejado, así que para ejercitarlo hay que borrar la fila de `devices` de su base primero. La prueba negativa de fingerprint distinto sigue cubierta solo por el loopback.
  - **Grupos de acciones y toggle de tema** — crear/renombrar/eliminar un grupo, filtrar la grilla, y alternar claro/oscuro no se probaron con clics reales.
- **GPU AMD en Linux** (`/sys/class/drm/`) **e Intel en cualquier plataforma**: AMD y NVIDIA en Windows ya están resueltos y verificados con hardware real (ver Fase 1 arriba), estas dos quedan pendientes — sin máquina Linux ni GPU Intel dedicada disponibles para probar.
- **CI no compila el APK**: `.github/workflows/ci.yml` corre `cargo build`/`test`, `flutter analyze`/`test` y `flutter build windows`/`linux`, pero **nunca `flutter build apk`**. Justo el bug de Fase 4 (el `.apk` generándose "exitosamente" sin `libnexodeck_ffi.so` adentro, porque Gradle no falla aunque cargokit no produzca la librería) es el que no tiene guardia de regresión. Vale agregar un job de Android que compile el APK y verifique que el `.so` está presente en las 3 arquitecturas, no solo que el build no falló.
- **Catálogo de acciones sin parámetros ni macros** (Fase 4): `ActionsCatalog` relaya nombre/ícono/id, no los parámetros dinámicos `{{variable}}` ni pasos de macro — ejecutar una acción parametrizada desde Android usa valores por defecto. Un prompt de parámetros de punta a punta y el motor de macros llegan en Fase 9.
- **Un solo dispositivo Android emparejado activo a la vez** (Fase 4): `AndroidShell` asume `list.first`; la PC sí soporta y persiste múltiples dispositivos, pero la UI de Android no tiene selector si hubiera más de uno emparejado.
