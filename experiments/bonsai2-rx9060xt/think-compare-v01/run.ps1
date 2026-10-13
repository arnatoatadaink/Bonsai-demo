$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Cfg = Get-Content (Join-Path $Root 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$Server = [string]$Cfg.server
$Model = [string]$Cfg.model
$Port = [int]$Cfg.port
$Base = 'http://127.0.0.1:' + $Port
$RunDir = Join-Path $Root ('results\run_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$Child = $null
$Failed = $false
$Rows = New-Object 'System.Collections.Generic.List[object]'

function Save-Json($Value, $Path) {
    $Value | ConvertTo-Json -Depth 30 | Out-File -LiteralPath $Path -Encoding UTF8
}
function Invoke-Json($Uri, $Data, $Timeout) {
    $Bytes = [Text.Encoding]::UTF8.GetBytes(($Data | ConvertTo-Json -Depth 20 -Compress))
    Invoke-RestMethod -Uri $Uri -Method Post -ContentType 'application/json; charset=utf-8' -Body $Bytes -TimeoutSec $Timeout
}
try {
    if (-not (Test-Path -LiteralPath $Server -PathType Leaf)) { throw "Executable missing: $Server" }
    if (-not (Test-Path -LiteralPath $Model -PathType Leaf)) { throw "Model missing: $Model" }
    $Client = New-Object Net.Sockets.TcpClient
    try {
        $Pending = $Client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if ($Pending.AsyncWaitHandle.WaitOne(500)) {
            try { $Client.EndConnect($Pending) } catch {}
            throw "Port $Port is occupied. Refusing to use an existing server."
        }
    } finally { $Client.Close() }

    $Arguments = @(
        '--model', ('"' + $Model + '"'),
        '--device', 'Vulkan0', '--split-mode', 'none', '--gpu-layers', 'all',
        '--ctx-size', [string]$Cfg.context, '--ctx-checkpoints', '0',
        '--cache-type-k', [string]$Cfg.cache_k, '--cache-type-v', [string]$Cfg.cache_v,
        '--threads', [string]$Cfg.threads, '--batch-size', [string]$Cfg.batch,
        '--ubatch-size', [string]$Cfg.ubatch, '--parallel', '1',
        '--flash-attn', 'on', '--spec-type', 'none', '--jinja',
        '--host', '127.0.0.1', '--port', [string]$Port
    ) -join ' '
    $Hash = (Get-FileHash -LiteralPath $Server -Algorithm SHA256).Hash
    Save-Json ([ordered]@{
        timestamp=(Get-Date).ToString('o');server=$Server;server_sha256=$Hash
        model=$Model;arguments=$Arguments;config=$Cfg
        ps_version=$PSVersionTable.PSVersion.ToString()
    }) (Join-Path $RunDir 'environment.json')

    Write-Host "Results: $RunDir"
    $Child = Start-Process -FilePath $Server -ArgumentList $Arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $RunDir 'server.stdout.log') -RedirectStandardError (Join-Path $RunDir 'server.stderr.log')
    $Ready = $false
    $Deadline = (Get-Date).AddSeconds([int]$Cfg.startup_timeout_sec)
    while ((Get-Date) -lt $Deadline) {
        if ($Child.HasExited) { throw "Server exited: $($Child.ExitCode)" }
        try {
            $Health = Invoke-RestMethod -Uri ($Base + '/health') -TimeoutSec 3
            if ($Health.status -eq 'ok') { $Ready = $true; break }
        } catch {}
        Start-Sleep -Seconds 2
    }
    if (-not $Ready) { throw 'Server health timeout.' }
    Save-Json (Invoke-RestMethod -Uri ($Base + '/v1/models') -TimeoutSec 10) (Join-Path $RunDir 'models.json')

    $Questions = @(Get-Content (Join-Path $Root 'questions.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
    foreach ($Question in $Questions) {
        foreach ($Mode in @('default','off','on')) {
            $Body = @{
                messages=@(@{role='user';content=[string]$Question.prompt})
                max_tokens=[int]$Cfg.max_tokens;temperature=0;top_k=1;seed=42
            }
            if ($Mode -eq 'off') {
                $Body['reasoning_effort']='none'
                $Body['chat_template_kwargs']=@{enable_thinking=$false}
            } elseif ($Mode -eq 'on') {
                $Body['reasoning_effort']='high'
                $Body['chat_template_kwargs']=@{enable_thinking=$true}
            }
            $Prefix = [string]$Question.id + '_' + $Mode
            Save-Json $Body (Join-Path $RunDir ($Prefix + '.request.json'))
            Write-Host "Testing $Prefix"
            $Watch = [Diagnostics.Stopwatch]::StartNew()
            try {
                $Result = Invoke-Json ($Base + '/v1/chat/completions') $Body ([int]$Cfg.request_timeout_sec)
                $Watch.Stop()
                Save-Json $Result (Join-Path $RunDir ($Prefix + '.response.json'))
                $Msg = $Result.choices[0].message
                ([string]$Msg.content + [Environment]::NewLine + '[REASONING_CONTENT]' + [Environment]::NewLine + [string]$Msg.reasoning_content) |
                    Out-File (Join-Path $RunDir ($Prefix + '.response.txt')) -Encoding UTF8
                $T = $Result.timings
                $Row = [pscustomobject]@{
                    id=$Question.id;mode=$Mode;status='OK'
                    prompt_tokens=$Result.usage.prompt_tokens;completion_tokens=$Result.usage.completion_tokens
                    finish_reason=$Result.choices[0].finish_reason
                    content_chars=([string]$Msg.content).Length;reasoning_chars=([string]$Msg.reasoning_content).Length
                    pp_tok_s=if($T){$T.prompt_per_second}else{$null}
                    tg_tok_s=if($T){$T.predicted_per_second}else{$null}
                    elapsed_sec=[Math]::Round($Watch.Elapsed.TotalSeconds,3);error=''
                }
            } catch {
                $Failed = $true
                $Watch.Stop()
                $Row = [pscustomobject]@{
                    id=$Question.id;mode=$Mode;status='ERROR';prompt_tokens=$null
                    completion_tokens=$null;finish_reason='';content_chars=0;reasoning_chars=0
                    pp_tok_s=$null;tg_tok_s=$null
                    elapsed_sec=[Math]::Round($Watch.Elapsed.TotalSeconds,3);error=$_.Exception.Message
                }
                Write-Warning $Row.error
            }
            $Rows.Add($Row)
            $Rows | Export-Csv (Join-Path $RunDir 'trials.csv') -NoTypeInformation -Encoding UTF8
            $Row | Format-List | Out-Host
        }
    }
} catch {
    $Failed = $true
    Write-Warning $_.Exception.Message
    $_ | Out-String | Out-File (Join-Path $RunDir 'failure.txt') -Encoding UTF8
} finally {
    if ($Child -and -not $Child.HasExited) {
        Write-Host "Stopping only child PID $($Child.Id)"
        Stop-Process -Id $Child.Id -ErrorAction SilentlyContinue
        try { $Child.WaitForExit(10000) | Out-Null } catch {}
    }
    Write-Host "Results: $RunDir"
}
if ($Failed) { exit 1 }
exit 0
