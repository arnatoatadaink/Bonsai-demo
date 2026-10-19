# Bonsai 2 27B — Windows 11 / Radeon RX 9060 XT / RX 9070 XT

## TL;DR

**Bonsai 2 27B PQ2_0 works on both RX 9060 XT and RX 9070 XT with PrismML llama.cpp / Vulkan.**

| GPU (16 GB) | PP | TG | Evidence |
|---|---:|---:|---|
| **RX 9060 XT** | **310.27 t/s** | **29.83 t/s** | PP: MTP OFF, 96K context / 32K input, 3-run mean; TG: historical typical value |
| RX 9070 XT | 743.67 t/s | 56.60 t/s | 4K short-context test only; **PP outlier** |

**Note:** RX 9060 XT uses PCIe 3.0 x1; older low PP readings may be environment-specific. **The RX 9070 XT short-context PP result is not representative of long-context operation.**

**These are separate test configurations, not a controlled GPU comparison. All Windows commands target Windows PowerShell 5.1.**

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

## 6. Evidence and Performance

### RX 9060 XT — long-context prompt processing, MTP OFF

**This is the primary PP performance reference in this report.** Measured on Bonsai 2 27B PQ2_0 with RX 9060 XT / Vulkan, MTP **OFF**, context **98,304 tokens**, prompt **32,768 tokens**, KV cache **K Q8_0 / V Q4_0**, logical batch `-b 32768`, physical microbatch `-ub 512`.

| Trial | PP (tokens/s) |
|---|---:|
| 1 | 313.79 |
| 2 | 309.05 |
| 3 | 307.96 |
| **Mean (3/3 valid)** | **310.27** |

Source run: `experiments/bonsai2-rx9060xt/pp-batch-v01/results/run_20261018_001236_ctx96k_pp32k_auto` (local experiment path; raw run records not committed with this report). Repeats recorded `cache_n=0`. Runner: `run_bonsai2_pp_ctx96k_auto.ps1` (experiment runner, not the general smoke-test script below).

**MTP ON measurements are intentionally excluded** from this report and these PP statistics. Other MTP OFF exploratory results with `-b 32768` were 308.71 t/s (`-ub 512`), 294.88 t/s (`-ub 1024`), and 292.14 t/s (`-ub 1536`). These suggest larger microbatches did not improve throughput in the tested setup, not a universal optimal setting.

### llama.cpp PP tuning notes

- `-b` / `--batch-size` controls logical batch size; `-ub` / `--ubatch-size` controls physical microbatch size. Verify flags with the installed PrismML fork’s `--help`.
- For **the RX 9060 XT 96K/32K workload**, `-b 32768 -ub 512` is the **best documented MTP OFF baseline** here. Do not infer that it is optimal at 4K or on another GPU.
- Keep **MTP OFF**, input tokens, context, K/V types, Flash Attention, GPU placement, cache reuse, and software build fixed when changing `-b` or `-ub`. Compare multiple repeats.
- The generic 4K verification script in Section 5 is a smoke test **not the 96K/32K performance benchmark**; its PP output must not be substituted for the MTP OFF long-context result.

### Other historical measurements

| GPU | Context | Prompt tokens | Generated tokens | PP t/s | TG t/s |
|---|---:|---:|---:|---:|---:|
| RX 9060 XT (MTP OFF, 3-run PP mean) | **98,304** | **32,768** | N/A | **310.27** | **29.83 (historical typical TG; separate run)** |
| RX 9070 XT (short-context outlier) | 4,096 | 2,292 | 1,804 | 743.67 | 56.60 |
| RX 9060 XT (older record) | Not reconciled | Not reconciled | Not reconciled | 44.16 | 29.83 |

**Do not interpret the RX 9070 XT 743.67 t/s (4K) as a typical long-context PP rate.** No matched RX 9070 XT 96K/32K test is available. There is not yet a controlled *context-length sweep* to graph.



RX9070XT timing detail: PP 2,292 tokens / 3,082.014 ms; TG 1,804 tokens / 31,857.099 ms. Completion ended at 4,096 tokens combined (finish_reason=length); sustained reasoning-token generation was verified, **not completed final-answer output**.

Original evidence archive: bonsai2_rx9070xt_20261016_144533.zip (user-provided, not committed). Model SHA256: 3907DC1658DB1F78A9826BF8D5BCB8DC65DB0D466388937AF57F2294FAE62EC1. Measured local-binary SHA256: 1BF104B2C3274899EF20BA92AFFDBBDAFB6CFD0903621C2492E702A284D16FEE.

**PCIe note:** RX 9060 XT runs in the PCIe 3.0 x1 secondary slot to preserve USB bandwidth. The old low PP result may be environment-dependent; the 4K RX 9070 XT PP result is also a short-context outlier. Neither establishes an intrinsic GPU speed ratio.

Power XML: -30% limit enabled; -65 mV and -500 MHz offsets saved but not enabled. Detailed provenance: [VERIFIED_GPU_STATUS.md](VERIFIED_GPU_STATUS.md). Gemma/Qwen comparisons and MTP stability are deliberately excluded.