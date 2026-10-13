param(
    [ValidateSet('bonsai','gemma')][string]$Model = 'gemma',
    [string]$DataDir = ''
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $DataDir) { $DataDir = Join-Path $Root 'dataset' }
$Port = if ($Model -eq 'bonsai') { 8078 } else { 8081 }
$Base = 'http://127.0.0.1:' + $Port
$RunDir = Join-Path $Root ('results\' + $Model + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
function Post-Json($Endpoint, $Body) {
    $Json = $Body | ConvertTo-Json -Depth 20 -Compress
    $Bytes = [Text.Encoding]::UTF8.GetBytes($Json)
    Invoke-RestMethod -Uri ($Base + $Endpoint) -Method Post -ContentType 'application/json; charset=utf-8' -Body $Bytes -TimeoutSec 1800
}
try {
    $PromptPath=Join-Path $DataDir 'prompt.txt'
    $GoldPath=Join-Path $DataDir 'gold.json'
    if (-not (Test-Path $PromptPath)) { throw 'Missing dataset. Execute prepare.bat first.' }
    Write-Host "[1/5] Loading dataset for $Model" -ForegroundColor Cyan
    $Prompt=Get-Content -LiteralPath $PromptPath -Raw -Encoding UTF8
    Write-Host ("Dataset characters: " + $Prompt.Length)
    $Gold=Get-Content -LiteralPath $GoldPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host "[2/5] Checking existing server $Base" -ForegroundColor Cyan
    $Health=Invoke-RestMethod ($Base+'/health') -TimeoutSec 10
    if ($Health.status -ne 'ok') { throw 'Server is not ready.' }
    $Models=Invoke-RestMethod ($Base+'/v1/models') -TimeoutSec 10
    $Models | ConvertTo-Json -Depth 20 | Out-File (Join-Path $RunDir 'models.json') -Encoding UTF8

    # Tokenization preflight is approximate: chat-template overhead is additional.
    Write-Host '[3/5] Tokenizing the full prompt (server CPU/GPU may be busy; this step can take time)' -ForegroundColor Cyan
    $TokenWatch=[Diagnostics.Stopwatch]::StartNew()
    $Tokens=Post-Json '/tokenize' @{content=$Prompt;add_special=$false}
    $TokenWatch.Stop()
    $TokenCount=@($Tokens.tokens).Count
    Write-Host ("Token count: $TokenCount; preflight seconds: " + [math]::Round($TokenWatch.Elapsed.TotalSeconds,1))
    if ($TokenCount -ge 60000) {
        throw "Prompt estimated at $TokenCount tokens. Must be under 60000 for safe 64k use. Lower --target-chars and regenerate."
    }
    $Body=@{
        messages=@(@{role='user';content=$Prompt})
        max_tokens=2048;temperature=0;top_k=1;seed=42
        reasoning_effort='none'
        chat_template_kwargs=@{enable_thinking=$false}
    }
    $Body | ConvertTo-Json -Depth 20 | Out-File (Join-Path $RunDir 'request.json') -Encoding UTF8
    Write-Host "[4/5] Requesting full answer from $Model; no streaming (console stays idle until response)" -ForegroundColor Cyan
    $Watch=[Diagnostics.Stopwatch]::StartNew()
    $R=Post-Json '/v1/chat/completions' $Body
    $Watch.Stop()
    $R | ConvertTo-Json -Depth 30 | Out-File (Join-Path $RunDir 'response.json') -Encoding UTF8
    $Answer=[string]$R.choices[0].message.content
    $Answer | Out-File (Join-Path $RunDir 'answer.txt') -Encoding UTF8

    $Parsed=@{}
    foreach ($Line in ($Answer -split "\r?\n")) {
        if ($Line -match '^\s*\*{0,2}(F\d\d)\*{0,2}\s*[:\uFF1A]\s*(.+?)\s*$') {
            $Parsed[$matches[1]]=$matches[2].Trim().TrimEnd('.',' ','*')
        }
    }
    Write-Host '[5/5] Scoring and saving answer' -ForegroundColor Cyan
    $Rows=@(foreach($Fact in $Gold) {
        $Value=if($Parsed.ContainsKey($Fact.id)){$Parsed[$Fact.id]}else{''}
        $Expected=[string]$Fact.expected
        # Strict exact-match screen; mismatches require human review.
        [pscustomobject]@{
            id=$Fact.id;expected=$Expected;observed=$Value
            exact_match=($Value -ceq $Expected)
            status=if(-not $Value){'MISSING'}elseif($Value -ceq $Expected){'EXACT'}else{'REVIEW'}
        }
    })
    $Rows | Export-Csv (Join-Path $RunDir 'fact_checks.csv') -NoTypeInformation -Encoding UTF8
    $Summary=[ordered]@{
        model=$Model;endpoint=$Base;dataset_sha256=(Get-FileHash $PromptPath -Algorithm SHA256).Hash
        tokenizer_estimate=$TokenCount;actual_prompt_tokens=$R.usage.prompt_tokens
        generated_tokens=$R.usage.completion_tokens
        stop=$R.choices[0].finish_reason
        elapsed_seconds=[math]::Round($Watch.Elapsed.TotalSeconds,2)
        pp_tok_s=$R.timings.prompt_per_second;tg_tok_s=$R.timings.predicted_per_second
        exact=@($Rows | Where-Object status -eq 'EXACT').Count
        review=@($Rows | Where-Object status -eq 'REVIEW').Count
        missing=@($Rows | Where-Object status -eq 'MISSING').Count
        caveat='EXACT is strict string equality only; REVIEW requires manual semantic grading. This is not an automatic hallucination score.'
    }
    $Summary | ConvertTo-Json -Depth 15 | Out-File (Join-Path $RunDir 'summary.json') -Encoding UTF8
    $Rows | Format-Table -AutoSize
    $Summary | Format-List
    Write-Host "Results: $RunDir"
    if ($R.usage.prompt_tokens -ge 63488) { Write-Warning 'Prompt close to server context boundary.' }
} catch {
    $_ | Out-String | Out-File (Join-Path $RunDir 'failure.txt') -Encoding UTF8
    Write-Warning $_.Exception.Message
    exit 1
}
