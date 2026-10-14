# Move an old summary-benchmark-results directory into the suite-local results layout.
# Defaults to preview only. Never overwrites destination.
param(
 [string]$Source = 'summary-benchmark-results',
 [switch]$Move,
 [string]$DestinationName = ''
)
$ErrorActionPreference='Stop'
$suiteRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot=(Resolve-Path (Join-Path $suiteRoot '..\..')).Path
$sourcePath=if([IO.Path]::IsPathRooted($Source)){$Source}else{Join-Path $repoRoot $Source}
if(!(Test-Path -LiteralPath $sourcePath -PathType Container)){throw "Source directory missing: $sourcePath"}
$targetRoot=Join-Path $suiteRoot 'results'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$name=if($DestinationName){$DestinationName}else{"run_imported_$stamp"}
if($name -notmatch '^run_[A-Za-z0-9_-]+$'){throw "DestinationName must begin run_ and use only letters, numbers, underscores, hyphens"}
$target=Join-Path $targetRoot $name
if(Test-Path -LiteralPath $target){throw "Target exists, refusing overwrite: $target"}
if([IO.Path]::GetFullPath($sourcePath).TrimEnd('\') -eq [IO.Path]::GetFullPath($target).TrimEnd('\')){throw 'Source and destination are identical'}
Write-Host "Source: $sourcePath"
Write-Host "Target: $target"
Write-Host 'Original directory contents are preserved without restructuring.'
if(!$Move){Write-Host 'Preview only. Pass -Move to actually move the directory.';exit 0}
New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
Move-Item -LiteralPath $sourcePath -Destination $target -ErrorAction Stop
Write-Host "Moved: $target"
