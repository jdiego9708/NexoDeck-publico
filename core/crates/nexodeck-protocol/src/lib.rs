use serde::{Deserialize, Serialize};

/// Mensaje raíz del protocolo NexoDeck. Versionado explícitamente desde el
/// día uno porque el core en la PC y el core en Android hablan el mismo
/// idioma sobre 3 transportes distintos (USB, BLE, WiFi).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum NexoDeckMessage {
    V1(MessageV1),
}

/// Duplicado deliberado de `nexodeck_hardware::HardwareSnapshot`: este crate
/// no depende de `nexodeck-hardware` (protocolo != implementación de una
/// plataforma concreta), y esta es la forma que efectivamente viaja por la
/// red. `nexodeck-ffi` tiene los `From` que conectan ambos lados con su
/// propio DTO de bridge.
///
/// Ya no es `Copy` (lleva la lista de discos). Se mueve en los dos lugares
/// que lo usan -- el tick del servidor y la entrega al cliente -- asi que no
/// obliga a clonar en ninguna ruta caliente.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HardwareSnapshot {
    pub cpu_usage: f32,
    pub cpu_freq_mhz: Option<u64>,
    pub cpu_temp: Option<f32>,
    pub ram_used_mb: f64,
    pub ram_total_mb: f64,
    pub disk_used_mb: f64,
    pub disk_total_mb: f64,
    /// Un elemento por disco fisico. **Campo agregado despues de la primera
    /// version de `V1`**: rompe el cable con binarios viejos, como ya paso al
    /// sumarle campos a `RemoteAction`. PC y telefono se compilan del mismo
    /// repo, asi que hay que reinstalar los dos juntos.
    pub disks: Vec<DiskUsageWire>,
    pub net_rx_bytes: u64,
    pub net_tx_bytes: u64,
    pub gpu_usage: Option<f32>,
    pub gpu_temp: Option<f32>,
    pub gpu_vram_used_mb: Option<f64>,
    pub gpu_vram_total_mb: Option<f64>,
    /// Reloj grafico actual en MHz. **Campo agregado despues**, al final del
    /// struct: postcard serializa por posicion, asi que meterlo en el medio
    /// correria todo lo que sigue. Rompe el cable con binarios viejos igual
    /// que `disks` -- PC y telefono se reinstalan juntos.
    pub gpu_clock_mhz: Option<u32>,
    /// Hilos logicos totales y cuantos estan trabajando. **Campos agregados
    /// despues**, al final del struct: postcard serializa por posicion.
    pub cpu_threads_total: u32,
    pub cpu_threads_busy: u32,
    /// Potencia actual de la GPU en watts y el techo que le impone el driver.
    /// **Campos agregados despues**, al final del struct por la misma razon
    /// que `gpu_clock_mhz`: postcard serializa por posicion. `None` fuera de
    /// NVIDIA. Rompe el cable con binarios viejos -- PC y telefono se
    /// reinstalan juntos.
    pub gpu_power_watts: Option<f32>,
    pub gpu_power_limit_watts: Option<f32>,
}

/// Un disco fisico del host, para la lista de almacenamiento del deck
/// remoto. Duplicado de `nexodeck_hardware::DiskUsage` por la misma razon
/// que [`HardwareSnapshot`].
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DiskUsageWire {
    pub mount_point: String,
    pub label: String,
    pub kind: DiskKindWire,
    pub used_mb: f64,
    pub total_mb: f64,
    /// Bytes/segundo de lectura y escritura, para la senal de vida de la UI.
    /// `None` cuando la PC no sabe medirlo (fuera de Windows, o un volumen
    /// sin letra de unidad).
    pub read_bytes_per_sec: Option<f64>,
    pub write_bytes_per_sec: Option<f64>,
    /// Temperatura del disco fisico en grados Celsius. **Campo agregado
    /// despues**, al final del struct: postcard serializa por posicion.
    /// `None` cuando el disco no la publica o la PC no sabe leerla.
    pub temp_c: Option<f32>,
    /// Hace cuantos segundos se tomo `temp_c`. **Campo agregado despues**, al
    /// final del struct: postcard serializa por posicion.
    pub temp_age_secs: Option<u64>,
}

/// Tipo de medio del disco. `Unknown` es un valor legitimo: hay
/// controladoras que no lo reportan.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DiskKindWire {
    Ssd,
    Hdd,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DevicePlatformWire {
    Android,
    Ios,
    Windows,
    Linux,
}

/// Que hace una accion. Viaja para que el deck remoto pueda diferenciar
/// visualmente una macro (que corre varios pasos y tarda) de una accion
/// simple, sin tener que adivinarlo por el icono.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RemoteActionKind {
    Clipboard,
    Terminal,
    Macro,
}

/// Como se le pide un valor al usuario. Espejo de `ParamInputType`
/// (Drift/Dart), duplicado aca por la misma razon que `HardwareSnapshot`:
/// el protocolo no depende de la implementacion de ninguna punta.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RemoteParamKind {
    Text,
    Number,
    Select,
}

/// Un dato que la accion le pide al usuario antes de correr, para
/// reemplazar `{{key}}` en su plantilla. Viaja completo (no solo la key)
/// porque el telefono tiene que poder DIBUJAR el prompt: sin `label` y
/// `kind` mostraria un campo de texto pelado rotulado con la variable
/// cruda.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RemoteActionParam {
    pub key: String,
    pub label: String,
    pub kind: RemoteParamKind,
    pub default_value: Option<String>,
    /// Solo relevante con `kind = Select`. Va como lista de strings y NO
    /// como el JSON crudo que guarda Drift en `options_json`: el protocolo
    /// nunca serializa JSON (ADR 0001). La conversion se hace del lado
    /// Dart, al armar el catalogo.
    pub options: Vec<String>,
}

/// Resumen de una `DeckAction` (Dart/Drift) para mostrar en el deck remoto.
///
/// Lleva los parametros dinamicos completos: el telefono arma el mismo
/// prompt que la PC y manda los valores ya cargados en `ExecuteAction`.
/// Antes solo viajaban id/nombre/icono/color, asi que ejecutar una accion
/// parametrizada desde Android corria con los valores por defecto sin
/// avisarle a nadie.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RemoteAction {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub color_hex: String,
    /// Grupo/categoria al que pertenece (ver `ActionGroups` en Drift). Va
    /// denormalizado (id + nombre + color) en vez de un id que Android
    /// tendria que resolver contra un catalogo aparte -- son pocos grupos
    /// y el catalogo se manda una sola vez por conexion, asi que el costo
    /// de mandar los 3 campos por accion es insignificante.
    pub group_id: Option<String>,
    pub group_name: Option<String>,
    pub group_color_hex: Option<String>,
    pub kind: RemoteActionKind,
    /// Para una macro son los parametros de TODOS sus pasos, deduplicados
    /// por `key` -- se le pregunta una sola vez al usuario y el valor se
    /// aplica a cada paso que use esa variable. Ver `promptParametersFor`
    /// del lado Dart, que es quien arma esta lista.
    pub parameters: Vec<RemoteActionParam>,
    /// Cantidad de pasos si `kind = Macro`, `0` en cualquier otro caso.
    pub step_count: u32,
}

