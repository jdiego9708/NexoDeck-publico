<#
.SYNOPSIS
    Prueba de humo de la pasarela contra el stack REAL (los servidores vLLM que haya levantados).

.DESCRIPTION
    Arranca una pasarela temporal en otro puerto (18888 por defecto) con una clave DESECHABLE en un
    directorio temporal, y comprueba desde Windows: /health, autenticacion (sin clave, clave mala,
    clave buena), lista de modelos, una generacion por cada modelo levantado, streaming, y que las
    rutas de administracion de vLLM (/sleep, /collective_rpc...) NO se alcanzan. Al terminar la
    para y borra todo. No toca la pasarela permanente ni sus claves.

    Necesita el binario release: `cargo build --release` en ..\gateway. Y al menos un modelo
    levantado (serve-profile.sh). Los modelos apagados se omiten.

    El fichero es solo ASCII a proposito: Windows PowerShell 5.1 lee mal los .ps1 UTF-8 sin BOM.

.EXAMPLE
    .\Test-Gateway.ps1
#>
[CmdletBinding()]
param(
    [int]$Port = 18888,
    [string]$Executable = ''
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot llega vacio en el valor por defecto de un parametro con `powershell.exe -File`.
if (-not $Executable) { $Executable = Join-Path $PSScriptRoot '..\gateway\target\release\llm-gateway.exe' }

if (-not (Test-Path -LiteralPath $Executable)) {
    throw "No existe $Executable. Compilalo con: cargo build --release (en llm-stack\gateway)."
}

$directory = Join-Path $env:TEMP ('llm-gateway-test-' + [guid]::NewGuid().ToString('N'))
$previousDirectory = $env:NEXODECK_GATEWAY_DIR
$env:NEXODECK_GATEWAY_DIR = $directory
$base = "http://127.0.0.1:$Port"
$failures = 0
$process = $null

function Write-Check {
    param([string]$Label, [bool]$Passed, [string]$Detail = '')
    $mark = if ($Passed) { 'OK  ' } else { 'FALLA' }
    Write-Host ("  {0} {1} {2}" -f $mark, $Label, $Detail)
    if (-not $Passed) { $script:failures++ }
}

# Devuelve el codigo HTTP y el cuerpo sin lanzar excepcion en 4xx/5xx.
function Invoke-Http {
    param([string]$Method, [string]$Path, [string]$Key, [string]$Body)
    $headers = @{}
    if ($Key) { $headers['Authorization'] = "Bearer $Key" }
    $arguments = @{ Uri = "$base$Path"; Method = $Method; Headers = $headers; UseBasicParsing = $true; TimeoutSec = 180 }
    if ($Body) { $arguments['Body'] = [System.Text.Encoding]::UTF8.GetBytes($Body); $arguments['ContentType'] = 'application/json' }
    try {
        $response = Invoke-WebRequest @arguments
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Content = $response.Content; Headers = $response.Headers }
    }
    catch {
        $status = 0
        $content = ''
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $content = $reader.ReadToEnd()
            }
            catch { }
        }
        return [pscustomobject]@{ Status = $status; Content = $content; Headers = @{} }
    }
}

# Peticion al modelo virtual `auto` con un texto; devuelve tambien las cabeceras de decision.
function Invoke-Auto {
    param([string]$Key, [string]$Text)
    $body = @{ model = 'auto'; max_tokens = 16; temperature = 0; messages = @(@{ role = 'user'; content = $Text }) } | ConvertTo-Json -Depth 5 -Compress
    return Invoke-Http POST '/v1/chat/completions' $Key $body
}

