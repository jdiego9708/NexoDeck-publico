# Guía: el centro de control y el stack multiagente

Esta guía explica, para quien usa la app (no para quien la programa), las
funciones nuevas de la pantalla principal de **escritorio**:

- el reparto **centro de control** (métricas, asistente y acciones);
- el **switch del stack**: Perfil A / B / C / Apagado, que arranca y para los
  modelos (y muestra los modelos elegidos de cada perfil);
- el alta de un **servicio de IA por internet**, incluida la pasarela del stack
  como «Otro (proxy propio)»;
- y los dos paneles que ahora se abren como **diálogo**: procesos y
  ejecuciones.

Solo aplica al escritorio. El móvil (`ConnectedDeviceScreen`) y el modo
compacto siguen como estaban.

---

## 1. La pantalla principal: centro de control

Es la disposición por defecto. Tiene tres zonas:

```
┌── métricas ──┬────── asistente (chat) ──────┬── acciones ──┐
│ riel con las │  bienvenida + conversación   │  grilla de   │
│ 5 métricas   │  input + botón de enviar     │  botones     │
│ (izquierda)  │  switch del stack debajo     │  (derecha)   │
└──────────────┴──────────────────────────────┴──────────────┘
```

- **Cada panel lateral se pliega** con el chevron de su borde. Plegado, el
  panel se queda en una barrita.
- **Los divisores se arrastran** con el mouse para repartir el ancho. Doble
  clic sobre un divisor devuelve ese reparto al valor automático.
- **El botón «Disposición» de la barra** rota entre las cinco disposiciones. El
  icono del botón es el de la disposición **actual**, no el de la siguiente.

| Disposición | Qué muestra |
|---|---|
| **Centro de control** (por defecto) | Métricas a la izquierda, asistente al centro, acciones a la derecha |
| Métricas arriba | Franja de métricas sobre el deck |
| Métricas a la izquierda | Riel lateral con el deck al lado |
| Métricas a la derecha | Lo mismo, del otro lado |
| Deck al máximo | Franja mínima de métricas abajo y todo el resto para el deck |

---

## 2. El asistente (chat del centro)

En el centro vive **el mismo asistente de siempre**, no una copia: la misma
conversación que abre el botón de la IA en la barra.

- **Si la IA está apagada**, el centro no muestra el chat sino una invitación
  («Asistente de IA» → **Activar el asistente**). La IA es opt-in: no se activa
  sola en una instalación nueva.
- **Estado vacío**: una bienvenida. Abajo, el campo
  «Escribí tu pregunta o pedido…».
- **Enter** envía; **Shift+Enter** hace un salto de línea.
- **Debajo del campo**, el switch **Preguntar / Automático** decide qué pasa
  con la próxima propuesta de ejecución: preguntar antes de correr (por
  defecto), o correrla sola. La **propuesta de ejecución** de un script aparece
  **abierta** en el hilo, con **Rechazar** y **Aprobar**; en Automático se
  ejecuta sin preguntar (salvo lo marcado como peligroso o que pida permisos
  de administrador, que siempre confirma).
- **Conversaciones guardadas, al lado del hilo.** En el centro de control, a la
  izquierda del chat hay un índice compacto con el **título** de cada
  conversación y **cuándo fue** («hace 5 min», «ayer»). Un clic la abre en el
  hilo; el menú **⋮** de cada fila permite **conservarla siempre**, archivarla o
  borrarla. La columna se pliega con el chevron de su cabecera (y en el diálogo
  del asistente ese índice no está: ahí sigue la hoja del icono de historial,
  con activas y archivadas).
- Abajo a la izquierda, el **selector de destino**: quién contesta (ver §3).
- Abajo a la derecha, **Empezar de nuevo** borra la conversación en pantalla.
- El icono de **historial** (en el encabezado «Asistente») abre las
  conversaciones guardadas; el de **«Cambiar de modelo»** abre la configuración
  (es por donde se da de alta un servicio por internet, ver §3).

---

## 3. Quién contesta: destinos y proveedores

Quien contesta se elige en el **selector de destino** (abajo a la izquierda del
chat). Las opciones que existan salen de **«Configura tus perfiles»** en la
configuración del asistente (el icono **«Cambiar de modelo»** del encabezado).

| Destino | Qué es |
|---|---|
| **Local** | Un modelo que corre entero en tu equipo (sin conexión, sin claves) |
| **Ollama** | Un modelo ya instalado en tu Ollama |
| **Claude Code** | Un corresponsal, no un modelo: tarda minutos |
| **Servicio por internet** | DeepSeek, OpenAI, o un proxy propio |

### Configura tus perfiles

La configuración del asistente tiene una sola sección, **«Configura tus
perfiles»**, que reemplaza a las antiguas «Quién puede contestar» y «Elegí el
modelo». Arriba muestra **qué motor hay configurado** (llama.cpp integrado,
Ollama y la pasarela vLLM del stack), y debajo los dos perfiles:

