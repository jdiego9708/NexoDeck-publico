/// Tokens de espaciado y radio reusados en los widgets del Home
/// (metricas + deck de acciones) para no repetir numeros magicos.
abstract final class AppSpacing {
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;

  /// Margen de pantalla del shell de escritorio. Se llama `gutter` y no
  /// "mdPlus" a proposito: no es un peldano mas de la escala, es el margen
  /// con el que respira el contenido contra el borde de la ventana.
  static const double gutter = 16.0;

  static const double lg = 20.0;
  static const double xl = 32.0;
}

abstract final class AppRadius {
  static const double card = 20.0;
  static const double chip = 12.0;

  /// Radio de los badges chicos (MHz, °C, VRAM) y de las barras de los
  /// charts, donde el radio de chip resulta demasiado redondo.
  static const double badge = 6.0;
}

/// Tamanos que gobiernan el layout responsive (metricas + deck). Viven aca
/// y no como constantes sueltas en cada widget porque son justamente los
/// numeros que hay que tocar para recalibrar como se reparte la pantalla
/// entre telefono vertical, telefono horizontal, tablet y escritorio.
abstract final class AppSizes {
  /// Grosor del area sensible de un divisor arrastrable. La linea que se ve
  /// sigue midiendo 1 px: esto es solo el blanco al que hay que apuntar.
  ///
  /// Un divisor de 1 px es **imposible de agarrar** con el mouse -- hay que
  /// acertarle al pixel-- asi que el area de agarre se extiende a los lados y
  /// se dibuja transparente. 8 px es lo que usan los editores de codigo para
  /// sus paneles.
  static const double resizeHandleThickness = 8.0;

  /// Cuanto avanza un divisor por cada pulsacion de flecha, cuando tiene el
  /// foco de teclado. Existe porque el arrastre con mouse no puede ser la
  /// **unica** forma de ajustar el reparto.
  static const double resizeKeyboardStep = 16.0;

  /// Lo que le tiene que quedar al deck en el eje VERTICAL para que la franja
  /// de metricas se pueda seguir estirando: dos filas de tarjetas. El
  /// equivalente de [minDeckWidthWithPanel] para el otro eje.
  static const double minDeckHeightWithStrip = 200.0;

  /// Hasta donde se puede **arrastrar** la franja de metricas, y desde donde.
  ///
  /// No confundir con el reparto por defecto ([metricStripFactor] y su clamp):
  /// ese es el que se calcula solo, y estos son los topes de lo que el usuario
  /// puede pedir a mano. El minimo es lo que necesita la densidad compacta
  /// (titulo y valor en la misma linea) mas sus margenes; por debajo la franja
  /// dejaria de decir que metrica es cada cosa.
  static const double metricStripDragMinHeight = 76.0;
  static const double metricStripDragMaxHeight = 320.0;

  /// El reparto por defecto de la franja: ~20% del alto del `body`, acotado.
  /// Es lo que habia antes de que el divisor fuera arrastrable, y sigue siendo
  /// lo que ve quien nunca lo toca.
  static const double metricStripFactor = 0.2;
  static const double metricStripPreferredMinHeight = 96.0;
  static const double metricStripPreferredMaxHeight = 168.0;

  /// Tope de arrastre del riel vertical: **sin limite propio**. Antes tenia
  /// un maximo fijo (340, bastante por encima de [metricRailMaxWidth] --el
  /// tope del calculo automatico-- porque con mas ancho la lista de discos
  /// pasa a una fila por unidad); costo real encontrado: el usuario queria
  /// seguir agrandandolo mas alla de eso y el divisor se negaba, aunque el
  /// deck de acciones tuviera de sobra para ceder (ver `bestColumnCountForAspect`,
  /// que ya reduce columnas solo con el ancho que le quede). Ahora el unico
  /// limite real es cuanto necesita el deck para seguir siendo usable
  /// (`PanelSlot.minRemaining`), no un numero fijo de este lado.
  static const double metricRailDragMaxWidth = double.infinity;

  /// Topes de arrastre de la franja micro (el layout "Deck al maximo"). El
  /// minimo **es** su alto natural: la franja micro ya es lo minimo que se
  /// puede mostrar, asi que solo se puede agrandar. Al crecer, los charts
  /// crecen con ella (derivan su radio del box), que es lo unico que cambia
  /// -- la densidad sigue siendo micro por definicion del layout.
  static const double microMetricStripDragMaxHeight = 160.0;

