<#
.SYNOPSIS
    Levanta el stack completo: sesion de WSL2, pasarela y los modelos de un perfil.

.DESCRIPTION
    Es lo que ejecuta la tarea programada al iniciar sesion (Install-StackTask.ps1), y tambien se
    puede lanzar a mano. Pasos, en este orden:

      1. Sesion de WSL2 abierta (Start-WslKeepAlive.ps1). Sin ella WSL2 apaga la distro a los
         ~15 s y los servidores vLLM mueren solos.
      2. Espera a que Docker responda dentro de la distro.
      3. Pasarela autenticada (llm-gateway.exe), supervisada por Start-Gateway.ps1: si el proceso se
         cae, vuelve sola. Va ANTES que los modelos: es barata y, mientras cargan (2-4 minutos), los
         clientes reciben un 503 claro en vez de un "conexion rechazada".
      4. Los modelos del perfil (serve-profile.sh) y comprobacion final: la pasarela tiene que
         reportar `up` cada rol del perfil, no solo responder /health.

    Perfiles: A (Router + Gemma), B (Router + Complejo), C (Router + Writer, texto: preguntas y
    conocimiento general), complex-solo, none (solo pasarela).
    El GPU queda ocupado por los modelos: para liberarlo (ODM, entrenamientos, juegos) usa
    Stop-Stack.ps1.

    ASCII a proposito: Windows PowerShell 5.1 lee mal los .ps1 UTF-8 sin BOM.

.EXAMPLE
    .\Start-Stack.ps1 -Profile B

.EXAMPLE
    .\Start-Stack.ps1 -Profile none      # solo la pasarela; los modelos se arrancan luego a mano
#>
[CmdletBinding()]
param(
    [ValidateSet('A', 'B', 'C', 'complex-solo', 'none')]
    [string]$Profile = 'A',
    [string]$Distro = 'Ubuntu',
    [int]$GatewayPort = 8888,
    [string]$Executable = ''
)

$ErrorActionPreference = 'Stop'

# OJO: $PSScriptRoot llega VACIO en el valor por defecto de un parametro cuando el script se lanza
# con `powershell.exe -File` (que es como lo lanza la tarea programada), aunque funcione al
# invocarlo con `&`. Por eso el valor por defecto se calcula aqui, en el cuerpo.
if (-not $Executable) { $Executable = Join-Path $PSScriptRoot '..\gateway\target\release\llm-gateway.exe' }

$logDirectory = Join-Path $env:LOCALAPPDATA 'nexodeck\LlmGateway\logs'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd'
$stackLog = Join-Path $logDirectory "stack-$stamp.log"

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -LiteralPath $stackLog -Value $line
}

function Test-GatewayUp {
    try {
        return (Invoke-WebRequest -Uri "http://127.0.0.1:$GatewayPort/health" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200
    }
    catch { return $false }
}

function Wait-GatewayUp {
    param([int]$TimeoutSeconds = 10)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-GatewayUp) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return (Test-GatewayUp)
}

# El supervisor de la pasarela se detecta por linea de comandos, igual que el keep-alive de WSL2:
# su nombre de proceso es powershell.exe y no lo delata por si solo.
function Get-GatewaySupervisor {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'Start-Gateway\.ps1' }
}

Write-Log "== Arrancando el stack: perfil $Profile =="

# 1. Sesion de WSL2.
& (Join-Path $PSScriptRoot 'Start-WslKeepAlive.ps1') -Distro $Distro | ForEach-Object { Write-Log $_ }

# 2. Docker dentro de la distro (systemd lo levanta al arrancar WSL, puede tardar unos segundos).
$dockerReady = $false
for ($attempt = 0; $attempt -lt 45 -and -not $dockerReady; $attempt++) {
    & wsl.exe -d $Distro -e docker info *> $null
    $dockerReady = ($LASTEXITCODE -eq 0)
    if (-not $dockerReady) { Start-Sleep -Seconds 2 }
}
if (-not $dockerReady) { throw 'Docker no responde dentro de WSL2 tras 90 s.' }
Write-Log 'Docker listo en WSL2.'

