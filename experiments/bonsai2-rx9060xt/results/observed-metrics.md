# Observed results (not generalized performance claims)

## v1.6.2 — identical corpus, PPL / KLD (2K context)
Source: `bonsai_kv_ppl_kld_v162_ppl_20261011_203718.zip`. Five PPL and five KLD tasks reported COMPLETE. Synthetic/repetitive corpus: **not** a general benchmark of knowledge or reasoning.

| K/V | PPL ↓ | mean KLD vs F16/F16 ↓ | same top-1 (%) ↑ |
|---|---:|---:|---:|
| f16/f16 | 1.1480 | 0 (reference) | 100 (reference) |
| q8_0/q8_0 | 1.1507 | 0.003403 | 99.560 |
| q8_0/q4_0 | 1.1564 | 0.014775 | 98.876 |
| q4_0/q8_0 | 1.1695 | 0.025934 | 98.436 |
| q4_0/q4_0 | 1.1725 | 0.036410 | 98.094 |

This *fixed-corpus distribution difference* cannot be read as the fraction of tokens changed during free generation.

## v1.7 — 8/8 complete; 32K/64K mixed K/V
Source: `bonsai_mtp_kv_split_v17_20261011_213653.zip`. MTP Draft2 ON. Max adapter-wide sampled VRAM:

| Context | Q4/Q4 MiB | Q8/Q4 MiB | Q4/Q8 MiB | Q8/Q8 MiB |
|---|---:|---:|---:|---:|
| 32K | 11291.5 | 11617.3 | 11582.6 | 11901.9 |
| 64K | 12041.2 | 12526.5 | 12537.3 | 13048.5 |

v1.7, 64K Q06 task (one deterministic-condition sample per config):

| K/V | generated tokens | TG tokens/s | MTP acceptance % | derived TG time (s) |
|---|---:|---:|---:|---:|
| Q4/Q4 | 3971 | 33.84 | 62.18 | 117.36 |
| Q8/Q4 | 3484 | 36.40 | 69.73 | 95.72 |
| Q4/Q8 | 5324 | 35.45 | 66.93 | 150.16 |
| Q8/Q8 | 5140 | 34.85 | 66.79 | 147.49 |

Answers completed. Same main conclusions do **not** establish identical reasoning or improved correctness. A hard-question exact-match check showed a shared `isSuspended` vs `user.isSuspended` spelling/path mismatch, despite semantically relevant flag identification.

## v1.8 — 96K guard and MTP OFF/ON path comparison
Source: `bonsai_mtp_followup_v18_capacity-smoke_20261012_020540.zip` (archive includes capacity-smoke, capacity-full, branch).

96K Q8/Q4 MTP Draft2: capacity-smoke **FAILED VRAM GUARD**, sampled 13,579.4 MiB ≥ 13,312 MiB; capacity-full **FAILED VRAM GUARD**, sampled 13,577.2 MiB ≥ 13,312 MiB. **These were not successful 96K full-length evaluations.**

Branch Q06 (all eight cases COMPLETE):

| ctx | KV | MTP | generated tokens | TG tokens/s |
|---|---|---|---:|---:|
|32K|Q4/Q4|OFF|4602|27.29|
|32K|Q4/Q4|ON|3971|34.54|
|32K|Q8/Q4|OFF|3852|27.15|
|32K|Q8/Q4|ON|3484|36.49|
|64K|Q4/Q4|OFF|5604|27.26|
|64K|Q4/Q4|ON|3971|34.30|
|64K|Q8/Q4|OFF|3852|27.25|
|64K|Q8/Q4|ON|3484|36.39|

**Observed:** KV configuration and MTP enablement change the generated traces under the tested conditions. **Not established:** causal source, first divergent token/logit, repeatability over runs, whether exact greedy settings were held equal, or whether differences indicate an MTP implementation defect. v1.8 adapter-wide VRAM readings varied from v1.7; do not equate monitors' peaks with isolated process memory.
