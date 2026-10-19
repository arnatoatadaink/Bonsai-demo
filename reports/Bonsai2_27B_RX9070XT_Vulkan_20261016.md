# Bonsai 2 27B — Radeon RX 9060 XT / RX 9070 XT (Windows Vulkan)

## TL;DR

**Bonsai 2 27B works on both GPUs with MTP OFF and ON (12/12 successful requests).**

| GPU | MTP | PP (tokens/s) | TG (tokens/s) |
|---|---|---:|---:|
| RX 9060 XT 16 GB | OFF | **312.80** | **26.35** |
| RX 9060 XT 16 GB | ON | **287.59** | **39.93** |
| RX 9070 XT 16 GB | OFF | **597.65** | **48.58** |
| RX 9070 XT 16 GB | ON | **562.37** | **66.03** |

**Same MTP-capable GGUF, same 32K prompt and 96K context, three requests per configuration.** MTP raises TG by **51.56%** (RX 9060 XT) and **35.91%** (RX 9070 XT), while PP falls by **8.06%** and **5.90%**, respectively. These are stage speeds, not end-to-end speedups.

**Note:** The RX 9060 XT secondary slot is configured for PCIe 3.0 x1, so GPU-to-GPU performance differences may be system-dependent.

## 1. Test Environment

| Item | Tested configuration |
|---|---|
| OS / Shell | Windows 11 Pro x64 / **PowerShell 5.1 for setup; PowerShell 7 for the 4-way matrix** |
| CPU / RAM | AMD Ryzen 7 5700X / 32 GB |
| Motherboard | ASUS TUF GAMING B550-PLUS |
| Main GPU | RX 9070 XT 16GB, primary PCIe 4.0 x16 slot |
| Secondary GPU | RX 9060 XT 16GB, secondary PCIe 3.0 x1 slot |
| Driver | AMD Adrenalin **26.3.1** |
| Engine | PrismML llama.cpp **build 10772**, commit **e8fd209c9**, Vulkan |
| Matrix model | `Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf` (different from the standalone PQ2_0 GGUF below) |
| GPU power | RX 9070 XT configured -30% power limit |

```powershell
$PSVersionTable.PSVersion
Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion
```

## 2. Installs (Windows PowerShell 5.1)

The 4-way benchmark runner requires **PowerShell 7 (`pwsh`)**. Install separately if you will reproduce the matrix: 

```powershell
winget install --id Microsoft.PowerShell -e --accept-package-agreements --accept-source-agreements
```

Open a new terminal and verify `pwsh --version` before running the matrix. The general Windows installation commands below use PowerShell 5.1.

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

### 4-way matrix model requirement

The 2026-10-19 MTP comparison **does not use the standalone GGUF downloaded above**. It requires the separately prepared **MTP-capable** `Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf`, SHA256:

`3CB3F0056D2E34EE44245A64396004A21F8492573D6CE1266EC4B7222C131DD4`

The source report specifies the model filename and hash but **does not document an authoritative download location or reproducible conversion recipe**. Do not rename or substitute the standalone PQ2_0 GGUF to enable MTP. For an independent reproduction, supply the verified MTP-capable file before running the matrix.

## 5. Launch and Verification

The actual Vulkan device indices vary by PC: use --list-devices before choosing the ID. Start one GPU server at a time, without MTP. This 4K launch is only a smoke test, **not** the RX 9060 XT 96K/32K PP tuning setup.

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

## 6. 4-way GPU × MTP verification (2026-10-19)

All cases used the same MTP-capable model and input; 32,768 input tokens, 512 requested output tokens, 98,304 context, K Q8_0 / V Q4_0, Flash Attention ON, `--fit off`, `--ctx-checkpoints 0`, `--dry-multiplier 0`, batch 4,096 / ubatch 256, single slot and no GPU splitting. MTP ON adds `--spec-type draft-mtp --spec-draft-n-max 2`.