# 3. Pasarela (supervisada por Start-Gateway.ps1: si el proceso se cae, vuelve sola).
$gatewayLog = Join-Path $logDirectory "gateway-$stamp.log"
if (Test-GatewayUp) {
    Write-Log "La pasarela ya esta en marcha en el puerto $GatewayPort."
}
elseif (@(Get-GatewaySupervisor).Count -gt 0) {
    Write-Log 'Ya hay un supervisor de la pasarela en marcha; espero a que responda.'
    if (-not (Wait-GatewayUp -TimeoutSeconds 30)) { throw "La pasarela no respondio en el puerto $GatewayPort. Mira $gatewayLog" }
}
else {
    if (-not (Test-Path -LiteralPath $Executable)) {
        throw "No existe $Executable. Compilalo con: cargo build --release (en llm-stack\gateway)."
    }
    $gatewayHost = Join-Path $PSScriptRoot 'Start-Gateway.ps1'
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', $gatewayHost, '-Executable', "`"$Executable`"", '-Port', $GatewayPort
    ) -WindowStyle Hidden | Out-Null
    if (-not (Wait-GatewayUp)) { throw "La pasarela no respondio en el puerto $GatewayPort. Mira $gatewayLog" }
    Write-Log "Pasarela supervisada arrancada en http://127.0.0.1:$GatewayPort (registro: $gatewayLog)."
}

# 4. Modelos.
if ($Profile -ne 'none') {
    $serveScript = (& wsl.exe -d $Distro -e wslpath -a (Join-Path $PSScriptRoot 'serve-profile.sh')).Trim()
    Write-Log "Arrancando los modelos del perfil $Profile (2-6 minutos)..."
    # Con `$ErrorActionPreference='Stop'` y `2>&1`, PowerShell 5.1 convierte CUALQUIER linea de
    # stderr de `wsl` en un error terminante: un aviso del stack (o el "Falta descargar..." de
    # serve-model.sh) abortaba aqui y el perfil parecia fallar. El veredicto real es el codigo de
    # salida, asi que se baja la preferencia mientras corre el comando y se restaura despues.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & wsl.exe -d $Distro -e bash $serveScript $Profile 2>&1 | ForEach-Object { Add-Content -LiteralPath $stackLog -Value "  $_" }
    $serveExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($serveExit -ne 0) { throw "serve-profile.sh $Profile fallo (codigo $serveExit). Mira $stackLog" }
}

# 5. Comprobacion final: cada rol que el perfil debia servir tiene que estar `up` en la pasarela,
# no solo "la pasarela responde". Los roles se leen de profiles.json (misma fuente que usa
# serve-profile.sh) para no reimplementar el mapeo perfil->roles aqui. El sondeo de la pasarela corre
# cada 2 s, asi que se deja un margen antes de dar por fallido un rol.
$expectedRoles = @()
if ($Profile -eq 'complex-solo') {
    $expectedRoles = @('complex')
}
elseif ($Profile -ne 'none') {
    $roleScript = (& wsl.exe -d $Distro -e wslpath -a (Join-Path $PSScriptRoot 'profile-roles.py')).Trim()
    foreach ($slot in @('router', 'thinking')) {
        $role = (& wsl.exe -d $Distro -e python3 $roleScript $Profile.ToUpper() $slot).Trim()
        if ($role) { $expectedRoles += $role }
    }
}

$allUp = $false
for ($attempt = 0; $attempt -lt 8 -and -not $allUp; $attempt++) {
    $availability = Invoke-RestMethod -Uri "http://127.0.0.1:$GatewayPort/health" -TimeoutSec 5
    $allUp = $true
    foreach ($role in $expectedRoles) {
        if ($availability.backends.$role -ne 'up') { $allUp = $false }
    }
    if (-not $allUp) { Start-Sleep -Seconds 2 }
}

$health = (Invoke-WebRequest -Uri "http://127.0.0.1:$GatewayPort/health" -UseBasicParsing -TimeoutSec 5).Content
Write-Log "Listo. Estado: $health"

if ($expectedRoles.Count -gt 0 -and -not $allUp) {
    throw "Algun rol del perfil $Profile no quedo arriba (esperados: $($expectedRoles -join ', ')). Mira $stackLog"
}