/// Un par `{{key}}` -> valor ya cargado por el usuario.
///
/// Va como lista de pares y no como mapa a proposito: el orden queda
/// determinista en el byte stream (util para los tests de round-trip) y no
/// obliga a postcard a serializar un `HashMap`, cuyo orden de iteracion no
/// esta definido.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ActionParamValue {
    pub key: String,
    pub value: String,
}

/// Variantes reales del protocolo v1.
///
/// Ver docs/architecture-decision-records/0001-postcard-sobre-json.md:
/// este enum se serializa "externally tagged" (default de serde), NUNCA con
/// `#[serde(tag = "type", content = "payload")]` (adjacently tagged), porque
/// ese atributo requiere `deserialize_any`, no soportado por postcard/bincode.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum MessageV1 {
    Ping,
    Pong,

    // --- Handshake de pairing (conexión aún no autenticada) ---
    /// Android -> PC: primer mensaje tras el upgrade WS+TLS.
    PairHello {
        device_name: String,
        platform: DevicePlatformWire,
    },
    /// PC -> Android: solo si el operador armó el modo "aceptar pairing" en
    /// la PC. Si no está armado, la PC responde `PairRejected`.
    PairPin {
        pin: String,
        host_name: String,
        host_platform: DevicePlatformWire,
    },
    /// Android -> PC: el usuario confirmó visualmente que el PIN coincide.
    PairConfirm,
    /// PC -> Android: el operador de la PC también confirmó. `device_id` es
    /// generado por la PC y es el mismo id que ambos lados persisten en su
    /// tabla `devices` local.
    PairAccepted {
        device_id: String,
        cert_fingerprint: String,
    },
    PairRejected {
        reason: String,
    },

    // --- Sesión post-pairing ---
    /// Android -> PC: reconexión con un `device_id` ya emparejado. Solo se
    /// envía si el fingerprint pinneado del certificado TLS coincidió (si no
    /// coincide, la conexión TLS ni siquiera se completa).
    Reconnect {
        device_id: String,
    },
    ReconnectAccepted,
    ReconnectRejected {
        reason: String,
    },

    /// PC -> Android, aprox. 1/s mientras la sesión esté viva.
    HardwareSnapshot(HardwareSnapshot),
    /// PC -> Android: catálogo de acciones disponibles, enviado al
    /// conectar. Necesario porque cada dispositivo siembra su propia
    /// base Drift con ids aleatorios propios -- Android no puede asumir
    /// que sus ids locales significan algo para la PC, así que la PC le
    /// manda los suyos y Android reenvía ESOS ids en `ExecuteAction`.
    ActionsCatalog {
        actions: Vec<RemoteAction>,
    },
    /// Android -> PC: pedido de ejecutar una acción, usando un `action_id`
    /// recibido en `ActionsCatalog` (nunca uno generado localmente).
    ///
    /// `params` trae los valores que el usuario cargó en el teléfono para
    /// los `{{placeholders}}` de la acción; va vacío si la acción no tiene
    /// parámetros. La PC los aplica con el mismo `renderCommand` que usa el
    /// deck local, así que una misma acción se comporta igual disparada
    /// desde cualquiera de las dos puntas.
    ExecuteAction {
        action_id: String,
        params: Vec<ActionParamValue>,
    },
    ActionAck {
        action_id: String,
        success: bool,
        error: Option<String>,
    },

    /// PC -> Android: como le va al comando que el telefono mando ejecutar.
    ///
    /// Complementa a `ActionAck`, que se sigue mandando y sigue significando
    /// "la PC recibio el pedido y lo lanzo". Esto es lo que pasa **despues**:
    /// si el comando termino bien, con que codigo, y con el final de su
    /// salida. Antes de la ejecucion capturada no habia forma de saberlo --
    /// un comando que fallaba le contestaba `success: true` al telefono.
    ///
    /// Va **al final del enum a proposito**: postcard identifica las
    /// variantes por indice, asi que agregar aca no corre las que ya existen.
    ///
    /// No se transmite la salida linea por linea: solo el inicio y el cierre
    /// con el final de la salida. Mandar cada lote de lineas por WiFi para
    /// dibujar una notificacion no se justifica.
    ActionRunUpdate {
        run_id: String,
        action_id: String,
        phase: RunPhaseWire,
        /// `None` mientras corre, o si el proceso no dejo codigo.
        exit_code: Option<i32>,
        elapsed_ms: u32,
        /// Final de la salida, recortado. Vacio salvo en las fases finales.
        output_tail: String,
    },

    /// Android -> PC: "empeza/deja de mandarme la lista de procesos".
    ///
    /// **Es una suscripcion y no un push permanente**, al reves que
    /// `HardwareSnapshot`. Recorrer los ~370 procesos de la maquina cuesta
    /// ~20 ms y la lista pesa 1-2 KB: pagarlo cada dos segundos por si el
    /// telefono llegara a abrir el panel seria tirar bateria y ancho de banda
    /// para nada. Con la suscripcion, cerrar el panel apaga el colector.
    ///
    /// Va al final del enum a proposito: postcard identifica las variantes por
    /// indice, asi que agregar aca no corre las que ya existen.
    WatchProcesses {
        enabled: bool,
    },

    /// PC -> Android, mientras haya suscripcion viva.
    TopProcesses(TopProcessesWire),

    /// Android -> PC: cerrar todos los procesos de una aplicacion.
    ///
    /// Viajan **nombre y pids**: la PC solo cierra los pids que sigan
    /// llamandose asi. Windows reutiliza los pids rapido y estos vienen de una
    /// muestra de hasta dos segundos atras, mas la latencia de la red; sin esa
    /// doble condicion, un toque en el telefono podria matar un programa que
    /// el usuario nunca vio en la lista.
    TerminateProcessGroup {
        name: String,
        pids: Vec<u32>,
    },

    /// PC -> Android: que paso con el pedido anterior.
    ProcessTerminated {
        name: String,
        /// Cuantos se cerraron de verdad.
        killed: u32,
        /// Matchearon pero no se pudieron cerrar; casi siempre, permisos.
        failed: u32,
        /// `None` si la PC ejecuto el pedido; con texto si lo rechazo entero
        /// (un proceso critico de Windows, o el propio NexoDeck).
        rejected_reason: Option<String>,
    },

    /// PC -> Android: como alcanzar a esta PC cuando NO comparten red.
    ///
    /// El telefono lo guarda y lo usa como ultimo recurso, despues de que
    /// mDNS y la direccion manual fallen. Se manda **por la sesion ya
    /// autenticada**, y esa es toda la seguridad del esquema: el token es la
    /// unica credencial que separa a un tercero de la PC cuando la sesion
    /// sale a internet, asi que no puede viajar por ningun canal mas debil
    /// ni escribirse a mano.
    ///
    /// `host` vacio significa "apague el tunel, olvida lo que tenias". Es
    /// una variante y no dos porque el telefono tiene que reaccionar igual
    /// en los dos casos: reemplazar lo que tenia guardado por esto.
    ///
    /// Va al final del enum a proposito: postcard identifica las variantes
    /// por indice, asi que agregar aca no corre las que ya existen.
    RelayOffer {
        host: String,
        port: u16,
        /// Hex de 64 caracteres (32 bytes). Se transporta como texto por lo
        /// mismo que el fingerprint del certificado: termina en una columna
        /// de Drift y en logs de diagnostico, y un `Vec<u8>` ahi no se puede
        /// ni leer ni comparar de un vistazo.
        token_hex: String,
    },

    /// PC -> Android: estado actual de TODAS las suscripciones en vivo
    /// (SignalR o WebSocket crudo), mandado al conectar y de nuevo cada vez
    /// que algo cambia (una se crea, cambia de estado, o le llega un
    /// mensaje). Lista COMPLETA, no un diff -- son pocas suscripciones a la
    /// vez, y sincronizar por diffs aca seria complejidad sin necesidad
    /// real (mismo criterio que `ActionsCatalog`).
    ///
    /// Solo lectura del lado Android: detener/reiniciar/crear sigue siendo
    /// una accion de la PC, igual que hoy el panel de ejecuciones no se
    /// controla desde el telefono.
    ///
    /// Va al final del enum a proposito: postcard identifica las variantes
    /// por indice, asi que agregar aca no corre las que ya existen.
    HubSubscriptionsSnapshot {
        subscriptions: Vec<HubSubscriptionWire>,
    },

    /// PC -> Android: nombres y caracteristicas de las piezas (modelo de CPU,
    /// memoria, GPU, adaptador de red), para el subtitulo de cada tile. Se lee
    /// una sola vez del lado PC (WMI/NVML son caros) y no cambia mientras la
    /// sesion vive, asi que se manda una vez al conectar, no en cada snapshot.
    ///
    /// Va al final del enum a proposito: postcard identifica las variantes
    /// por indice, asi que agregar aca no corre las que ya existen.
    HostComponents(HostComponentsWire),

    /// PC -> Android: si el asistente de IA esta habilitado (switch de
    /// arriba en la PC) y si ademas hay un motor vivo y listo para
    /// conversar. Se manda al conectar y de nuevo cada vez que cualquiera
    /// de los dos cambia -- el telefono decide que UI mostrar solo con
    /// esto, nunca preguntando.
    ///
    /// Va al final del enum a proposito: postcard identifica las variantes
    /// por indice, asi que agregar aca no corre las que ya existen.
    AiStatus {
        enabled: bool,
        ready: bool,
    },

    /// PC -> Android: un evento de la conversacion con el asistente.
    ///
    /// Bundle en un solo enum interno (`AiChatEventWire`), mismo criterio
    /// que `RunPhaseWire` adentro de `ActionRunUpdate`, para no agregarle
    /// media docena de variantes sueltas a `MessageV1`.
    ///
    /// **Nunca viaja token por token.** El asistente emite un token cada
    /// 15-30ms; por WiFi/relay a un telefono eso es exactamente lo que
    /// `ActionRunUpdate` ya evito a proposito (ver su comentario mas
    /// arriba). El texto en construccion se resume en un solo
    /// `AiChatEventWire::Typing` mientras se genera, y el contenido real
    /// llega recien completo en `AssistantMessage`.
    ///
    /// Va al final del enum a proposito: postcard identifica las variantes
    /// por indice, asi que agregar aca no corre las que ya existen.
    AiChatEvent(AiChatEventWire),

    /// Android -> PC: el usuario escribio esto en el chat del telefono.
    AiSendMessage {
        text: String,
    },

    /// Android -> PC: "activa el asistente ahora". Solo tiene sentido
    /// cuando el ultimo `AiStatus` recibido dice `enabled: true, ready:
    /// false` -- si ya esta listo, o si esta apagado, la PC no tiene nada
    /// que hacer con esto.
    AiActivate,

    /// Android -> PC: guardar este borrador como boton nuevo.
    ///
    /// El comando de cada paso ya viene resuelto (sin `{{variables}}`): el
    /// telefono ya junto los parametros con el mismo dialogo que usa la
    /// PC, asi que la PC no vuelve a preguntar nada -- mismo modelo de
    /// confianza que ya rige `ExecuteAction`.
    AiApplyDraft {
        draft: AiDraftWire,
    },

    /// Android -> PC: correr este borrador ahora, en vivo. Mismas reglas
    /// que `AiApplyDraft` sobre los comandos ya resueltos.
    AiRunDraft {
        draft: AiDraftWire,
    },

    /// Android -> PC: que la IA explique este proceso -- que es, hace
    /// cuanto corre, que esta haciendo, quien lo lanzo. El grupo viaja tal
    /// cual lo tiene el telefono en pantalla (cpu/memoria/disco/tiempo ya
    /// conocidos); la PC agrega lo que falta (proceso padre, linea de
    /// comando, dueno) con una consulta fresca antes de armar la pregunta
    /// (ver `nexodeck_hardware::processes::process_details`).
    AiAskAboutProcess {
        group: ProcessGroupWire,
    },

    /// Android -> PC: algo sobre las notas (leer la boveda, guardar, crear,
    /// borrar).
    ///
    /// **Lleva `request_id` porque aca si hace falta correlacionar.** El resto
    /// del protocolo se apaña con ids de dominio (`action_id`, `run_id`) o es
    /// un empuje sin respuesta; esto no: el telefono puede tener varias
    /// peticiones en vuelo a la vez (el manifiesto, el texto de una nota, una
    /// tanda de cambios encolados sin cobertura) y necesita saber cual contesto
    /// la PC. El id lo genera el telefono, que es quien espera.
    ///
    /// La operacion va en un enum interno (`NotesRequestWire`), mismo criterio
    /// que `AiChatEventWire`: lo que crece es ese enum, no `MessageV1`.
    ///
    /// Va al final del enum a proposito: postcard identifica las variantes por
    /// indice, asi que agregar aca no corre las que ya existen.
    NotesRequest {
        request_id: String,
        request: NotesRequestWire,
    },

    /// PC -> Android: la respuesta a una `NotesRequest`, con su mismo
    /// `request_id`.
    ///
    /// **Siempre llega una**, tambien cuando la peticion falla (`Failed`): el
    /// telefono que espera sin respuesta no sabria distinguir "todavia no" de
    /// "nunca", que es justo lo que el buzon de `nexodeck-control` ya aprendio
    /// (ver `outbox.rs`).
    NotesResponse {
        request_id: String,
        response: NotesResponseWire,
    },

    /// PC -> Android: la boveda cambio (se guardo una nota, se aprobo una
    /// propuesta, alguien edito en Obsidian).
    ///
    /// **No lleva el cambio, solo el aviso**: el telefono pide el manifiesto y
    /// decide. Mandar el contenido aca obligaria a la PC a saber que tiene ya
    /// cada telefono, y a los dos a ponerse de acuerdo sobre el orden de los
    /// avisos; con el manifiesto, el que compara es siempre quien tiene la
    /// copia.
    NotesChanged,
}

