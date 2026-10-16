# Bonsai 2 27B — Windows 11 / Radeon RX 9060 XT / RX 9070 XT

## TL;DR

**Bonsai 2 27B PQ2_0 works on both RX 9060 XT and RX 9070 XT with PrismML llama.cpp / Vulkan.**

| GPU (16 GB) | PP | TG |
|---|---:|---:|
| **RX 9070 XT** | **743.67 t/s** | **56.60 t/s** |
| **RX 9060 XT** | **44.16 t/s** | **29.83 t/s** |

**Note:** The RX 9060 XT's unusually low PP may be related to its PCIe 3.0 x1 connection.

**Separate test runs; not a controlled comparison. Tested on Windows 11 using Windows PowerShell 5.1.**

## 1. Test Environment

| Item | Tested configuration |
|---|---|
| OS / Shell | Windows 11 Pro x64 / **Windows PowerShell 5.1** |
| CPU / RAM | AMD Ryzen 7 5700X / 32 GB |
| Motherboard | ASUS TUF GAMING B550-PLUS |
| Main GPU | RX 9070 XT 16GB, primary PCIe 4.0 x16 slot |
| Secondary GPU | RX 9060 XT 16GB, secondary PCIe 3.0 x1 slot |
| Driver | AMD Adrenalin **26.3.1** |
| Engine | PrismML llama.cpp **build 10772**, commit **e8fd209c9**, Vulkan |
| GPU power | RX 9070 XT configured -30% power limit |

```powershell
$PSVersionTable.PSVersion
Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion
```

## 2. Installs (Windows PowerShell 5.1)