try {
    & $Executable init | Out-Null
    $configPath = Join-Path $directory 'gateway.json'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $config.listen = "127.0.0.1:$Port"
    $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding ASCII

    # La clave se captura en una variable y nunca se imprime.
    $key = (& $Executable keys add prueba-de-humo | Where-Object { $_ -match '^ndk_' } | Select-Object -First 1).Trim()

    $process = Start-Process -FilePath $Executable -ArgumentList 'serve' -WindowStyle Hidden -PassThru `
        -RedirectStandardError (Join-Path $directory 'gateway.log') -RedirectStandardOutput (Join-Path $directory 'gateway.out')

    $ready = $false
    for ($attempt = 0; $attempt -lt 40 -and -not $ready; $attempt++) {
        Start-Sleep -Milliseconds 250
        $ready = (Invoke-Http GET '/health').Status -eq 200
    }
    if (-not $ready) { throw 'La pasarela no respondio en 10 s.' }
    Write-Host "Pasarela de prueba en $base (PID $($process.Id))"

    Write-Host '[salud y autenticacion]'
    # /health responde al instante con lo que sabe el sondeo de fondo (cada 2 s): al principio los
    # modelos salen como "unknown" y hay que esperar al primer sondeo.
    $health = Invoke-Http GET '/health'
    for ($attempt = 0; $attempt -lt 40 -and $health.Content -match 'unknown'; $attempt++) {
        Start-Sleep -Milliseconds 250
        $health = Invoke-Http GET '/health'
    }
    Write-Check '/health sin clave' ($health.Status -eq 200) $health.Content
    $up = @((($health.Content | ConvertFrom-Json).backends.PSObject.Properties | Where-Object { $_.Value -eq 'up' }).Name)
    Write-Check 'hay al menos un modelo levantado' ($up.Count -gt 0) ("(" + ($up -join ', ') + ")")

    $chat = '{"model":"%M%","max_tokens":24,"temperature":0,"messages":[{"role":"user","content":"Di hola en una palabra."}]}'
    $first = if ($up.Count -gt 0) { $up[0] } else { 'router' }
    Write-Check 'sin clave -> 401' ((Invoke-Http POST '/v1/chat/completions' $null $chat.Replace('%M%', $first)).Status -eq 401)
    Write-Check 'clave mala -> 401' ((Invoke-Http POST '/v1/chat/completions' 'ndk_mala' $chat.Replace('%M%', $first)).Status -eq 401)

    Write-Host '[modelos]'
    $models = Invoke-Http GET '/v1/models' $key
    Write-Check '/v1/models con clave' ($models.Status -eq 200) $models.Content.Substring(0, [Math]::Min(90, $models.Content.Length))
    Write-Check '/v1/models sin clave -> 401' ((Invoke-Http GET '/v1/models').Status -eq 401)

    Write-Host '[generacion por cada modelo levantado]'
    foreach ($model in $up) {
        $reply = Invoke-Http POST '/v1/chat/completions' $key $chat.Replace('%M%', $model)
        $tokens = 0
        if ($reply.Status -eq 200) { $tokens = [int](($reply.Content | ConvertFrom-Json).usage.completion_tokens) }
        Write-Check "$model genera tokens" ($reply.Status -eq 200 -and $tokens -gt 0) "(HTTP $($reply.Status), $tokens tokens)"
    }

    Write-Host '[streaming]'
    $stream = Invoke-Http POST '/v1/chat/completions' $key ($chat.Replace('%M%', $first).Replace('"max_tokens":24', '"max_tokens":24,"stream":true'))
    Write-Check 'SSE con data: y [DONE]' ($stream.Status -eq 200 -and $stream.Content -match 'data: ' -and $stream.Content -match '\[DONE\]')

    Write-Host '[modelo virtual auto]'
    $worker = @('complex', 'fast') | Where-Object { $up -contains $_ } | Select-Object -First 1
    $lightUp = $up -contains 'router'
    Write-Check '/v1/models ofrece auto' ($models.Content -match '"id":"auto"')
    if ($lightUp -and $worker) {
        $secret = 'MARCA-SECRETA-DEL-PROMPT'
        $cases = @(
            @{ Label = 'corto -> simple -> router'; Text = "Cuanto es 6 por 7? $secret"; Decision = 'simple'; Model = 'router' },
            @{ Label = 'palabra de arquitectura -> trabajador'; Text = 'Refactoriza este modulo'; Decision = 'complex_keywords'; Model = $worker },
            @{ Label = 'clasificacion -> router'; Text = 'Classify this ticket: la impresora no funciona'; Decision = 'meta'; Model = 'router' },
            @{ Label = 'largo -> trabajador'; Text = ('la casa es azul y el sol brilla. ' * 40); Decision = 'complex'; Model = $worker }
        )
        foreach ($case in $cases) {
            $reply = Invoke-Auto $key $case.Text
            $decision = [string]$reply.Headers['x-nexodeck-decision']
            $chosen = [string]$reply.Headers['x-nexodeck-model']
            Write-Check $case.Label ($reply.Status -eq 200 -and $decision -eq $case.Decision -and $chosen -eq $case.Model) "(HTTP $($reply.Status), decision=$decision, modelo=$chosen)"
        }
        $decisionsFile = Join-Path $directory 'decisions.jsonl'
        $lines = @(Get-Content -LiteralPath $decisionsFile -ErrorAction SilentlyContinue)
        Write-Check 'registro de decisiones con una linea por peticion auto' ($lines.Count -eq 4) "($($lines.Count) lineas)"
        Write-Check 'el registro no guarda el texto del prompt' (-not (($lines -join ' ').Contains($secret)))

        # Resultado verificado de la ultima peticion `auto`: se une a su decision por el id.
        $requestId = [string]$reply.Headers['x-nexodeck-request-id']
        Write-Check 'la respuesta trae x-nexodeck-request-id' ($requestId -match '^req_[0-9a-f]{16}$') "($requestId)"
        $report = (@{ request_id = $requestId; verified = $true; verifier = 'test-gateway' } | ConvertTo-Json -Compress)
        Write-Check 'POST /v1/feedback registra el resultado' ((Invoke-Http POST '/v1/feedback' $key $report).Status -eq 200)
        Write-Check 'el mismo resultado dos veces -> 409' ((Invoke-Http POST '/v1/feedback' $key $report).Status -eq 409)
        Write-Check 'feedback sin clave -> 401' ((Invoke-Http POST '/v1/feedback' $null $report).Status -eq 401)
        $unknown = (@{ request_id = 'req_0000000000000000'; verified = $true } | ConvertTo-Json -Compress)
        Write-Check 'una peticion desconocida -> 404' ((Invoke-Http POST '/v1/feedback' $key $unknown).Status -eq 404)
        $lines = @(Get-Content -LiteralPath $decisionsFile)
        $linked = @($lines | Where-Object { $_ -match '"type":"outcome"' -and $_ -match [regex]::Escape($requestId) })
        Write-Check 'el resultado queda en el registro unido por el id' ($linked.Count -eq 1) "($($lines.Count) lineas)"
    }
    else {
        Write-Host '  (se omiten las decisiones: hacen falta el router y un trabajador levantados)'
    }

    Write-Host '[errores y superficie]'
    Write-Check 'modelo inexistente -> 404' ((Invoke-Http POST '/v1/chat/completions' $key $chat.Replace('%M%', 'gpt-99')).Status -eq 404)
    Write-Check 'cuerpo sin model -> 400' ((Invoke-Http POST '/v1/chat/completions' $key '{"messages":[]}').Status -eq 400)
    foreach ($path in '/sleep', '/wake_up', '/collective_rpc', '/metrics', '/is_sleeping') {
        Write-Check "$path no expuesto (404)" ((Invoke-Http POST $path $key).Status -eq 404)
    }
    $down = @((($health.Content | ConvertFrom-Json).backends.PSObject.Properties | Where-Object { $_.Value -eq 'down' }).Name)
    foreach ($model in $down) {
        Write-Check "$model apagado -> 503" ((Invoke-Http POST '/v1/chat/completions' $key $chat.Replace('%M%', $model)).Status -eq 503)
    }

    Write-Host '[revocacion en caliente]'
    & $Executable keys remove prueba-de-humo | Out-Null
    Start-Sleep -Milliseconds 300
    Write-Check 'clave revocada -> 401 sin reiniciar' ((Invoke-Http POST '/v1/chat/completions' $key $chat.Replace('%M%', $first)).Status -eq 401)

    Write-Host '[el registro no contiene prompts ni claves]'
    Start-Sleep -Milliseconds 200
    $log = Get-Content -LiteralPath (Join-Path $directory 'gateway.log') -Raw
    Write-Check 'sin el texto del prompt' ($log -notmatch 'Di hola')
    Write-Check 'sin la clave' (-not $log.Contains($key))
}
finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    $env:NEXODECK_GATEWAY_DIR = $previousDirectory
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
}

if ($failures -eq 0) { Write-Host 'TODO OK'; exit 0 }
Write-Host "$failures comprobacion(es) fallaron"
exit 1
