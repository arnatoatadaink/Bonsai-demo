# MTP-02F observation — 2026-10-13

The user ran 10 independent 32768 Q8/Q4 MTP ON repetitions in `run_20261013_133812`.

- Each run has 1024 emitted IDs, zero errors, and valid counts.
- R1: draft_n=1009, accepted=517, verification rounds=505, raw target top2 samples=1516.
- R2-R10: draft_n=1011, accepted=516, rounds=506, target top2 samples=1519; they match each other.
- R1 vs R2-R10: emitted ID difference **none**; first verification-round difference index 109, first top2-record difference index 330.
- Do **not** call sample-index 330 a same-prefix numerical logit difference. It might be a change of draft verification structure, resulting in differently aligned batch indices. The earlier MTP-01 visible reasoning divergence remains a separate phenomenon.

Inspect the existing local traces, without rerunning:

```powershell
Set-Location "D:\AI\PrismML\dev\Bonsai-demo"
git pull --ff-only origin research/bonsai2-mtp-kv-baseline-2026-10-12
$run="D:\AI\PrismML\benchmark-results\mtp-first-divergence\run_20261013_133812"
python ".\experiments\bonsai2-rx9060xt\runner\inspect-mtp-round.py" $run --a 32768_q8q4_on_r1 --b 32768_q8q4_on_r2 --window 1
```

For diagnosis compare `n_past`, `anchor`, `proposed`, `accepted_prefix`, `confirmed` and each ordinal's Top-2. Distinguish candidate path changes from actual output changes. This script is read-only and outputs raw token IDs only; it does not alter the model or server.
