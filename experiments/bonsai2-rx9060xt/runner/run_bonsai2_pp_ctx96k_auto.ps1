# Automated 96k context / 32k PP test; PowerShell 7.
param(
 [string]$ServerPath="", [string]$ModelPath="", [string]$InputPath="",
 [ValidateSet("baseline","quick","extended","downshift","downshift-extended","midpoint","midpoint-edge","pp-tg-all","tg-anomaly-recheck","mtp-pp-tg-focus")][string]$Mode="baseline",
 [int]$Port=18082, [string]$Device="Vulkan0", [ValidateRange(1,100)][int]$Repetitions=3,
 [int]$TimeoutSec=360, [ValidateRange(32,2048)][int]$GenerateTokens=512,
 [ValidateSet("on","off")][string]$Mtp="on", [double]$TgAnomalyThreshold=38.0, [string]$OutputDir=""
)
$ErrorActionPreference="Stop"
if ($Mode -eq "mtp-pp-tg-focus" -and -not $PSBoundParameters.ContainsKey("Repetitions")) { $Repetitions=5 }
if ($TgAnomalyThreshold -le 0) { throw "TgAnomalyThreshold must be positive" }
$root=(Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$prismRoot=Join-Path $root "..\.."
if(!$ServerPath){$ServerPath=Join-Path $prismRoot "dev\llama.cpp\build-vulkan-ucrt64\bin\llama-server.exe"}
if(!$ModelPath){$ModelPath=Join-Path $prismRoot "MTP-experiment\models\Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf"}
if(!$InputPath){$InputPath=Join-Path $root "experiments\bonsai2-rx9060xt\distributed-summary-v01\dataset\prompt.txt"}
if(!$OutputDir){$OutputDir=Join-Path $root "experiments\bonsai2-rx9060xt\pp-batch-v01\results"}
foreach($f in @($ServerPath,$ModelPath,$InputPath)){if(!(Test-Path -LiteralPath $f -PathType Leaf)){throw "File missing: $f"}}
if(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue){throw "Port $Port occupied"}
$runner=Join-Path $PSScriptRoot "test_bonsai2_pp_ctx96k.ps1"
switch($Mode){
 "baseline" {$bs=@(32768);$ubs=@(512)}
 "quick" {$bs=@(32768,65536);$ubs=@(512,1024,1536)}
 "extended" {$bs=@(32768,65536,131072);$ubs=@(512,1024,1536,2048)}
 "downshift" {$bs=@(16384,32768);$ubs=@(256,512)}
 "downshift-extended" {$bs=@(8192,16384,32768);$ubs=@(128,256,512)}
 "midpoint" {$bs=@(8192,12288,16384);$ubs=@(192,256,384)}
 "midpoint-edge" {$bs=@(4096,8192);$ubs=@(192,256,384)}
 "pp-tg-all" {$bs=@(4096,8192,12288,16384,32768,65536,131072);$ubs=@(128,192,256,384,512,1024,1536,2048)}
 "tg-anomaly-recheck" {$bs=@(4096);$ubs=@(256)}
 "mtp-pp-tg-focus" {$bs=@(4096,8192,16384);$ubs=@(128,192,256,384)}
}
$out=Join-Path $OutputDir ("run_"+(Get-Date -Format "yyyyMMdd_HHmmss")+"_ctx96k_pp32k_auto")
New-Item -ItemType Directory -Force -Path $out | Out-Null
$metadata=[ordered]@{
 model_sha256=(Get-FileHash $ModelPath -Algorithm SHA256).Hash
 server_sha256=(Get-FileHash $ServerPath -Algorithm SHA256).Hash
 input_sha256=(Get-FileHash $InputPath -Algorithm SHA256).Hash
 mode=$Mode;device=$Device;context=98304;tokens=32768;repetitions=$Repetitions;generate_tokens=$GenerateTokens;tg_anomaly_threshold=$TgAnomalyThreshold
 kv="K Q8_0 / V Q4_0";flash_attention="on";mtp=$Mtp;spec_type=$(if($Mtp -eq "on"){"draft-mtp"}else{"none"});spec_draft_n_max=$(if($Mtp -eq "on"){2}else{0});fit="off";parallel=1
 batch_values=$bs;ubatch_values=$ubs;order="ascending batch then ascending ubatch"
}
$metadata|ConvertTo-Json|Set-Content (Join-Path $out "manifest.json")
$rows=@();$trialRows=@()
foreach($b in $bs){foreach($ub in $ubs){
 $id=("b{0}_ub{1}" -f $b,$ub);$dir=Join-Path $out $id
 New-Item -ItemType Directory -Force -Path $dir|Out-Null
 $stdout=Join-Path $dir "server.stdout.log";$stderr=Join-Path $dir "server.stderr.log"
 $argsList=@("-m",$ModelPath,"--device",$Device,"-ngl","99","-sm","none","-c","98304",
 "-b",[string]$b,"-ub",[string]$ub,"-fa","on","-ctk","q8_0","-ctv","q4_0",
 "-np","1","--ctx-checkpoints","0","--fit","off","--dry-multiplier","0",
 "--host","127.0.0.1","--port",[string]$Port)
 if($Mtp -eq "on"){$argsList+=@("--spec-type","draft-mtp","--spec-draft-n-max","2")}
 $argsList|ConvertTo-Json|Set-Content (Join-Path $dir "arguments.json")
 $status="ERROR";$avg=$null;$tgAvg=$null;$reason="";$proc=$null
 try{
  if(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue){throw "Port occupied"}
  $psi=[Diagnostics.ProcessStartInfo]::new()
  $psi.FileName=(Resolve-Path $ServerPath).Path
  $psi.WorkingDirectory=Split-Path $ServerPath
  $psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  foreach($a in $argsList){[void]$psi.ArgumentList.Add($a)}
  $proc=[Diagnostics.Process]::Start($psi)
  $o=[IO.File]::Create($stdout);$e=[IO.File]::Create($stderr)
  try{
   $ot=$proc.StandardOutput.BaseStream.CopyToAsync($o)
   $et=$proc.StandardError.BaseStream.CopyToAsync($e)
   $limit=(Get-Date).AddSeconds($TimeoutSec);$ready=$false
   while((Get-Date) -lt $limit){
    $proc.Refresh();if($proc.HasExited){throw "Server exited during load: $($proc.ExitCode)"}
    try{$h=Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 3;if($h.status -eq "ok"){$ready=$true;break}}catch{}
    Start-Sleep -Seconds 2
   }
   if(!$ready){throw "Health timeout"}
   & $runner -InputPath $InputPath -ServerUrl "http://127.0.0.1:$Port" -ContextSize 98304 -PromptTokens 32768 -Repetitions $Repetitions -GenerateTokens $GenerateTokens -OutputDir $dir
   $runs=@(Get-ChildItem $dir -Directory -Filter "run_*"|Sort-Object LastWriteTime -Descending)
   if(!$runs.Count){throw "No child summary"}
   $trials=@(Import-Csv (Join-Path $runs[0].FullName "summary.csv"))
   $valid=@($trials|Where-Object {$_.status -eq "OK" -and [double]$_.prompt_per_second -gt 0})
   if($valid.Count -ne $Repetitions){throw "Full prefill count $($valid.Count)/$Repetitions"}
   foreach($t in $trials) {
    $tgv=0.0
    $hasTG=[double]::TryParse([string]$t.tg_per_second,[ref]$tgv)
    $trialRows+= [pscustomobject]@{
      case=$id;batch=$b;ubatch=$ub;trial=$t.trial;status=$t.status
      pp_tok_s=$t.prompt_per_second;tg_tok_s=$t.tg_per_second
      draft_n=$t.draft_n;draft_accepted=$t.draft_accepted;draft_acceptance_pct=$t.draft_acceptance_pct
      tg_anomaly=($t.status -eq "OK" -and $hasTG -and $tgv -lt $TgAnomalyThreshold)
    }
   }
   $avg=($valid|Measure-Object prompt_per_second -Average).Average
   $tgAvg=($valid|Measure-Object tg_per_second -Average).Average;$status="OK"
  }finally{
   if($proc -and !$proc.HasExited){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue;$proc.WaitForExit(10000)|Out-Null}
   try{$ot.Wait(10000)|Out-Null;$et.Wait(10000)|Out-Null}catch{}
   $o.Dispose();$e.Dispose()
  }
 }catch{$reason=$_.Exception.Message;$reason|Set-Content (Join-Path $dir "error.txt");Write-Warning $reason}
 finally{if($proc -and !$proc.HasExited){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue}}
 $own=@($trialRows|Where-Object {$_.case -eq $id -and $_.status -eq "OK"})
 $bad=@($own|Where-Object {$_.tg_anomaly -eq $true}).Count
 $tgMin=if($own.Count){($own|Measure-Object tg_tok_s -Minimum).Minimum}else{$null}
 $acceptMean=if(@($own|Where-Object {$_.draft_acceptance_pct -ne ""}).Count){(@($own|Where-Object {$_.draft_acceptance_pct -ne ""})|Measure-Object draft_acceptance_pct -Average).Average}else{$null}
 $rows+= [pscustomobject]@{case=$id;batch=$b;ubatch=$ub;context=98304;prompt=32768;status=$status;avg_pp_tok_s=$avg;avg_tg_tok_s=$tgAvg;min_tg_tok_s=$tgMin;tg_anomalies=$bad;valid_trials=$own.Count;tg_anomaly_rate=$(if($own.Count){$bad/$own.Count}else{$null});mean_draft_acceptance_pct=$acceptMean;error=$reason}
 $rows|Export-Csv (Join-Path $out "summary.csv") -NoTypeInformation -Encoding utf8
 $trialRows|Export-Csv (Join-Path $out "trials.csv") -NoTypeInformation -Encoding utf8
 Write-Host "$id : $status PP=$avg TG=$tgAvg"
 Start-Sleep -Seconds 2
}}
Write-Host "Results: $out"
if(@($rows|Where-Object status -ne "OK").Count){throw "Some cases failed; inspect summary.csv"}
