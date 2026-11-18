#Requires -Version 5.1
<#
.SYNOPSIS
    Corre NexoDeck en modo debug en un dispositivo Android fisico.

.DESCRIPTION
    Elige el dispositivo Android al que lanzar la app:
      - Si hay UNO conectado (y autorizado), lo usa directamente.
      - Si hay VARIOS, muestra una lista numerada y deja elegir con un numero.
      - Si no hay ninguno, falla explicando que revisar (cable, depuracion USB).

    Los emuladores se ignoran a proposito: esto es para hardware real, que es
    donde se verifica el transporte WiFi/AOA. Los dispositivos en `unauthorized`
    o `offline` se avisan aparte y no se intentan.

    Documentacion completa en docs\ejecutar-en-debug.md.

.EXAMPLE
    .\scripts\run_android_debug.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir   = Join-Path $repoRoot 'app'

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Resolve-Adb {
    if ($env:ANDROID_HOME) {
        $candidate = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "No encuentro adb. Defini ANDROID_HOME o agrega platform-tools al PATH."
}

function Get-AndroidDevices {
    param([string]$Adb)

    $result = @()
    $lines = & $Adb devices -l
    foreach ($line in $lines) {
        $line = $line.Trim()
        if ($line -eq '' -or $line -match '^List of devices') { continue }
        if ($line -notmatch '^(\S+)\s+(\S+)') { continue }
        $serial = $Matches[1]
        $state  = $Matches[2]
        if ($serial -like 'emulator-*') { continue }   # solo hardware real

        $model = 'desconocido'
        if ($line -match 'model:(\S+)') { $model = $Matches[1] }

        $result += [pscustomobject]@{
            Serial = $serial
            Model  = $model
            State  = $state
        }
    }
    return $result
}

function Select-Device {
    param([object[]]$Devices)

    Write-Host ""
    Write-Host "Dispositivos Android conectados:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Devices.Count; $i++) {
        Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $Devices[$i].Model, $Devices[$i].Serial)
    }
    Write-Host ""

    while ($true) {
        $choice = Read-Host ("Elegi un numero (1..{0})" -f $Devices.Count)
        if ($choice -match '^\d+$') {
            $n = [int]$choice
            if ($n -ge 1 -and $n -le $Devices.Count) { return $Devices[$n - 1] }
        }
        Write-Warning ("Opcion invalida: elegi un numero entre 1 y {0}." -f $Devices.Count)
    }
}

# --- herramientas ------------------------------------------------------------
$adb = Resolve-Adb

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "No encuentro `flutter` en el PATH."
}

# --- dispositivos ------------------------------------------------------------
Write-Step "Buscando dispositivos Android"
$all = @(Get-AndroidDevices -Adb $adb)

foreach ($d in @($all | Where-Object { $_.State -eq 'unauthorized' })) {
    Write-Warning ("El dispositivo {0} esta 'unauthorized': acepta el dialogo de depuracion USB en la pantalla." -f $d.Serial)
}
foreach ($d in @($all | Where-Object { $_.State -eq 'offline' })) {
    Write-Warning ("El dispositivo {0} esta 'offline': revisa el cable o reinicia adb." -f $d.Serial)
}

$ready = @($all | Where-Object { $_.State -eq 'device' })
if ($ready.Count -eq 0) {
    throw ("No hay ningun dispositivo Android fisico conectado y autorizado.`n" +
           "Revisa: 1) cable USB, 2) 'Depuracion USB' activada, 3) aceptar el dialogo en el telefono.")
}

if ($ready.Count -eq 1) {
    $target = $ready[0]
    Write-Host "    Un solo dispositivo: $($target.Model) ($($target.Serial))"
} else {
    $target = Select-Device -Devices $ready
}

Write-Step ("flutter run -d {0}" -f $target.Serial)
Push-Location $appDir
try {
    & flutter run -d $target.Serial
    if ($LASTEXITCODE -ne 0) { throw "flutter run fallo (codigo $LASTEXITCODE)" }
} finally {
    Pop-Location
}