  /// Ancho minimo de una tile de metrica antes de reducir la cantidad de
  /// columnas de la franja horizontal. Calibrado para que un telefono de
  /// 360 dp entre en 2 columnas (y no en 1): con los paddings y el chevron
  /// quedan ~300 dp utiles, o sea ~150 por tile.
  static const double minMetricTileWidth = 142.0;

  /// Alto minimo para la tile completa: titulo, valor y badges en tres
  /// lineas. Por debajo de esto la franja baja de densidad.
  static const double minFullMetricTileHeight = 86.0;

  /// Alto de tile a partir del cual la densidad completa tambien dibuja el
  /// subtitulo (el nombre de la pieza: "Ryzen 7 5700X", "Ethernet").
  ///
  /// Son los tres lineas de [minFullMetricTileHeight] mas una cuarta para el
  /// subtitulo. La franja de un telefono vertical mide justo el minimo, asi
  /// que ahi **no** aparece -- que es lo que pide el contrato del subtitulo:
  /// es contexto y nunca puede empujar al valor fuera de la tile. El reparto
  /// por defecto del escritorio arranca en `metricStripPreferredMinHeight`
  /// (96) y por lo tanto si lo muestra.
  static const double minFullMetricTileWithSubtitleHeight = 96.0;

  /// Alto minimo de la tile compacta, que pone titulo y valor en la MISMA
  /// linea y los badges debajo. Por debajo de esto solo entra el valor
  /// (`MetricDensity.micro`).
  static const double minCompactMetricTileHeight = 48.0;

  /// Ancho del riel vertical de metricas (modo horizontal en movil).
  static const double metricRailMinWidth = 150.0;
  static const double metricRailMaxWidth = 220.0;

  /// Piso del alto por tile en el riel. Repartir la altura entre las 5
  /// alcanza en un telefono apaisado tipico gracias a la densidad compacta;
  /// si la pantalla es aun mas baja, el riel scrollea antes que perder los
  /// badges (MHz, °C, VRAM) -- que es justo la informacion que faltaba en
  /// movil.
  static const double railPreferredTileHeight = minCompactMetricTileHeight;

  /// Fraccion del ancho disponible que toma el riel antes de clampear.
  static const double metricRailWidthFactor = 0.26;

  /// Alto de la franja micro de metricas del modo compacto: solo grafico y
  /// valor, una sola fila. Es el minimo con el que el chart sigue leyendose
  /// arriba del numero -- por debajo el donut de RAM/GPU queda en un hilo.
  static const double microMetricStripHeight = 58.0;

  /// Ancho minimo de una tile en esa franja. Muy por debajo de
  /// [minMetricTileWidth] porque la tile micro no dibuja ni titulo ni
  /// badges: solo tiene que entrar el valor. Si las metricas no entran en
  /// una fila a este ancho, la franja pasa a dos filas en vez de seguir
  /// achicandolas.
  static const double minMicroMetricTileWidth = 44.0;

  /// Ancho a partir del cual la tile micro deja de apilar grafico y valor y
  /// los pone lado a lado.
  ///
  /// Por debajo de esto (la franja de la ventana compacta, ~52 dp por tile)
  /// no hay lugar para dos cosas en la misma fila. Por encima --la franja
  /// del layout "Deck al maximo", donde cada tile se lleva ~250 dp-- apilar
  /// desperdicia el ancho y deja el chart aplastado contra el alto: el donut
  /// de RAM/GPU quedaba tan chico que su porcentaje interior era ilegible.
  static const double microMetricRowMinWidth = 120.0;

  /// Ancho del panel de procesos acoplado a un costado. El minimo es lo que
  /// necesitan el nombre de la app, su consumo y el tiempo corriendo sin que
  /// ninguno quede en puntos suspensivos. El maximo es el del reparto
  /// AUTOMATICO (quien nunca toca el divisor) -- el arrastre a mano usa
  /// [processPanelDragMaxWidth], sin este tope.
  static const double processPanelMinWidth = 260.0;
  static const double processPanelMaxWidth = 380.0;

  /// Tope de arrastre del panel de procesos: **sin limite propio**, igual
  /// que [metricRailDragMaxWidth] y por el mismo motivo real (el usuario
  /// pedia mas ancho y el deck de acciones tenia de sobra para cederlo). El
  /// unico limite es [minDeckWidthWithPanel].
  static const double processPanelDragMaxWidth = double.infinity;

  /// Lo que le tiene que quedar al deck para que el panel se pueda abrir: una
  /// tarjeta de accion mas los margenes. Por debajo de esto el panel no se
  /// dibuja y las tiles dejan de ser clicables.
  static const double minDeckWidthWithPanel = 260.0;

