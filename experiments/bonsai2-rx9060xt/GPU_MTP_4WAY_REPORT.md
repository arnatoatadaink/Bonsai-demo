# Bonsai2 27B: RX 9060 XT / RX 9070 XT × MTP OFF / ON

## Purpose

Measure PP, TG, and MTP draft acceptance for the **same Bonsai2 GGUF and same tokenized long-text prompt** on the two GPUs, for publication as a Bonsai-demo verification report.

## Fixed setup

- Windows 11, local PrismML llama.cpp Vulkan build, PowerShell 7
- GGUF: `Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf`
- Dataset: `experiments/bonsai2-rx9060xt/distributed-summary-v01/dataset/prompt.txt`
- Exactly 32,768 prompt tokens + 512 requested output tokens, 98,304 reserved context
- KV: K Q8_0 / V Q4_0; Flash Attention ON; Fit OFF; ctx-checkpoints 0; dry-multiplier 0
- Logical batch 4096, physical ubatch 256, one parallel slot, no GPU splitting
- MTP ON: `--spec-type draft-mtp --spec-draft-n-max 2` / MTP OFF: no speculative arguments
- Three repetitions per combination by default, same running server per combination, fresh server between combinations

These settings are held fixed to isolate GPU and MTP as experimental variables. They do not assert that batch 4096/ubatch 256 is the optimal RX 9070 XT configuration.

## Run

First verify physical device names from the local binary:

```powershell
git pull --ff-only origin bench/bonsai2-rx9060xt-pp-batch-20261017
& "D:\AI\PrismML\dev\llama.cpp\build-vulkan-ucrt64\bin\llama-server.exe" --list-devices
```

The runner assumes `Vulkan0 = RX 9060 XT` and `Vulkan1 = RX 9070 XT`; check before running. Then:

```powershell
pwsh -NoProfile -File .\experiments\bonsai2-rx9060xt\runner\run_bonsai2_gpu_mtp_matrix.ps1 -Repetitions 3
```

Optional flags: `-ServerPath`, `-BonsaiModelPath`, `-InputPath`, `-Port`, `-GenerateTokens`, `-BetweenRunsSec`, `-OutputDir`.

Execution order: RX 9060 XT/MTP OFF → RX 9070 XT/MTP OFF → RX 9060 XT/MTP ON → RX 9070 XT/MTP ON. Each case launches its own server and retains raw outputs. The order is fixed and not randomized; session-long thermals, display load, PCIe lane configuration, and clock/power variation may confound between-GPU comparisons.

Results are written to `experiments/bonsai2-rx9060xt/gpu-mtp-matrix/results/matrix_*/`:
- `manifest.json`: model/binary/input SHA-256, settings
- `summary.csv`: 4 rows with mean PP/TG speed, acceptance, status
- each case `arguments.json`, `server.stdout.log`, `server.stderr.log`
- nested `run_*/summary.csv`, `response_1.json`, `response_2.json`, `response_3.json` and `metadata.json`

Only report results when each case has all requested valid trials. For publication, add: OS, driver, Vulkan device-to-GPU mapping, PCIe link width, model and server hashes, per-case samples, means, and any launch failures. **Do not interpret MTP OFF draft acceptance values as zero; they are inapplicable.**

## Results (fill after local execution)

| GPU | MTP | PP tok/s mean | TG tok/s mean | Draft acceptance | Successful trials |
|---|---|---:|---:|---:|---:|
| RX 9060 XT | OFF | — | — | N/A | — |
| RX 9070 XT | OFF | — | — | N/A | — |
| RX 9060 XT | ON, draft 2 | — | — | — | — |
| RX 9070 XT | ON, draft 2 | — | — | — | — |

No new performance figures are claimed before the script is executed on the actual hardware.
