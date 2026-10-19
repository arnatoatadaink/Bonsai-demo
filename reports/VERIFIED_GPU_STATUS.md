# Bonsai2-27B GPU verification status (2026-10-16)

## Verified
- **RX 9060 XT 16 GB**: Bonsai2-27B PQ2_0 previously verified on Windows/Vulkan. **Preferred MTP OFF long-context PP evidence:** 96K context, 32K input, `-b 32768 -ub 512`, K Q8_0 / V Q4_0, 3/3 valid PP measurements 313.79 / 309.05 / 307.96 t/s (**mean 310.27 t/s**, `cache_n=0`). Historical 44.16 PP and 29.83 TG need original test condition reconciliation.
- **RX 9070 XT 16 GB**: Bonsai2-27B PQ2_0 independently verified on Vulkan1, PrismML llama.cpp build 10772, commit `e8fd209c9`, AMD Adrenalin 26.3.1. Model loaded, 2,292 tokens evaluated, 1,804 tokens generated. **PP 743.6696 t/s (4K short-context outlier, NOT representative of long-context PP), TG 56.5965 t/s**. First raw completion test returned EOS immediately; second chat-template test successfully performed sustained generation.

## RX 9060 XT MTP OFF long-context PP evidence

- GPU: RX 9060 XT 16GB / Vulkan; model: Bonsai2-27B PQ2_0.
- MTP **OFF**. Context **98,304**, input **32,768** tokens. KV **K q8_0 / V q4_0**. Logical batch **32768**, physical microbatch **512**.
- Three valid PP speeds: **313.79, 309.05, 307.96 t/s**, average **310.27 t/s**; no reused prompt tokens (`cache_n=0`).
- Original local results directory: `experiments/bonsai2-rx9060xt/pp-batch-v01/results/run_20261018_001236_ctx96k_pp32k_auto`; benchmark runner `run_bonsai2_pp_ctx96k_auto.ps1` (not included in this branch).
- MTP **ON** data excluded. Do not infer an RX 9070 XT long-context speed from its 4K PP result.

## RX 9070 XT result: 2026-10-16 14:45
Evidence archive: `bonsai2_rx9070xt_20261016_144533.zip` provided by user (not stored in Git repository).

- CPU: Ryzen 7 5700X; System RAM: 32 GB; OS: Windows 11 Pro.
- Model: `Ternary-Bonsai-2-27B-PQ2_0.gguf` (SHA256 `3907DC1658DB1F78A9826BF8D5BCB8DC65DB0D466388937AF57F2294FAE62EC1`).
- Server binary SHA256 `1BF104B2C3274899EF20BA92AFFDBBDAFB6CFD0903621C2492E702A284D16FEE`.
- Device Vulkan1 / 16GB RX9070XT; context 4096; K/V q8_0; Flash Attention on; -ngl 99; -sm none; -np 1; --jinja; MTP off.
- Timings: PP 2292 tokens / 3082.014 ms / **743.67 t/s**; TG 1804 tokens / 31857.099 ms / **56.60 t/s**.
- Finish reason `length`, answer content empty and reasoning content present: input 2292 + output 1804 = 4096 context limit. **Model inference/throughput verified, final answer completion not yet verified.**
- TG comparison to RX9060XT historical 29.83 t/s is approximately **1.90x**, but cross-run settings are not matched; PP comparison must not be interpreted as a GPU speed ratio.
- Power profile from user-supplied `RX9070XT_UD65.xml`: power limit -30% enabled; -65 mV and -500 clock offset saved but their respective XML state enable flags false.

Other-model comparisons are out of scope for this reporting branch.


## Motherboard and PCIe topology (user-confirmed, 2026-10-16)

