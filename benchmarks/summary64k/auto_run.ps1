param(
 [Parameter(Mandatory=$true)][string]$LlamaServer,
 [ValidateSet('all','bonsai8','gemma12','qwen9')][string]$Model='all',
 [string]$Levels='1,2,3,4,5',
 [string]$Device='',
 [string]$OutputRoot='summary-benchmark-results',
 [int]$Port=18080,
 [int]$StartupTimeoutSeconds=240,
 [switch]$SmokeOnly,
 [switch]$OriginalSuite
)
$ErrorActionPreference='Stop'
if (!(Test-Path -LiteralPath $LlamaServer -PathType Leaf)) {throw "Executable not found: $LlamaServer"}
$LlamaServer=(Resolve-Path -LiteralPath $LlamaServer).Path
$root=Join-Path (Get-Location).Path $OutputRoot
New-Item -ItemType Directory -Force $root | Out-Null
$models=@{
 bonsai8='D:\lmstudio_models\prism-ml\Ternary-Bonsai-8B-gguf\Ternary-Bonsai-8B-PQ2_0.gguf'
 gemma12='D:\lmstudio_models\unsloth\gemma-4-12b-it-GGUF\gemma-4-12B-it-qat-UD-Q4_K_XL.gguf'
 qwen9='D:\lmstudio_models\unsloth\Qwen3.5-9B-MTP-GGUF\Qwen3.5-9B-UD-Q4_K_XL.gguf'
}
$selected=if ($Model -eq 'all') {@('bonsai8','gemma12','qwen9')} else {@($Model)}
$listing=(& $LlamaServer --list-devices 2>&1 | Out-String)
$listing | Set-Content -Encoding utf8 (Join-Path $root 'device-list.txt')
if (!$Device) {
 $lines=@($listing -split '\r?\n' | Where-Object {$_ -match 'RX\s*9070\s*XT'})
 $ids=@($lines | ForEach-Object {if ($_ -match '(?i)\b(Vulkan\d+)\b') {$Matches[1]}} | Select-Object -Unique)
 if ($ids.Count -ne 1) {throw "RX 9070 XT GPU ID could not be resolved uniquely: see device-list.txt; pass -Device VulkanN"}
 $Device=$ids[0]
}
if ($Device -notmatch '^Vulkan\d+$') {throw "Expected VulkanN: $Device"}
$deviceLine=@($listing -split '\r?\n' | Where-Object {$_ -match [regex]::Escape($Device) -and $_ -match 'RX\s*9070\s*XT'})
if ($deviceLine.Count -ne 1) {throw "Selected $Device does not uniquely match RX 9070 XT; aborting."}
$helpText=(& $LlamaServer --help 2>&1 | Out-String)
foreach ($flag in @('--cache-type-k','--cache-type-v','--device','--jinja')) {
 if (!$helpText.Contains($flag)) {throw "Missing CLI flag $flag in llama-server --help"}
}
$manifest=[ordered]@{
 hardware='AMD RX 9070 XT'; device=$Device; context=65536; cache_k='q8_0'; cache_v='q8_0'
 flash_attention='on'; mtp='off'; binary=$LlamaServer; models=$selected
 levels=$(if ($SmokeOnly) {'1'} else {$Levels}); started_utc=(Get-Date).ToUniversalTime().ToString('o')
 verification='Requested configuration only; check runtime logs for actual allocation'
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $root 'manifest.json')
foreach ($name in $selected) {
 $file=$models[$name]
 if (!(Test-Path -LiteralPath $file -PathType Leaf)) {throw "GGUF missing: $file"}
 $stdout=Join-Path $root "$name.stdout.log"
 $stderr=Join-Path $root "$name.stderr.log"
 $launch=@('-m',$file,'--host','127.0.0.1','--port',"$Port",'--device',$Device,
 '-ngl','99','-sm','none','-c','65536','--cache-type-k','q8_0','--cache-type-v','q8_0',
 '-fa','on','-np','1','--jinja')
 $process=$null
 try {
  $process=Start-Process -FilePath $LlamaServer -ArgumentList $launch -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $ready=$false; $deadline=(Get-Date).AddSeconds($StartupTimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
   if ($process.HasExited) {throw "Server exited ($($process.ExitCode)); see $stderr"}
   try {
    $health=Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 3
    if ($health.status -eq 'ok') {$ready=$true; break}
   } catch {}
   Start-Sleep -Seconds 2
  }
  if (!$ready) {throw "Server startup timeout; see $stderr"}
  $lv=if ($SmokeOnly) {'1'} else {$Levels}
  if ($OriginalSuite) {
   & python benchmarks/summary64k/run_original_suite.py --model $name --suite both --base-url "http://127.0.0.1:$Port" --output (Join-Path $root 'original-suite') $(if ($SmokeOnly) {'--smoke'})
  } else {
   & python benchmarks/summary64k/run.py --model $name --levels $lv --base-url "http://127.0.0.1:$Port" --output $root --acknowledge-server-settings
  }
  if ($LASTEXITCODE -ne 0) {throw "Benchmark failed: $name"}
 } finally {
  if ($process -and !$process.HasExited) {Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue; $process.WaitForExit()}
  Start-Sleep -Seconds 2
 }
}
Write-Host "Completed: $root"