  /// Ancho del panel de acciones acoplado en el centro de control. El mismo
  /// criterio que el riel de metricas: un reparto automatico acotado que el
  /// usuario puede arrastrar.
  static const double actionsPanelMinWidth = 180.0;
  static const double actionsPanelMaxWidth = 320.0;
  static const double actionsPanelWidthFactor = 0.22;
  static const double actionsPanelDragMaxWidth = double.infinity;

  /// Ancho minimo del contenido CENTRAL -- el chat -- cuando tiene paneles a
  /// los dos lados. Por debajo, las burbujas y el composer dejan de leerse.
  static const double minChatWidthWithPanels = 360.0;

  /// Alto de una tile del panel de acciones compacto (icono + etiqueta en una
  /// linea) y ancho minimo para que quepan dos columnas.
  static const double compactActionTileHeight = 40.0;
  static const double minCompactActionTileWidth = 150.0;

  /// Ancho del panel compacto de conversaciones guardadas, dentro del panel del
  /// chat del centro de control. Angosto a proposito: es un indice para saltar
  /// entre charlas de un vistazo, no el contenido.
  static const double conversationsPanelWidth = 208.0;

  /// Ancho del panel de ejecuciones acoplado. Mas ancho que el de procesos
  /// porque lo que muestra son **lineas de salida**: a menos de esto, la
  /// salida de un `cargo build` o de ODM se parte cada tres palabras y deja
  /// de poder leerse en diagonal, que es justo para lo que se mira. El
  /// maximo de aca es el del reparto AUTOMATICO; el arrastre a mano usa
  /// [runPanelDragMaxWidth].
  static const double runPanelMinWidth = 320.0;
  static const double runPanelMaxWidth = 480.0;

  /// Tope de arrastre del panel de ejecuciones: sin limite propio, mismo
  /// criterio que [processPanelDragMaxWidth].
  static const double runPanelDragMaxWidth = double.infinity;

  /// A partir de este ancho el panel pone la lista de ejecuciones y la salida
  /// **lado a lado** en vez de una sobre otra. Es el equivalente de las
  /// columnas del panel de procesos: lo decide el ancho medido, no el dock.
  static const double runPanelSideBySideWidth = 720.0;

  /// Alto de una fila de la lista de ejecuciones: dos lineas (la etiqueta y,
  /// debajo, el estado con el cronometro).
  static const double runRowHeight = 46.0;

  /// A partir de este ancho, una fila del panel muestra todas las columnas
  /// (CPU, memoria y GPU por separado) en vez de solo la metrica elegida. Es
  /// lo que separa al panel acoplado del maximizado sin preguntarle al dock.
  static const double processPanelFullColumnsWidth = 560.0;

  /// Margen a cada lado de las filas del panel de procesos, encabezado
  /// incluido. **Una sola constante para los dos**: si el encabezado y las
  /// filas usan margenes distintos, las columnas quedan corridas y el error es
  /// dificil de ver -- todo "parece" bien, solo esta desalineado.
  ///
  /// El de la derecha ademas no es cosmetico: maximizado, o acoplado a la
  /// derecha, el panel llega hasta el borde de la ventana y sin margen la «x»
  /// de cada fila quedaba cortada por la mitad contra el marco.
  static const double processRowGutter = 14.0;

  /// Alto de una fila del panel de procesos. Entra la cifra con su contexto
  /// debajo (`4.0 GB` sobre `12% del total`, `3 h` sobre `21 min`): es lo que
  /// permite meter dos datos en el ancho de una columna.
  static const double processRowHeight = 40.0;

  /// Alto/ancho de la barrita que queda cuando las metricas estan
  /// colapsadas (la que contiene el chevron para volver a mostrarlas).
  static const double collapsedMetricsExtent = 28.0;

  /// Alto de una fila de la lista de discos (`DiskUsageList`). Es el minimo
  /// con el que la etiqueta de la unidad y la cifra siguen siendo legibles en
  /// `labelSmall`; el que manda cuantos discos se ven sin scrollear dentro de
  /// la tile ancha de almacenamiento.
  ///
  /// En la franja ancha, `DiskHeartbeat` vive anclada al borde derecho de
  /// esta misma fila (no en una fila propia), asi que este valor no crecio
  /// al sumarla -- ver [diskHeartbeatHeight].
  static const double diskRowExtent = 20.0;

  /// Ancho del termometro de la tile de CPU. Fijo y angosto a proposito: un
  /// termometro ancho se lee como una barra de progreso y deja de reconocerse.
  static const double thermometerWidth = 18.0;

