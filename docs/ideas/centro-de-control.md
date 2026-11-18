# Idea: pantalla principal como centro de control (chat al centro)

**Estado: F1–F5 hechas (2026-09-23), salvo el overlay no modal del panel de
ejecuciones (ver F5).** El usuario quiere que el
chat con el asistente de IA deje de ser un diálogo y pase a ser **lo principal**
de la pantalla de escritorio, con las métricas a un lado y los comandos
(acciones) al otro, en paneles acoplados que se pueden ocultar y redimensionar.

Solo **escritorio**. El móvil (`ConnectedDeviceScreen`) y el modo compacto
siguen como están.

## Objetivo

```
┌─── métricas ────┬─────────── chat de IA ───────────┬─── acciones ───┐
│ (panel actual,  │  bienvenida + red neuronal      │ grid compacto  │
│  ocultable y    │  input + botón                   │ icono+texto    │
│  movible)       │  switch Rápido / Contexto largo  │ 1–2 columnas   │
└─────────────────┴──────────────────────────────────┴────────────────┘
```

Cada panel lateral se puede **ocultar/mostrar** y su ancho se reparte con los
divisores arrastrables que ya existen (`ResizeHandle` + `PanelSlot`).

## Reutilización: el chat NO se reescribe

El chat **ya existe** y se reutiliza tal cual:

- `_AiAssistantView` / `AiChatView` (`app/lib/features/ai_assistant/presentation/`)
  ya son un `Column` puro; solo están envueltos por un `Dialog` de 900×620.
- El hilo y el streaming viven en providers (`chatConversationProvider`,
  `chatBackendProvider`, suscripción directa al `Stream`), así que **moverlo de
  sitio no pierde conversación ni tokens**.
- Lo que hay que hacer es **extraer el cuerpo a un panel reutilizable** que usen
  a la vez el diálogo de siempre y el centro de la pantalla. Una sola
  implementación; el diálogo queda como atajo para el móvil/uso rápido.

## Decisiones

| Tema | Decisión |
|:---|:---|
| Alcance | Solo escritorio |
| Chat | **Reutilizar** el actual (extraer su cuerpo a un panel compartido) |
| Métricas | Mismo `MetricsPanel`; «ocultar» = plegar (chevron); «cambiar de posición» = el ciclo de layouts actual |
| Panel de acciones | Grid **compacto** (icono + etiqueta), **1–2 columnas** según ancho medido |
| Procesos / ejecuciones | Pasan a **hoja/diálogo** (no compiten por el ancho con los dos paneles) |
| Switch de perfil | **Rápido (A) / Contexto largo (B) / Apagado**, que **arranca o cambia el perfil** |
| Arranque | Reusar el **runner de comandos capturados** (`start_captured_command`) + panel de ejecuciones |
| Ruta del stack | **Configurable** en Ajustes (por defecto `llm-stack\scripts`) |
| Progreso | **Panel de ejecuciones + aviso**; mientras carga, la pasarela da 503 y se dice |
| Modelo del chat | Se apunta a la pasarela con `auto` (elige el trabajador del perfil levantado), así el switch no toca el modelo |

**Nombres del switch.** A = «Rápido» (Router + Gemma), B = «Contexto largo»
(Router + Qwen3-Coder). Se evita «pensamiento profundo» porque **no es cierto**:
Gemma (A) gana al Complejo en código y en MMLU; B solo gana velocidad (2,2×) y
contexto (16k). Ver `docs/llm-stack/11-mejoras-y-decisiones.md` §7.28.

## Fases

- **F1 — Shell de 3 zonas.** Nuevo `HomeLayout` por defecto: métricas a la
  izquierda (reusa `MetricsPanel` + plegado), **chat reutilizado al centro**, y
  **panel de acciones compacto** a la derecha, con dos divisores y persistencia.
  Los procesos/ejecuciones, de momento, siguen acoplándose dentro del centro
  (sobre el chat) para no romper nada.
- **F2 — Estado vacío del chat.** Mensaje centrado de bienvenida («iniciá una
  conversación y preguntá lo que necesites») + fondo de **red neuronal**
  reusando el painter de `NeuralBackground`, con animaciones sutiles; input y
  botón debajo. Sin crear un chat nuevo: es el mismo panel, con otro estado
  inicial.
- **F3 — Switch de perfil.** Ajuste de la carpeta del stack; el switch lanza
  `Stop-Stack` + `Start-Stack -Profile A|B` (o solo Stop para Apagado) por el
  runner capturado, con el progreso en el panel de ejecuciones; estado por
  `/health`; si no hay ruta configurada, degrada a solo-aviso.
- **F4 — Procesos/ejecuciones como hoja.** Reusar las hojas del móvil y retirar
  el acoplado lateral del centro.
- **F5 — Pulido, tests y docs. (hecha)** Limpieza del acoplado que quedaba: se
  retiraron los slots `PanelSlot.processPanel`/`runPanel`, los overrides y
  providers de dock, y las referencias muertas. `flutter analyze` limpio (9
  `info` preexistentes), 58 tests de Dart en verde y build de Windows OK. Docs
  actualizadas (`CLAUDE.md`, `ESTADO-DEL-PROYECTO.md` y este documento).
  **Pendiente:** el panel de ejecuciones es **modal**, y su motivo original era
  vigilar un comando de horas sin que tape el deck; debería pasar a un overlay
  flotante **no modal**.

## Riesgos

- **`_metricsKey` es `GlobalKey` única** (`home_layout_view.dart`): tiene que
  haber **una sola** `MetricsRow` viva; no montarla en dos zonas a la vez.
- **Un solo `remote_provider_config`**: con `auto` basta; no abrir un segundo
  slot remoto para A/B.
- **Arrancar el perfil usa WSL2 + Docker + PowerShell y tarda 2–4 min**; en una
  instalación sin el stack, el switch debe avisar y no romper.
- **Cambio grande**: se mete **detrás de un layout nuevo**; los cuatro layouts
  actuales siguen funcionando y se conservan.
- **Procesos/ejecuciones como hoja ya existe en el móvil**: reusar, no
  reinventar.
- **Tokens congelados** (`AppSpacing.sm/md/lg`, `AppRadius.card/chip`, varias
  `AppSizes`): no cambiarlos; cualquier recalibración se verifica con captura.

## Verificación

`melos run app:analyze` + `flutter test`. Capturas de la ventana (Win32). E2E
del switch: lanzar A (panel de ejecuciones + `/health` en `up` → el chat con
`auto` responde), cambiar a B, **Apagado**, y `Stop-Stack -ReleaseWsl` al
terminar.