```powershell
# Skip packages already installed.
winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements
winget install -e --id Python.Python.3.11 --accept-package-agreements --accept-source-agreements
# Open a new PowerShell 5.1 window after installing.
git --version
py -3.11 --version
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

The Vulkan runtime comes with a compatible AMD GPU driver. A Vulkan SDK is **not required merely to run** prebuilt llama.cpp. The repository-wide setup.ps1 auto-detects a backend and might select HIP or CPU, so the following instructions explicitly install the fixed Vulkan release.

## 3. llama.cpp Source and Installation

Source: [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp). Pinned release: [prism-b10772-e8fd209](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b10772-e8fd209).

The benchmark used a locally built binary from the pinned source commit. The following commands install the published release instead; binary hashes may differ.

```powershell
$work = Join-Path $HOME "Bonsai-test"
New-Item -ItemType Directory -Force $work | Out-Null
Set-Location $work
if (-not (Test-Path ".\Bonsai-demo\.git")) {
  if (Test-Path ".\Bonsai-demo") { throw "Bonsai-demo exists but is not a Git repository." }
  git clone https://github.com/arnatoatadaink/Bonsai-demo.git
  if ($LASTEXITCODE -ne 0) { throw "Git clone failed." }
}
Set-Location .\Bonsai-demo
git fetch origin
if ($LASTEXITCODE -ne 0) { throw "Git fetch failed." }
git switch reports/bonsai2-27b-rx9070xt-20261016
if ($LASTEXITCODE -ne 0) { throw "Git switch failed." }
git pull --ff-only origin reports/bonsai2-27b-rx9070xt-20261016
if ($LASTEXITCODE -ne 0) { throw "Git pull failed." }
$tag = "prism-b10772-e8fd209"
$base = "https://github.com/PrismML-Eng/llama.cpp/releases/download/$tag"
$dest = Join-Path (Get-Location) "bin\vulkan"
New-Item -ItemType Directory -Force $dest | Out-Null
$cpuZip = Join-Path $env:TEMP "bonsai-llama-cpu.zip"
$vkZip = Join-Path $env:TEMP "bonsai-llama-vulkan.zip"
Invoke-WebRequest -UseBasicParsing -Uri "$base/llama-$tag-bin-win-cpu-x64.zip" -OutFile $cpuZip
Invoke-WebRequest -UseBasicParsing -Uri "$base/llama-$tag-bin-win-vulkan-x64.zip" -OutFile $vkZip
if (-not (Test-Path $cpuZip) -or -not (Test-Path $vkZip)) { throw "Binary download failed." }
Expand-Archive -LiteralPath $cpuZip -DestinationPath $dest -Force
Expand-Archive -LiteralPath $vkZip -DestinationPath $dest -Force
$server = Join-Path $dest "llama-server.exe"
if (-not (Test-Path $server)) { throw "llama-server.exe was not found after extraction." }
& $server --list-devices
```

The archive filenames follow the repository setup.ps1. If device detection fails, check the AMD driver and DLLs. This binary has not yet been validated on the second PC.

## 4. Model Source and Installation

Model: [prism-ml/Ternary-Bonsai-2-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf), **PQ2_0**, tested model size 7,206,168,928 bytes.

```powershell
py -3.11 -m venv .venv
$py = Join-Path (Get-Location) ".venv\Scripts\python.exe"
& $py -m pip install --upgrade pip "huggingface_hub[cli]"
$modelDir = Join-Path (Get-Location) "models\bonsai2-gguf\27B"
New-Item -ItemType Directory -Force $modelDir | Out-Null
$hf = Join-Path (Get-Location) ".venv\Scripts\hf.exe"
& $hf download prism-ml/Ternary-Bonsai-2-27B-gguf --include "*-PQ2_0.gguf" --local-dir $modelDir
$gguf = (Get-ChildItem -LiteralPath $modelDir -Filter "*-PQ2_0.gguf" -File | Select-Object -First 1).FullName
if (-not $gguf -or -not (Test-Path $gguf)) { throw "Model download failed." }
$expectedSha = "3907DC1658DB1F78A9826BF8D5BCB8DC65DB0D466388937AF57F2294FAE62EC1"
$actualSha = (Get-FileHash -LiteralPath $gguf -Algorithm SHA256).Hash
if ($actualSha -ne $expectedSha) { throw "Model SHA256 does not match the benchmarked GGUF; check model revision." }
Get-Item $gguf | Select-Object Name,Length
```

Image input is not used in this text-only test; mmproj is optional.

## 5. Launch and Verification

The actual Vulkan device indices vary by PC: use --list-devices before choosing the ID. Start one GPU server at a time, without MTP.

```powershell
& $server --list-devices
$device = "Vulkan1" # EXAMPLE ONLY: replace with the ID listed for your GPU.
& $server -m $gguf --host 127.0.0.1 --port 18081 --device $device -ngl 99 -sm none -c 4096 --cache-type-k q8_0 --cache-type-v q8_0 -fa on -np 1 --jinja
```

In a **second** PowerShell window:

```powershell
Invoke-RestMethod http://127.0.0.1:18081/health
Invoke-RestMethod http://127.0.0.1:18081/v1/models
$body = @{messages=@(@{role="system";content="You are a helpful assistant."},@{role="user";content="Explain why 1+1=2 in Japanese."});max_tokens=1024;temperature=1.0;top_p=0.95;stream=$false} | ConvertTo-Json -Depth 10
$r = Invoke-RestMethod -Method Post -Uri http://127.0.0.1:18081/v1/chat/completions -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body))
$r.choices[0].message
$r.timings | Format-List
```

Stop the server (Ctrl+C) before running the automated benchmark in a PowerShell window **where $server and $gguf have been defined**. If opening another session, rerun the path assignments shown below:

```powershell
Set-Location (Join-Path $HOME "Bonsai-test\Bonsai-demo")
$server = Join-Path (Get-Location) "bin\vulkan\llama-server.exe"
$gguf = (Get-ChildItem ".\models\bonsai2-gguf\27B" -Filter "*-PQ2_0.gguf" -File | Select-Object -First 1).FullName
.\reports\verify_bonsai2_rx9070xt.ps1 -ModelPath $gguf -LlamaServer $server -GpuName "RX 9070 XT" -Context 4096 -MaxTokens 2048
```

For RX 9060 XT, change `-GpuName` to `"RX 9060 XT"`. Benchmark results from each GPU should be saved separately and compared only after matching all settings.

## 6. Evidence and Performance

| GPU | Context | Prompt tokens | Generated tokens | PP t/s | TG t/s |
|---|---:|---:|---:|---:|---:|
| RX 9070 XT | **4,096** | **2,292** | **1,804** | **743.67** | **56.60** |
| RX 9060 XT (historical) | Not reconciled | Not reconciled | Not reconciled | 44.16 | 29.83 |

**No context-length sweep has been recorded for Bonsai2-27B on RX9070XT.** Do not infer 8K/32K/64K throughput from the 4K run. A context-length performance graph will be added only when multiple measured contexts are available.



RX9070XT timing detail: PP 2,292 tokens / 3,082.014 ms; TG 1,804 tokens / 31,857.099 ms. Completion ended at 4,096 tokens combined (finish_reason=length); sustained reasoning-token generation was verified, **not completed final-answer output**.

Original evidence archive: bonsai2_rx9070xt_20261016_144533.zip (user-provided, not committed). Model SHA256: 3907DC1658DB1F78A9826BF8D5BCB8DC65DB0D466388937AF57F2294FAE62EC1. Measured local-binary SHA256: 1BF104B2C3274899EF20BA92AFFDBBDAFB6CFD0903621C2492E702A284D16FEE.

**PCIe note:** RX 9060 XT runs in the PCIe 3.0 x1 secondary slot to preserve USB bandwidth. The unusual PP gap is environment-dependent and cannot establish an intrinsic GPU speed ratio.

Power XML: -30% limit enabled; -65 mV and -500 MHz offsets saved but not enabled. Detailed provenance: [VERIFIED_GPU_STATUS.md](VERIFIED_GPU_STATUS.md). Gemma/Qwen comparisons and MTP stability are deliberately excluded.