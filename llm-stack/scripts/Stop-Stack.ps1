<#
.SYNOPSIS
    Para el stack y libera la GPU (y opcionalmente la RAM de WSL2).

.DESCRIPTION
    Es la forma de "hacer sitio" para ODM, entrenamientos o juegos: los modelos ocupan ~15 GiB de
    VRAM y no se pueden dormir en este equipo (Sleep Mode nivel 1 deja la RAM de WSL2 al limite y
    el nivel 2 corrompe el modelo; ver doc 11 apartado 7.17). Volver a subir cuesta el arranque
    completo (2-6 minutos con las caches calientes).

      - Para y elimina los contenedores vLLM.
      - Para la pasarela (salvo -KeepGateway: asi los clientes reciben 503 en vez de "conexion
        rechazada" mientras el stack esta parado).
      - Con -ReleaseWsl tambien cierra la sesion de WSL2 y termina la distro, devolviendo a Windows
        los ~8-16 GB de RAM que use.

    ASCII a proposito: Windows PowerShell 5.1 lee mal los .ps1 UTF-8 sin BOM.

.EXAMPLE
    .\Stop-Stack.ps1 -ReleaseWsl
#>
[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu',
    [switch]$KeepGateway,
    [switch]$ReleaseWsl
)

$ErrorActionPreference = 'Stop'

# Contenedores. Si la distro esta parada no hay nada que parar.
$stopScript = (& wsl.exe -d $Distro -e wslpath -a (Join-Path $PSScriptRoot 'stop-models.sh')).Trim()
& wsl.exe -d $Distro -e bash $stopScript

if (-not $KeepGateway) {
    # El supervisor va PRIMERO: si la pasarela se para con el todavia vivo, la relanza y Stop-Stack
    # quedaria mintiendo. Se detecta por linea de comandos, igual que el keep-alive de WSL2.
    $supervisors = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -match 'Start-Gateway\.ps1' })
    foreach ($process in $supervisors) { Stop-Process -Id $process.ProcessId -Force }
    Write-Host "Supervisor de la pasarela: $($supervisors.Count) proceso(s) detenido(s)."

    $gateways = @(Get-Process -Name 'llm-gateway' -ErrorAction SilentlyContinue)
    foreach ($process in $gateways) { Stop-Process -Id $process.Id -Force }
    Write-Host "Pasarela: $($gateways.Count) proceso(s) detenido(s)."
}

if ($ReleaseWsl) {
    & (Join-Path $PSScriptRoot 'Start-WslKeepAlive.ps1') -Stop
    & wsl.exe --terminate $Distro
    # `--terminate` deja viva la maquina virtual (proceso vmmemWSL, ~700 MB). `--shutdown` la apaga,
    # pero mata TODAS las distros: solo se usa si no queda ninguna otra en marcha.
    $others = ((& wsl.exe --list --running --quiet 2>$null | Out-String) -replace "`0", '').Trim()
    if ($others -eq '') {
        & wsl.exe --shutdown
        Write-Host "WSL2 ($Distro) terminada y maquina virtual apagada: RAM devuelta a Windows."
    }
    else {
        Write-Host "WSL2 ($Distro) terminada; la VM sigue viva porque hay otras distros en marcha."
    }
}

Start-Sleep -Seconds 3

# --- Verificacion de la limpieza -------------------------------------------------------------
# Regla del proyecto: al terminar de usar un perfil se LIMPIAN TODOS LOS PROCESOS y se deja el
# hardware libre. Parar no basta: hay que comprobar que quedo limpio y decirlo, o listar lo que
# sigue vivo. Sale con codigo 1 si queda algo.
Write-Host '[limpieza]'
$leftovers = @()

$gateways = @(Get-Process -Name 'llm-gateway' -ErrorAction SilentlyContinue)
if ($gateways.Count -gt 0 -and -not $KeepGateway) { $leftovers += "pasarela: $($gateways.Count) proceso(s) siguen vivos" }

$supervisors = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -match 'Start-Gateway\.ps1' })
if ($supervisors.Count -gt 0 -and -not $KeepGateway) { $leftovers += "supervisor de la pasarela: $($supervisors.Count) proceso(s) siguen vivos" }

if ($ReleaseWsl) {
    $keepAlives = @(Get-CimInstance Win32_Process -Filter "Name = 'wsl.exe'" |
        Where-Object { $_.CommandLine -match 'sleep infinity' })
    if ($keepAlives.Count -gt 0) { $leftovers += "keep-alive de WSL2: $($keepAlives.Count) proceso(s)" }

    # `wsl --list --running` escribe en UTF-16: se quitan los NUL antes de buscar el nombre.
    $running = ((& wsl.exe --list --running 2>$null | Out-String) -replace "`0", '')
    if ($running -match [regex]::Escape($Distro)) { $leftovers += "WSL2: la distro '$Distro' sigue en marcha (y con ella su RAM)" }

    # La VM de WSL2 tarda unos segundos en desaparecer tras el shutdown: se espera hasta 15 s.
    $vm = @(Get-Process -Name 'vmmemWSL' -ErrorAction SilentlyContinue)
    for ($i = 0; $vm.Count -gt 0 -and $i -lt 5; $i++) {
        Start-Sleep -Seconds 3
        $vm = @(Get-Process -Name 'vmmemWSL' -ErrorAction SilentlyContinue)
    }
    if ($vm.Count -gt 0) { $leftovers += "WSL2: vmmemWSL sigue vivo ($([int]($vm[0].WorkingSet64 / 1MB)) MB)" }
}
else {
    Write-Host '  (sin -ReleaseWsl: la distro de WSL2 y su RAM se dejan como estaban)'
}

$gpu = ((& nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits) -join '').Split(',')
$gpuUsed = [int]$gpu[0].Trim()
Write-Host "  GPU: $gpuUsed de $($gpu[1].Trim()) MiB usados"
# Windows solo ocupa ~0.8-1.5 GiB con el escritorio. Bajo WDDM nvidia-smi no atribuye la memoria a
# procesos, asi que si hay mas es una advertencia, no una prueba de que sea del stack.
if ($gpuUsed -gt 2000) { $leftovers += "GPU: $gpuUsed MiB usados (el escritorio suele ocupar ~1000); puede ser otra aplicacion de Windows" }

$freeGb = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
Write-Host "  RAM libre de Windows: $freeGb GB"

if ($leftovers.Count -eq 0) {
    Write-Host 'LIMPIO: no queda ningun proceso del stack y el hardware esta libre.'
    exit 0
}
Write-Host 'NO ESTA LIMPIO:'
foreach ($item in $leftovers) { Write-Host "  - $item" }
exit 1
