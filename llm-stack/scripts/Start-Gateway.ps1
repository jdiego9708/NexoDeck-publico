<#
.SYNOPSIS
    Arranca la pasarela llm-gateway y la relanza si el proceso se cae.

.DESCRIPTION
    Start-Stack.ps1 lanzaba llm-gateway.exe con Start-Process y se olvidaba: si el proceso moria
    (crash, cierre inesperado), la pasarela no volvia y la app mostraba "la pasarela no responde"
    hasta el siguiente arranque manual. Este envoltorio la supervisa.

    - Se lanza DESACOPLADO desde Start-Stack.ps1 (que espera por /health); este script se queda en
      primer plano del proceso que lo hospeda y no vuelve hasta agotar el presupuesto de reinicios.
    - Presupuesto acotado (MaxRestarts, 5 por defecto): la pasarela es barata, pero una configuracion
      rota que la hace salir al instante dejaria un bucle girando y llenando el registro.
    - Idempotente: si ya responde /health, no arranca nada.
    - Stop-Stack.ps1 lo detiene ANTES de matar la pasarela: si el supervisor sigue vivo, la relanza.

    ASCII a proposito: Windows PowerShell 5.1 lee mal los .ps1 UTF-8 sin BOM.

.EXAMPLE
    .\Start-Gateway.ps1
#>
[CmdletBinding()]
param(
    [string]$Executable = '',
    [int]$Port = 8888,
    [int]$MaxRestarts = 5
)

$ErrorActionPreference = 'Stop'

# OJO: $PSScriptRoot llega VACIO en el valor por defecto de un parametro cuando el script se lanza
# con `powershell.exe -File` (que es como lo lanza Start-Stack.ps1). Por eso se calcula en el cuerpo.
if (-not $Executable) { $Executable = Join-Path $PSScriptRoot '..\gateway\target\release\llm-gateway.exe' }

$logDirectory = Join-Path $env:LOCALAPPDATA 'nexodeck\LlmGateway\logs'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd'
$gatewayLog = Join-Path $logDirectory "gateway-$stamp.log"
$gatewayOut = Join-Path $logDirectory "gateway-$stamp.out"
$supervisorLog = Join-Path $logDirectory "gateway-supervisor-$stamp.log"

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $supervisorLog -Value $line
}

function Test-GatewayUp {
    try {
        return (Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200
    }
    catch { return $false }
}

if (Test-GatewayUp) {
    Write-Log "La pasarela ya responde en el puerto $Port; no arranco nada."
    return
}

if (-not (Test-Path -LiteralPath $Executable)) {
    Write-Log "No existe $Executable; no hay nada que supervisar."
    exit 1
}

for ($attempt = 1; $attempt -le $MaxRestarts + 1; $attempt++) {
    Write-Log "Arrancando la pasarela (intento $attempt de $($MaxRestarts + 1))."
    $process = Start-Process -FilePath $Executable -ArgumentList 'serve' -WindowStyle Hidden -PassThru `
        -RedirectStandardError $gatewayLog -RedirectStandardOutput $gatewayOut
    $process.WaitForExit()
    Write-Log "La pasarela termino (codigo $($process.ExitCode))."
    if ($attempt -le $MaxRestarts) {
        # Espera creciente (5, 10, ... 30 s) para no martillear si el fallo es de configuracion.
        Start-Sleep -Seconds ([math]::Min(5 * $attempt, 30))
        if (Test-GatewayUp) {
            Write-Log 'La pasarela ya responde (la levanto otra instancia); salgo.'
            return
        }
    }
}

Write-Log "La pasarela no se mantuvo tras $($MaxRestarts + 1) intentos; me rindo."
exit 1
