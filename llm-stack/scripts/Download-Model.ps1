<#
.SYNOPSIS
    Descarga un modelo del stack vLLM (download-models.sh dentro de WSL2).

.DESCRIPTION
    Lo lanza la app desde el selector de modelos, en el tile de un rol del stack
    que sale "Falta descargar". Es un envoltorio fino: resuelve la ruta del
    script dentro de WSL2 con wslpath y ejecuta download-models.sh, que lee
    models.json. El progreso sale por el panel de Ejecuciones (es el runner
    capturado, el mismo del switch del stack).

    Una sesion de WSL2 se abre sola para el comando, asi que no hace falta el
    keep-alive: la distro se levanta si estaba apagada. La descarga es
    reanudable: volver a lanzarla no vuelve a bajar lo que ya esta.

    ASCII a proposito: Windows PowerShell 5.1 lee mal los .ps1 UTF-8 sin BOM.

.EXAMPLE
    .\Download-Model.ps1 -Role writer
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Role,
    [string]$Distro = 'Ubuntu',
    [string]$ScriptsDir = ''
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot llega VACIO en el valor por defecto de un parametro cuando el
# script se lanza con `powershell.exe -File` (que es como lo lanza la app).
# Por eso el valor por defecto se calcula aqui, en el cuerpo.
if (-not $ScriptsDir) { $ScriptsDir = $PSScriptRoot }

$downloadScript = Join-Path $ScriptsDir 'download-models.sh'
if (-not (Test-Path -LiteralPath $downloadScript)) {
    throw "No existe $downloadScript. Apunta la carpeta del stack con el engranaje del switch."
}

Write-Host "== Descargando el modelo del rol '$Role' (reanudable; puede tardar) =="

$wslPath = (& wsl.exe -d $Distro -e wslpath -a $downloadScript).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "No se pudo resolver la ruta del script en WSL2 (distro '$Distro')."
}

& wsl.exe -d $Distro -e bash $wslPath $Role
if ($LASTEXITCODE -ne 0) { throw "download-models.sh '$Role' fallo (codigo $LASTEXITCODE)." }

Write-Host "== Descarga de '$Role' terminada. =="