- **PERFIL A**, **PERFIL B** y **PERFIL C**, cada uno con un slot
  **Router** (modelo liviano) y otro **Pensamiento** (modelo pesado).
- En cada slot se elige un modelo del motor que quieras: un rol del stack vLLM,
  un modelo de llama.cpp, uno de Ollama, la sesión de **Claude Code**, o un
  **servicio por internet** (la clave se guarda por slot, así el router y el
  pensamiento pueden usar servicios distintos).
- Cada modelo dice **qué es** y si **ya está descargado** o **falta
  descargarlo**. Los modelos de llama.cpp se descargan **con la barra dentro de
  la sección**; Ollama y los del stack vLLM descargan por comandos y el progreso
  se ve en el panel de **Ejecuciones**.
- **La detección de descargados corre sola al entrar** a esta pantalla: consulta
  WSL2 para saber qué hay bajado y **no la levanta** si está apagada. WSL2 se
  levanta solo al pulsar **«Levantar»** en un perfil, y se libera al apagar el
  asistente. Los perfiles cuyos modelos del stack falten no se muestran.

Lo elegido se guarda en el stack (`profiles.json`); la próxima vez que se
levante el perfil, vLLM carga esos modelos. Si un slot es un servicio por
internet, la pasarela reenvía ese rol al servicio con su clave.

### Dar de alta un servicio por internet

1. En el chat, tocá el icono **«Cambiar de modelo»** (el del encabezado).
2. Bajá hasta **«O usa un servicio por internet»** y tocá
   **«Configurar un servicio…»**.
3. Elegí el proveedor en el segmentado:

   | Proveedor | Dirección y modelo que trae puestos |
   |---|---|
   | **DeepSeek** | `https://api.deepseek.com`, `deepseek-flash` |
   | **OpenAI** | `https://api.openai.com`, `gpt-4o-mini` |
   | **Otro (proxy propio)** | Vacío: los escribís vos |

4. Completá:
   - **Clave de API** (para los dos primeros, el botón «Copiar dónde
     sacarla» apunta a su página; un proxy propio no la tiene y ese botón no
     aparece);
   - **Modelo** (opcional: **«Ver los que hay»** pide la lista al servicio y
     ofrece las que conteste, pero también se puede escribir a mano);
   - **Dirección base** (si pegás la URL completa del endpoint, se recorta
     sola).
5. **«Usar este servicio»**. Antes de instalar nada, NexoDeck **comprueba la
   clave** contra el servicio; si contesta, guarda la configuración y deja ese
   proveedor como **destino por defecto**. Si la clave está mal, el error sale
   en este diálogo, no dentro de la conversación.

Dos cosas que conviene saber:

- **Los mensajes salen de tu máquina.** Lo que el asistente lea de tus
  proyectos para contestar viaja al servicio que elijas. El propio diálogo lo
  dice.
- **La clave se guarda en el directorio de datos de NexoDeck, en texto plano**
  (un fichero por proveedor). Es lo que dice el propio campo.

---

## 4. El modo del stack: Perfil A / Perfil B / Perfil C / Apagado

Debajo del campo del chat hay un botón **MODO…**; al tocarlo se elige el perfil
con el que contesta el asistente. Cada renglón muestra **los modelos elegidos en
ese perfil** (locales o de la nube), así que se actualiza al cambiar un slot.

| Opción | Qué usa | Cuándo conviene |
|---|---|---|
| **Perfil A** | Lo configurado (por defecto Router + **Gemma**) | Respuestas rápidas; Gemma gana en calidad general y código |
| **Perfil B** | Por defecto Router + **Qwen3-Coder** | Velocidad (≈2,2×) y contexto largo (16k) |
| **Perfil C** | Por defecto Router + **Qwen3.5 9B** (texto) | Preguntas y conocimiento general |
| **Apagado** | Para todo y **libera la GPU** y la RAM de WSL2 | Cuando no lo vas a usar |

Un perfil puede tener sus dos slots en un **servicio por internet** (p. ej.
DeepSeek): entonces no levanta nada en tu equipo y, si había modelos locales
cargados, **los para** para liberar la GPU. Los nombres viejos («Rápido»,
«Contexto largo», «Texto») eran los del perfil A/B/C; «Contexto largo» **no** es
«pensamiento profundo»: Gemma gana en calidad, B solo gana velocidad y contexto.

Cómo funciona:

- **Al tocar una opción** se guarda la elección y se lanza el script
  correspondiente por el mismo motor de comandos del deck, con la etiqueta
  **«Stack: Perfil A»** (o la que sea). El **progreso y la salida** salen por el
  panel de **Ejecuciones** y por su aviso en la barra.
