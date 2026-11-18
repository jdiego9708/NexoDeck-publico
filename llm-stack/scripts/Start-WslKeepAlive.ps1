<#
.SYNOPSIS
    Mantiene viva la distro de WSL2 mientras haya contenedores del stack en marcha.

.DESCRIPTION
    WSL2 apaga la distro pasados unos segundos sin ninguna sesion abierta (un proceso `wsl.exe`).
    Los contenedores Docker NO cuentan como sesion: al terminar el ultimo `wsl -e ...`, la distro
    se cierra y Docker manda SIGTERM a los servidores vLLM. En el registro aparece como
    "API server: shutdown triggered" seguido de una salida limpia (codigo 0), sin ningun error,
    y el sintoma es que el servidor "se cae solo" ~15 s despues de arrancar. Paso el 18-sep-2026.

    Este script deja un `wsl.exe -e sleep infinity` oculto que actua de sesion. Es idempotente:
    si ya hay uno, no lanza otro. Para detenerlo: -Stop.

    Es una solucion de laboratorio. Para dejar el stack permanente hace falta algo que arranque
    con Windows (tarea programada al iniciar sesion), pendiente de decidir.

.EXAMPLE
    .\Start-WslKeepAlive.ps1

.EXAMPLE
    .\Start-WslKeepAlive.ps1 -Stop
#>
[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu',
    [switch]$Stop
)

$ErrorActionPreference = 'Stop'

function Get-KeepAliveProcess {
    Get-CimInstance Win32_Process -Filter "Name = 'wsl.exe'" |
        Where-Object { $_.CommandLine -match 'sleep infinity' }
}

$existing = @(Get-KeepAliveProcess)

if ($Stop) {
    foreach ($process in $existing) { Stop-Process -Id $process.ProcessId -Force }
    Write-Host "Detenidos $($existing.Count) proceso(s) de keep-alive."
    return
}

if ($existing.Count -gt 0) {
    Write-Host "Ya hay un keep-alive en marcha (PID $($existing[0].ProcessId))."
    return
}

$started = Start-Process -FilePath 'wsl.exe' -ArgumentList @('-d', $Distro, '-e', 'sleep', 'infinity') `
    -WindowStyle Hidden -PassThru
Write-Host "Keep-alive lanzado (PID $($started.Id)) para la distro '$Distro'."
