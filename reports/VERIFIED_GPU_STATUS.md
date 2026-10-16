# Bonsai2-27B GPU verification status (2026-10-16)

## Verified
- **RX 9060 XT 16 GB**: Bonsai2-27B PQ2_0 previously verified on Windows/Vulkan. Historical speed entries PP 44.16 t/s and TG 29.83 t/s require original test condition reconciliation; do not treat as matching the RX9070XT run.
- **RX 9070 XT 16 GB**: Bonsai2-27B PQ2_0 independently verified on Vulkan1, PrismML llama.cpp build 10772, commit `e8fd209c9`, AMD Adrenalin 26.3.1. Model loaded, 2,292 tokens evaluated, 1,804 tokens generated. **PP 743.6696 t/s, TG 56.5965 t/s**. First raw completion test returned EOS immediately; second chat-template test successfully performed sustained generation.

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
- Historical RX9060XT PP 44.16 t/s vs RX9070XT PP 743.67 t/s are **not matched-condition results**; the apparent 16.84x PP ratio **may be specific to this board/slot/USB lane-sharing configuration, not an intrinsic GPU PP speed ratio**, and cannot be attributed directly to PCIe bandwidth without controlled tests. PCIe mainly matters for transfers/CPU offload/multi-GPU; if the working set is GPU resident, arithmetic and VRAM access are key. Avoid making an unverified PCIe bottleneck claim.
- To compare fairly: capture PCIe negotiated link speed/width under load, GPU and CPU layer split, whether all weights and KV are in VRAM, `n_batch`, `n_ubatch`, context, prompt length, cache-hit state, PP timing, and GPU power/clock. Compare identical GGUF, llama.cpp build, drivers, and prompt on each GPU.
- ASUS specs: https://www.asus.com/jp/motherboards-components/motherboards/all-series/tuf-gaming-b550-plus/techspec/
- ASUS board manual: https://dlcdnets.asus.com/pub/ASUS/mb/SocketAM4/TUF_GAMING_B550-PLUS/J16576_TUF_GAMING_B550-PLUS_UM_WEB.pdf

**Reporting interpretation:** PP should be classified as *environment-dependent, not an established intrinsic GPU comparison*. RX9060XT is deliberately restricted to PCIe 3.0 x1 to secure USB bandwidth; distinguish the standard 8x theoretical difference (PCIe 4.0 x16 versus PCIe 3.0 x4) from the active configuration's 32x theoretical link-bandwidth difference (PCIe 4.0 x16 versus PCIe 3.0 x1). The observed PP ratio of approximately 16.84x is neither of those theoretical ratios and remains confounded by benchmarking conditions and residency.
