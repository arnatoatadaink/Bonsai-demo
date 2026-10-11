# Source manifest and curation decisions

Collected in the user's ChatGPT file Library; selected for this initial Git commit because they are directly relevant to MTP × KV behavior.

| File | Role | Included here |
|---|---|---|
| `Bonsai2_MTP_KV_Reasoning_Hypothesis_Research_2026-10-11.md` | hypotheses, confounds, measurement plan | synthesized in protocol |
| `Bonsai2_27B_MTP_Context_Handover_2026-10-10.md` | previous measurements and context | baseline summary |
| `bonsai_kv_ppl_kld_v162_ppl_20261011_203718.zip` | PPL/KLD logs + summaries | *summary values only* |
| `bonsai_mtp_kv_split_v17_20261011_213653.zip` | 32K/64K comparison and responses | *summary values only* |
| `bonsai_mtp_followup_v18_capacity-smoke_20261012_020540.zip` | v1.8 capacity and eight branches | *summary values only* |
| `bonsai2_kv_ppl_kld_v162.zip` | Windows BAT/PowerShell runner for v1.6.2 | not committed: keep upstream demo unmodified; can port when reviewed |
| `bonsai2_mtp_kv_split_v17.zip` | v1.7 Windows runner | not committed yet: contains machine-specific paths |
| `bonsai2_mtp_followup_v18.zip` | v1.8 Windows runner | not committed yet: contains machine-specific paths |
| `SC_ToT_ASC_Harness_Research_2026-10-12.md` | separate general harness research | excluded: outside current MTP/KV scope |

Excluded: GGUF model weights, downloaded executables, 1GB KLD logit baseline, repeated exploratory ZIP copies, raw responses, and potentially identifying Windows absolute paths. Retain original ZIPs in Library / local storage for independent audit. Values here are the *source-run summaries*, not fresh re-runs or software certification.

Provenance SHA256:
- `llama-server.exe`: `34AC496BC927D0840E88937171AE00226128128D988D250706F232DCF761B291`
- MTP GGUF: `3CB3F0056D2E34EE44245A64396004A21F8492573D6CE1266EC4B7222C131DD4`

**Next reproducibility gate:** freeze the runtime source commit corresponding to `prism-b10743-adfffbe`, review and normalize the Windows test scripts, then commit portable runner files in a separate change. Do not claim the present text-only commit already ships a runnable complete harness.
