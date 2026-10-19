# Bonsai 2 27B — Windows Vulkan GPU × MTP Benchmark

## TL;DR

**Bonsai 2 27B ran successfully on RX 9060 XT and RX 9070 XT with MTP OFF and ON: 4 server starts, 12/12 successful requests.**

| GPU (16 GB) | MTP | PP (tokens/s) | TG (tokens/s) |
|---|---|---:|---:|
| RX 9060 XT | OFF | **312.80** | **26.35** |
| RX 9060 XT | ON | **287.59** | **39.93** |
| RX 9070 XT | OFF | **597.65** | **48.58** |
| RX 9070 XT | ON | **562.37** | **66.03** |

**Protocol:** 96K context, 32K input, 512 generated tokens, 3 runs per condition using the *same MTP-capable GGUF*. MTP raised TG by 36–52% and reduced PP by 6–8% in these tests. These are separate processing-stage speeds, not end-to-end response-time gains.

**Note:** RX 9060 XT uses a PCIe 3.0 x1 secondary slot; across-GPU performance differences are environment-dependent.

## 1. Test environment

| Item | Tested setup |
|---|---|
| OS / shell | Windows 11 Pro x64; **PowerShell 7** for benchmark |
| CPU / RAM | AMD Ryzen 7 5700X / 32 GB |
| Board | ASUS TUF GAMING B550-PLUS |
| GPUs | RX 9070 XT (primary PCIe 4.0 x16); RX 9060 XT (secondary configured PCIe 3.0 x1) |
| Driver | AMD Adrenalin 26.3.1 |
| Runtime | PrismML llama.cpp, Vulkan, build 10772 / commit `e8fd209c9` |
| Model | `Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf` |
| Power | RX 9070 XT -30% power limit was configured |

## 2. Installs (Windows PowerShell 5.1 bootstrap)

Install Git and PowerShell 7 if absent, then reopen the terminal as PowerShell 7 (`pwsh`). The benchmark itself runs in **PowerShell 7**, not Windows PowerShell 5.1.

```powershell
winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements
winget install -e --id Microsoft.PowerShell --accept-package-agreements --accept-source-agreements
pwsh --version
```

Install or update a compatible AMD graphics driver with Vulkan support. A Vulkan SDK is not necessary merely to run the prebuilt binary.

## 3. llama.cpp source and install

Source: [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp). Benchmark binary commit: `e8fd209c9`; packaged release family: [`prism-b10772-e8fd209`](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b10772-e8fd209). The measured binary was locally built; packaged binaries may differ.

```powershell
$work = Join-Path $HOME 'Bonsai-test'
New-Item -ItemType Directory -Force $work | Out-Null
Set-Location $work
if (-not (Test-Path .\Bonsai-demo\.git)) {
  git clone https://github.com/arnatoatadaink/Bonsai-demo.git
  if ($LASTEXITCODE -ne 0) { throw 'Clone failed' }
}
Set-Location .\Bonsai-demo
git fetch origin
if ($LASTEXITCODE -ne 0) { throw 'Fetch failed' }
git switch reports/bonsai2-27b-rx9070xt-20261016
if ($LASTEXITCODE -ne 0) { throw 'Branch switch failed' }
git pull --ff-only origin reports/bonsai2-27b-rx9070xt-20261016
if ($LASTEXITCODE -ne 0) { throw 'Pull failed' }
$tag = 'prism-b10772-e8fd209'
$url = "https://github.com/PrismML-Eng/llama.cpp/releases/download/$tag"
$bin = Join-Path (Get-Location) 'bin\vulkan'
New-Item -ItemType Directory -Force $bin | Out-Null
$cpuZip = Join-Path $env:TEMP 'bonsai-cpu.zip'
$vkZip = Join-Path $env:TEMP 'bonsai-vulkan.zip'
Invoke-WebRequest -UseBasicParsing -Uri "$url/llama-$tag-bin-win-cpu-x64.zip" -OutFile $cpuZip
Invoke-WebRequest -UseBasicParsing -Uri "$url/llama-$tag-bin-win-vulkan-x64.zip" -OutFile $vkZip
Expand-Archive -LiteralPath $cpuZip -DestinationPath $bin -Force
Expand-Archive -LiteralPath $vkZip -DestinationPath $bin -Force
$server = Join-Path $bin 'llama-server.exe'
if (-not (Test-Path $server)) { throw 'llama-server.exe missing' }
& $server --list-devices
```

Verify the displayed GPU-to-Vulkan mapping before measuring. The provided runner uses **Vulkan0 = RX 9060 XT** and **Vulkan1 = RX 9070 XT**, as on the measured PC; these IDs are not portable.

## 4. Model and input prerequisites

**The matrix requires the MTP-capable model, not the standalone `*-PQ2_0.gguf` model.** Do not rename the standalone model to attempt MTP testing.

| Input | Exact file / SHA256 |
|---|---|
| GGUF | `Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf` |
| Model SHA256 | `3CB3F0056D2E34EE44245A64396004A21F8492573D6CE1266EC4B7222C131DD4` |
| Long-prompt source | `distributed-summary-v01/dataset/prompt.txt` (local experiment) |
| Prompt source SHA256 | `758A9BE8F2DF0181226C15C070D8E8E704AC17EEBA893BBABB9726E6525A400F` |

**Reproducibility limitation:** The source experiment provides no verified public URL or generation recipe for this exact MTP-capable GGUF, and the original prompt dataset is not tracked in Git. Obtain the original verified artifacts separately. Installation alone cannot recreate the published measurements.

After providing these files on your machine, confirm hashes in PowerShell 7:

