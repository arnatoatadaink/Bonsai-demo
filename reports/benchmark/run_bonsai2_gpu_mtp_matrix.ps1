# Four-way Bonsai2 27B GPU x MTP ON/OFF reproducibility matrix.
# PowerShell 7; no concurrent GPU work. Existing dataset and child timing runner.
[CmdletBinding()]
param(
 [string]$ServerPath="",
 [string]$BonsaiModelPath="",
 [string]$InputPath="",
 [string]$OutputDir="",
 [ValidateRange(1,100)][int]$Repetitions=3,
 [ValidateRange(32,2048)][int]$GenerateTokens=512,
 [int]$Port=18082,
 [ValidateRange(60,1800)][int]$StartupTimeoutSec=360,
 [ValidateRange(0,600)][int]$BetweenRunsSec=15
)
$ErrorActionPreference="Stop"
$repo=(Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$base=Join-Path $repo "..\.."
if(!$ServerPath){throw "Specify -ServerPath explicitly (no machine-specific default)."}
if(!$BonsaiModelPath){throw "Specify -BonsaiModelPath explicitly (verified MTP GGUF required)."}
if(!$InputPath){throw "Specify -InputPath explicitly (original dataset required)."}
if(!$OutputDir){$OutputDir=Join-Path $repo "experiments\bonsai2-rx9060xt\gpu-mtp-matrix\results"}
foreach($file in @($ServerPath,$BonsaiModelPath,$InputPath)){
 if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw "Required file not found: $file"}
}
$child=Join-Path $PSScriptRoot "test_bonsai2_pp_ctx96k.ps1"
if(!(Test-Path -LiteralPath $child)){throw "Missing child runner: $child"}
function PortOccupied([int]$p){
 return [bool]@(Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue).Count
}
if(PortOccupied $Port){throw "Port $Port is in use. Stop the existing server."}
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$out=Join-Path $OutputDir "matrix_$stamp"
New-Item -ItemType Directory -Path $out -Force|Out-Null
$profiles=@(
 [pscustomobject]@{name="rx9060_mtp_off";device="Vulkan0";model=$BonsaiModelPath;ctx=98304;batch=4096;ubatch=256;k="q8_0";v="q4_0";threads=4;layers="99";mtp=$false;draftN=0},
 [pscustomobject]@{name="rx9070_mtp_off";device="Vulkan1";model=$BonsaiModelPath;ctx=98304;batch=4096;ubatch=256;k="q8_0";v="q4_0";threads=4;layers="99";mtp=$false;draftN=0},
 [pscustomobject]@{name="rx9060_mtp_on";device="Vulkan0";model=$BonsaiModelPath;ctx=98304;batch=4096;ubatch=256;k="q8_0";v="q4_0";threads=4;layers="99";mtp=$true;draftN=2},
 [pscustomobject]@{name="rx9070_mtp_on";device="Vulkan1";model=$BonsaiModelPath;ctx=98304;batch=4096;ubatch=256;k="q8_0";v="q4_0";threads=4;layers="99";mtp=$true;draftN=2}
)
$manifest=[ordered]@{
 order="RX9060 MTP off, RX9070 MTP off, RX9060 MTP on, RX9070 MTP on; fresh server per case";repetitions=$Repetitions
 prompt_tokens=32768;generate_tokens=$GenerateTokens;between_runs_sec=$BetweenRunsSec
 server_sha256=(Get-FileHash -LiteralPath $ServerPath -Algorithm SHA256).Hash
 input_sha256=(Get-FileHash -LiteralPath $InputPath -Algorithm SHA256).Hash
 profiles=@($profiles | ForEach-Object {
  [ordered]@{name=$_.name;device=$_.device;context=$_.ctx;batch=$_.batch;ubatch=$_.ubatch;kv="$($_.k)/$($_.v)";draft_n=$_.draftN;mtp=$_.mtp
    model_sha256=(Get-FileHash -LiteralPath $_.model -Algorithm SHA256).Hash
}
 })
 note="Same Bonsai GGUF, same prompt token IDs, context, KV and batch/ubatch. Only GPU and MTP vary. Verify GPU device IDs with --list-devices. Each case makes Repetitions completion requests in one server start."
}
$manifest|ConvertTo-Json -Depth 12|Set-Content (Join-Path $out "manifest.json") -Encoding utf8
$rows=@()
foreach($p in $profiles){
  $caseUb=$p.ubatch
  $id=$p.name
  $dir=Join-Path $out $id
  New-Item -ItemType Directory -Path $dir -Force|Out-Null
  $argsList=@("--model",$p.model,"--device",$p.device,"--split-mode","none",
    "--gpu-layers",[string]$p.layers,"--ctx-size",[string]$p.ctx,
    "--cache-type-k",$p.k,"--cache-type-v",$p.v,"--threads",[string]$p.threads,
    "--batch-size",[string]$p.batch,"--ubatch-size",[string]$caseUb,
    "--parallel","1","--flash-attn","on","--ctx-checkpoints","0",
    "--fit","off","--dry-multiplier","0",
    "--host","127.0.0.1","--port",[string]$Port)
  if($p.mtp){$argsList+=@("--spec-type","draft-mtp","--spec-draft-n-max",[string]$p.draftN)}
  $argsList|ConvertTo-Json -Depth 5|Set-Content (Join-Path $dir "arguments.json")
  $proc=$null;$stdout=$null;$stderr=$null;$ot=$null;$et=$null
  $status="ERROR";$pp=$null;$tg=$null;$draft=$null;$reason=""
  try{
   if(PortOccupied $Port){throw "Port $Port occupied before $id"}
   $psi=[Diagnostics.ProcessStartInfo]::new()
   $psi.FileName=(Resolve-Path -LiteralPath $ServerPath).Path
   $psi.WorkingDirectory=Split-Path -Parent $ServerPath
   $psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
   foreach($a in $argsList){[void]$psi.ArgumentList.Add($a)}
   $start=(Get-Date).ToString("o")
   $proc=[Diagnostics.Process]::Start($psi)
   $stdout=[IO.File]::Create((Join-Path $dir "server.stdout.log"))
   $stderr=[IO.File]::Create((Join-Path $dir "server.stderr.log"))
   $ot=$proc.StandardOutput.BaseStream.CopyToAsync($stdout)
   $et=$proc.StandardError.BaseStream.CopyToAsync($stderr)
   $deadline=(Get-Date).AddSeconds($StartupTimeoutSec);$ready=$false
   while((Get-Date) -lt $deadline){
    $proc.Refresh()
    if($proc.HasExited){throw "Server quit during load, code=$($proc.ExitCode)"}
    try{
     $health=Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 3
     if($health.status -eq "ok"){$ready=$true;break}
    }catch{}
    Start-Sleep -Seconds 2
   }
   if(!$ready){throw "Startup health timeout"}
   & $child -InputPath $InputPath -ServerUrl "http://127.0.0.1:$Port" -ContextSize $p.ctx -PromptTokens 32768 -GenerateTokens $GenerateTokens -Repetitions $Repetitions -OutputDir $dir
   $runs=@(Get-ChildItem -LiteralPath $dir -Directory -Filter "run_*"|Sort-Object LastWriteTime -Descending)
   if(!$runs.Count){throw "Missing child output"}
   $trials=@(Import-Csv (Join-Path $runs[0].FullName "summary.csv"))
   $valid=@($trials|Where-Object {$_.status -eq "OK"})
   if($valid.Count -ne $Repetitions){throw "Valid trials $($valid.Count)/$Repetitions"}
   $pp=($valid|Measure-Object prompt_per_second -Average).Average
   $tg=($valid|Measure-Object tg_per_second -Average).Average
   $draft=($valid|Where-Object {$_.draft_acceptance_pct -ne ""}|Measure-Object draft_acceptance_pct -Average).Average
   $status="OK"
  }catch{
   $reason=$_.Exception.Message
   $reason|Set-Content (Join-Path $dir "error.txt")
   Write-Warning "$id : $reason"
  }finally{
   if($proc){
    try{if(!$proc.HasExited){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue}}catch{}
    try{$proc.WaitForExit(10000)|Out-Null}catch{}
   }
   try{if($ot){$ot.Wait(10000)|Out-Null};if($et){$et.Wait(10000)|Out-Null}}catch{}
   if($stdout){$stdout.Dispose()}
   if($stderr){$stderr.Dispose()}
  }
  $rows+=[pscustomobject]@{case=$id;model="Bonsai2-27B";gpu=$p.device;mtp=$p.mtp;repetitions=$Repetitions;batch=$p.batch;ubatch=$caseUb
    context=$p.ctx;prompt_tokens=32768;generate_tokens=$GenerateTokens;status=$status
    pp_tok_s=$pp;tg_tok_s=$tg;draft_acceptance_pct=$draft;error=$reason}
  $rows|Export-Csv (Join-Path $out "summary.csv") -NoTypeInformation -Encoding utf8
  Write-Host "$id : $status PP=$pp TG=$tg"
  if($BetweenRunsSec -gt 0){Start-Sleep -Seconds $BetweenRunsSec}
 }
Write-Host "Results: $out"
if(@($rows|Where-Object {$_.status -ne "OK"}).Count){throw "Some test cases failed. Inspect summary.csv."}
