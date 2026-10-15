# MTP load/unload stability: sequential server restarts, isolated per trial.
# No external process is killed. PowerShell 5.1 compatible.
param(
 [Parameter(Mandatory=$true)][string]$LlamaServer,
 [ValidateSet('all','gemma12','gemma26')][string]$Model='all',
 [ValidateSet('9060','9070')][string]$Gpu='9060',
 [int]$Repeat=10,
 [int]$Context=4096,
 [int]$DraftNMax=2,
 [int]$Port=18080,
 [int]$StartupTimeoutSeconds=240,
 [int]$CooldownSeconds=5,
 [switch]$ProbeInference,
 [string]$OutputRoot=''
)
$ErrorActionPreference='Stop'
if($Repeat -lt 1 -or $Repeat -gt 100 -or $Context -lt 1024 -or $CooldownSeconds -lt 0){throw 'Invalid test parameters'}
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
$root=if($OutputRoot){[IO.Path]::GetFullPath($OutputRoot)}else{Join-Path $here 'results'}
$run=Join-Path $root ('run_mtp_restart_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
if(Test-Path -LiteralPath $run){throw "Run exists: $run"}
New-Item -ItemType Directory -Force -Path $run | Out-Null
if(!(Test-Path -LiteralPath $LlamaServer -PathType Leaf)){throw "Missing llama-server: $LlamaServer"}
$exe=(Resolve-Path -LiteralPath $LlamaServer).Path
$cfg=@{
 gemma12=@{target='D:\lmstudio_models\unsloth\gemma-4-12b-it-GGUF\gemma-4-12B-it-qat-UD-Q4_K_XL.gguf';draft='D:\lmstudio_models\unsloth\gemma-4-12b-it-GGUF\gemma-4-12B-it-Q8_0-MTP.gguf'}
 gemma26=@{target='D:\lmstudio_models\unsloth\gemma-4-26B-A4B-it-qat-GGUF\gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf';draft='D:\lmstudio_models\unsloth\gemma-4-26B-A4B-it-qat-GGUF\gemma-4-26B-A4B-it-Q8_0-MTP.gguf'}
}
$names=if($Model -eq 'all'){@('gemma12','gemma26')}else{@($Model)}
foreach($name in $names){foreach($p in @($cfg[$name].target,$cfg[$name].draft)){if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw "GGUF missing: $p"}}}
$deviceList=(& $exe --list-devices 2>&1 | Out-String)
$deviceList | Set-Content -Encoding UTF8 (Join-Path $run 'device-list.txt')
$pattern=if($Gpu -eq '9060'){'RX\s*9060\s*XT'}else{'RX\s*9070\s*XT'}
$ids=@($deviceList -split '\r?\n' | Where-Object {$_ -match $pattern} | ForEach-Object {if($_ -match '(?i)\b(Vulkan\d+)\b'){$Matches[1]}} | Select-Object -Unique)
if($ids.Count -ne 1){throw "Cannot uniquely resolve GPU RX $Gpu XT; inspect device-list.txt"}
$device=$ids[0]
$helpText=(& $exe --help 2>&1 | Out-String)
foreach($flag in @('--ctx-checkpoints','--fit','--spec-type','--spec-draft-n-max','--spec-draft-device')){
 if(!$helpText.Contains($flag)){throw "Required flag missing from llama-server --help: $flag"}
}
$draftFlag=if($helpText.Contains('--spec-draft-model')){'--spec-draft-model'}elseif($helpText.Contains('--model-draft')){'--model-draft'}else{throw 'Draft-model flag unsupported'}
$draftNgl=if($helpText.Contains('--spec-draft-ngl')){'--spec-draft-ngl'}elseif($helpText.Contains('--n-gpu-layers-draft')){'--n-gpu-layers-draft'}else{''}
$manifest=[ordered]@{
 purpose='MTP model load/release restarts, not throughput benchmark'; models=$names; repeats_per_model=$Repeat
 gpu="RX $Gpu XT";device=$device;binary=$exe;binary_sha256=(Get-FileHash $exe -Algorithm SHA256).Hash
 context=$Context;kv_k='q8_0';kv_v='q8_0';fa='on';checkpoints=0;fit='off'
 draft_n_max=$DraftNMax;inference_probe=[bool]$ProbeInference;startup_timeout_sec=$StartupTimeoutSeconds
 draft_flag=$draftFlag;started=(Get-Date).ToString('o')
}
$manifest|ConvertTo-Json -Depth 6|Set-Content -Encoding UTF8 (Join-Path $run 'manifest.json')
$rows=New-Object System.Collections.Generic.List[object]
function SaveRows {
 if($rows.Count -gt 0){$rows|Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $run 'trials.csv')}
}
# Refuse an occupied port before the first trial.
$existing=Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if($existing){throw "Port $Port already has listener(s); test will not attach to or terminate them."}
foreach($name in $names){
 for($i=1;$i -le $Repeat;$i++){
  $trialDir=Join-Path $run ($name+'\restart_'+('{0:d2}' -f $i))
  New-Item -ItemType Directory -Force -Path $trialDir | Out-Null
  $stdout=Join-Path $trialDir 'server.stdout.log'
  $stderr=Join-Path $trialDir 'server.stderr.log'
  $target=$cfg[$name].target;$draft=$cfg[$name].draft
  $argv=@('-m',('"'+$target+'"'),'--host','127.0.0.1','--port',"$Port",
   '--device',$device,'-ngl','99','-sm','none','-c',"$Context",
   '--cache-type-k','q8_0','--cache-type-v','q8_0','-fa','on','-np','1','--jinja',
   '--ctx-checkpoints','0','--fit','off','--spec-type','draft-mtp',
   '--spec-draft-n-max',"$DraftNMax",$draftFlag,('"'+$draft+'"'),
   '--spec-draft-device',$device)
  if($draftNgl){$argv+=@($draftNgl,'99')}
  $argv -join ' ' | Set-Content -Encoding UTF8 (Join-Path $trialDir 'command.txt')
  $proc=$null;$ok=$false;$probeOK=$false;$why='';$exitCode='';$started=Get-Date
  try{
   if(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue){throw "Port $Port occupied"}
   Write-Host "[$name $i/$Repeat] loading MTP on $device ..."
   $proc=Start-Process -FilePath $exe -ArgumentList ($argv -join ' ') -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
   $deadline=(Get-Date).AddSeconds($StartupTimeoutSeconds)
   while((Get-Date) -lt $deadline){
    $proc.Refresh()
    if($proc.HasExited){$exitCode=$proc.ExitCode;throw "llama-server exited during initialization: $exitCode"}
    try{
     $health=Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 3
     if($health.status -eq 'ok'){$ok=$true;break}
    }catch{}
    Start-Sleep -Seconds 2
   }
   if(!$ok){throw 'Health readiness timeout'}
   $metadata=Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/models" -TimeoutSec 15
   $metadata|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 (Join-Path $trialDir 'models.json')
   if($ProbeInference){
    $body=@{messages=@(@{role='user';content='Reply with the word OK.'});max_tokens=16;temperature=0;stream=$false}|ConvertTo-Json -Depth 8
    $resp=Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat/completions" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json' -TimeoutSec 120
    $resp|ConvertTo-Json -Depth 20|Set-Content -Encoding UTF8 (Join-Path $trialDir 'probe.json')
    $probeOK=$true
   }
  }catch{
   $why=$_.Exception.Message
   $why|Set-Content -Encoding UTF8 (Join-Path $trialDir 'failure.txt')
   Write-Warning "[$name $i] $why"
  }finally{
   if($proc){
    $proc.Refresh()
    if(!$proc.HasExited){
     # Forcefully terminate *only our child*; this exercises OS teardown,
     # not graceful llama-server shutdown.
     Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
     try{$proc.WaitForExit(10000)|Out-Null}catch{}
    }
    $proc.Refresh()
    if($proc.HasExited){$exitCode=$proc.ExitCode}
   }
   $elapsed=[math]::Round(((Get-Date)-$started).TotalSeconds,2)
   $rows.Add([pscustomobject]@{model=$name;iteration=$i;ready=$ok;probe_ok=$probeOK;status=$(if($ok -and (!$ProbeInference -or $probeOK)){'PASS'}else{'FAIL'});elapsed_sec=$elapsed;exit_code=$exitCode;error=$why;trial_dir=$trialDir})
   SaveRows
   Start-Sleep -Seconds $CooldownSeconds
  }
 }
}
$summary=@($names|ForEach-Object{
 $n=$_;$subset=@($rows|Where-Object {$_.model -eq $n});[pscustomobject]@{model=$n;attempts=$subset.Count;pass=@($subset|Where-Object {$_.status -eq 'PASS'}).Count;fail=@($subset|Where-Object {$_.status -eq 'FAIL'}).Count}
})
$summary|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 (Join-Path $run 'summary.json')
$summary|Format-Table -AutoSize
Write-Host "Saved: $run"
if(@($rows|Where-Object {$_.status -eq 'FAIL'}).Count -gt 0){exit 2}
