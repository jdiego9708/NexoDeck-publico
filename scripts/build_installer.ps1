#Requires -Version 5.1
<#
.SYNOPSIS
    Construye el instalador de Windows de NexoDeck (installer\nexodeck.iss).

.DESCRIPTION
    Hace las cinco cosas en orden, porque compilar el .iss suelto produce un
    instalador incompleto en silencio:

      1. Lee la version de app\pubspec.yaml (unica fuente de verdad).
      2. flutter build windows --release.
      3. Copia el runtime de MSVC dentro de Release\ (Flutter NO lo hace, y sin
         esas DLLs la app no arranca en una PC sin el VC++ Redistributable).
      4. Publica el sidecar de sensores en dist\sensors (dotnet publish). Es
         lo que le da a la app la temperatura del CPU en Windows, y el .iss lo
         empaqueta desde ahi.
      5. Invoca ISCC.exe, que se busca en el registro: en este proyecto Inno
         Setup no esta en Program Files, y hardcodear la ruta rompe en cuanto
         se cambia de equipo.

    El resultado queda en dist\nexodeck-setup-<version>-x64.exe.

.PARAMETER SkipFlutterBuild
    Reusa el Release\ que ya existe. Solo para iterar sobre el .iss sin esperar
    los ~4 minutos del build; nunca para producir un instalador de verdad.

.PARAMETER SkipSensorsBuild
    Reusa el dist\sensors que ya existe. Util cuando el sidecar esta corriendo
    (dotnet no puede sobrescribir un .exe en uso) y ya se publico despues del
    ultimo cambio.

.PARAMETER AllowMissingCrt
    Empaqueta aunque no se encuentre el runtime de MSVC. El instalador
    resultante solo funciona en PCs que ya tengan el VC++ Redistributable.

.EXAMPLE
    .\scripts\build_installer.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipFlutterBuild,
    [switch]$AllowMissingCrt,
    [switch]$SkipSensorsBuild,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'

# Si algo falla, el throw termina el script y --si se lanzo con doble clic-- la
# consola se cierra antes de que se pueda leer el error. El trap imprime el
# motivo en rojo y espera un Enter para que el fallo quede a la vista.
# Con -NoPause se salta la espera (para correrlo desde una terminal propia o
# un pipeline que no tiene a nadie mirando).
trap {
    Write-Host ""
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host ""
    if (-not $NoPause) { Read-Host "Presiona Enter para salir" }
    exit 1
}

function Test-LaunchedFromExplorer {
    # True si el script lo lanzo un doble clic (proceso padre explorer.exe), o
    # sea una consola que se cierra sola al terminar. Sirve para esperar un
    # Enter al final y dejar leer el "Listo" sin obligar a eso en una terminal.
    if ($Host.Name -ne 'ConsoleHost') { return $false }
    try {
        $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId
        return (Get-Process -Id $parent -ErrorAction Stop).ProcessName -eq 'explorer'
    } catch {
        return $false
    }
}

$repoRoot   = Split-Path -Parent $PSScriptRoot
$appDir     = Join-Path $repoRoot 'app'
$releaseDir = Join-Path $appDir  'build\windows\x64\runner\Release'
$issFile    = Join-Path $repoRoot 'installer\nexodeck.iss'
$distDir    = Join-Path $repoRoot 'dist'
$sensorsDir = Join-Path $distDir  'sensors'

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# --- 1. Version -------------------------------------------------------------
# pubspec dice "version: 1.0.0+1"; el build number no le sirve a Inno, que
# quiere x.y.z para VersionInfoVersion.
$pubspec = Get-Content (Join-Path $appDir 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
    throw "No pude leer la version de app\pubspec.yaml"
}
$version = $Matches[1]
Write-Step "NexoDeck $version"

