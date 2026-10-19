# Probe read-only AMD GPU telemetry on Windows. PowerShell 7.
# No drivers, sensor services, or settings are installed/changed.
[CmdletBinding()]
param(
 [ValidateRange(1,600)][int]$DurationSec=20,
 [ValidateRange(1,10)][int]$IntervalSec=2,
 [string]$OutputDir="",
 [string]$GpuMatch="9060"
)
$ErrorActionPreference="Stop"
$root=(Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
if(!$OutputDir){$OutputDir=Join-Path $root "experiments\bonsai2-rx9060xt\gpu-telemetry\results"}
$out=Join-Path $OutputDir ("probe_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $out|Out-Null
$meta=[ordered]@{
 date=(Get-Date).ToString("o");powershell=$PSVersionTable.PSVersion.ToString()
 gpu_match=$GpuMatch;duration_sec=$DurationSec;interval_sec=$IntervalSec
 note="All sensors are read-only. Missing sensors are not interpreted as zero."
}
$video=@(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
 Select-Object Name,AdapterCompatibility,DriverVersion,PNPDeviceID)
$video|ConvertTo-Json -Depth 4|Set-Content (Join-Path $out "adapters.json")
$meta.adapters=$video
# Built-in Windows thermal zones are generally motherboard/ACPI sensors and
# must not be mislabeled as AMD GPU temperatures.
$providers=@()
foreach($ns in @("root\LibreHardwareMonitor","root\OpenHardwareMonitor")){
 try {
  $s=@(Get-CimInstance -Namespace $ns -ClassName Sensor -ErrorAction Stop)
  $h=@(Get-CimInstance -Namespace $ns -ClassName Hardware -ErrorAction SilentlyContinue)
  $providers+= [pscustomobject]@{namespace=$ns;status="AVAILABLE";sensors=$s.Count;hardware=$h.Count}
 }catch{
  $providers+= [pscustomobject]@{namespace=$ns;status="UNAVAILABLE";error=$_.Exception.Message}
 }
}
$meta.providers=$providers
# ADLX is the AMD-native source, but PowerShell has no built-in ADLX client.
# Detect availability; do NOT attempt unmanaged calls without correct bindings.
$meta.adlx_dll_candidates=@(
 Join-Path $env:WINDIR "System32\atiadlxx.dll"
 Join-Path $env:WINDIR "System32\amdadlx64.dll"
) | ForEach-Object { [pscustomobject]@{path=$_;exists=(Test-Path -LiteralPath $_)} }
$meta|ConvertTo-Json -Depth 8|Set-Content (Join-Path $out "probe.json") -Encoding utf8
$readings=New-Object System.Collections.Generic.List[object]
$end=(Get-Date).AddSeconds($DurationSec)
do{
 $now=(Get-Date).ToString("o")
 foreach($p in @($providers|Where-Object status -eq "AVAILABLE")){
  try{
   $sensors=@(Get-CimInstance -Namespace $p.namespace -ClassName Sensor -ErrorAction Stop)
   $hardware=@(Get-CimInstance -Namespace $p.namespace -ClassName Hardware -ErrorAction SilentlyContinue)
   $gpuHardware=@($hardware|Where-Object {($_.Name -match "AMD|Radeon|9060|9070") -or ($_.HardwareType -match "GpuAmd")})
   foreach($s in $sensors){
    $id=[string]$s.Identifier
    $parent=[string]$s.Parent
    $gpuRelated=($id -match "gpu") -or ($parent -match "gpu") -or (@($gpuHardware|Where-Object {$id.StartsWith([string]$_.Identifier) -or $parent -eq [string]$_.Identifier}).Count -gt 0)
    if(!$gpuRelated){continue}
    $match=$id -match $GpuMatch -or $parent -match $GpuMatch -or ($GpuMatch -eq "")
    # Keep ALL GPU samples, including other GPUs, so ambiguous GPU IDs can be diagnosed.
    $readings.Add([pscustomobject]@{
      timestamp=$now;provider=$p.namespace;identifier=$id;parent=$parent
      name=$s.Name;type=$s.SensorType;value=$s.Value
      gpu_hint_matched=$match
    })
   }
  }catch{Write-Warning "Read failed from $($p.namespace): $($_.Exception.Message)"}
 }
 if((Get-Date) -ge $end){break}
 Start-Sleep -Seconds $IntervalSec
}while($true)
$readings|Export-Csv (Join-Path $out "sensors.csv") -NoTypeInformation -Encoding utf8
$latest=@($readings|Where-Object {$_.type -match "Temperature|Clock|Power|Load|Fan"})
$summary=[ordered]@{
 output=$out;provider_status=$providers;gpu_readings=$readings.Count
 unique_gpu_sensor_names=@($latest|Select-Object -ExpandProperty name -Unique)
 temperature_sensor_count=@($latest|Where-Object {$_.type -match "Temperature"}|Select-Object -ExpandProperty identifier -Unique).Count
 caveat="ADLX DLL detection is not proof of accessible metrics; LHM/OHM WMI requires the respective monitoring service/app running."
}
$summary|ConvertTo-Json -Depth 6|Set-Content (Join-Path $out "summary.json") -Encoding utf8
$summary|ConvertTo-Json -Depth 6
Write-Host "Results: $out"
