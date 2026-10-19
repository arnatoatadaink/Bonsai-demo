# Windows PowerShell 5.1, manual fixed paths. No scanning or auto-detection.
[CmdletBinding()]
param(
 [string]$ConfigPath=(Join-Path $PSScriptRoot 'paths.local.psd1')
)
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $ConfigPath -PathType Leaf)){
 throw "Missing local paths config: $ConfigPath. Copy paths.example.psd1 to paths.local.psd1 and edit 3 paths."
}
$config=Import-PowerShellDataFile -LiteralPath $ConfigPath
foreach($key in @('LlamaServer','ModelPath','PromptPath')){
 $value=[string]$config[$key]
 if([string]::IsNullOrWhiteSpace($value) -or $value -like 'REPLACE_WITH_*'){
  throw "Set $key in $ConfigPath"
 }
 if(-not[IO.Path]::IsPathRooted($value)){throw "$key must be an absolute path: $value"}
 if(-not(Test-Path -LiteralPath $value -PathType Leaf)){throw "$key not found: $value"}
}
$runner=Join-Path $PSScriptRoot 'run_bonsai2_4way_pp_tg.ps1'
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw "Missing runner: $runner"}
Write-Host 'Bonsai2-27B: 4 conditions x 3 runs / Windows PowerShell 5.1'
Write-Host ('Server: ' + [IO.Path]::GetFileName($config.LlamaServer))
Write-Host ('Model:  ' + [IO.Path]::GetFileName($config.ModelPath))
Write-Host ('Prompt: ' + [IO.Path]::GetFileName($config.PromptPath))
Write-Host 'No auto-detection, no model download, no path fallbacks.'
& $runner -LlamaServer $config.LlamaServer -ModelPath $config.ModelPath -PromptPath $config.PromptPath -Repetitions 3
if(-not $?){throw 'Benchmark failed. Inspect results_4way logs.'}
