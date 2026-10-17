# Real-context PP benchmarking against a running Bonsai2 llama-server.
# Run llama-server with -c 98304, -np 1, then supply an existing long text dataset.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$InputPath,
  [string]$ServerUrl = "http://127.0.0.1:8080",
  [int]$ContextSize = 98304,
  [int]$PromptTokens = 32768,
  [ValidateSet("quick","extended")][string]$Mode = "quick",
  [int]$Repetitions = 3,
  [switch]$RepeatInput,
  [string]$OutputDir = ""
)
$ErrorActionPreference="Stop"
if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "Missing input data: $InputPath" }
if (-not $OutputDir) {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
  $OutputDir = Join-Path $repoRoot "experiments\bonsai2-rx9060xt\pp-batch-v01\results"
}
$runDir=Join-Path $OutputDir ("run_"+(Get-Date -Format "yyyyMMdd_HHmmss")+"_ctx96k_pp32k")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$base=$ServerUrl.TrimEnd("/")
$props=Invoke-RestMethod -Uri "$base/props" -Method Get -TimeoutSec 30
$props | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $runDir "server_props.json") -Encoding utf8
# Explicit configuration check; server properties vary by build, so also record full properties.
$ctx=$null
if ($props.default_generation_settings -and $props.default_generation_settings.n_ctx) { $ctx=[int]$props.default_generation_settings.n_ctx }
elseif ($props.n_ctx) { $ctx=[int]$props.n_ctx }
if ($null -ne $ctx -and $ctx -ne $ContextSize) { throw "Server reported context $ctx; expected $ContextSize" }
$text=Get-Content -LiteralPath $InputPath -Raw -Encoding utf8
if ([string]::IsNullOrWhiteSpace($text)) { throw "Input file is empty" }
# /tokenize provides the precise token sequence for the active model.
function Tokenize([string]$value) {
  $body=@{content=$value;add_special=$false} | ConvertTo-Json -Compress -Depth 4
  $r=Invoke-RestMethod -Uri "$base/tokenize" -Method Post -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 900
  return ,@($r.tokens)
}
$ids=@(Tokenize $text)
if ($ids.Count -lt $PromptTokens -and -not $RepeatInput) {
  throw "Only $($ids.Count) tokens in dataset, less than requested $PromptTokens. Supply a longer text or explicitly use -RepeatInput."
}
if ($RepeatInput -and $ids.Count -lt $PromptTokens) {
  $piece=$ids
  while ($ids.Count -lt $PromptTokens) { $ids+= $piece }
}
$ids=@($ids | Select-Object -First $PromptTokens)
if ($ids.Count -ne $PromptTokens) { throw "Failed to prepare requested token count" }
$hash=(Get-FileHash -LiteralPath $InputPath -Algorithm SHA256).Hash
$metadata=[ordered]@{input_file=[IO.Path]::GetFileName($InputPath);input_sha256=$hash;input_original_tokens=$ids.Count;prompt_tokens=$PromptTokens;context_expected=$ContextSize;context_reported=$ctx;server=$base;mode=$Mode;repetitions=$Repetitions;repeat_input=$RepeatInput.IsPresent;warning="Server startup parameters -c 98304 -np 1 and cache behavior must be verified via log. Restart server between configurations; repeated runs may be cache-affected."}
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir "metadata.json") -Encoding utf8
$rows=@()
for ($i=1;$i -le $Repetitions;$i++) {
  # llama-server completion accepts token ids as prompt, avoiding retokenization.
  # cache_prompt=false requests no prefix reuse; check timings.prompt_n to detect residual reuse.
  $body=@{prompt=$ids;n_predict=1;cache_prompt=$false;stream=$false;temperature=0;seed=1234} | ConvertTo-Json -Compress -Depth 10
  try {
    $response=Invoke-RestMethod -Uri "$base/completion" -Method Post -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 1800
    $response | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $runDir "response_$i.json") -Encoding utf8
    $timings=$response.timings
    $measured=[int]$timings.prompt_n
    $status= if ($measured -ge ($PromptTokens-16)) {"OK"} else {"CACHE_OR_SHORT_PREFILL"}
    $rows += [pscustomobject]@{trial=$i;status=$status;requested_tokens=$PromptTokens;actual_prompt_n=$measured;prompt_ms=$timings.prompt_ms;prompt_per_second=$timings.prompt_per_second}
  } catch {
    $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $runDir "error_$i.txt")
    $rows += [pscustomobject]@{trial=$i;status="ERROR";requested_tokens=$PromptTokens;actual_prompt_n=$null;prompt_ms=$null;prompt_per_second=$null}
  }
  $rows | Export-Csv -LiteralPath (Join-Path $runDir "summary.csv") -NoTypeInformation -Encoding utf8
  Write-Host "Trial $i : $($rows[-1].status) $($rows[-1].prompt_per_second) tok/s (prompt_n=$($rows[-1].actual_prompt_n))"
}
Write-Host "Result: $(Join-Path $runDir 'summary.csv')"