# --- 2. Build de Flutter ----------------------------------------------------
if ($SkipFlutterBuild) {
    Write-Step "Salteando el build de Flutter (-SkipFlutterBuild)"
    if (-not (Test-Path (Join-Path $releaseDir 'nexodeck.exe'))) {
        throw "No hay un build previo en $releaseDir. Corre sin -SkipFlutterBuild."
    }
} else {
    # Si la app esta abierta, cargokit no puede reescribir nexodeck_ffi.dll y
    # MSBuild lo reporta como un MSB8066 con codigo -1 que no menciona el
    # archivo en uso por ningun lado. Vale mas fallar aca con el motivo real.
    $running = @(Get-Process -Name 'nexodeck' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        throw ("NexoDeck esta corriendo (PID {0}). Cerralo: cargokit no puede " -f ($running[0].Id) +
               "reescribir nexodeck_ffi.dll y el build falla con un MSB8066 opaco.")
    }

    Write-Step "flutter build windows --release"
    Push-Location $appDir
    try {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows --release fallo (codigo $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
}

# El exit code de Flutter no siempre alcanza: comprobamos las piezas que el
# instalador da por sentadas.
foreach ($required in @('nexodeck.exe', 'flutter_windows.dll', 'nexodeck_ffi.dll', 'data\app.so')) {
    $path = Join-Path $releaseDir $required
    if (-not (Test-Path $path)) { throw "Falta $required en $releaseDir - el build quedo incompleto" }
}

# --- 3. Runtime de MSVC, app-local ------------------------------------------
# Va al lado del .exe en vez de instalar el VC++ Redistributable: asi el
# instalador sigue sin necesitar elevacion. Windows resuelve primero la DLL
# del directorio de la app, tenga o no el sistema su propia copia.
Write-Step "Copiando el runtime de MSVC"
$crtSource = $null
$vsRoots = @(
    'C:\Program Files\Microsoft Visual Studio',
    'C:\Program Files (x86)\Microsoft Visual Studio'
) | Where-Object { Test-Path $_ }

foreach ($root in $vsRoots) {
    $candidate = Get-ChildItem -Path $root -Recurse -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*\x64\*' -and $_.FullName -notlike '*onecore*' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($candidate) { $crtSource = $candidate.FullName; break }
}

if (-not $crtSource) {
    $msg = "No encontre el redistributable de MSVC (Microsoft.VC*.CRT) en ninguna instalacion de Visual Studio."
    if ($AllowMissingCrt) {
        Write-Warning "$msg El instalador va a exigir el VC++ Redistributable en la PC destino."
    } else {
        throw "$msg Instala 'Desktop development with C++' o pasa -AllowMissingCrt."
    }
} else {
    Write-Host "    desde $crtSource"
    # Solo lo que el runner de Flutter y las DLLs de Rust enlazan de verdad;
    # vccorlib140.dll es de C++/CX y aca no la usa nadie.
    foreach ($pattern in @('msvcp140*.dll', 'vcruntime140*.dll', 'concrt140.dll')) {
        Get-ChildItem -Path (Join-Path $crtSource $pattern) -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName -Destination $releaseDir -Force
            Write-Host "    + $($_.Name)"
        }
    }
}

# --- 4. Sidecar de sensores -------------------------------------------------
# Sin esto el .iss falla al no encontrar dist\sensors, y peor: si alguien
# quitara esa referencia, el instalador saldria "bien" y la app quedaria sin
# temperatura de CPU sin ningun error visible.
Write-Step "Publicando el sidecar de sensores"
if ($SkipSensorsBuild) {
    Write-Host "    salteado (-SkipSensorsBuild)"
} else {
    # Mismo caso que nexodeck.exe mas arriba: si el sidecar esta corriendo,
    # dotnet no puede sobrescribir el .exe y el error no dice cual archivo es.
    # Corre como el servicio de Windows `NexoDeckSensors` (LocalSystem, arranque
    # automatico), asi que matar el proceso no alcanza: hay que detener el
    # servicio, y eso pide una consola de administrador.
    $runningSensors = @(Get-Process -Name 'NexoDeckSensors' -ErrorAction SilentlyContinue)
    if ($runningSensors.Count -gt 0) {
        throw ("El sidecar de sensores esta corriendo (PID {0}) y dotnet no puede " -f ($runningSensors[0].Id) +
               "sobrescribir su .exe. Deten el servicio desde una consola de administrador " +
               "(Stop-Service NexoDeckSensors) o usa -SkipSensorsBuild si ya esta publicado al dia.")
    }

    & dotnet publish (Join-Path $repoRoot 'sensors\NexoDeckSensors') -c Release -o $sensorsDir
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish del sidecar fallo (codigo $LASTEXITCODE)" }
}

$sensorsExe = Join-Path $sensorsDir 'NexoDeckSensors.exe'
if (-not (Test-Path $sensorsExe)) {
    throw "Falta NexoDeckSensors.exe en $sensorsDir - el instalador quedaria sin temperatura de CPU"
}

# --- 5. Inno Setup ----------------------------------------------------------
Write-Step "Compilando el instalador"
$iscc = $null
if ($env:ISCC_PATH -and (Test-Path $env:ISCC_PATH)) {
    $iscc = $env:ISCC_PATH
} else {
    # Inno no se instala siempre en Program Files (en el equipo principal de
    # este proyecto vive en E:\DevTools\InnoSetup6), asi que la ruta sale del
    # registro y no de una constante.
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $entry = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Inno Setup*' -and $_.InstallLocation } |
        Select-Object -First 1
    if ($entry) {
        $candidate = Join-Path $entry.InstallLocation 'ISCC.exe'
        if (Test-Path $candidate) { $iscc = $candidate }
    }
}
if (-not $iscc) {
    throw ("No encontre ISCC.exe. Instala Inno Setup 6 " +
           "(winget install JRSoftware.InnoSetup) o define `$env:ISCC_PATH.")
}
Write-Host "    $iscc"

if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }

& $iscc "/DAppVersion=$version" $issFile
if ($LASTEXITCODE -ne 0) { throw "ISCC fallo (codigo $LASTEXITCODE)" }

$output = Join-Path $distDir "nexodeck-setup-$version-x64.exe"
if (-not (Test-Path $output)) { throw "ISCC termino bien pero no aparecio $output" }

$sizeMb = [math]::Round((Get-Item $output).Length / 1MB, 1)
Write-Step "Listo"
Write-Host ""
Write-Host "    $($output)" -ForegroundColor Green
Write-Host "    $sizeMb MB"
Write-Host ""

# Si se lanzo con doble clic, la consola se cerraria al instante y no se
# veria ni la ruta del instalador. Se espera un Enter para que quede a la
# vista; en una terminal propia se puede pasar -NoPause para saltearlo.
if (-not $NoPause -and (Test-LaunchedFromExplorer)) {
    Read-Host "Presiona Enter para salir"
}