- **Arrancar tarda 2–6 minutos.** Mientras carga, la pasarela contesta `503`
  («modelo apagado»), que es lo que verás en el chat si preguntás antes de
  tiempo. Para que eso no confunda, **mientras el perfil arranca el botón
  MODO… y el campo del chat quedan deshabilitados**: no se puede preguntar ni
  cambiar de perfil hasta que termine. La línea de estado lo dice
  («Arrancando «Perfil A»… puede tardar 2–6 minutos»).
- **Cambiar de perfil es un solo paso**: el script para los modelos viejos y
  arranca los nuevos. No hace falta apagar y volver a encender.
- **Apagado** ejecuta la parada **con liberación de WSL2**, así que devuelve la
  RAM y la GPU a Windows.

**La línea de estado** (debajo del switch) dice lo que hay cargado de verdad,
no lo que pediste. Sondea la pasarela cada pocos segundos y muestra uno de tres
mensajes:

- «Consultando el stack…» — todavía sin respuesta;
- «La pasarela no responde (stack apagado o arrancando).»;
- «Pasarela arriba, sin modelos cargados.»;
- «Cargados: Router · Gemma» (o «… · Complejo» con el perfil B).

### La carpeta del stack

El **engranaje** a la derecha del switch dice **dónde están los scripts**:

- Tiene que ser la carpeta con `Start-Stack.ps1`, `Stop-Stack.ps1` y
  `llm-gateway.exe`.
- El diálogo muestra, **antes de guardar**, el comando exacto que se lanzaría
  para el perfil elegido.
- En la máquina de desarrollo el valor por defecto es
  `D:\Repositorios\NexoDeck\llm-stack\scripts`; en otra
  instalación se apunta a donde tengas el stack.
- Si la carpeta no existe, al tocar el switch sale un aviso y **no se lanza
  nada**.

---

## 5. Enlazar el asistente con la pasarela (proxy propio)

Con el stack levantado, la pasarela escucha en `http://127.0.0.1:8888` y expone
los modelos en un dialecto compatible con OpenAI. Para que el chat la use, se
da de alta como **«Otro (proxy propio)»**:

1. Seguí los pasos de §3 y elegí **«Otro (proxy propio)»**.
2. **Clave de API**: la que crea la pasarela. Se pide una vez con
   `llm-gateway.exe keys add <nombre>` y se **enseña una sola vez** (la
   pasarela solo guarda su hash). Empieza por `ndk_`.
3. **Modelo**: `auto` (recomendado), o `router` / `fast` / `complex`.
4. **Dirección base**: `http://127.0.0.1:8888` (sin `/v1` ni
   `/chat/completions`: se recorta sola si la pegás entera).
5. Tocá **«Ver los que hay»** para confirmar que la clave sirve: deberían
   aparecer `fast`, `router` y `auto` (y `complex` con el perfil B).
6. **«Usar este servicio»**.

Qué modelos ofrecerá depende del perfil:

| Modelo | Qué es |
|---|---|
| `auto` | La pasarela decide según la petición; es lo recomendado |
| `router` | El modelo ligero (siempre está) |
| `fast` | Gemma (perfil A) |
| `complex` | Qwen3-Coder (perfil B) |

Con `auto`, la pasarela elige nivel (peticiones cortas o «meta» → el ligero;
el resto → el trabajador) y el código va siempre al trabajador. La respuesta
lleva dos cabeceras (`x-nexodeck-decision`, `x-nexodeck-model`) que dicen qué
eligió, y queda registrada en el log de decisiones de la pasarela.

**Un solo proveedor remoto a la vez.** Dar de alta otro reemplaza la
configuración anterior (la clave de cada proveedor sí se conserva por
separado).

---

## 6. Procesos y ejecuciones: ahora en diálogo

Los dos dejaron de acoplarse a un costado y se abren como **diálogo**, para no
competir por el ancho con los paneles del centro de control.

- **Procesos por métrica**: tocá una tile de **CPU, RAM, GPU o Disco** y se
  abre la lista de aplicaciones que más usan ese recurso, con su consumo, hace
  cuánto corren y un botón para cerrarlas. El diálogo se cierra con el botón,
  `Esc` o tocando afuera.
- **Ejecuciones**: el botón **«Ejecuciones»** de la barra abre el panel de lo
  que corre **ahora**, con su salida en vivo y el botón de detener. Ahí es
  donde se ve el progreso del switch del stack.

---

## 7. Resumen: por dónde empezar

1. **Activá la IA** si está apagada (el botón «Activar el asistente» del
   centro).
2. **Levantá el stack**: tocá **Perfil A** en el switch y esperá a que la línea
   diga «Cargados: Router · Gemma».
3. **Enlazá la pasarela**: «Cambiar de modelo» → **Configurar un servicio…** →
   **Otro (proxy propio)** → clave `ndk_…`, modelo `auto`,
   `http://127.0.0.1:8888` → **Usar este servicio**.
4. **Preguntá** en el chat.
5. Al terminar, tocá **Apagado** para devolver la GPU y la RAM a Windows.