/// Lo que el telefono le pide a la PC sobre las notas (ver
/// `MessageV1::NotesRequest`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum NotesRequestWire {
    /// Todas las notas con su hash: con esto el telefono sabe que le falta, que
    /// le sobra y que cambio, sin bajarse nada. Incluye `privado/`.
    Manifest,
    /// El texto de estas notas. Se piden varias juntas porque tras un rato sin
    /// cobertura suelen ser varias, y una peticion por nota multiplicaria las
    /// idas y vueltas por el enlace mas lento (datos moviles).
    Fetch {
        paths: Vec<String>,
    },
    /// Guardar, crear o borrar. Viajan **en una tanda y en orden**: es lo que el
    /// telefono tenia encolado, y aplicar la mitad dejaria la copia local
    /// diciendo algo distinto de la boveda.
    Apply {
        ops: Vec<NoteOpWire>,
    },
}

/// Un cambio sobre una nota, tal como cruza el cable.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum NoteOpWire {
    /// Guardar. `base_hash` es el hash con el que el telefono abrio la nota;
    /// `None` la crea y **nunca pisa** una que ya exista.
    Save {
        path: String,
        text: String,
        base_hash: Option<String>,
    },
    /// Borrar (la PC la mueve a `.trash/`). Con `base_hash`, si alguien la
    /// edito mientras tanto no se borra nada y se contesta con lo que hay.
    Delete {
        path: String,
        base_hash: Option<String>,
    },
}

