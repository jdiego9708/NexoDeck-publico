# Ejecutar en modo debug

Dos scripts para lanzar la app en desarrollo, uno por plataforma. Viven en
`scripts/` y se corren desde la raíz del repo (o desde cualquier lado: resuelven
`app/` solos por la posición del script, igual que `build_installer.ps1`).

| Script | Plataforma | Qué hace |
|---|---|---|
| `scripts/run_windows_debug.ps1` | Windows (escritorio) | `flutter run -d windows` con comprobaciones previas |
| `scripts/run_android_debug.ps1` | Android físico | Elige el dispositivo y `flutter run -d <id>` |

## Requisitos

Los mismos del primer arranque (ver `CLAUDE.md` → "Setup en una máquina nueva"):

- Flutter 3.41.9 + Dart en el `PATH`.
- Rust stable MSVC — cargokit lo invoca durante el build, sin esto no compila.
- Android: SDK + `platform-tools` (`adb`) y **Depuración USB** activada en el teléfono.

## Windows

```powershell
.\scripts\run_windows_debug.ps1
```

Compila en debug y abre la app con la consola atada para hot reload (`r`) y salir
(`q`). Si ya hay una instancia de NexoDeck corriendo, **aborta con el motivo**:
dos instancias pelean por el puerto 58643 y el fallo es mudo, sin ningún error
visible.

## Android físico

```powershell
.\scripts\run_android_debug.ps1
```

La elección de dispositivo sigue tres caminos:

- **Un** dispositivo conectado y autorizado → se usa directamente.
- **Varios** → lista numerada en la consola; se elige escribiendo el número.
- **Ninguno** → falla explicando qué revisar (cable, depuración USB, diálogo).

Los emuladores se ignoran a propósito. Los dispositivos en `unauthorized` o
`offline` se avisan aparte y no se intentan, con el motivo en cada caso.

### Antes de correr

1. Conectá el teléfono por USB.
2. Activá **Depuración USB** (Opciones de desarrollador).
3. Aceptá el diálogo "¿Permitir depuración USB?" si aparece.

La primera compilación para Android tarda (cargokit compila el `.so` de Rust por
ABI); las siguientes reusan lo ya compilado.

## Notas comunes

- Ambos dejan `flutter run` en primer plano: la consola queda atada hasta `q`.
- La app de escritorio levanta el host en el puerto **58643**; una segunda
  instancia no puede. El script de Windows lo comprueba antes de arrancar.
- Para compilar sin ejecutar: `flutter build windows --debug` o
  `flutter build apk --debug` desde `app/`.
