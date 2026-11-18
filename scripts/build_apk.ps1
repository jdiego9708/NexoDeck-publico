#Requires -Version 5.1
<#
.SYNOPSIS
    Construye el APK de NexoDeck para Android (flutter build apk).

.DESCRIPTION
    Compila el APK de release (o de debug con -Debug) y deja la ruta del
    archivo resultante en la salida de la terminal.

    Antes de compilar verifica lo que el build da por sentado y que falla con
    errores opacos si no esta:

      1. `flutter` en el PATH.
      2. Los targets de Rust para Android (cargokit compila el .so de
         nexodeck-ffi por ABI dentro del build de Flutter; sin el target
         correspondiente el build falla a mitad sin apuntar a la causa).
      3. app\pubspec.yaml, que es de donde sale la version.

    El APK queda en app\build\app\outputs\flutter-apk\. En release se firma
    con la clave de debug (ver el signingConfig en app\android\app\build.gradle.kts):
    sirve para instalar y probar, no para publicar en una tienda.

.PARAMETER DebugBuild
    Construye el APK de debug en vez del de release. Es el que usa
    scripts\run_android_debug.ps1 al correr en un dispositivo.

.PARAMETER SplitPerAbi
    Genera un APK por arquitectura en vez de uno unico que las contiene a
    todas (apk "fat"). Util para instalar solo el .so que el dispositivo
    necesita y bajar el tamano del archivo que se transfiere.

.PARAMETER NoPause
    No espera un Enter al terminar. Para correrlo desde una terminal propia
    o un pipeline; con doble clic, el script ya espera para que se vea la
    ruta del APK.

.EXAMPLE
    .\scripts\build_apk.ps1
    .\scripts\build_apk.ps1 -SplitPerAbi
    .\scripts\build_apk.ps1 -DebugBuild
#>
[CmdletBinding()]
param(
    [switch]$DebugBuild,
    [switch]$SplitPerAbi,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'

# Igual que en build_installer.ps1: si algo falla, el throw termina el script
# y --con doble clic-- la consola se cierra sin dejar leer el error. El trap
# imprime el motivo en rojo y espera un Enter.
trap {
    Write-Host ""
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host ""
    if (-not $NoPause) { Read-Host "Presiona Enter para salir" }
    exit 1
}

function Test-LaunchedFromExplorer {
    # True si el script lo lanzo un doble clic (proceso padre explorer.exe).
    if ($Host.Name -ne 'ConsoleHost') { return $false }
    try {
        $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId
        return (Get-Process -Id $parent -ErrorAction Stop).ProcessName -eq 'explorer'
    } catch {
        return $false
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir   = Join-Path $repoRoot 'app'
$apkDir   = Join-Path $appDir 'build\app\outputs\flutter-apk'

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# --- herramientas ------------------------------------------------------------
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "No encuentro `flutter` en el PATH. Instala Flutter y agregalo al PATH."
}

# --- version -----------------------------------------------------------------
$pubspec = Get-Content (Join-Path $appDir 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
    throw "No pude leer la version de app\pubspec.yaml"
}
$version = $Matches[1]
Write-Step "NexoDeck $version - APK de $(if ($DebugBuild) { 'debug' } else { 'release' })"

# --- targets de Rust para Android -------------------------------------------
# cargokit invoca cargo por ABI durante el build; sin el target instalado el
# error aparece en el .so que falta, no en el target que no se agrego.
$neededTargets = @('aarch64-linux-android', 'armv7-linux-androideabi', 'x86_64-linux-android')
if (Get-Command rustup -ErrorAction SilentlyContinue) {
    $installed = @(& rustup target list --installed)
    $missing = @($neededTargets | Where-Object { $installed -notcontains $_ })
    if ($missing.Count -gt 0) {
        throw ("Faltan targets de Rust para Android: {0}. Agregalos con:`n" -f ($missing -join ', ') +
               "    rustup target add {0}" -f ($missing -join ' '))
    }
} else {
    Write-Warning "No encuentro `rustup` en el PATH; no pude verificar los targets de Android."
}

# --- build -------------------------------------------------------------------
$buildArgs = @('build', 'apk')
if ($DebugBuild) { $buildArgs += '--debug' } else { $buildArgs += '--release' }
if ($SplitPerAbi) { $buildArgs += '--split-per-abi' }

Write-Step ("flutter {0}" -f ($buildArgs -join ' '))
Push-Location $appDir
try {
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk fallo (codigo $LASTEXITCODE)" }
} finally {
    Pop-Location
}

# --- resultado ---------------------------------------------------------------
# Con -SplitPerAbi hay un .apk por ABI; sin el, uno solo (fat). El glob final
# descarta los .sha1 que Flutter deja al lado.
$apks = @(Get-ChildItem -Path $apkDir -Filter '*.apk' -ErrorAction SilentlyContinue |
    Where-Object {
        if ($SplitPerAbi) {
            $_.Name -match '^app-(arm64-v8a|armeabi-v7a|x86_64)-(debug|release)\.apk$'
        } else {
            $_.Name -eq ('app-{0}.apk' -f $(if ($DebugBuild) { 'debug' } else { 'release' }))
        }
    })

if ($apks.Count -eq 0) {
    throw "flutter build apk termino bien pero no aparecio ningun .apk en $apkDir"
}

$totalMb = [math]::Round(($apks | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
Write-Step "Listo"
Write-Host ""
foreach ($apk in $apks) {
    Write-Host "    $($apk.FullName)" -ForegroundColor Green
    Write-Host "    $([math]::Round($apk.Length / 1MB, 1)) MB"
}
Write-Host ""
Write-Host "    Total: $totalMb MB ($($apks.Count) archivo$(if ($apks.Count -ne 1) { 's' }))"

# Con doble clic la consola se cerraria al instante y no se veria la ruta.
if (-not $NoPause -and (Test-LaunchedFromExplorer)) {
    Read-Host "Presiona Enter para salir"
}
