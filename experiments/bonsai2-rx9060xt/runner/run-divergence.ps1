param(
 [ValidateSet('smoke','full')][string]$Mode='smoke',
 [string]$Server='D:\AI\PrismML\dev\llama.cpp\build-vulkan-ucrt64\bin\llama-server.exe',
 [string]$Model='D:\AI\PrismML\MTP-experiment\models\Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf',
 [string]$PromptFile='',
 [string]$OutputRoot='D:\AI\PrismML\benchmark-results\mtp-first-divergence',
 [int]$Port=18080,
 [int]$MaxTokens=1024,
 [int]$Context=32768,
 [int]$Seed=42,
 [int]$LoadTimeoutSec=180,
 [switch]$Include64K
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if(!(Test-Path -LiteralPath $Server)){throw "Server not found: $Server"}
if(!(Test-Path -LiteralPath $Model)){throw "Model not found: $Model"}
if($MaxTokens -lt 32){throw 'MaxTokens must be >= 32'}
if($Context -notin @(32768,65536)){throw 'Context must be 32768 or 65536'}
if($Include64K -and $Mode -eq 'smoke'){throw '64K only in full mode'}
$reps=if($Mode -eq 'smoke'){1}else{3}
$contexts=if($Include64K){@(32768,65536)}else{@($Context)}
$prompt=if($PromptFile){Get-Content -LiteralPath $PromptFile -Raw -Encoding UTF8}else{
  "Review an access-control change: an API uses user.isSuspended, but one proposed patch checks isSuspended without a receiver. Analyze likely failure modes, list at least three tests, and propose a minimal safe fix. Explicitly distinguish confirmed facts from assumptions."
}
$now=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $OutputRoot ("run_"+$now)
New-Item -ItemType Directory -Force -Path $out | Out-Null
$env:PATH=([IO.Path]::GetDirectoryName((Resolve-Path $Server).Path))+';D:\msys64\ucrt64\bin;'+$env:PATH
$meta=[ordered]@{
 mode=$Mode; repeats=$reps; contexts=$contexts; seed=$Seed; max_tokens=$MaxTokens
 port=$Port; prompt_sha256=(Get-TextSha256 $prompt)
 server_sha256=(Get-FileHash -LiteralPath $Server -Algorithm SHA256).Hash
 model_sha256=(Get-FileHash -LiteralPath $Model -Algorithm SHA256).Hash
 note='tokenization is post-hoc re-tokenization of visible API fields, not internal raw token IDs'
}
$meta | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $out 'manifest.json') -Encoding utf8
$prompt | Set-Content -LiteralPath (Join-Path $out 'prompt.txt') -Encoding utf8
function Get-TextSha256([string]$value){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($value))).Replace('-','').ToLower())}
 finally{$sha.Dispose()}
}
function Invoke-Json([string]$url,[object]$payload){
 $json=$payload | ConvertTo-Json -Depth 12 -Compress
 return Invoke-RestMethod -Uri $url -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json; charset=utf-8' -TimeoutSec 600
}
function Get-TokenIds([string]$base,[string]$value){
 $r=Invoke-Json "$base/tokenize" @{content=$value;add_special=$false}
 if($null -eq $r.tokens){throw 'Tokenizer API did not return tokens'}
 return @($r.tokens | ForEach-Object {[int]$_})
}
function Get-FirstDiff($a,$b){
 $len=[Math]::Min($a.Count,$b.Count)
 for($i=0;$i -lt $len;$i++){if($a[$i] -ne $b[$i]){return $i}}
 if($a.Count -ne $b.Count){return $len}
 return -1
}
$records=New-Object System.Collections.Generic.List[object]
$cases=@(
 @{id='q4q4_off';k='q4_0';v='q4_0';mtp=$false},
 @{id='q4q4_on';k='q4_0';v='q4_0';mtp=$true},
 @{id='q8q4_off';k='q8_0';v='q4_0';mtp=$false},
 @{id='q8q4_on';k='q8_0';v='q4_0';mtp=$true}
)
$base="http://127.0.0.1:$Port"
foreach($ctx in $contexts){
 foreach($c in $cases){
  for($rep=1;$rep -le $reps;$rep++){
   $id="$($ctx)_$($c.id)_r$rep"
   $stdout=Join-Path $out "$id.stdout.log"; $stderr=Join-Path $out "$id.stderr.log"
   $args=@('--model',$Model,'--device','Vulkan0','--n-gpu-layers','99','--ctx-size',"$ctx",
     '--batch-size','4096','--ubatch-size','1536','--flash-attn','on',
     '--cache-type-k',$c.k,'--cache-type-v',$c.v,'--parallel','1',
     '--dry-multiplier','0','--host','127.0.0.1','--port',"$Port")
   if($c.mtp){$args+=@('--spec-type','draft-mtp','--spec-draft-n-max','2')}
   # Never terminate an unrelated process already listening on the selected port.
   try {$existing=Invoke-RestMethod -Uri "$base/health" -TimeoutSec 2;throw "Port $Port is occupied. Close the existing server before running."}
   catch {if($_.Exception.Message -like 'Port * is occupied*'){throw}}
   Write-Host "Starting $id"
   $proc=$null
   try{
    $proc=Start-Process -FilePath $Server -ArgumentList $args -WorkingDirectory (Split-Path $Server) -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $deadline=(Get-Date).AddSeconds($LoadTimeoutSec)
    $ready=$false
    while((Get-Date) -lt $deadline){
     $proc.Refresh()
     if($proc.HasExited){throw "Server exited during initialization ($id)"}
     try{$h=Invoke-RestMethod -Uri "$base/health" -TimeoutSec 2;if($h.status -eq 'ok'){$ready=$true;break}}
     catch{}
     Start-Sleep -Seconds 2
    }
    if(!$ready){throw "Health timeout: $id"}
    $request=@{model='local';messages=@(@{role='user';content=$prompt});temperature=0;top_k=1;seed=$Seed;max_tokens=$MaxTokens;stream=$false;cache_prompt=$false}
    $response=Invoke-Json "$base/v1/chat/completions" $request
    $msg=$response.choices[0].message
    $reason=if($null -ne $msg.reasoning_content){[string]$msg.reasoning_content}else{''}
    $content=if($null -ne $msg.content){[string]$msg.content}else{''}
    # Separate fields preserve what the API actually returned; joint tokenization is diagnostic only.
    $reasonTokens=Get-TokenIds $base $reason
    $contentTokens=Get-TokenIds $base $content
    $combinedTokens=Get-TokenIds $base ($reason+$content)
    $rawPath=Join-Path $out "$id.json"
    $response | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $rawPath -Encoding utf8
    [pscustomobject]@{reason=$reasonTokens;content=$contentTokens;combined=$combinedTokens} | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath (Join-Path $out "$id.tokens.json") -Encoding utf8
    $tim=$response.timings
    $records.Add([pscustomobject]@{id=$id;context=$ctx;kv=$c.id;mtp=$c.mtp;rep=$rep;finish=$response.choices[0].finish_reason;reason_tokens=$reasonTokens.Count;content_tokens=$contentTokens.Count;total_tokens=$combinedTokens.Count;predicted_n=$tim.predicted_n;draft_n=$tim.draft_n;draft_accepted=$tim.draft_n_accepted;predicted_tps=$tim.predicted_per_second;status='OK'})
   }catch{
    $records.Add([pscustomobject]@{id=$id;context=$ctx;kv=$c.id;mtp=$c.mtp;rep=$rep;status='ERROR';error=$_.Exception.Message})
    Write-Warning "$id : $($_.Exception.Message)"
   }finally{
    if($null -ne $proc){try{if(!$proc.HasExited){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue;$proc.WaitForExit(10000)|Out-Null}}catch{}}
    Start-Sleep -Seconds 2
   }
  }
 }
}
$records | Export-Csv -LiteralPath (Join-Path $out 'summary.csv') -NoTypeInformation -Encoding utf8
$diffs=New-Object System.Collections.Generic.List[object]
foreach($ctx in $contexts){
 for($rep=1;$rep -le $reps;$rep++){
  foreach($pair in @(@('q4q4_off','q4q4_on'),@('q8q4_off','q8q4_on'),@('q4q4_off','q8q4_off'),@('q4q4_on','q8q4_on'))){
   $a="$($ctx)_$($pair[0])_r$rep";$b="$($ctx)_$($pair[1])_r$rep"
   $ap=Join-Path $out "$a.tokens.json";$bp=Join-Path $out "$b.tokens.json"
   if(!(Test-Path $ap) -or !(Test-Path $bp)){continue}
   $ta=Get-Content $ap -Raw | ConvertFrom-Json;$tb=Get-Content $bp -Raw | ConvertFrom-Json
   $d=Get-FirstDiff @($ta.combined) @($tb.combined)
   $diffs.Add([pscustomobject]@{context=$ctx;repeat=$rep;a=$a;b=$b;first_diff_zero_based=$d;common_prefix_tokens=if($d -eq -1){@($ta.combined).Count}else{$d};a_tokens=@($ta.combined).Count;b_tokens=@($tb.combined).Count;limitation='post-hoc rendered text re-tokenization'})
  }
 }
}
$diffs | Export-Csv -LiteralPath (Join-Path $out 'first-divergence.csv') -NoTypeInformation -Encoding utf8
Write-Host "Output: $out"
if(@($records | Where-Object status -eq 'ERROR').Count -gt 0){exit 1}