/// Lo que la PC contesta (ver `MessageV1::NotesResponse`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum NotesResponseWire {
    Manifest {
        notes: Vec<NoteStampWire>,
    },
    Fetch {
        notes: Vec<NoteContentWire>,
    },
    /// Un resultado por operacion, **en el mismo orden** que llegaron.
    Applied {
        results: Vec<NoteOpResultWire>,
    },
    /// La peticion entera no se pudo atender: no hay boveda configurada, o el
    /// buzon todavia no arranco.
    Failed {
        detail: String,
    },
}

/// Una nota de la boveda sin su texto. Espejo de `nexodeck_docs::NoteStamp`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NoteStampWire {
    /// Relativa a la boveda, con `/` y `.md`.
    pub path: String,
    /// sha256 del fichero tal como esta en disco.
    pub hash: String,
    /// Segundos desde epoca, como los da el sistema de ficheros. `None` si no
    /// los da.
    pub modified_secs: Option<i64>,
    /// Esta en `privado/`: ningun agente la lee, pero el usuario si.
    pub private: bool,
}

/// El texto de una nota, con el hash que le corresponde.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NoteContentWire {
    pub path: String,
    /// Con `\n`. La PC conserva el CRLF y el BOM del fichero al guardar.
    pub text: String,
    pub hash: String,
    pub private: bool,
    /// `false` si la nota ya no existe; entonces `text` y `hash` van vacios.
    pub exists: bool,
}

/// Que paso con una operacion de la tanda.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum NoteOpResultWire {
    Saved {
        path: String,
        hash: String,
    },
    Deleted {
        path: String,
    },
    /// La nota cambio en la PC mientras el telefono estaba sin conexion. **No
    /// se escribio nada**: viaja lo que hay en disco para que el telefono
    /// conserve las dos versiones y el usuario elija.
    Conflict {
        path: String,
        disk_text: String,
        disk_hash: String,
    },
    Failed {
        path: String,
        detail: String,
    },
}

/// Un evento de la conversacion con el asistente de IA, tal como cruza el
/// cable (ver `MessageV1::AiChatEvent`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum AiChatEventWire {
    /// El usuario escribio ESTO en la PC. Lo que escribe el propio
    /// telefono no se re-manda de vuelta: ya lo muestra el solo, apenas lo
    /// escribe, antes incluso de mandarlo.
    UserMessage {
        text: String,
    },
    /// El asistente esta generando una respuesta. Se manda una sola vez al
    /// arrancar una tanda (el primer token tras un evento terminal) y no
    /// de nuevo hasta el proximo -- ver el comentario de
    /// `MessageV1::AiChatEvent`.
    Typing,
    AssistantMessage {
        text: String,
    },
    ToolStarted {
        name: String,
        summary: String,
    },
    ToolFinished {
        name: String,
        ok: bool,
        summary: String,
    },
    DraftReady {
        draft: AiDraftWire,
    },
    TurnDone,
    Failed {
        detail: String,
    },
}

/// Borrador de boton propuesto por el asistente, tal como cruza el cable.
/// Espejo de `nexodeck_ai::draft::ActionDraft` (`nexodeck-ffi::api::ai::AiActionDraft`),
/// duplicado por la misma razon que el resto de los tipos de este archivo:
/// el protocolo no depende de la implementacion de ninguna punta.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiDraftWire {
    pub name: String,
    pub description: Option<String>,
    pub icon: String,
    pub color_hex: String,
    pub summary: String,
    pub steps: Vec<AiDraftStepWire>,
    pub is_macro: bool,
    pub risk: AiRiskWire,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiDraftStepWire {
    pub name: String,
    pub description: Option<String>,
    pub action_type: RemoteActionKind,
    /// Como lo escribio el modelo, sin resolver. Se muestra en la vista
    /// previa porque es lo mas legible.
    pub command: String,
    /// El que realmente se ejecuta -- con el `working_directory` ya
    /// plegado adentro, y (cuando este mensaje viaja Android -> PC en
    /// `AiApplyDraft`/`AiRunDraft`) tambien con los `{{parametros}}` ya
    /// sustituidos por valores concretos.
    pub resolved_command: String,
    pub terminal: AiTerminalWire,
    pub requires_admin: bool,
    pub show_terminal_window: bool,
    pub working_directory: Option<String>,
    /// Los `{{parametros}}` que le faltan al comando. Cuando este mensaje
    /// viaja de vuelta a la PC (`AiApplyDraft`/`AiRunDraft`) ya no importan
    /// -- el que lo mando ya los resolvio -- pero igual viajan completos,
    /// por si la PC los necesita para guardar la accion con sus campos de
    /// parametro tal como los definio el modelo.
    pub parameters: Vec<RemoteActionParam>,
    pub delay_ms_after: u32,
    pub risk: AiRiskWire,
    pub risk_notes: Vec<String>,
    pub auto_subscribe: Option<AiAutoSubscribeWire>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AiTerminalWire {
    DefaultShell,
    PowerShell,
    Bash,
    Cmd,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AiRiskWire {
    Safe,
    Caution,
    Dangerous,
}

/// Suscripcion a un hub que un paso arranca solo al terminar bien. Espejo
/// de `nexodeck_ai::draft::DraftAutoSubscribe`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiAutoSubscribeWire {
    pub base_url: String,
    pub hub_path: String,
    pub invoke_method: String,
    pub json_field: String,
    pub allow_invalid_cert: bool,
}

/// Nombres y caracteristicas de las piezas del equipo (ver
/// `MessageV1::HostComponents`). Mismos campos que
/// `nexodeck_hardware::HostComponents`/la struct FFI de
/// `nexodeck-ffi/src/api/components.rs` -- es el mismo dato, solo que este
/// es el que cruza el cable.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HostComponentsWire {
    pub cpu_name: Option<String>,
    pub ram_vendor: Option<String>,
    pub ram_part_number: Option<String>,
    pub ram_speed_mts: Option<u32>,
    pub ram_speed_rated_mts: Option<u32>,
    pub ram_module_count: Option<u32>,
    pub gpu_name: Option<String>,
    pub gpu_vram_total_mb: Option<f64>,
    pub network_adapter: Option<String>,
}