| GPU / MTP | PP trial speeds (t/s) | TG trial speeds (t/s) | PP mean | TG mean | Draft accepted |
|---|---|---|---:|---:|---:|
| RX 9060 XT / OFF | 317.140 / 311.268 / 310.003 | 26.412 / 26.298 / 26.330 | **312.804** | **26.347** | N/A |
| RX 9060 XT / ON | 288.264 / 287.454 / 287.052 | 40.451 / 40.204 / 39.140 | **287.590** | **39.932** | 89.112% |
| RX 9070 XT / OFF | 597.562 / 598.036 / 597.360 | 48.775 / 48.492 / 48.473 | **597.653** | **48.580** | N/A |
| RX 9070 XT / ON | 564.207 / 561.560 / 561.327 | 58.913 / 69.629 / 69.540 | **562.365** | **66.028** | 78.392% |

**Important:** RX 9070 XT/MTP ON's first TG run was slower (58.913 t/s vs about 69.6 t/s in runs two and three); the source does not establish why. All measurements are successful requests, not a multi-hour stability test. The four cases were run in a fixed order, with a new server per condition but three requests on the same server; thermal and display effects were not independently controlled.

### Reproduce the matrix (PowerShell 7)

Source script: [`run_bonsai2_gpu_mtp_matrix.ps1`](https://github.com/arnatoatadaink/Bonsai-demo/blob/bench/bonsai2-rx9060xt-pp-batch-20261017/experiments/bonsai2-rx9060xt/runner/run_bonsai2_gpu_mtp_matrix.ps1).

```powershell
# From a checkout of the experimental branch, in PowerShell 7:
pwsh -NoProfile -File .\experiments\bonsai2-rx9060xt\runner\run_bonsai2_gpu_mtp_matrix.ps1 `
  -ServerPath "<absolute-path-to-llama-server.exe>" `
  -BonsaiModelPath "<absolute-path-to-MTP-capable-GGUF>" `
  -InputPath "<absolute-path-to-original-prompt.txt>" `
  -Repetitions 3
```

The local dataset is `experiments/bonsai2-rx9060xt/distributed-summary-v01/dataset/prompt.txt` (not included in the Git repository). The script assumes `Vulkan0 = RX 9060 XT` and `Vulkan1 = RX 9070 XT`; verify this with `--list-devices` first. These are **PowerShell 7** commands, unlike the standalone model installation and 4K smoke test above.

### Raw evidence and caveats

- [Source matrix report](https://github.com/arnatoatadaink/Bonsai-demo/blob/bench/bonsai2-rx9060xt-pp-batch-20261017/experiments/bonsai2-rx9060xt/GPU_MTP_4WAY_REPORT.md) (all 12 runs succeeded). Local result archive `matrix_20261019_162628.zip` was supplied separately; it is not committed.
- Server SHA256: `1BF104B2C3274899EF20BA92AFFDBBDAFB6CFD0903621C2492E702A284D16FEE`; MTP-capable model SHA256: `3CB3F0056D2E34EE44245A64396004A21F8492573D6CE1266EC4B7222C131DD4`; input SHA256: `758A9BE8F2DF0181226C15C070D8E8E704AC17EEBA893BBABB9726E6525A400F`.
- The early 4K, non-MTP RX 9070 XT test (PP 743.67 t/s, TG 56.60 t/s) used a **different standalone GGUF, different workload, and shorter context**. It is not a representative 96K/32K comparison and is superseded by the matrix for the TL;DR.
- Older RX 9060 XT PP 44.16 t/s and typical TG 29.83 t/s came from separate, non-matched tests; they are not part of the matrix means.
- The four-way matrix used **PowerShell 7**. Installation steps and the separate smoke test in this report target **Windows PowerShell 5.1**.
- Radeon RX 9060 XT's PCIe x1 configuration, GPU power limits, and the fixed sequence of cases limit hardware-independent interpretation.

Additional hardware and historical details: [VERIFIED_GPU_STATUS.md](VERIFIED_GPU_STATUS.md).
