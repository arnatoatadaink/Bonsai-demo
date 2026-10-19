# Bonsai2-27B: RX9060XT/RX9070XT x MTP off/on x 3 runs; Windows PowerShell 5.1
# Server settings follow the supplied llama_bonsai2(2).ps1; only device/MTP changes.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$LlamaServer,
 [Parameter(Mandatory=$true)][string]$ModelPath,
 [Parameter(Mandatory=$true)][string]$PromptPath,
 [string]$OutputDir=(Join-Path $PSScriptRoot 'results_4way'),
 [int]$Port=8078,
 [int]$Repetitions=3,
 [int]$PromptTargetTokens=32768,
 [int]$MaxOutputTokens=512,
 [int]$StartupTimeoutSec=300,
 [int]$RequestTimeoutSec=1200
)
$ErrorActionPreference='Stop'
if($Repetitions -ne 3){throw 'Protocol requires exactly 3 runs per condition.'}
foreach($path in @($LlamaServer,$ModelPath,$PromptPath)){
 if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing file: $path"}
}
$exe=(Resolve-Path -LiteralPath $LlamaServer).Path
$model=(Resolve-Path -LiteralPath $ModelPath).Path
$promptFile=(Resolve-Path -LiteralPath $PromptPath).Path
$source=[IO.File]::ReadAllText($promptFile,[Text.Encoding]::UTF8)
if($source.Length -lt 10000){throw 'Dataset is too small for the expected 32K prompt.'}
$run=Join-Path $OutputDir (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Force -Path $run|Out-Null
$manifest=[ordered]@{
 protocol='Bonsai2-27B 4x3 Vulkan MTP comparison';runs_per_condition=3
 timestamp=(Get-Date).ToString('o');model_name=[IO.Path]::GetFileName($model)
 model_sha256=(Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash
 binary_sha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
 dataset_name=[IO.Path]::GetFileName($promptFile)
 dataset_sha256=(Get-FileHash -LiteralPath $promptFile -Algorithm SHA256).Hash
 context=98304;batch=4096;ubatch=256;kv_k='q8_0';kv_v='q4_0'
 threads=4;parallel=1;flash_attention='on';ctx_checkpoints=0
 load_mode='none';mtp_draft_n_max=2;prompt_target=$PromptTargetTokens
}
$manifest|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 (Join-Path $run 'manifest.json')
function Capture([string[]]$cmd,[string]$label){
 $out=Join-Path $run "$label.stdout.log";$err=Join-Path $run "$label.stderr.log"
 $argLine=($cmd -join ' ')
 $p=Start-Process -FilePath $exe -ArgumentList $argLine -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
 if($p.ExitCode -ne 0){throw "$label failed: $($p.ExitCode). See $err"}
 return (Get-Content $out -Raw)+(Get-Content $err -Raw)
}
$null=Capture @('--version') 'version'
$deviceText=Capture @('--list-devices') 'devices'
function FindDevice([string]$name){
 $pat=(($name -split '\s+')|ForEach-Object{[regex]::Escape($_)}) -join '\s*'
 $ids=@($deviceText -split '\r?\n' | Where-Object {$_ -match $pat} |
  ForEach-Object {if($_ -match '\b(Vulkan\d+)\b'){$Matches[1]}} | Select-Object -Unique)
 if($ids.Count -ne 1){throw "Cannot identify $name uniquely. See devices logs."}
 return $ids[0]
}
$gpu=@(
 @{name='RX 9060 XT';device=(FindDevice 'RX 9060 XT')},
 @{name='RX 9070 XT';device=(FindDevice 'RX 9070 XT')}
)
function Post([string]$route,[object]$body,[int]$timeout){
 $json=$body|ConvertTo-Json -Depth 12 -Compress
 Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$Port$route" -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec $timeout
}
function StopServer($p){
 if($null -ne $p){try{$p.Refresh();if(-not $p.HasExited){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue;$p.WaitForExit(10000)|Out-Null}}catch{}}
 Start-Sleep -Seconds 2
}
function StartServer($g,[bool]$mtp,[string]$dir){
 if(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue){throw "Port $Port is in use"}
 $args=@('--model',$model,'--device',$g.device,'--split-mode','none','--gpu-layers','all',
  '--ctx-size','98304','--cache-type-k','q8_0','--cache-type-v','q4_0',
  '--threads','4','--batch-size','4096','--ubatch-size','256',
  '--parallel','1','--flash-attn','on','--ctx-checkpoints','0',
  '--jinja','--host','127.0.0.1','--port',"$Port",'--load-mode','none')
 if($mtp){$args+=@('--spec-type','draft-mtp','--spec-draft-n-max','2')}
 $line=($args|ForEach-Object{if($_ -match '\s'){'"'+$_+'"'}else{$_}})-join ' '
 $line|Set-Content -Encoding UTF8 (Join-Path $dir 'server_args.txt')
 $p=$null
 try{
  $p=Start-Process -FilePath $exe -ArgumentList $line -PassThru -RedirectStandardOutput (Join-Path $dir 'server.stdout.log') -RedirectStandardError (Join-Path $dir 'server.stderr.log')
  $deadline=(Get-Date).AddSeconds($StartupTimeoutSec)
  while((Get-Date) -lt $deadline){
   $p.Refresh()
   if($p.HasExited){throw "Server exited: $($p.ExitCode)"}
   try{$health=Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 5;if($health.status -eq 'ok'){return $p}}catch{}
   Start-Sleep -Seconds 2
  }
  throw 'Server startup timeout'
 }catch{StopServer $p;throw}
}
function Prefix32K([string]$txt,[int]$target){
 $lo=1000;$hi=$txt.Length;$best=$null;$n=0
 for($i=0;$i -lt 19 -and $lo -le $hi;$i++){
  $mid=[int][math]::Floor(($lo+$hi)/2)
  if($mid -lt $txt.Length -and [char]::IsHighSurrogate($txt[$mid-1])){$mid--}
  $sub=$txt.Substring(0,$mid)
  $tok=Post '/tokenize' @{content=$sub;add_special=$false} 240
  $count=@($tok.tokens).Count
  if($count -le $target){$best=$sub;$n=$count;$lo=$mid+1}else{$hi=$mid-1}
 }
 if($null -eq $best -or $n -lt ($target-256)){throw "Failed to prepare 32K prompt: count=$n"}
 return @{text=$best;tokens=$n}
}
# Three occurrences per condition; alternating order moderates heat effects.
$plan=@(
 @(0,$false),@(1,$false),@(0,$true),@(1,$true),
 @(1,$true),@(0,$true),@(1,$false),@(0,$false),
 @(0,$false),@(1,$false),@(0,$true),@(1,$true)
)
$records=New-Object System.Collections.Generic.List[object]
$prefix=$null
for($i=0;$i -lt $plan.Count;$i++){
 $g=$gpu[[int]$plan[$i][0]];$mtp=[bool]$plan[$i][1]
 $mode=if($mtp){'ON'}else{'OFF'}
 $key="$($g.name.Replace(' ',''))_MTP$mode"
 $repeat=1+@($records|Where-Object{$_.condition -eq $key}).Count
 $dir=Join-Path $run ('{0:D2}_{1}_r{2}' -f ($i+1),$key,$repeat)
 New-Item -ItemType Directory -Force -Path $dir|Out-Null
 $p=$null;$row=$null
 Write-Host "[$($i+1)/12] $key repeat $repeat"
 try{
  $p=StartServer $g $mtp $dir
  if($null -eq $prefix){
   $prefix=Prefix32K $source $PromptTargetTokens
   [IO.File]::WriteAllText((Join-Path $run 'fixed_prompt.txt'),$prefix.text,[Text.Encoding]::UTF8)
   @{prefix_tokens=$prefix.tokens;characters=$prefix.text.Length}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $run 'prompt_manifest.json')
  }
  $content="Summarize the document in English. Include main findings and supporting evidence." + [Environment]::NewLine + $prefix.text
  $body=@{messages=@(@{role='system';content='You are a helpful assistant.'},@{role='user';content=$content});max_tokens=$MaxOutputTokens;temperature=1.0;top_p=0.95;top_k=20;reasoning_effort='medium';stream=$false;cache_prompt=$false}
  $body|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 (Join-Path $dir 'request.json')
  $res=Post '/v1/chat/completions' $body $RequestTimeoutSec
  $res|ConvertTo-Json -Depth 35|Set-Content -Encoding UTF8 (Join-Path $dir 'response.json')
  $nIn=[int]$res.usage.prompt_tokens;$nOut=[int]$res.usage.completion_tokens
  $pp=[double]$res.timings.prompt_per_second;$tg=[double]$res.timings.predicted_per_second
  if($nIn -lt ($PromptTargetTokens-256) -or $nIn -gt ($PromptTargetTokens+512)){throw "Input token count mismatch: $nIn"}
  if($pp -le 0 -or $tg -le 0 -or $nOut -lt 32){throw "Invalid throughput: PP=$pp TG=$tg out=$nOut"}
  $row=[pscustomobject]@{condition=$key;gpu=$g.name;device=$g.device;mtp=$mode;repeat=$repeat;prompt_tokens=$nIn;output_tokens=$nOut;pp_tps=$pp;tg_tps=$tg;status='PASS';folder=(Split-Path $dir -Leaf)}
 }catch{
  $msg="[$($i+1)/12] $key repeat $repeat : $($_.Exception.Message)"
  Add-Content -Path (Join-Path $run 'errors.txt') -Value $msg
  Write-Warning $msg
  $row=[pscustomobject]@{condition=$key;gpu=$g.name;device=$g.device;mtp=$mode;repeat=$repeat;prompt_tokens='';output_tokens='';pp_tps='';tg_tps='';status='FAIL';folder=(Split-Path $dir -Leaf)}
 }finally{StopServer $p}
 $records.Add($row)
 $records|Export-Csv -Path (Join-Path $run 'all_trials.csv') -Encoding UTF8 -NoTypeInformation
}
$summary=foreach($g in $gpu){foreach($mode in @('OFF','ON')){
 $key="$($g.name.Replace(' ',''))_MTP$mode"
 $ok=@($records|Where-Object{$_.condition -eq $key -and $_.status -eq 'PASS'})
 if($ok.Count -eq 3){[pscustomobject]@{condition=$key;runs=3;pp_mean=[math]::Round(($ok|Measure-Object pp_tps -Average).Average,2);tg_mean=[math]::Round(($ok|Measure-Object tg_tps -Average).Average,2);status='COMPLETE'}}
 else{[pscustomobject]@{condition=$key;runs=$ok.Count;pp_mean='';tg_mean='';status='INCOMPLETE'}}
}}
$summary|Export-Csv -Path (Join-Path $run 'summary.csv') -Encoding UTF8 -NoTypeInformation
$summary|Format-Table -AutoSize
Write-Host "Results: $run"
if(@($summary|Where-Object{$_.status -ne 'COMPLETE'}).Count){throw 'Incomplete condition; see errors.txt and logs.'}
