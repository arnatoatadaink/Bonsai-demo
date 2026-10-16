# Bonsai2-27B generic Windows Vulkan GPU PP/TG smoke test (PowerShell 5.1)
param(
 [Parameter(Mandatory=$true)][string]$ModelPath,
 [Parameter(Mandatory=$true)][string]$LlamaServer,
 [string]$GpuName='RX 9070 XT',
 [int]$Port=18081,
 [int]$Context=4096,
 [int]$MaxTokens=512
)
$ErrorActionPreference='Stop'
if(!(Test-Path -LiteralPath $ModelPath -PathType Leaf)){throw "Missing model: $ModelPath"}
if(!(Test-Path -LiteralPath $LlamaServer -PathType Leaf)){throw "Missing server: $LlamaServer"}
$model=(Resolve-Path -LiteralPath $ModelPath).Path
$exe=(Resolve-Path -LiteralPath $LlamaServer).Path
$run=Join-Path $PSScriptRoot ('results\bonsai2_vulkan_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $run -Force|Out-Null
$deviceOut=Join-Path $run 'devices.stdout.txt'
$deviceErr=Join-Path $run 'devices.stderr.txt'
$deviceProc=Start-Process -FilePath $exe -ArgumentList '--list-devices' -Wait -PassThru -RedirectStandardOutput $deviceOut -RedirectStandardError $deviceErr
if($deviceProc.ExitCode -ne 0){throw 'Device discovery failed; inspect devices.stderr.txt'}
$devices=(Get-Content -Raw $deviceOut)+(Get-Content -Raw $deviceErr)
$devices|Set-Content -Encoding UTF8 (Join-Path $run 'devices.txt')
$gpuPattern=(($GpuName -split '\s+') | ForEach-Object {[regex]::Escape($_)}) -join '\s*'
$ids=@($devices -split '\r?\n'|Where-Object {$_ -match $gpuPattern}|ForEach-Object {if($_ -match '\b(Vulkan\d+)\b'){$Matches[1]}}|Select-Object -Unique)
if($ids.Count -ne 1){throw "GPU selection not unique for $GpuName; inspect $run/devices.stdout.txt and devices.stderr.txt"}
$device=$ids[0]
if(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue){throw "Port $Port is busy"}
# PowerShell 5.1 promotes native stderr to a terminating error under Stop.
# Capture version output with a child process instead of 2>&1.
$versionOut=Join-Path $run 'version.stdout.txt'
$versionErr=Join-Path $run 'version.stderr.txt'
$verProc=Start-Process -FilePath $exe -ArgumentList '--version' -PassThru -Wait -RedirectStandardOutput $versionOut -RedirectStandardError $versionErr
if($verProc.ExitCode -ne 0){Write-Warning "llama-server --version exit=$($verProc.ExitCode); see version.stderr.txt"}
$manifest=[ordered]@{
 model_name=[IO.Path]::GetFileName($model);model_sha256=(Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash
 binary_name=[IO.Path]::GetFileName($exe);binary_sha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
 gpu=$GpuName;device=$device;context=$Context;max_tokens=$MaxTokens
 kv_k='q8_0';kv_v='q8_0';flash_attention='on';gpu_layers=99;speculative='off'
 timestamp=(Get-Date).ToString('o')
}
$manifest|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 (Join-Path $run 'manifest.json')
$stderr=Join-Path $run 'server.stderr.log'
$stdout=Join-Path $run 'server.stdout.log'
$argsList=@('-m',('"'+$model+'"'),'--host','127.0.0.1','--port',"$Port",
 '--device',$device,'-ngl','99','-sm','none','-c',"$Context",
 '--cache-type-k','q8_0','--cache-type-v','q8_0','-fa','on','-np','1','--jinja')
($argsList -join ' ')|Set-Content -Encoding UTF8 (Join-Path $run 'command.txt')
$proc=$null
try{
 $proc=Start-Process -FilePath $exe -ArgumentList ($argsList -join ' ') -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
 $deadline=(Get-Date).AddSeconds(240);$ready=$false
 while((Get-Date) -lt $deadline){
  $proc.Refresh()
  if($proc.HasExited){throw "Server exited during model load with code $($proc.ExitCode)"}
  try{$h=Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 3;if($h.status -eq 'ok'){$ready=$true;break}}catch{}
  Start-Sleep -Seconds 2
 }
 if(!$ready){throw "Startup timeout"}
 $meta=Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/models" -TimeoutSec 15
 $meta|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $run 'models.json')
 $records=(1..120|ForEach-Object {('Record {0}: quarter {1}; units {2}; approved {3}.' -f $_,(($_ % 4)+1),($_*3),($_ % 3 -eq 0))}) -join [Environment]::NewLine
 $prompt="Summarize the quarterly counts and exceptions from these audit records in English:" + [Environment]::NewLine + $records
 $body=@{messages=@(@{role='system';content='You are a helpful assistant.'},@{role='user';content=$prompt});max_tokens=$MaxTokens;temperature=1.0;top_k=20;top_p=0.95;stream=$false;reasoning_effort='medium'}
 $payload=$body|ConvertTo-Json -Depth 8
 $payload|Set-Content -Encoding UTF8 (Join-Path $run 'request.json')
 $res=Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat/completions" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -ContentType 'application/json; charset=utf-8' -TimeoutSec 900
 $res|ConvertTo-Json -Depth 30|Set-Content -Encoding UTF8 (Join-Path $run 'response.json')
 $time=$res.timings
 $pp=$time.prompt_per_second;$tg=$time.predicted_per_second
 $inTokens=$res.usage.prompt_tokens;$outTokens=$res.usage.completion_tokens
 $choice=$res.choices[0]
 $answer=[string]$choice.message.content
 $reason=[string]$choice.message.reasoning_content
 $status=if($outTokens -ge 32 -and $tg -gt 0 -and ($answer.Length -gt 0 -or $reason.Length -gt 0)){'PASS'}else{'INCOMPLETE'}
 $summary=[ordered]@{status=$status;device=$device;model=[IO.Path]::GetFileName($model);pp_tok_s=$pp;tg_tok_s=$tg;prompt_tokens=$inTokens;generated_tokens=$outTokens;finish_reason=$choice.finish_reason;answer_chars=$answer.Length;reasoning_chars=$reason.Length;log_dir=(Split-Path $run -Leaf)}
 $summary|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 (Join-Path $run 'summary.json')
 if($status -ne 'PASS'){throw "No sustained text generation: tokens=$outTokens TG=$tg finish=$($choice.finish_reason); inspect response.json"}
 Write-Host ("Bonsai2 / {0}: PP={1} tokens/s, TG={2} tokens/s, generated={3}" -f $device,$pp,$tg,$outTokens)
 Write-Host "Results: $run"
}finally{
 if($proc){$proc.Refresh();if(!$proc.HasExited){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue;try{$proc.WaitForExit(10000)|Out-Null}catch{}}}
}
