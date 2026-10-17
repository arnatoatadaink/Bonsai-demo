# Bonsai2 PP sweep / RX 9060 XT. Requires PowerShell 7 and matching PrismML llama-bench.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ModelPath,
  [Parameter(Mandatory)][string]$BenchPath,
  [string]$Device = "Vulkan0",
  [ValidateSet("quick","extended","stress")][string]$Mode = "quick",
  [ValidateRange(1,10)][int]$Repetitions = 3,
  [string]$OutputDir = ""
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
  $OutputDir = Join-Path $repoRoot "experiments\bonsai2-rx9060xt\pp-batch-v01\results"
}
foreach ($file in @($ModelPath,$BenchPath)) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "File not found: $file" }
}
switch ($Mode) {
  "quick" { $bs=@(32768,65536); $ubs=@(512,1024,1536); $ps=@(4096,8192) }
  "extended" { $bs=@(32768,65536,131072); $ubs=@(512,1024,1536,2048); $ps=@(4096,8192,16384) }
  "stress" { $bs=@(131072,262144); $ubs=@(1024,1536,2048,4096); $ps=@(8192,16384) }
}
$runDir=Join-Path $OutputDir ("run_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$metadata=[ordered]@{
  timestamp=(Get-Date).ToString("o");mode=$Mode;device=$Device
  model=$ModelPath;bench=$BenchPath;repetitions=$Repetitions
  k="q8_0";v="q4_0";flashAttention="on";threads=4
  note="PP-only: no MTP, does not reserve server's 98304 context"
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir "metadata.json") -Encoding utf8
$rows=@()
foreach ($p in $ps) { foreach ($b in $bs) { foreach ($ub in $ubs) {
  $name="p${p}_b${b}_ub${ub}"
  $outFile=Join-Path $runDir "$name.json"
  $errFile=Join-Path $runDir "$name.stderr.txt"
  $argsList=@("-m",$ModelPath,"-dev",$Device,"-sm","none","-ngl","99",
      "-p","$p","-n","0","-b","$b","-ub","$ub",
      "-ctk","q8_0","-ctv","q4_0","-fa","on","-t","4","-r","$Repetitions","-o","json")
  $status="ERROR";$avg=$null;$sd=$null;$exit=-1
  try {
    $psi=[Diagnostics.ProcessStartInfo]::new()
    $psi.FileName=$BenchPath
    $psi.WorkingDirectory=Split-Path -Parent $BenchPath
    $psi.UseShellExecute=$false
    $psi.RedirectStandardOutput=$true
    $psi.RedirectStandardError=$true
    foreach ($a in $argsList) { [void]$psi.ArgumentList.Add($a) }
    $proc=[Diagnostics.Process]::Start($psi)
    $output=$proc.StandardOutput.ReadToEndAsync()
    $errors=$proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $output.GetAwaiter().GetResult() | Set-Content -LiteralPath $outFile -Encoding utf8
    $errors.GetAwaiter().GetResult() | Set-Content -LiteralPath $errFile -Encoding utf8
    $exit=$proc.ExitCode
    if ($exit -eq 0) {
      $items=@(Get-Content -LiteralPath $outFile -Raw | ConvertFrom-Json)
      $match=$items | Where-Object { $_.n_prompt -eq $p -and $_.n_gen -eq 0 } | Select-Object -First 1
      if ($null -ne $match -and $null -ne $match.avg_ts) {
        $avg=[double]$match.avg_ts;$sd=[double]$match.stddev_ts;$status="OK"
      } else { $status="PARSE_ERROR" }
    } else { $status="EXIT_$exit" }
  } catch {
    $status="EXCEPTION"
    $_.Exception.ToString() | Add-Content -LiteralPath $errFile
  }
  $rows+= [pscustomobject]@{
    prompt_tokens=$p;batch=$b;ubatch=$ub;status=$status
    avg_tok_s=$avg;stddev_tok_s=$sd;exit_code=$exit
    stdout_file=$outFile;stderr_file=$errFile
  }
  $rows | Export-Csv -LiteralPath (Join-Path $runDir "summary.csv") -NoTypeInformation -Encoding utf8
  Write-Host "$name $status $avg tok/s"
}}}
Write-Host "Complete: $(Join-Path $runDir 'summary.csv')"
