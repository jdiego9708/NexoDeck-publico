#Requires -Version 5.1
<#
.SYNOPSIS
    Corre NexoDeck en modo debug en Windows (flutter run -d windows).

.DESCRIPTION
    Lanza la app de escritorio en modo depuracion con hot reload. Es el comando
    de desarrollo del dia a dia: compila en debug (con el bridge de Rust via
    cargokit) y deja la consola atada a la app para `r` (hot reload) y `q`
    (salir).

    Antes de arrancar comprueba lo que el build da por sentado: que `flutter`
    este en el PATH y que no haya otra instancia de NexoDeck corriendo (la
    segunda falla al levantar el host, puerto 58643, con un sintoma mudo).

    Documentacion completa en docs\ejecutar-en-debug.md.

.EXAMPLE
    .\scripts\run_windows_debug.ps1
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

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "No encuentro `flutter` en el PATH. Instala Flutter y agregalo al PATH."
}

if (-not (Test-Path (Join-Path $appDir 'pubspec.yaml'))) {
    throw "No encuentro app\pubspec.yaml en $appDir. Correlo desde el repo o revisa la ubicacion del script."
}

# Dos instancias no pueden compartir el host (puerto 58643): la segunda se
# queda sin levantar el host y el fallo es mudo, sin ningun error visible.
$running = @(Get-Process -Name 'nexodeck' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    throw ("Ya hay una instancia de NexoDeck corriendo (PID {0}). Cerrala antes " -f ($running[0].Id) +
           "de lanzar otra: las dos pelean por el puerto 58643.")
}

Write-Step "flutter run -d windows"
Push-Location $appDir
try {
    & flutter run -d windows
    if ($LASTEXITCODE -ne 0) { throw "flutter run -d windows fallo (codigo $LASTEXITCODE)" }
} finally {
    Pop-Location
}
