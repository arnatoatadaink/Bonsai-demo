# Sequential alternating Bonsai2 RX9060XT / Gemma4 RX9070XT PP+TG validation.
# PowerShell 7; no concurrent GPU work. Existing dataset and child timing runner.
[CmdletBinding()]
param(
 [string]$ServerPath="",
 [string]$BonsaiModelPath="",
 [Parameter(Mandatory)][string]$GemmaModelPath,
 [Parameter(Mandatory)][string]$GemmaMtpPath,
 [string]$InputPath="",
 [string]$OutputDir="",
 [ValidateRange(1,100)][int]$Rounds=2,
 [switch]$GemmaUbatchCompare,
 [ValidateRange(32,2048)][int]$GenerateTokens=512,
 [int]$Port=18082,
 [ValidateRange(60,1800)][int]$StartupTimeoutSec=360,
 [ValidateRange(0,600)][int]$BetweenRunsSec=15
)
$ErrorActionPreference="Stop"
$repo=(Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$base=Join-Path $repo "..\.."
if(!$ServerPath){$ServerPath=Join-Path $base "dev\llama.cpp\build-vulkan-ucrt64\bin\llama-server.exe"}
if(!$BonsaiModelPath){$BonsaiModelPath=Join-Path $base "MTP-experiment\models\Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf"}
if(!$InputPath){$InputPath=Join-Path $repo "experiments\bonsai2-rx9060xt\distributed-summary-v01\dataset\prompt.txt"}
if(!$OutputDir){$OutputDir=Join-Path $repo "experiments\bonsai2-rx9060xt\alternating-pp-tg\results"}
foreach($file in @($ServerPath,$BonsaiModelPath,$GemmaModelPath,$GemmaMtpPath,$InputPath)){
 if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw "Required file not found: $file"}
}
$child=Join-Path $PSScriptRoot "test_bonsai2_pp_ctx96k.ps1"
if(!(Test-Path -LiteralPath $child)){throw "Missing child runner: $child"}
function PortOccupied([int]$p){
 return [bool]@(Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue).Count
}
if(PortOccupied $Port){throw "Port $Port is in use. Stop the existing server."}
if($GemmaUbatchCompare -and -not $PSBoundParameters.ContainsKey("Rounds")){$Rounds=4}
$gemmaSchedule=@(1536,256,256,1536)
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$out=Join-Path $OutputDir "alternating_$stamp"
New-Item -ItemType Directory -Path $out -Force|Out-Null
$profiles=@(
 [pscustomobject]@{
  name="bonsai2";device="Vulkan0";model=$BonsaiModelPath;draft="";ctx=98304
  batch=4096;ubatch=256;k="q8_0";v="q4_0";threads=4;layers="all";draftN=2
 },
 [pscustomobject]@{
  name="gemma4";device="Vulkan1";model=$GemmaModelPath;draft=$GemmaMtpPath;ctx=65536
  batch=4096;ubatch=1536;k="q8_0";v="q8_0";threads=2;layers="61";draftN=1
 }
)
$manifest=[ordered]@{
 order="Bonsai2 then Gemma4, repeated by round";rounds=$Rounds;gemma_ubatch_compare=$GemmaUbatchCompare.IsPresent;gemma_ubatch_sequence=$(if($GemmaUbatchCompare){@(1..$Rounds | ForEach-Object {$gemmaSchedule[($_-1)%4]})}else{@(1536)})
 prompt_tokens=32768;generate_tokens=$GenerateTokens;between_runs_sec=$BetweenRunsSec
 server_sha256=(Get-FileHash -LiteralPath $ServerPath -Algorithm SHA256).Hash
 input_sha256=(Get-FileHash -LiteralPath $InputPath -Algorithm SHA256).Hash
 profiles=@($profiles | ForEach-Object {
  [ordered]@{name=$_.name;device=$_.device;context=$_.ctx;batch=$_.batch;ubatch=$_.ubatch;kv="$($_.k)/$($_.v)";draft_n=$_.draftN
    model_sha256=(Get-FileHash -LiteralPath $_.model -Algorithm SHA256).Hash
    draft_sha256=$(if($_.draft){(Get-FileHash -LiteralPath $_.draft -Algorithm SHA256).Hash}else{$null})}
 })
 note="Gemma uses the same raw text file, but each model tokenizes it independently. Exactly 32768 tokens per model. Not identical token IDs."
}
$manifest|ConvertTo-Json -Depth 12|Set-Content (Join-Path $out "manifest.json") -Encoding utf8
$rows=@()
for($round=1;$round -le $Rounds;$round++){
 foreach($p in $profiles){
  $caseUb=if($p.name -eq "gemma4" -and $GemmaUbatchCompare){$gemmaSchedule[($round-1)%4]}else{$p.ubatch}
  $id="{0}_round{1}_ub{2}" -f $p.name,$round,$caseUb
  $dir=Join-Path $out $id
  New-Item -ItemType Directory -Path $dir -Force|Out-Null
  $argsList=@("--model",$p.model,"--device",$p.device,"--split-mode","none",
    "--gpu-layers",[string]$p.layers,"--ctx-size",[string]$p.ctx,
    "--cache-type-k",$p.k,"--cache-type-v",$p.v,"--threads",[string]$p.threads,
    "--batch-size",[string]$p.batch,"--ubatch-size",[string]$caseUb,
    "--parallel","1","--flash-attn","on","--ctx-checkpoints","0",
    "--spec-type","draft-mtp","--spec-draft-n-max",[string]$p.draftN,
    "--jinja","--host","127.0.0.1","--port",[string]$Port,"--load-mode","none")
  if($p.name -eq "gemma4"){
   $argsList+=@("--model-draft",$p.draft,"--spec-draft-device",$p.device,"--fit","off")
  }
  # Bonsai is also kept on a fixed-fit/no-checkpoint path for apples-to-apples runtime stability.
  if($p.name -eq "bonsai2"){$argsList+=@("--fit","off","--dry-multiplier","0")}
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
   & $child -InputPath $InputPath -ServerUrl "http://127.0.0.1:$Port" -ContextSize $p.ctx -PromptTokens 32768 -GenerateTokens $GenerateTokens -Repetitions 1 -OutputDir $dir
   $runs=@(Get-ChildItem -LiteralPath $dir -Directory -Filter "run_*"|Sort-Object LastWriteTime -Descending)
   if(!$runs.Count){throw "Missing child output"}
   $trials=@(Import-Csv (Join-Path $runs[0].FullName "summary.csv"))
   if($trials.Count -ne 1 -or $trials[0].status -ne "OK"){throw "Child timing not valid"}
   $pp=[double]$trials[0].prompt_per_second
   $tg=[double]$trials[0].tg_per_second
   $draft=$trials[0].draft_acceptance_pct
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
  $rows+=[pscustomobject]@{round=$round;case=$id;model=$p.name;gpu=$p.device;batch=$p.batch;ubatch=$caseUb
    context=$p.ctx;prompt_tokens=32768;generate_tokens=$GenerateTokens;status=$status
    pp_tok_s=$pp;tg_tok_s=$tg;draft_acceptance_pct=$draft;error=$reason}
  $rows|Export-Csv (Join-Path $out "summary.csv") -NoTypeInformation -Encoding utf8
  Write-Host "$id : $status PP=$pp TG=$tg"
  if($BetweenRunsSec -gt 0){Start-Sleep -Seconds $BetweenRunsSec}
 }
}
Write-Host "Results: $out"
if(@($rows|Where-Object {$_.status -ne "OK"}).Count){throw "Some test cases failed. Inspect summary.csv."}
