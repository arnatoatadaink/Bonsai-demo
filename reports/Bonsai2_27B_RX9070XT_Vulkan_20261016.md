# Bonsai 2 27B — AMD Radeon RX 9060 XT / 9070 XT (Windows Vulkan)

## TL;DR

**Bonsai 2 27B (PQ2_0) works on both RX 9060 XT and RX 9070 XT with PrismML llama.cpp / Vulkan.**

| GPU (16 GB each) | Prompt Processing (PP) | Token Generation (TG) | Status |
|---|---:|---:|---|
| **RX 9070 XT** | **743.67 t/s** | **56.60 t/s** | Verified |
| **RX 9060 XT** | **44.16 t/s** | **29.83 t/s** | Verified (historical run) |

**※ RX 9060 XTのPP低速はPCIe 3.0 x1接続に由来する可能性があります。** 実測条件は完全に同一ではなく、GPU単体のPP性能差ではありません。

## RX 9070 XT — Tested configuration

| Item | Configuration |
|---|---|
| Model | Ternary-Bonsai-2-27B-PQ2_0.gguf |
| Inference | PrismML llama.cpp 0.2.0-dev, build 10772, commit `e8fd209c9`; Vulkan |
| GPU / device | Radeon RX 9070 XT 16GB / Vulkan1 |
| Driver / OS | AMD Adrenalin 26.3.1 / Windows 11 Pro |
| CPU / RAM | Ryzen 7 5700X / 32GB |
| Mainboard | ASUS TUF GAMING B550-PLUS |
| Model settings | Context 4096; KV Q8_0/Q8_0; Flash Attention ON; -ngl 99; -sm none; -np 1; --jinja; no MTP |
| Power tuning | Radeon power limit -30% (enabled per saved AMD profile) |

The RX 9070 XT measurement processed **2,292 prompt tokens** in **3,082 ms** and generated **1,804 tokens** in **31,857 ms**. Generation stopped at the 4,096-token context limit (finish_reason=`length`); sustained generation was verified, but a final answer was not completed.

The RX 9060 XT figures are from an earlier working configuration. They are **not** a matched-prompt, matched-settings controlled performance comparison with the RX 9070 XT.

## PCIe layout and PP caveat

| GPU | Slot / routing | Configured PCIe link | Nominal one-way bandwidth |
|---|---|---|---:|
| RX 9070 XT | CPU-connected primary slot | PCIe 4.0 x16 | ~31.5 GB/s |
| RX 9060 XT | Chipset-connected secondary slot | **PCIe 3.0 x1**, intentionally set to preserve USB bandwidth | ~0.985 GB/s |

The nominal PCIe throughput ratio for the configured slots is about 32x; the historical PP results differ by about 16.8x. Those ratios must not be conflated: the actual RX 9060 XT PP bottleneck was not isolated in a controlled experiment. PCIe limitation is an **environment-specific plausible contributor**, not proof that the GPU's native prompt-processing performance is 16.8x lower.

The GPUs both have 16GB VRAM; RX 9070 XT has 640 GB/s rated VRAM bandwidth versus RX 9060 XT's 320 GB/s, and roughly twice the compute resources. Historical TG is 56.60 / 29.83 = **1.90x**, consistent with the hardware tier, but cross-run conditions differ.

## Evidence and limitations

- RX 9070 XT source run: `bonsai2_rx9070xt_20261016_144533.zip` (user-provided, not committed).
- PrismML llama.cpp: build 10772, commit `e8fd209c9`; model SHA256: `3907DC1658DB1F78A9826BF8D5BCB8DC65DB0D466388937AF57F2294FAE62EC1`; server SHA256: `1BF104B2C3274899EF20BA92AFFDBBDAFB6CFD0903621C2492E702A284D16FEE`.
- GPU tuning XML `RX9070XT_UD65.xml`: power-limit -30% enabled; saved voltage offset -65 and clock offset -500 have disabled state flags, so actual application is unconfirmed.
- RX 9060 XT historical PP 44.16 / TG 29.83 requires original run-condition reconciliation.
- The first RX 9070 XT raw `/completion` attempt returned EOS after 1 token and cannot be used for TG. The verified result used the chat template.
- Longer contexts, completed final answers, and matched-GPU benchmarking are outside this report.
- Other-model comparisons (Gemma / Qwen / MTP testing) are kept on a separate branch.

Additional provenance: [VERIFIED_GPU_STATUS.md](VERIFIED_GPU_STATUS.md). ASUS slot specifications: https://www.asus.com/jp/motherboards-components/motherboards/all-series/tuf-gaming-b550-plus/techspec/
