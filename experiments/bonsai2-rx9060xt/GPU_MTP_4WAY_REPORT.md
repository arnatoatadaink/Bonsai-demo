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

## Measured results — 2026-10-19 local run

Archive supplied by tester: `matrix_20261019_162628.zip` (retained locally, not committed).
All **12/12** requests completed successfully. Each condition uses a fresh server process with 3 requests (32,768 prompt tokens + 512 generated tokens), MTP ON = draft 2, context 98,304, batch 4096, ubatch 256, KV Q8_0/Q4_0, Flash Attention ON.

| Device | MTP | PP mean tok/s | TG mean tok/s | Draft acceptance | Valid trials |
|---|---|---:|---:|---:|---:|
| RX 9060 XT (Vulkan0) | OFF | 312.804 | 26.347 | N/A | 3/3 |
| RX 9070 XT (Vulkan1) | OFF | 597.653 | 48.580 | N/A | 3/3 |
| RX 9060 XT (Vulkan0) | ON / draft 2 | 287.590 | 39.932 | 89.112% | 3/3 |
| RX 9070 XT (Vulkan1) | ON / draft 2 | 562.365 | 66.028 | 78.392% | 3/3 |

MTP ON vs OFF: RX9060XT PP **−8.06%**, TG **+51.56%**; RX9070XT PP **−5.90%**, TG **+35.91%**. These are **separate stages' measured throughputs**, not end-to-end application latency improvements.

### Individual samples

| Device / MTP | PP trial 1 / 2 / 3 tok/s | TG trial 1 / 2 / 3 tok/s |
|---|---|---|
| RX9060 / OFF | 317.140 / 311.268 / 310.003 | 26.412 / 26.298 / 26.330 |
| RX9070 / OFF | 597.562 / 598.036 / 597.360 | 48.775 / 48.492 / 48.473 |
| RX9060 / ON | 288.264 / 287.454 / 287.052 | 40.451 / 40.204 / 39.140 |
| RX9070 / ON | 564.207 / 561.560 / 561.327 | 58.913 / 69.629 / 69.540 |

Note: RX9070 MTP ON's first TG trial is unusually slow despite identical reported `draft_n=398`, `draft_n_accepted=312` in each trial. Thus mean TG 66.028 tok/s combines two ~69.6 tok/s trials and one ~58.9 tok/s trial; cause is not determined.

### Evidence hashes from manifest

- Server SHA-256: `1BF104B2C3274899EF20BA92AFFDBBDAFB6CFD0903621C2492E702A284D16FEE`
- Model SHA-256: `3CB3F0056D2E34EE44245A64396004A21F8492573D6CE1266EC4B7222C131DD4`
- Input SHA-256: `758A9BE8F2DF0181226C15C070D8E8E704AC17EEBA893BBABB9726E6525A400F`

### Limitations

- Four cases are executed in a fixed order, not counterbalanced; thermals, display activity, clocks and PCIe may confound GPU comparison.
- The 9070 XT and 9060 XT share test settings, but are not claimed to be equally tuned.
- MTP ON and OFF may differ in PP overhead and allocation behavior; the PP difference is reported as observed, not solely attributed to MTP's algorithm.
- This is an operational verification (12 successful requests), not evidence of long-term crash-free stability.
- Physical GPU mapping and PCIe link widths must be verified from system output before final public release.