```powershell
$model = '<absolute-path-to-MTP-capable-GGUF>'
$input = '<absolute-path-to-original-prompt.txt>'
if (-not (Test-Path -LiteralPath $model) -or -not (Test-Path -LiteralPath $input)) { throw 'Required files missing' }
$expectedModel = '3CB3F0056D2E34EE44245A64396004A21F8492573D6CE1266EC4B7222C131DD4'
$expectedInput = '758A9BE8F2DF0181226C15C070D8E8E704AC17EEBA893BBABB9726E6525A400F'
if ((Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ne $expectedModel) { throw 'Model SHA256 mismatch' }
if ((Get-FileHash -LiteralPath $input -Algorithm SHA256).Hash -ne $expectedInput) { throw 'Input SHA256 mismatch' }
Write-Host 'Model and input hashes verified'
```

## 5. Launch and verify (PowerShell 7)

The publication branch contains both the four-case runner and its dependent request runner under [`reports/benchmark/`](benchmark/). It starts/stops llama-server automatically: one server per GPU × MTP case, three requests per server. **Do not use the older standalone 4K smoke test for these results.**

```powershell
pwsh -NoProfile -File .\reports\benchmark\run_bonsai2_gpu_mtp_matrix.ps1 `
  -ServerPath $server `
  -BonsaiModelPath $model `
  -InputPath $input `
  -Gpu9060Device Vulkan0 `
  -Gpu9070Device Vulkan1 `
  -Repetitions 3
```

**Caution:** This copied runner has not yet been independently rerun from the publication branch. Set `-Gpu9060Device` and `-Gpu9070Device` from the actual `--list-devices` output. The runner checks model/input SHA256 and stops on mismatches. Stop other llama-server instances before running. The underlying original benchmark completed 12/12 requests.

## 6. Results and evidence

| GPU / MTP | PP mean | TG mean | Draft acceptance | Valid |
|---|---:|---:|---:|---:|
| RX 9060 XT / OFF | 312.804 | 26.347 | N/A | 3/3 |
| RX 9060 XT / ON | 287.590 | 39.932 | 89.112% | 3/3 |
| RX 9070 XT / OFF | 597.653 | 48.580 | N/A | 3/3 |
| RX 9070 XT / ON | 562.365 | 66.028 | 78.392% | 3/3 |

All runs used context 98,304; 32,768 prompt tokens; 512 output tokens; K Q8_0 / V Q4_0; Flash Attention ON; `--fit off`; `--ctx-checkpoints 0`; `--dry-multiplier 0`; batch 4,096; ubatch 256; one parallel slot; no GPU splitting. MTP ON used `--spec-type draft-mtp --spec-draft-n-max 2`.

The RX 9070 XT MTP ON TG trials were **58.913 / 69.629 / 69.540 t/s**. The lower first trial has no established cause; the mean is not a stability guarantee. Cases ran in a fixed order, so thermal, display and PCIe effects may remain.

Raw individual trials, acceptance measurements and runner notes are documented in the [original experiment report](https://github.com/arnatoatadaink/Bonsai-demo/blob/bench/bonsai2-rx9060xt-pp-batch-20261017/experiments/bonsai2-rx9060xt/GPU_MTP_4WAY_REPORT.md). Original archive: `matrix_20261019_162628.zip` (not tracked in Git). The measured server binary SHA256 was `1BF104B2C3274899EF20BA92AFFDBBDAFB6CFD0903621C2492E702A284D16FEE`.

Previous 4K/standalone-GGUF measurements and earlier RX 9060 XT readings are intentionally excluded from the headline comparison. See [historical GPU status](VERIFIED_GPU_STATUS.md).

## 7. AI-assisted setup and troubleshooting

If the setup, download, build, or launch commands fail, a coding assistant (for example, GPT-6.1-sol) can complete the machine-specific installation. Provide this report and both scripts in [`reports/benchmark/`](benchmark/).

1. Read the benchmark report, matrix runner and request runner before changing the environment.
2. Inspect Windows version, PowerShell 7, AMD driver, Vulkan device enumeration, local llama.cpp build/release, and any missing runtime DLLs.
3. Fix local installation paths, archive extraction, dependencies or build steps as necessary. Record the installed llama.cpp commit and binary SHA256. A release binary is **not** automatically equivalent to the measured locally built executable.
4. Locate the exact MTP-capable GGUF and the original dataset; **verify their SHA256 hashes** against Section 4. Do not silently replace either file with another model or synthetic input.
5. Confirm which physical GPU corresponds to each Vulkan device; pass the correct `-Gpu9060Device` and `-Gpu9070Device` arguments. Keep both GPUs separate and run all four GPU × MTP conditions with three trials each.
6. Save the complete result folder, successful/failed trial counts, relevant server logs and any deviations from the published setup.

**Fixed experimental conditions:** model and input identity (SHA256), 98,304 context, 32,768 prompt tokens, 512 generated tokens, K Q8_0 / V Q4_0, Flash Attention ON, `--fit off`, `--ctx-checkpoints 0`, `--dry-multiplier 0`, batch 4,096 / ubatch 256, one parallel slot, no GPU split, and MTP draft length 2 for MTP ON. Do not silently alter these to get a successful run.

**Machine-specific adjustments allowed:** filesystem paths, dependencies, installation method, driver troubleshooting, and device IDs. If the binary or settings differ from the published benchmark, label the result a **modified configuration**, not an exact reproduction. A missing verified GGUF or dataset is a reproducibility blocker, not permission to substitute one.

**Current validation status:** the original 2026-10-19 matrix completed 12/12 requests. The copied, path-corrected runner in this reporting branch has not yet been rerun on the Windows GPU host.