- Motherboard: **ASUS TUF GAMING B550-PLUS** (non-Wi-Fi model).
- CPU: **AMD Ryzen 7 5700X**.
- GPU placement: **RX 9070 XT in main slot**; **RX 9060 XT in secondary slot**, each 16 GB.
- Per ASUS product specification: main PCIEX16_1 (CPU-attached) supports **PCIe 4.0 x16** with Ryzen 5000; secondary PCIEX16_2 (B550 chipset-attached) supports **PCIe 3.0 x4 maximum**. When a PCIEX1 slot is in use, ASUS manual says PCIEX16_2 shares lanes and drops to **x1**. The user explicitly configured the secondary slot for **PCIe 3.0 x1** to preserve USB bandwidth. The link setting is user-confirmed; independent runtime link negotiation telemetry has not been captured.
- Nominal one-way peak bandwidth: PCIe 4.0 x16 ~31.5 GB/s; PCIe 3.0 x4 ~3.94 GB/s (8x nominal ratio); **configured PCIe 3.0 x1 ~0.985 GB/s (32x nominal ratio relative to main slot)**.
- Historical RX9060XT PP 44.16 t/s vs RX9070XT PP 743.67 t/s are **not matched-condition results**; the former is superseded for PP reporting by RX9060XT MTP OFF 96K/32K average 310.27 t/s, and the latter is a short-context outlier. The apparent 16.84x PP ratio **may be specific to this board/slot/USB lane-sharing configuration, not an intrinsic GPU PP speed ratio**, and cannot be attributed directly to PCIe bandwidth without controlled tests. PCIe mainly matters for transfers/CPU offload/multi-GPU; if the working set is GPU resident, arithmetic and VRAM access are key. Avoid making an unverified PCIe bottleneck claim.
- To compare fairly: capture PCIe negotiated link speed/width under load, GPU and CPU layer split, whether all weights and KV are in VRAM, `n_batch`, `n_ubatch`, context, prompt length, cache-hit state, PP timing, and GPU power/clock. Compare identical GGUF, llama.cpp build, drivers, and prompt on each GPU.
- ASUS specs: https://www.asus.com/jp/motherboards-components/motherboards/all-series/tuf-gaming-b550-plus/techspec/
- ASUS board manual: https://dlcdnets.asus.com/pub/ASUS/mb/SocketAM4/TUF_GAMING_B550-PLUS/J16576_TUF_GAMING_B550-PLUS_UM_WEB.pdf

**Reporting interpretation:** PP should be classified as *environment-dependent, not an established intrinsic GPU comparison*. RX9060XT is deliberately restricted to PCIe 3.0 x1 to secure USB bandwidth; distinguish the standard 8x theoretical difference (PCIe 4.0 x16 versus PCIe 3.0 x4) from the active configuration's 32x theoretical link-bandwidth difference (PCIe 4.0 x16 versus PCIe 3.0 x1). The observed PP ratio of approximately 16.84x is neither of those theoretical ratios and remains confounded by benchmarking conditions and residency.


## AMD official GPU specifications (reviewed 2026-10-16)

| Metric | RX 9070 XT | RX 9060 XT 16 GB | Ratio |
|---|---:|---:|---:|
| VRAM capacity | 16 GB | 16 GB | 1.00 |
| VRAM bandwidth | 640 GB/s | 320 GB/s | 2.00 |
| Bus width | 256-bit | 128-bit | 2.00 |
| Compute Units | 64 | 32 | 2.00 |
| Stream processors | 4096 | 2048 | 2.00 |
| AI accelerators | 128 | 64 | 2.00 |
| Infinity Cache | 64 MB | 32 MB | 2.00 |
| Peak FP32 | 48.7 TFLOPS | 25.6 TFLOPS | 1.90 |
| Game clock | 2400 MHz | 2530 MHz | 0.95 |

Sources: [AMD RX 9070 XT](https://www.amd.com/ja/products/graphics/desktops/radeon/9000-series/amd-radeon-rx-9070xt.html), [AMD RX 9060 XT](https://www.amd.com/ja/products/graphics/desktops/radeon/9000-series/amd-radeon-rx-9060xt.html).

**Interpretation:** On-chip GPU resources are roughly 2x, with exactly 2x *rated* VRAM bandwidth at equal capacity. The measured Bonsai2 TG ratio 56.60 / 29.83 ~1.90 is consistent with a ~2x hardware tier but is not a controlled comparison. The measured PP ratio is *not* a pure GPU comparison because the RX9060XT secondary slot is user-configured PCIe 3.0 x1, while the RX9070XT is in the primary slot (PCIe 4.0 x16). Other measurement conditions must also be matched.