/// Resumen de una suscripcion (ver `HubSubscriptionsSnapshot`), para
/// mostrar en el panel remoto sin que el telefono tenga que resolver nada
/// contra una base propia -- la suscripcion vive en la PC, el telefono solo
/// la mira.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HubSubscriptionWire {
    pub id: String,
    pub name: String,
    /// `base_url` + `hub_path` (o la URL entera si es WebSocket crudo) ya
    /// resuelto, para mostrar de un vistazo sin que Android arme el string.
    pub target: String,
    pub status: HubSubscriptionStatusWire,
    /// Extracto corto del ultimo mensaje (el nombre del evento + un pedazo
    /// del payload), no el JSON entero -- "resumido" a proposito, para no
    /// mandar por WiFi cada mensaje completo por algo que el telefono solo
    /// mira de pasada.
    pub last_event_summary: Option<String>,
    /// Unix seconds. `None` si todavia no llego ningun mensaje.
    pub last_event_at: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum HubSubscriptionStatusWire {
    Active,
    Stopped,
    Failed,
}

/// Las tres listas de procesos, tal como viajan por el cable.
///
/// Duplicado de `nexodeck_hardware::TopProcesses` por la misma razon que
/// [`HardwareSnapshot`]: el protocolo no depende de los tipos del crate de
/// hardware.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TopProcessesWire {
    pub by_cpu: Vec<ProcessGroupWire>,
    pub by_memory: Vec<ProcessGroupWire>,
    pub by_gpu: Vec<ProcessGroupWire>,
    pub by_disk: Vec<ProcessGroupWire>,
    /// Si la PC puede medir GPU por proceso. Distingue "aca no se puede" de
    /// "nadie la esta usando", que si no son la misma lista vacia.
    pub gpu_available: bool,
}

/// Una aplicacion y lo que consume en la PC.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProcessGroupWire {
    pub name: String,
    pub pids: Vec<u32>,
    pub cpu_percent: f32,
    pub memory_mb: f64,
    pub gpu_percent: Option<f32>,
    /// Bytes/segundo de lectura + escritura combinadas, sumado del grupo.
    pub disk_bytes_per_sec: f64,
    /// Segundos corriendo del mas viejo del grupo. `0` es **desconocido**, no
    /// recien arrancado: Windows no deja leer el arranque de los procesos del
    /// sistema.
    pub run_time_secs: u32,
    /// El grupo de NexoDeck: se muestra pero no se deja cerrar.
    pub is_self: bool,
}

