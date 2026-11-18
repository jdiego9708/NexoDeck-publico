<#
.SYNOPSIS
    Registra (o quita) la tarea programada que levanta el stack al iniciar sesion en Windows.

.DESCRIPTION
    Crea la tarea `NexoDeckLlmStack`: al iniciar sesion, con un retraso (60 s por defecto, para
    que Windows termine de arrancar), ejecuta Start-Stack.ps1 con el perfil elegido.

    - Se ejecuta como TU usuario y sin privilegios elevados: no hace falta ser administrador.
    - Solo cuando has iniciado sesion (no con el equipo en la pantalla de bloqueo sin usuario).
    - Es reversible: -Remove la quita; Stop-Stack.ps1 libera la GPU en cualquier momento.

    ATENCION: con un perfil de modelos, cada inicio de sesion ocupa ~15 GiB de VRAM y 8+ GB de RAM
    de WSL2, y compite con ODM, entrenamientos y juegos. Si prefieres decidir cuando se cargan
    los modelos, usa -Profile none (solo pasarela, que es casi gratis) y lanza
    `Start-Stack.ps1 -Profile A|B` cuando los necesites.

    ASCII a proposito: Windows PowerShell 5.1 lee mal los .ps1 UTF-8 sin BOM.

.EXAMPLE
    .\Install-StackTask.ps1 -Profile none -WhatIf     # ensayo, no registra nada

.EXAMPLE
    .\Install-StackTask.ps1 -Profile A

.EXAMPLE
    .\Install-StackTask.ps1 -Remove
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('A', 'B', 'C', 'complex-solo', 'none')]
    [string]$Profile = 'none',
    [int]$DelaySeconds = 60,
    [switch]$Remove,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'
$taskName = 'NexoDeckLlmStack'
$account = "$env:USERDOMAIN\$env:USERNAME"

if ($Status) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) { Write-Host "La tarea $taskName no esta registrada."; return }
    $info = Get-ScheduledTaskInfo -TaskName $taskName
    Write-Host "Tarea: $taskName  Estado: $($task.State)"
    Write-Host "Accion: $($task.Actions[0].Execute) $($task.Actions[0].Arguments)"
    Write-Host "Ultima ejecucion: $($info.LastRunTime)  Resultado: $($info.LastTaskResult)"
    return
}

if ($Remove) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($taskName, 'Quitar la tarea programada')) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Host "Tarea $taskName eliminada."
        }
    }
    else { Write-Host "La tarea $taskName no estaba registrada." }
    return
}

$startScript = Join-Path $PSScriptRoot 'Start-Stack.ps1'
$arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startScript`" -Profile $Profile"

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $account
$trigger.Delay = 'PT{0}S' -f $DelaySeconds
$principal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
# El arranque de los modelos tarda 2-6 minutos: el limite de 30 evita que un cuelgue deje la tarea
# viva para siempre.
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

if ($PSCmdlet.ShouldProcess($taskName, "Registrar la tarea de inicio de sesion (perfil $Profile, retraso ${DelaySeconds}s)")) {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal `
        -Settings $settings -Description 'Levanta la pasarela y los modelos vLLM (llm-stack)' -Force | Out-Null
    Write-Host "Tarea $taskName registrada: al iniciar sesion arrancara el perfil '$Profile' tras ${DelaySeconds}s."
    Write-Host 'Quitarla: .\Install-StackTask.ps1 -Remove   Liberar la GPU: .\Stop-Stack.ps1 -ReleaseWsl'
}
