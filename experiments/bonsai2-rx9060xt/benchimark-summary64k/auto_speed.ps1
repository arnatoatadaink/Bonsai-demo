# Automated baseline/MTP speed benchmark, Windows PowerShell.
# Owns only the server process it starts. Requires Python3 + compatible llama-server.
param(
 [Parameter(Mandatory=$true)][string]$LlamaServer,
 [ValidateSet('all','qwen9','gemma12','gemma26')][string]$Model='all',
 [ValidateSet('both','baseline','mtp')][string]$Mode='both',
 [string]$Device='',
 [int]$Port=18080,
 [int]$DraftNMax=4,
 [int]$Repeat=3,
 [int]$StartupTimeoutSeconds=300,
 [string]$OutputRoot=''
)
$ErrorActionPreference='Stop'
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
$root=if($OutputRoot){[IO.Path]::GetFullPath($OutputRoot)}else{Join-Path $here 'results'}
$run=Join-Path $root ('run_speed_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
if(Test-Path $run){throw "Destination exists: $run"}
New-Item -ItemType Directory -Force -Path $run | Out-Null
if(!(Test-Path -LiteralPath $LlamaServer -PathType Leaf)){throw "llama-server missing: $LlamaServer"}
$LlamaServer=(Resolve-Path -LiteralPath $LlamaServer).Path
$models=@{
 qwen9=@{target='D:\lmstudio_models\unsloth\Qwen3.5-9B-MTP-GGUF\Qwen3.5-9B-UD-Q4_K_XL.gguf';draft=''}
 gemma12=@{target='D:\lmstudio_models\unsloth\gemma-4-12b-it-GGUF\gemma-4-12B-it-qat-UD-Q4_K_XL.gguf';draft='D:\lmstudio_models\unsloth\gemma-4-12b-it-GGUF\gemma-4-12B-it-Q8_0-MTP.gguf'}
 gemma26=@{target='D:\lmstudio_models\unsloth\gemma-4-26B-A4B-it-qat-GGUF\gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf';draft='D:\lmstudio_models\unsloth\gemma-4-26B-A4B-it-qat-GGUF\gemma-4-26B-A4B-it-Q8_0-MTP.gguf'}
}
$listing=(& $LlamaServer --list-devices 2>&1 | Out-String)
$listing | Set-Content -Encoding utf8 (Join-Path $run 'device-list.txt')
if(!$Device){
 $ids=@($listing -split '\r?\n' | Where-Object {$_ -match 'RX\s*9070\s*XT'} | ForEach-Object {if($_ -match '\b(Vulkan\d+)\b'){$Matches[1]}} | Select-Object -Unique)
 if($ids.Count -ne 1){throw "RX9070XT device ambiguous; see $run/device-list.txt"}
 $Device=$ids[0]
}
if(@($listing -split '\r?\n' | Where-Object {$_ -match [regex]::Escape($Device) -and $_ -match 'RX\s*9070\s*XT'}).Count -ne 1){throw "Device $Device is not uniquely RX9070XT"}
$selected=if($Model -eq 'all'){@('qwen9','gemma12','gemma26')}else{@($Model)}
$modes=if($Mode -eq 'both'){@('baseline','mtp')}else{@($Mode)}
$helpText=(& $LlamaServer --help 2>&1 | Out-String)
if($Mode -ne 'baseline'){
 foreach($flag in @('--spec-type','--spec-draft-n-max','--model-draft')){if(!$helpText.Contains($flag)){throw "MTP requested but $flag unsupported"}}
}
$manifest=[ordered]@{binary=$LlamaServer;sha256=(Get-FileHash $LlamaServer -Algorithm SHA256).Hash;device=$Device;context=65536;cache_k='q8_0';cache_v='q8_0';flash_attention='on';models=$selected;modes=$modes;draft_n_max=$DraftNMax;repetitions=$Repeat;created=(Get-Date).ToString('o')}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $run 'manifest.json')
foreach($name in $selected){
 $cfg=$models[$name]
 if(!(Test-Path -LiteralPath $cfg.target -PathType Leaf)){throw "Missing model: $($cfg.target)"}
 foreach($currentMode in $modes){
  if($currentMode -eq 'mtp' -and $cfg.draft -and !(Test-Path -LiteralPath $cfg.draft -PathType Leaf)){throw "Missing draft: $($cfg.draft)"}
  $caseDir=Join-Path $run ($name+'_'+$currentMode)
  New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
  $stdout=Join-Path $caseDir 'server.stdout.log'
  $stderr=Join-Path $caseDir 'server.stderr.log'
  $argsList=@('-m',('"' + $cfg.target + '"'),'--host','127.0.0.1','--port',"$Port",'--device',$Device,'-ngl','99','-sm','none','-c','65536','--cache-type-k','q8_0','--cache-type-v','q8_0','-fa','on','-np','1','--jinja')
  if($currentMode -eq 'mtp'){
   $argsList+=@('--spec-type','draft-mtp','--spec-draft-n-max',"$DraftNMax")
   if($cfg.draft){$argsList+=@('--model-draft',('"' + $cfg.draft + '"'))}
  }
  $argsList | Set-Content -Encoding utf8 (Join-Path $caseDir 'argv.txt')
  $proc=$null
  try{
   $tcp=New-Object System.Net.Sockets.TcpClient
   try{
    $task=$tcp.ConnectAsync('127.0.0.1',$Port)
    if($task.Wait(500) -and $tcp.Connected){throw "Port $Port already used; refusing to attach"}
   }finally{$tcp.Dispose()}
   Write-Host "Starting $name / $currentMode / $Device"
   $proc=Start-Process -FilePath $LlamaServer -ArgumentList ($argsList -join ' ') -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
   $deadline=(Get-Date).AddSeconds($StartupTimeoutSeconds);$ready=$false
   while((Get-Date) -lt $deadline){
    if($proc.HasExited){throw "Server exited ($($proc.ExitCode)): $stderr"}
    try{$health=Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 3;if($health.status -eq 'ok'){$ready=$true;break}}catch{}
    Start-Sleep -Seconds 2
   }
   if(!$ready){throw "Server startup timeout: $stderr"}
   $modelMeta=Invoke-RestMethod "http://127.0.0.1:$Port/v1/models" -TimeoutSec 15
   $modelMeta | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 (Join-Path $caseDir 'models.json')
   & python (Join-Path $here 'speed_probe.py') --base-url "http://127.0.0.1:$Port" --label ($name+'_'+$currentMode) --repeat $Repeat --output $caseDir
   if($LASTEXITCODE -ne 0){throw "Probe failed: $name / $currentMode"}
  }catch{
   $_ | Out-String | Set-Content -Encoding utf8 (Join-Path $caseDir 'failure.txt')
   throw
  }finally{
   if($proc -and !$proc.HasExited){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue;try{$proc.WaitForExit(10000)|Out-Null}catch{}}
   Start-Sleep -Seconds 3
  }
 }
}
Write-Host "Finished: $run"
