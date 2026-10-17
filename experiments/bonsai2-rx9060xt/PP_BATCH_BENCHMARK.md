# RX 9060 XT / Bonsai2: PP batch sweep

## Purpose
Measure prompt-processing throughput versus logical batch (`-b`) and microbatch (`-ub`) with Bonsai2 PQ2_0 and the matching PrismML llama.cpp fork. No model files, binaries, local launch scripts, or machine-specific paths are committed.

## Prerequisites
- Windows PowerShell 7 (`pwsh`); `llama-bench.exe` from the **Bonsai-compatible PrismML fork**, not stock llama.cpp.
- RX 9060 XT selected as `Vulkan0` (verify with `llama-bench.exe --list-devices` where supported).
- Stop any llama-server occupying VRAM. Point `-ModelPath` to the installed Bonsai2 GGUF and `-BenchPath` to the corresponding executable.

## Quick test (12 cases, 3 repeats per case)
```powershell
pwsh -NoProfile -File .\experiments\bonsai2-rx9060xt\runner\test_bonsai2_pp_rx9060xt.ps1 -Mode quick -ModelPath "<model.gguf>" -BenchPath "<llama-bench.exe>" -Device Vulkan0
```
Change `-Mode` to `extended` (36 cases) or `stress` (16 cases) only after quick succeeds.

| Mode | Logical batches | Physical microbatches | PP lengths |
|---|---|---|---|
| quick | 32768, 65536 | 512, 1024, 1536 | 4096, 8192 |
| extended | 32768, 65536, 131072 | 512, 1024, 1536, 2048 | 4096, 8192, 16384 |
| stress | 131072, 262144 | 1024, 1536, 2048, 4096 | 8192, 16384 |

Fixed: GPU offload 99 layers, Vulkan device, split mode none, K q8_0 / V q4_0, Flash Attention on, threads 4, PP-only (generation disabled). These match the relevant performance knobs of the local launcher; no speculative decoding/MTP.

## Results / interpretation
Results are written outside the checkout by default, under the Windows temp directory `bonsai2-pp-results/<timestamp>-<mode>/`. Each case generates a JSON benchmark, stderr log, and a CSV summary that also preserves failed cases. Override with `-OutputDir`.

A logical batch of 32768 does not mean 32768 actual prompt tokens: for this experiment prompt lengths are varied independently. `llama-bench` does **not** reserve the existing llama-server configuration's full 98304-token context; follow with server tests at 96k using actual 16k/32k/64k input for long-context validation. Track driver, llama.cpp build, GPU power limit, VRAM residency, and temperature separately.

Status: scripts committed for execution; **no RX 9060 XT measurements have been performed by ChatGPT**.
