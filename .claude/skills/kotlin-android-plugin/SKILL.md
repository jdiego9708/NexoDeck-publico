---
name: kotlin-android-plugin
description: Cómo agregar código Android nativo puntual (Kotlin) cuando Flutter no cubre algo, ej. el overlay tipo bubble o BLE del lado Android.
---

# kotlin-android-plugin

Primer caso real: `MulticastLock` para el descubrimiento mDNS de Fase 4
(`app/android/app/src/main/kotlin/com/nexodeck/nexodeck/MainActivity.kt`).
Úsalo como plantilla para el próximo caso (overlay `SYSTEM_ALERT_WINDOW` de
modo compacto en Android, o el plugin BLE de Fase 6).

## Patrón: `MethodChannel` puntual sobre `MainActivity`

No hace falta un plugin Flutter completo (`flutter create --template=plugin`)
para una pieza nativa chica y específica de esta app — alcanza con:

1. Override `configureFlutterEngine` en `MainActivity.kt` y registrar un
   `MethodChannel` con un nombre namespaced (`com.nexodeck.nexodeck/<algo>`).
2. `setMethodCallHandler { call, result -> when (call.method) { ... } }`
   despachando por nombre de método, `result.success(...)`/`result.error(...)`
   /`result.notImplemented()`.
3. Del lado Dart, un wrapper delgado en `data/` de la feature correspondiente
   (ver `app/lib/features/pairing/data/multicast_lock_service.dart`) que
   guarda las llamadas detrás de `if (!Platform.isAndroid) return;` — el
   resto de la app (incluido `flutter analyze`/tests en Windows/Linux) nunca
   toca el canal.
4. Si la pieza necesita liberar un recurso (locks, listeners), libéralo
   también en `onDestroy()` de `MainActivity`, no solo cuando Dart lo pide
   explícitamente — la app puede matarse sin que el widget Dart alcance a
   llamar `release()`.

## Permisos

Cualquier permiso nuevo que la pieza nativa necesite va en
`app/android/app/src/main/AndroidManifest.xml`, con un comentario explicando
qué feature lo necesita y por qué (ver el bloque de permisos de Fase 4 ahí
mismo). La mayoría de los permisos usados hasta ahora son "normales"
(otorgados en instalación, sin prompt) — si una fase futura necesita un
permiso peligroso (`runtime permission`, ej. `SYSTEM_ALERT_WINDOW` para el
overlay), eso sí requiere flujo de solicitud explícito del lado Kotlin
(`Settings.canDrawOverlays` + `Intent(ACTION_MANAGE_OVERLAY_PERMISSION)`),
no alcanza con declararlo en el manifest.

## Verificación

No hay automatización de UI de escritorio/Android en este entorno de
desarrollo (misma limitación documentada para otras fases) — `flutter build
apk` confirma que el Kotlin compila y que cargokit sigue cross-compilando
`nexodeck-ffi` correctamente, pero el comportamiento real (¿el lock evita
que se droppeen paquetes multicast?) solo se confirma con un dispositivo
físico corriendo la app e interactuando con el flujo completo.