/// En que punto esta una ejecucion remota.
///
/// Enum propio y no un `bool`: "lanzada" (una app que se abrio y sigue viva)
/// no es ni exito ni fallo, y aplastarlo a un booleano fue exactamente el
/// problema que tenia `ActionAck`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RunPhaseWire {
    Started,
    /// Seguia viva y muda: era una app, no un comando con salida.
    Launched,
    Succeeded,
    Failed,
    Cancelled,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roundtrip(msg: NexoDeckMessage) {
        let bytes = postcard::to_allocvec(&msg).expect("serialize");
        let back: NexoDeckMessage = postcard::from_bytes(&bytes).expect("deserialize");
        assert_eq!(msg, back);
    }

    #[test]
    fn roundtrip_ping() {
        roundtrip(NexoDeckMessage::V1(MessageV1::Ping));
    }

    #[test]
    fn roundtrip_relay_offer() {
        roundtrip(NexoDeckMessage::V1(MessageV1::RelayOffer {
            host: "vps.ejemplo.com".into(),
            port: 58644,
            token_hex: "a".repeat(64),
        }));
    }

    /// Apagar el tunel viaja como la misma variante con el host vacio.
    #[test]
    fn roundtrip_relay_offer_vacia() {
        roundtrip(NexoDeckMessage::V1(MessageV1::RelayOffer {
            host: String::new(),
            port: 0,
            token_hex: String::new(),
        }));
    }

    #[test]
    fn roundtrip_pong() {
        roundtrip(NexoDeckMessage::V1(MessageV1::Pong));
    }

    #[test]
    fn roundtrip_notes_request_manifest() {
        roundtrip(NexoDeckMessage::V1(MessageV1::NotesRequest {
            request_id: "r-1".into(),
            request: NotesRequestWire::Manifest,
        }));
    }

    #[test]
    fn roundtrip_notes_request_fetch() {
        roundtrip(NexoDeckMessage::V1(MessageV1::NotesRequest {
            request_id: "r-2".into(),
            request: NotesRequestWire::Fetch {
                paths: vec!["temas/malla.md".into(), "privado/claves.md".into()],
            },
        }));
    }

    /// Lo que el telefono tenia encolado sin cobertura: guardar una nota nueva,
    /// guardar una que ya tenia y borrar otra.
    #[test]
    fn roundtrip_notes_request_apply() {
        roundtrip(NexoDeckMessage::V1(MessageV1::NotesRequest {
            request_id: "r-3".into(),
            request: NotesRequestWire::Apply {
                ops: vec![
                    NoteOpWire::Save {
                        path: "temas/nueva.md".into(),
                        text: "# Nueva\n\nñandú\n".into(),
                        base_hash: None,
                    },
                    NoteOpWire::Save {
                        path: "temas/malla.md".into(),
                        text: "# Malla\n".into(),
                        base_hash: Some("h1".into()),
                    },
                    NoteOpWire::Delete {
                        path: "temas/vieja.md".into(),
                        base_hash: Some("h2".into()),
                    },
                ],
            },
        }));
    }

    #[test]
    fn roundtrip_notes_response_manifest() {
        roundtrip(NexoDeckMessage::V1(MessageV1::NotesResponse {
            request_id: "r-1".into(),
            response: NotesResponseWire::Manifest {
                notes: vec![
                    NoteStampWire {
                        path: "temas/malla.md".into(),
                        hash: "h1".into(),
                        modified_secs: Some(1_789_000_000),
                        private: false,
                    },
                    NoteStampWire {
                        path: "privado/claves.md".into(),
                        hash: "h2".into(),
                        modified_secs: None,
                        private: true,
                    },
                ],
            },
        }));
    }

    #[test]
    fn roundtrip_notes_response_fetch() {
        roundtrip(NexoDeckMessage::V1(MessageV1::NotesResponse {
            request_id: "r-2".into(),
            response: NotesResponseWire::Fetch {
                notes: vec![
                    NoteContentWire {
                        path: "temas/malla.md".into(),
                        text: "# Malla\n\nla ortofoto sale deformada\n".into(),
                        hash: "h1".into(),
                        private: false,
                        exists: true,
                    },
                    // Una que ya no esta: el telefono la borra de su copia.
                    NoteContentWire {
                        path: "temas/vieja.md".into(),
                        text: String::new(),
                        hash: String::new(),
                        private: false,
                        exists: false,
                    },
                ],
            },
        }));
    }

    /// Cada operacion contesta lo suyo, incluido el choque que conserva las dos
    /// versiones.
    #[test]
    fn roundtrip_notes_response_applied() {
        roundtrip(NexoDeckMessage::V1(MessageV1::NotesResponse {
            request_id: "r-3".into(),
            response: NotesResponseWire::Applied {
                results: vec![
                    NoteOpResultWire::Saved {
                        path: "temas/nueva.md".into(),
                        hash: "h3".into(),
                    },
                    NoteOpResultWire::Conflict {
                        path: "temas/malla.md".into(),
                        disk_text: "# Malla editada en la PC\n".into(),
                        disk_hash: "h9".into(),
                    },
                    NoteOpResultWire::Deleted {
                        path: "temas/vieja.md".into(),
                    },
                    NoteOpResultWire::Failed {
                        path: "temas/rota.md".into(),
                        detail: "no es UTF-8".into(),
                    },
                ],
            },
        }));
    }

    #[test]
    fn roundtrip_notes_response_failed() {
        roundtrip(NexoDeckMessage::V1(MessageV1::NotesResponse {
            request_id: "r-4".into(),
            response: NotesResponseWire::Failed {
                detail: "no hay ninguna boveda configurada".into(),
            },
        }));
    }

    #[test]
    fn roundtrip_notes_changed() {
        roundtrip(NexoDeckMessage::V1(MessageV1::NotesChanged));
    }

    #[test]
    fn roundtrip_pair_hello() {
        roundtrip(NexoDeckMessage::V1(MessageV1::PairHello {
            device_name: "Pixel de Juan".into(),
            platform: DevicePlatformWire::Android,
        }));
    }

    #[test]
    fn roundtrip_pair_pin() {
        roundtrip(NexoDeckMessage::V1(MessageV1::PairPin {
            pin: "482913".into(),
            host_name: "DESKTOP-JUAN".into(),
            host_platform: DevicePlatformWire::Windows,
        }));
    }

    #[test]
    fn roundtrip_pair_confirm() {
        roundtrip(NexoDeckMessage::V1(MessageV1::PairConfirm));
    }

    #[test]
    fn roundtrip_pair_accepted() {
        roundtrip(NexoDeckMessage::V1(MessageV1::PairAccepted {
            device_id: "3d6f6d2a-8f0a-4b8e-9c1a-6f8e2b1a9c3d".into(),
            cert_fingerprint: "ab".repeat(32),
        }));
    }

    #[test]
    fn roundtrip_pair_rejected() {
        roundtrip(NexoDeckMessage::V1(MessageV1::PairRejected {
            reason: "PIN incorrecto".into(),
        }));
    }

    #[test]
    fn roundtrip_reconnect() {
        roundtrip(NexoDeckMessage::V1(MessageV1::Reconnect {
            device_id: "3d6f6d2a-8f0a-4b8e-9c1a-6f8e2b1a9c3d".into(),
        }));
    }

    #[test]
    fn roundtrip_reconnect_accepted() {
        roundtrip(NexoDeckMessage::V1(MessageV1::ReconnectAccepted));
    }

    #[test]
    fn roundtrip_reconnect_rejected() {
        roundtrip(NexoDeckMessage::V1(MessageV1::ReconnectRejected {
            reason: "dispositivo no autorizado".into(),
        }));
    }

    #[test]
    fn roundtrip_hardware_snapshot() {
        roundtrip(NexoDeckMessage::V1(MessageV1::HardwareSnapshot(
            HardwareSnapshot {
                cpu_usage: 42.5,
                cpu_freq_mhz: Some(3600),
                cpu_temp: Some(61.2),
                ram_used_mb: 8192.0,
                ram_total_mb: 16384.0,
                disk_used_mb: 512_000.0,
                disk_total_mb: 1_000_000.0,
                disks: vec![
                    DiskUsageWire {
                        mount_point: "C:".into(),
                        label: "Sistema".into(),
                        kind: DiskKindWire::Ssd,
                        used_mb: 312_000.0,
                        total_mb: 500_000.0,
                        temp_c: Some(44.0),
                        temp_age_secs: Some(12),
                        read_bytes_per_sec: Some(1_048_576.0),
                        write_bytes_per_sec: Some(0.0),
                    },
                    // Con la etiqueta vacia, el medio desconocido y sin
                    // actividad medible (volumen sin letra, o PC sin
                    // Windows): los casos reales que la UI tiene que saber
                    // dibujar.
                    DiskUsageWire {
                        mount_point: "D:".into(),
                        label: String::new(),
                        kind: DiskKindWire::Unknown,
                        used_mb: 200_000.0,
                        total_mb: 500_000.0,
                        read_bytes_per_sec: None,
                        write_bytes_per_sec: None,
                        temp_c: None,
                        temp_age_secs: None,
                    },
                ],
                net_rx_bytes: 123_456,
                net_tx_bytes: 654_321,
                gpu_usage: None,
                gpu_temp: None,
                gpu_vram_used_mb: None,
                gpu_vram_total_mb: None,
                gpu_clock_mhz: Some(2520),
                cpu_threads_total: 16,
                cpu_threads_busy: 5,
                gpu_power_watts: Some(182.5),
                gpu_power_limit_watts: Some(450.0),
            },
        )));
    }

    #[test]
    fn roundtrip_top_processes() {
        roundtrip(NexoDeckMessage::V1(MessageV1::TopProcesses(
            TopProcessesWire {
                by_cpu: vec![ProcessGroupWire {
                    name: "chrome.exe".into(),
                    pids: vec![100, 101, 102],
                    cpu_percent: 12.5,
                    memory_mb: 4096.0,
                    gpu_percent: Some(3.5),
                    disk_bytes_per_sec: 2048.0,
                    run_time_secs: 3661,
                    is_self: false,
                }],
                by_memory: vec![],
                // Vacia y con `gpu_available` en true: "nadie usa la GPU", que
                // es distinto de "esta PC no lo sabe medir".
                by_gpu: vec![],
                by_disk: vec![],
                gpu_available: true,
            },
        )));
    }

    #[test]
    fn roundtrip_watch_processes() {
        roundtrip(NexoDeckMessage::V1(MessageV1::WatchProcesses {
            enabled: true,
        }));
    }

    #[test]
    fn roundtrip_terminate_process_group() {
        roundtrip(NexoDeckMessage::V1(MessageV1::TerminateProcessGroup {
            name: "notepad.exe".into(),
            pids: vec![4242],
        }));
        roundtrip(NexoDeckMessage::V1(MessageV1::ProcessTerminated {
            name: "lsass.exe".into(),
            killed: 0,
            failed: 0,
            rejected_reason: Some("es un proceso critico".into()),
        }));
    }

    #[test]
    fn roundtrip_actions_catalog() {
        roundtrip(NexoDeckMessage::V1(MessageV1::ActionsCatalog {
            actions: vec![
                RemoteAction {
                    id: "abc-123".into(),
                    name: "Git status".into(),
                    icon: "terminal".into(),
                    color_hex: "#6366F1".into(),
                    group_id: Some("group-dev".into()),
                    group_name: Some("Desarrollo".into()),
                    group_color_hex: Some("#6366F1".into()),
                    kind: RemoteActionKind::Terminal,
                    parameters: vec![],
                    step_count: 0,
                },
                RemoteAction {
                    id: "def-456".into(),
                    name: "Abrir OBS".into(),
                    icon: "videocam".into(),
                    color_hex: "#EF4444".into(),
                    group_id: None,
                    group_name: None,
                    group_color_hex: None,
                    kind: RemoteActionKind::Clipboard,
                    parameters: vec![],
                    step_count: 0,
                },
            ],
        }));
    }

    #[test]
    fn roundtrip_actions_catalog_empty() {
        roundtrip(NexoDeckMessage::V1(MessageV1::ActionsCatalog { actions: vec![] }));
    }

    /// Los tres tipos de parametro y una macro con pasos en el mismo
    /// catalogo: es la forma que efectivamente arma el lado PC cuando hay
    /// acciones parametrizadas, y la que el telefono necesita para dibujar
    /// el prompt sin inventar nada.
    #[test]
    fn roundtrip_actions_catalog_with_parameters_and_macro() {
        roundtrip(NexoDeckMessage::V1(MessageV1::ActionsCatalog {
            actions: vec![
                RemoteAction {
                    id: "deploy".into(),
                    name: "Deploy".into(),
                    icon: "rocket".into(),
                    color_hex: "#6366F1".into(),
                    group_id: None,
                    group_name: None,
                    group_color_hex: None,
                    kind: RemoteActionKind::Macro,
                    parameters: vec![
                        RemoteActionParam {
                            key: "branch".into(),
                            label: "Rama".into(),
                            kind: RemoteParamKind::Text,
                            default_value: Some("main".into()),
                            options: vec![],
                        },
                        RemoteActionParam {
                            key: "entorno".into(),
                            label: "Entorno".into(),
                            kind: RemoteParamKind::Select,
                            default_value: None,
                            options: vec!["staging".into(), "produccion".into()],
                        },
                        RemoteActionParam {
                            key: "reintentos".into(),
                            label: "Reintentos".into(),
                            kind: RemoteParamKind::Number,
                            default_value: Some("3".into()),
                            options: vec![],
                        },
                    ],
                    step_count: 4,
                },
            ],
        }));
    }

    #[test]
    fn roundtrip_execute_action() {
        roundtrip(NexoDeckMessage::V1(MessageV1::ExecuteAction {
            action_id: "git-status".into(),
            params: vec![],
        }));
    }

    #[test]
    fn roundtrip_execute_action_with_params() {
        roundtrip(NexoDeckMessage::V1(MessageV1::ExecuteAction {
            action_id: "deploy".into(),
            params: vec![
                ActionParamValue {
                    key: "branch".into(),
                    value: "feature/pin".into(),
                },
                // Un valor vacio no es lo mismo que un parametro ausente:
                // ausente cae al default de la accion, vacio es una eleccion
                // explicita del usuario.
                ActionParamValue {
                    key: "entorno".into(),
                    value: String::new(),
                },
            ],
        }));
    }

    #[test]
    fn roundtrip_action_ack_ok() {
        roundtrip(NexoDeckMessage::V1(MessageV1::ActionAck {
            action_id: "git-status".into(),
            success: true,
            error: None,
        }));
    }

    #[test]
    fn roundtrip_action_ack_error() {
        roundtrip(NexoDeckMessage::V1(MessageV1::ActionAck {
            action_id: "git-status".into(),
            success: false,
            error: Some("comando no encontrado".into()),
        }));
    }

    #[test]
    fn roundtrip_action_run_update_started() {
        roundtrip(NexoDeckMessage::V1(MessageV1::ActionRunUpdate {
            run_id: "run_3_1712_0".into(),
            action_id: "analizar".into(),
            phase: RunPhaseWire::Started,
            exit_code: None,
            elapsed_ms: 0,
            output_tail: String::new(),
        }));
    }

    #[test]
    fn roundtrip_action_run_update_failed() {
        roundtrip(NexoDeckMessage::V1(MessageV1::ActionRunUpdate {
            run_id: "run_4_1713_0".into(),
            action_id: "analizar".into(),
            phase: RunPhaseWire::Failed,
            exit_code: Some(1),
            elapsed_ms: 31_450,
            output_tail: "error - falta un punto y coma\n".into(),
        }));
    }

    /// Las cinco fases tienen que sobrevivir el ida y vuelta: agregar una
    /// variante al medio de `RunPhaseWire` correria los indices de postcard.
    #[test]
    fn roundtrip_every_run_phase() {
        for phase in [
            RunPhaseWire::Started,
            RunPhaseWire::Launched,
            RunPhaseWire::Succeeded,
            RunPhaseWire::Failed,
            RunPhaseWire::Cancelled,
        ] {
            roundtrip(NexoDeckMessage::V1(MessageV1::ActionRunUpdate {
                run_id: "r".into(),
                action_id: "a".into(),
                phase,
                exit_code: None,
                elapsed_ms: 1,
                output_tail: String::new(),
            }));
        }
    }

    #[test]
    fn roundtrip_hub_subscriptions_snapshot_empty() {
        roundtrip(NexoDeckMessage::V1(MessageV1::HubSubscriptionsSnapshot {
            subscriptions: vec![],
        }));
    }

    #[test]
    fn roundtrip_hub_subscriptions_snapshot() {
        roundtrip(NexoDeckMessage::V1(MessageV1::HubSubscriptionsSnapshot {
            subscriptions: vec![
                HubSubscriptionWire {
                    id: "sub-1".into(),
                    name: "Entrenamiento IA: iniciar · job-123".into(),
                    target: "http://localhost:5242/hubs/plant-training-progress".into(),
                    status: HubSubscriptionStatusWire::Active,
                    last_event_summary: Some(
                        "ReceivePlantTrainingProgress: {\"pct\":50}".into(),
                    ),
                    last_event_at: Some(1_800_000_000),
                },
                HubSubscriptionWire {
                    id: "sub-2".into(),
                    name: "WS de prueba".into(),
                    target: "ws://localhost:9000/eventos".into(),
                    status: HubSubscriptionStatusWire::Failed,
                    last_event_summary: None,
                    last_event_at: None,
                },
            ],
        }));
    }

    #[test]
    fn roundtrip_host_components_completo() {
        roundtrip(NexoDeckMessage::V1(MessageV1::HostComponents(
            HostComponentsWire {
                cpu_name: Some("AMD Ryzen 7 5700X 8-Core Processor".into()),
                ram_vendor: Some("Corsair".into()),
                ram_part_number: Some("CM4X16GD3600C18K2D".into()),
                ram_speed_mts: Some(3600),
                ram_speed_rated_mts: Some(3600),
                ram_module_count: Some(2),
                gpu_name: Some("NVIDIA GeForce RTX 5060 Ti".into()),
                gpu_vram_total_mb: Some(16311.0),
                network_adapter: Some("Ethernet".into()),
            },
        )));
    }

    #[test]
    fn roundtrip_host_components_vacio() {
        roundtrip(NexoDeckMessage::V1(MessageV1::HostComponents(
            HostComponentsWire {
                cpu_name: None,
                ram_vendor: None,
                ram_part_number: None,
                ram_speed_mts: None,
                ram_speed_rated_mts: None,
                ram_module_count: None,
                gpu_name: None,
                gpu_vram_total_mb: None,
                network_adapter: None,
            },
        )));
    }

    #[test]
    fn roundtrip_ai_status() {
        roundtrip(NexoDeckMessage::V1(MessageV1::AiStatus {
            enabled: true,
            ready: false,
        }));
    }

    fn sample_ai_draft() -> AiDraftWire {
        AiDraftWire {
            name: "Iniciar entrenamiento y suscribirse al hub".into(),
            description: Some("Dispara el job y escucha su progreso".into()),
            icon: "terminal".into(),
            color_hex: "#6366F1".into(),
            summary: "El comando usa curl instalado en C:\\WINDOWS\\system32".into(),
            steps: vec![AiDraftStepWire {
                name: "Iniciar entrenamiento".into(),
                description: None,
                action_type: RemoteActionKind::Terminal,
                command: "curl -s -X POST http://localhost:5242/PlantDetection/training/start"
                    .into(),
                resolved_command:
                    "curl -s -X POST http://localhost:5242/PlantDetection/training/start".into(),
                terminal: AiTerminalWire::PowerShell,
                requires_admin: false,
                show_terminal_window: false,
                working_directory: None,
                parameters: vec![],
                delay_ms_after: 0,
                risk: AiRiskWire::Safe,
                risk_notes: vec![],
                auto_subscribe: Some(AiAutoSubscribeWire {
                    base_url: "http://localhost:5242".into(),
                    hub_path: "/trainingHub".into(),
                    invoke_method: "SubscribeToJob".into(),
                    json_field: "run_id".into(),
                    allow_invalid_cert: false,
                }),
            }],
            is_macro: false,
            risk: AiRiskWire::Safe,
        }
    }

    #[test]
    fn roundtrip_ai_chat_event_user_message() {
        roundtrip(NexoDeckMessage::V1(MessageV1::AiChatEvent(
            AiChatEventWire::UserMessage {
                text: "que gpu tengo?".into(),
            },
        )));
    }

    #[test]
    fn roundtrip_ai_chat_event_typing() {
        roundtrip(NexoDeckMessage::V1(MessageV1::AiChatEvent(
            AiChatEventWire::Typing,
        )));
    }

    #[test]
    fn roundtrip_ai_chat_event_assistant_message() {
        roundtrip(NexoDeckMessage::V1(MessageV1::AiChatEvent(
            AiChatEventWire::AssistantMessage {
                text: "Tenes una RTX 5060 Ti con 16 GB de VRAM.".into(),
            },
        )));
    }

    #[test]
    fn roundtrip_ai_chat_event_tool_started_y_finished() {
        roundtrip(NexoDeckMessage::V1(MessageV1::AiChatEvent(
            AiChatEventWire::ToolStarted {
                name: "find_project".into(),
                summary: "Buscando el proyecto".into(),
            },
        )));
        roundtrip(NexoDeckMessage::V1(MessageV1::AiChatEvent(
            AiChatEventWire::ToolFinished {
                name: "find_project".into(),
                ok: true,
                summary: "11 resultados".into(),
            },
        )));
    }

    #[test]
    fn roundtrip_ai_chat_event_draft_ready() {
        roundtrip(NexoDeckMessage::V1(MessageV1::AiChatEvent(
            AiChatEventWire::DraftReady {
                draft: sample_ai_draft(),
            },
        )));
    }

    #[test]
    fn roundtrip_ai_chat_event_turn_done_y_failed() {
        roundtrip(NexoDeckMessage::V1(MessageV1::AiChatEvent(
            AiChatEventWire::TurnDone,
        )));
        roundtrip(NexoDeckMessage::V1(MessageV1::AiChatEvent(
            AiChatEventWire::Failed {
                detail: "error hablando con el modelo".into(),
            },
        )));
    }

    #[test]
    fn roundtrip_ai_send_message() {
        roundtrip(NexoDeckMessage::V1(MessageV1::AiSendMessage {
            text: "abrime obs".into(),
        }));
    }

    #[test]
    fn roundtrip_ai_activate() {
        roundtrip(NexoDeckMessage::V1(MessageV1::AiActivate));
    }

    #[test]
    fn roundtrip_ai_apply_draft() {
        roundtrip(NexoDeckMessage::V1(MessageV1::AiApplyDraft {
            draft: sample_ai_draft(),
        }));
    }

    #[test]
    fn roundtrip_ai_run_draft() {
        roundtrip(NexoDeckMessage::V1(MessageV1::AiRunDraft {
            draft: sample_ai_draft(),
        }));
    }

    #[test]
    fn roundtrip_ai_ask_about_process() {
        roundtrip(NexoDeckMessage::V1(MessageV1::AiAskAboutProcess {
            group: ProcessGroupWire {
                name: "chrome.exe".into(),
                pids: vec![100, 101, 102],
                cpu_percent: 12.5,
                memory_mb: 4096.0,
                gpu_percent: Some(3.5),
                disk_bytes_per_sec: 2048.0,
                run_time_secs: 3661,
                is_self: false,
            },
        }));
    }
}
