# Bonsai2-27B / RX9070XT independent load and PP/TG smoke test
param(
 [Parameter(Mandatory=$true)][string]$ModelPath,
 [string]$LlamaServer='D:\AI\PrismML\dev\llama.cpp\build-vulkan-ucrt64\bin\llama-server.exe',
 [int]$Port=18081,
 [int]$Context=4096,
 [int]$MaxTokens=512
)
$ErrorActionPreference='Stop'
if(!(Test-Path -LiteralPath $ModelPath -PathType Leaf)){throw "Missing model: $ModelPath"}
if(!(Test-Path -LiteralPath $LlamaServer -PathType Leaf)){throw "Missing server: $LlamaServer"}
$model=(Resolve-Path -LiteralPath $ModelPath).Path
$exe=(Resolve-Path -LiteralPath $LlamaServer).Path
$run=Join-Path $PSScriptRoot ('results\bonsai2_rx9070xt_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $run -Force|Out-Null
$devices=(& $exe --list-devices 2>&1|Out-String)
$devices|Set-Content -Encoding UTF8 (Join-Path $run 'devices.txt')
$ids=@($devices -split '\r?\n'|Where-Object {$_ -match 'RX\s*9070\s*XT'}|ForEach-Object {if($_ -match '\b(Vulkan\d+)\b'){$Matches[1]}}|Select-Object -Unique)
if($ids.Count -ne 1){throw "RX9070XT GPU ambiguity; inspect $run/devices.txt"}
$device=$ids[0]
if(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue){throw "Port $Port is busy"}
(& $exe --version 2>&1|Out-String)|Set-Content -Encoding UTF8 (Join-Path $run 'version.txt')
$manifest=[ordered]@{
 model=$model;model_sha256=(Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash
 binary=$exe;binary_sha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
 gpu='RX 9070 XT';device=$device;context=$Context;max_tokens=$MaxTokens
 kv_k='q8_0';kv_v='q8_0';flash_attention='on';gpu_layers=99;speculative='off'
 timestamp=(Get-Date).ToString('o')
}
$manifest|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 (Join-Path $run 'manifest.json')
$stderr=Join-Path $run 'server.stderr.log'
$stdout=Join-Path $run 'server.stdout.log'
$argsList=@('-m',('"'+$model+'"'),'--host','127.0.0.1','--port',"$Port",
 '--device',$device,'-ngl','99','-sm','none','-c',"$Context",
 '--cache-type-k','q8_0','--cache-type-v','q8_0','-fa','on','-np','1')
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
 $prompt="Summarize the quarterly counts and exceptions from these audit records in Japanese:" + [Environment]::NewLine + $records
 $body=@{prompt=$prompt;n_predict=$MaxTokens;temperature=0.7;top_k=20;top_p=0.8;stream=$false}
 $payload=$body|ConvertTo-Json -Depth 6
 $payload|Set-Content -Encoding UTF8 (Join-Path $run 'request.json')
 $res=Invoke-RestMethod -Uri "http://127.0.0.1:$Port/completion" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -ContentType 'application/json; charset=utf-8' -TimeoutSec 900
 $res|ConvertTo-Json -Depth 30|Set-Content -Encoding UTF8 (Join-Path $run 'response.json')
 $time=$res.timings
 $pp=$time.prompt_per_second;$tg=$time.predicted_per_second
 $summary=[ordered]@{device=$device;model=$model;pp_tok_s=$pp;tg_tok_s=$tg;prompt_tokens=$res.tokens_evaluated;generated_tokens=$res.tokens_predicted;stop_type=$res.stop_type;log_dir=$run}
 $summary|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 (Join-Path $run 'summary.json')
 if($null -eq $pp -or $null -eq $tg){throw "No PP/TG timings; inspect response.json"}
 Write-Host ("Bonsai2 / {0}: PP={1} tokens/s, TG={2} tokens/s" -f $device,$pp,$tg)
 Write-Host "Results: $run"
}finally{
 if($proc){$proc.Refresh();if(!$proc.HasExited){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue;try{$proc.WaitForExit(10000)|Out-Null}catch{}}}
}