  /// Ancho a partir del cual la tile de CPU dibuja las tres cosas juntas
  /// (cifras, chip y termometro). Por debajo, el chip se queda con toda la
  /// caja y la temperatura y la frecuencia vuelven a los badges.
  ///
  /// En el reparto lateral el grafico mide 36-48 dp: ahi las tres columnas
  /// dejaban al chip en ~10 dp y a las cifras escaladas hasta ser ilegibles,
  /// que es exactamente lo contrario de lo que el termometro venia a aportar.
  static const double cpuGaugesFullWidth = 140.0;

  /// Alto minimo para que una tile apile titulo, grafico y cifras en filas
  /// propias (`MetricSpec.stackedChart`). No alcanza con la densidad
  /// completa: la franja de un telefono da tiles de ~100 dp, que entran en
  /// `full` pero no en cuatro filas -- ahi la tile de GPU **desbordaba 7 dp**,
  /// con la banda amarilla y todo. Verificado en un S24 real.
  static const double minStackedTileHeight = 132.0;

  /// Alto de una fila de disco cuando el ancho obliga a apilar la etiqueta
  /// sobre la barra (el riel lateral). Son dos lineas, asi que mide mas que
  /// [diskRowExtent]. `DiskHeartbeat` vive en la PRIMERA linea, anclada al
  /// borde derecho mientras la etiqueta queda a la izquierda; el margen
  /// extra sobre el valor historico de dos lineas sin ella (34) es el mismo
  /// colchon que ya hizo falta una vez para esta fila -- verificar con
  /// captura real antes de bajarlo.
  static const double diskRowStackedExtent = 38.0;

  /// A partir de este ancho, la fila de un disco entra en una sola linea
  /// (identificador, barra y cifras). Por debajo se apila: en el riel hay
  /// ~190 dp y meter las tres cosas en una linea dejaba la barra en un hilo
  /// y la etiqueta sin lugar.
  static const double diskRowInlineWidth = 320.0;

  /// Alto de la barra de progreso de cada disco. Fina a proposito: en una
  /// fila de 20 dp una barra mas gruesa compite con el texto en vez de
  /// acompanarlo.
  static const double diskBarHeight = 6.0;

  /// Ancho reservado para el identificador del disco (`C:`) al principio de
  /// su fila. Fijo para que las barras de todos los discos arranquen
  /// alineadas: con un ancho automatico, `C:` y `/home` desalinean la lista
  /// entera.
  static const double diskMountPointWidth = 30.0;

  /// Ancho de la senal de vida de actividad de disco (`DiskHeartbeat`). Vive
  /// pegada al identificador del disco (`D: Secundario ‹señal›`), asi que
  /// tiene que ser angosta -- es un indicador de "hay actividad y en que
  /// direccion", no un grafico para leer valores exactos -- pero con lugar
  /// para que sus triangulos (estilo monitor de signos vitales) se
  /// distingan entre si.
  static const double diskHeartbeatWidth = 40.0;

  /// Alto de `DiskHeartbeat`. Mide lo mismo que una linea de texto
  /// `labelSmall`, porque vive EN esa linea (junto al identificador del
  /// disco), no en una propia.
  static const double diskHeartbeatHeight = 14.0;

  /// Ancho maximo de una tarjeta de accion cuando la grilla de movil ya no
  /// puede llenar la pantalla y pasa a scrollear: el ancho disponible se
  /// reparte en `ceil(ancho / esto)` columnas, o sea ~2 en un telefono
  /// vertical y 4-6 en horizontal o en tablet, sin breakpoints.
  static const double maxActionTileExtent = 172.0;

  /// Proporcion ancho/alto de una tarjeta de accion en ese modo scrolleable.
  static const double actionTileAspectRatio = 1.25;

  /// Por debajo de esto una tarjeta deja de ser comoda de tocar, y la
  /// grilla de movil prefiere scrollear antes que seguir achicandolas.
  static const double minActionTileWidth = 132.0;
  static const double minActionTileHeight = 96.0;

  /// Alto de la barra de chips de grupos, compartida por el filtro de
  /// escritorio y el de Android.
  static const double groupFilterBarHeight = 40.0;

  /// Alto de la barra de titulo propia del modo compacto (la ventana no
  /// tiene decoracion del SO en ese modo).
  static const double compactTitleBarHeight = 32.0;

  /// Radio del punto de color que identifica a un grupo en su chip.
  static const double groupDotRadius = 6.0;

  /// Ancho maximo del contenido de emparejamiento (hoja de la PC, dialogo del
  /// telefono, estados vacios). Mismo numero que usa `EmptyState` adentro,
  /// para que las dos puntas del ritual midan igual.
  static const double pairingContentMaxWidth = 320.0;
}
