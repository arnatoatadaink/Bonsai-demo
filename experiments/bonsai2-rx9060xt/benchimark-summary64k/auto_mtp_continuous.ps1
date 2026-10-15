# Continuous MTP inference / crash isolation on RX 9060 XT.
# Each model is started once, serves up to N sequential requests, then is stopped.
# Checkpoint=0 and fit=off are mandatory.
param(
 [Parameter(Mandatory=$true)][string]$LlamaServer,
 [ValidateSet('all','gemma12','gemma26')][string]$Model='all',
 [ValidateSet('9060','9070')][string]$Gpu='9060',
 [int]$Repeat=20,
 [int]$Context=65536,
 [int]$DraftNMax=2,
 [int]$Port=18080,
 [int]$MaxTokens=512,
 [int]$StartupTimeoutSeconds=300,
 [int]$RequestTimeoutSeconds=900,
 [int]$CooldownSeconds=10,
 [string]$OutputRoot='',
 [int]$LongInputTokens=0,
 [ValidateSet('fixed','vary')][string]$InputMode='fixed'
)
$ErrorActionPreference='Stop'
if($Repeat -lt 1 -or $Repeat -gt 10000 -or $Context -lt 4096 -or $MaxTokens -lt 1){throw 'Invalid parameter'}
if($LongInputTokens -gt 0 -and $LongInputTokens+$MaxTokens+1024 -gt $Context){throw 'Long input plus output and safety reserve exceeds context'}
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
$root=if($OutputRoot){[IO.Path]::GetFullPath($OutputRoot)}else{Join-Path $here 'results'}
$run=Join-Path $root ('run_mtp_continuous_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
if(Test-Path $run){throw "Run directory exists: $run"}
New-Item -ItemType Directory -Force -Path $run | Out-Null
if(!(Test-Path -LiteralPath $LlamaServer -PathType Leaf)){throw "Missing server: $LlamaServer"}
$exe=(Resolve-Path -LiteralPath $LlamaServer).Path
$configs=@{
 gemma12=@{target='D:\lmstudio_models\unsloth\gemma-4-12b-it-GGUF\gemma-4-12B-it-qat-UD-Q4_K_XL.gguf';draft='D:\lmstudio_models\unsloth\gemma-4-12b-it-GGUF\gemma-4-12B-it-Q8_0-MTP.gguf'}
 gemma26=@{target='D:\lmstudio_models\unsloth\gemma-4-26B-A4B-it-qat-GGUF\gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf';draft='D:\lmstudio_models\unsloth\gemma-4-26B-A4B-it-qat-GGUF\gemma-4-26B-A4B-it-Q8_0-MTP.gguf'}
}
$selected=if($Model -eq 'all'){@('gemma12','gemma26')}else{@($Model)}
foreach($name in $selected){foreach($p in @($configs[$name].target,$configs[$name].draft)){if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing GGUF: $p"}}}
$listing=(& $exe --list-devices 2>&1 | Out-String)
$listing|Set-Content -Encoding UTF8 (Join-Path $run 'device-list.txt')
$pattern=if($Gpu -eq '9060'){'RX\s*9060\s*XT'}else{'RX\s*9070\s*XT'}
$ids=@($listing -split '\r?\n' | Where-Object {$_ -match $pattern} | ForEach-Object {if($_ -match '(?i)\b(Vulkan\d+)\b'){$Matches[1]}} | Select-Object -Unique)
if($ids.Count -ne 1){throw "RX $Gpu XT Vulkan GPU detection failed"}
$device=$ids[0]
$helpText=(& $exe --help 2>&1 | Out-String)
foreach($flag in @('--ctx-checkpoints','--fit','--spec-type','--spec-draft-n-max','--spec-draft-device')){
 if(!$helpText.Contains($flag)){throw "Missing CLI flag: $flag"}
}
$draftFlag=if($helpText.Contains('--spec-draft-model')){'--spec-draft-model'}elseif($helpText.Contains('--model-draft')){'--model-draft'}else{throw "No draft model option"}
$draftNgl=if($helpText.Contains('--spec-draft-ngl')){'--spec-draft-ngl'}elseif($helpText.Contains('--n-gpu-layers-draft')){'--n-gpu-layers-draft'}else{''}
if(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue){throw "Port $Port is in use"}
$manifest=[ordered]@{gpu="RX $Gpu XT";device=$device;server=$exe;server_sha256=(Get-FileHash $exe -Algorithm SHA256).Hash;models=$selected;repeat=$Repeat;context=$Context;checkpoint=0;fit='off';cache_k='q8_0';cache_v='q8_0';fa='on';draft_n_max=$DraftNMax;max_tokens=$MaxTokens;created=(Get-Date).ToString('o');workload=$(if($LongInputTokens -gt 0){'exact-tokenized long-context MTP inference'}else{'repeated deterministic structured answer'});long_input_tokens=$LongInputTokens;input_mode=$InputMode}
$manifest|ConvertTo-Json -Depth 6|Set-Content -Encoding UTF8 (Join-Path $run 'manifest.json')
$rows=New-Object System.Collections.Generic.List[object]
function SaveRows {if($rows.Count -gt 0){$rows|Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $run 'trials.csv')}}
# Repeat prompt is fixed: comparison across models, repeat=20 isolates runtime stability.
$prompt=@'
以下の記録を整理し、日本語で6項目の要約を出力してください。数値・条件を省略しないでください。
2026年Q1売上120百万円、営業利益14百万円。
2026年Q2売上135百万円、営業利益11百万円。
Q2設備投資22百万円のうち8百万円は承認済み。
Q3の実績は未発表。Nimbus計画は未承認。
北部地域の例外規則は2026年12月31日まで有効。
予測と実績、未承認と承認済みを区別して出力してください。
'@
foreach($name in $selected){
 $dir=Join-Path $run $name
 New-Item -ItemType Directory -Force -Path $dir|Out-Null
 $cfg=$configs[$name];$stderr=Join-Path $dir 'server.stderr.log';$stdout=Join-Path $dir 'server.stdout.log'
 $argsList=@('-m',('"'+$cfg.target+'"'),'--host','127.0.0.1','--port',"$Port",
  '--device',$device,'-ngl','99','-sm','none','-c',"$Context",
  '--cache-type-k','q8_0','--cache-type-v','q8_0','-fa','on','-np','1','--jinja',
  '--ctx-checkpoints','0','--fit','off','--spec-type','draft-mtp','--spec-draft-n-max',"$DraftNMax",
  $draftFlag,('"'+$cfg.draft+'"'),'--spec-draft-device',$device)
 if($draftNgl){$argsList+=@($draftNgl,'99')}
 ($argsList -join ' ')|Set-Content -Encoding UTF8 (Join-Path $dir 'command.txt')
 $proc=$null;$ready=$false;$modelError='';$attempted=0
 try{
  if(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue){throw "Port occupied"}
  $proc=Start-Process -FilePath $exe -ArgumentList ($argsList -join ' ') -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $deadline=(Get-Date).AddSeconds($StartupTimeoutSeconds)
  while((Get-Date) -lt $deadline){
   $proc.Refresh()
   if($proc.HasExited){throw "Startup exited with code $($proc.ExitCode)"}
   try{$h=Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 3;if($h.status -eq 'ok'){$ready=$true;break}}catch{}
   Start-Sleep -Seconds 2
  }
  if(!$ready){throw 'Startup timeout'}
  $meta=Invoke-RestMethod "http://127.0.0.1:$Port/v1/models" -TimeoutSec 15
  $meta|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 (Join-Path $dir 'models.json')
  if($LongInputTokens -gt 0){
   & python (Join-Path $here 'long_context_probe.py') --base-url "http://127.0.0.1:$Port" --output (Join-Path $dir 'long_input') --repeat $Repeat --target-tokens $LongInputTokens --input-mode $InputMode --context $Context --max-tokens $MaxTokens --timeout $RequestTimeoutSeconds
   if($LASTEXITCODE -ne 0){throw "Long context probe failed for $name; inspect long_input/trials.csv"}
  } else {
  for($i=1;$i -le $Repeat;$i++){
   $proc.Refresh()
   if($proc.HasExited){$modelError="Server exited before request $i, exit=$($proc.ExitCode)";break}
   $attempted=$i;$start=Get-Date;$status='ERROR';$err='';$finish='';$tokens='';$tg=''
   $body=@{messages=@(@{role='user';content=$prompt});max_tokens=$MaxTokens;temperature=0;top_k=1;seed=42;stream=$false;reasoning_effort='none';chat_template_kwargs=@{enable_thinking=$false}}
   $body|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 (Join-Path $dir ('request_'+('{0:d3}' -f $i)+'.json'))
   try{
    $data=$body|ConvertTo-Json -Depth 10 -Compress
    $response=Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat/completions" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($data)) -ContentType 'application/json; charset=utf-8' -TimeoutSec $RequestTimeoutSeconds
    $response|ConvertTo-Json -Depth 40|Set-Content -Encoding UTF8 (Join-Path $dir ('response_'+('{0:d3}' -f $i)+'.json'))
    $finish=[string]$response.choices[0].finish_reason;$tokens=$response.usage.completion_tokens;$tg=$response.timings.predicted_per_second;$status='OK'
   }catch{$err=$_.Exception.Message;$err|Set-Content -Encoding UTF8 (Join-Path $dir ('error_'+('{0:d3}' -f $i)+'.txt'))}
   $proc.Refresh()
   $dead=$proc.HasExited
   $elapsed=[math]::Round(((Get-Date)-$start).TotalSeconds,2)
   $rows.Add([pscustomobject]@{model=$name;iteration=$i;status=$status;elapsed_sec=$elapsed;finish_reason=$finish;generated_tokens=$tokens;tg_tok_s=$tg;server_exited=$dead;exit_code=$(if($dead){$proc.ExitCode}else{''});error=$err})
   SaveRows
   Write-Host "[$name $i/$Repeat] $status, $elapsed sec, alive=$(!$dead)"
   if($status -ne 'OK' -or $dead){$modelError="Failure at request $i";break}
   if($CooldownSeconds -gt 0){Start-Sleep -Seconds $CooldownSeconds}
  }
  }
 }catch{
  $modelError=$_.Exception.Message
 }finally{
  if($modelError){$modelError|Set-Content -Encoding UTF8 (Join-Path $dir 'failure.txt');Write-Warning "[$name] $modelError"}
  if($proc){$proc.Refresh();if(!$proc.HasExited){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue;try{$proc.WaitForExit(10000)|Out-Null}catch{}}}
  Start-Sleep -Seconds 5
 }
}
$summary=@($selected|ForEach-Object{
 $n=$_;$subset=@($rows|Where-Object {$_.model -eq $n})
 $longSummary=Join-Path (Join-Path $run $n) 'long_input/summary.json'
 if($LongInputTokens -gt 0){
  if(Test-Path -LiteralPath $longSummary){$d=Get-Content -LiteralPath $longSummary -Raw | ConvertFrom-Json;[pscustomobject]@{model=$n;requested=$Repeat;completed=$d.passed;failed=$d.failed;not_attempted=$Repeat-$d.attempted}}
  else{[pscustomobject]@{model=$n;requested=$Repeat;completed=0;failed=1;not_attempted=$Repeat}}
 }else{[pscustomobject]@{model=$n;requested=$Repeat;completed=@($subset|Where-Object {$_.status -eq 'OK'}).Count;failed=@($subset|Where-Object {$_.status -ne 'OK'}).Count;not_attempted=$Repeat-$subset.Count}}

})
$summary|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 (Join-Path $run 'summary.json')
$summary|Format-Table -AutoSize
Write-Host "Results: $run"
if(@($summary|Where-Object {$_.completed -lt $Repeat}).Count){exit 2}
