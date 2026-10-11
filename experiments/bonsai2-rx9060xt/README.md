# Bonsai 2 27B — RX 9060 XT Vulkan MTP / KV experiments

**Status:** independently measured experimental record (2026-10-10 to 2026-10-12); **not an official PrismML benchmark or fix**.

This directory preserves the **small, reproducible subset** of the local experiment history. It does not contain model weights, private local paths, 1 GiB KLD baseline logits, complete conversations, or all intermediate exploratory archives.

## Tested baseline
- Hardware: AMD Radeon RX 9060 XT 16 GB; Windows 11; Vulkan0.
- PrismML runtime: `prism-b10743-adfffbe`; llama-server SHA256 `34AC496BC927D0840E88937171AE00226128128D988D250706F232DCF761B291`.
- Test model: `Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf`, SHA256 `3CB3F0056D2E34EE44245A64396004A21F8492573D6CE1266EC4B7222C131DD4`.
- Baseline params: `--device Vulkan0 --n-gpu-layers 99 --batch-size 4096 --ubatch-size 1536 --flash-attn on --parallel 1 --dry-multiplier 0`; `--spec-type draft-mtp --spec-draft-n-max 2` when MTP ON. Sampling: `temperature=0` in the prior comparison; validate actual sampler chain and seed before calling this strict greedy decoding.
- VRAM observed by sampled *adapter-wide* monitor, not guaranteed exact Vulkan process peak. Safety line: 13,824 MiB; cautious 96K probe line: 13,312 MiB.
- Stable working candidates: **64K Q8_0/Q4_0 + MTP Draft2**; memory-efficient **64K Q4_0/Q4_0**; long-document **96K Q4_0/Q4_0**. **96K Q8_0/Q4_0 not approved** after guard stop. 128K Q4_0/Q4_0 is conditional, with narrow margin.

## Records
- [Observed metrics](results/observed-metrics.md) — evidence and limits from v1.6.2 PPL/KLD, v1.7 KV split, v1.8 MTP branch/capacity.
- [Source manifest](results/source-manifest.md) — original run archive names and identifiers; source files are not duplicated here.
- [First-token divergence protocol](protocols/first-token-divergence.md) — next experiment before modifying llama.cpp.
- [KV ensemble idea](ideas/kv-pseudo-ensemble.md) — separate, deferred idea.

**Important distinction:** Bonsai-demo hosts reproducible test harnesses and published observations; the PrismML `llama.cpp` fork hosts C++/GPU speculative-decoding instrumentation. Do not conflate MTP output divergence with improved model reasoning or with an established correctness bug before controlled reproduction.
