<#
.SYNOPSIS
    Fija memoria, hilos y swap de WSL2 en .wslconfig sin tocar el resto del fichero.

.DESCRIPTION
    Sustituye o anade las claves de [wsl2] (memory, processors, swap) y conserva comentarios y
    demas secciones. Si `autoMemoryReclaim` esta en [wsl2] lo quita: WSL lo ignora ahi con el aviso
    "Clave 'wsl2.autoMemoryReclaim' desconocida" (doc 01, seccion 9.3). Con -ReclaimMemory lo pone donde
    corresponde, en [experimental].

    Los cambios NO se aplican en caliente: hace falta `wsl --shutdown` (o -Restart). Cerrar WSL
    corta cualquier distro y contenedor en marcha.

.EXAMPLE
    .\Set-WslResources.ps1 -MemoryGB 16 -Processors 8 -WhatIf

.EXAMPLE
    .\Set-WslResources.ps1 -MemoryGB 16 -Processors 8 -SwapGB 8 -ReclaimMemory -Restart
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [int]$MemoryGB = 16,
    [int]$Processors = 8,
    [int]$SwapGB = 8,
    [string]$Path = (Join-Path $env:USERPROFILE '.wslconfig'),
    [switch]$ReclaimMemory,
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'

function Find-Section {
    param([System.Collections.Generic.List[string]]$Lines, [string]$Section)
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -ieq "[$Section]") { return $i }
    }
    return -1
}

function Set-IniKey {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Section,
        [string]$Key,
        [string]$Value
    )
    $start = Find-Section -Lines $Lines -Section $Section
    if ($start -lt 0) {
        if ($Lines.Count -gt 0 -and $Lines[$Lines.Count - 1].Trim() -ne '') { $Lines.Add('') }
        $Lines.Add("[$Section]")
        $Lines.Add("$Key=$Value")
        return
    }
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim().StartsWith('[')) { break }
        if ($Lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") {
            $Lines[$i] = "$Key=$Value"
            return
        }
    }
    $Lines.Insert($start + 1, "$Key=$Value")
}

function Remove-IniKey {
    param([System.Collections.Generic.List[string]]$Lines, [string]$Section, [string]$Key)
    $start = Find-Section -Lines $Lines -Section $Section
    if ($start -lt 0) { return }
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim().StartsWith('[')) { break }
        if ($Lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") {
            $Lines.RemoveAt($i)
            return
        }
    }
}

$lines = New-Object 'System.Collections.Generic.List[string]'
if (Test-Path -LiteralPath $Path) {
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) { $lines.Add($line) }
}

Set-IniKey -Lines $lines -Section 'wsl2' -Key 'memory' -Value "${MemoryGB}GB"
Set-IniKey -Lines $lines -Section 'wsl2' -Key 'processors' -Value "$Processors"
Set-IniKey -Lines $lines -Section 'wsl2' -Key 'swap' -Value "${SwapGB}GB"
Remove-IniKey -Lines $lines -Section 'wsl2' -Key 'autoMemoryReclaim'
if ($ReclaimMemory) {
    Set-IniKey -Lines $lines -Section 'experimental' -Key 'autoMemoryReclaim' -Value 'gradual'
}

if ($PSCmdlet.ShouldProcess($Path, "Escribir memory=${MemoryGB}GB processors=$Processors swap=${SwapGB}GB")) {
    # UTF-8 sin BOM: con BOM, WSL puede no reconocer la primera clave.
    [System.IO.File]::WriteAllLines($Path, $lines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Escrito $Path"
    if ($Restart) {
        Write-Host 'Cerrando WSL para aplicar los cambios...'
        wsl --shutdown
        Start-Sleep -Seconds 8
        wsl -d Ubuntu -u root -e sh -c 'free -h | head -2; nproc'
    }
    else {
        Write-Host 'Aplica los cambios con: wsl --shutdown'
    }
}
