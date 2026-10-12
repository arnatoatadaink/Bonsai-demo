# MTP-01 next diagnostic: within-condition repeatability

Run on Windows PowerShell with Python 3.13 installed:

```powershell
Set-Location "D:\AI\PrismML\dev\Bonsai-demo"
python ".\experiments\bonsai2-rx9060xt\runner\analyze-repetitions.py" "D:\AI\PrismML\benchmark-results\mtp-first-divergence\run_20261012_153229"
```

Outputs, **locally only**: `within-condition-divergence.csv`, `within-condition-report.json`.

Compares the three independent repetitions **within the same KV/MTP configuration** using raw `message.reasoning_content` and `message.content` equality and SHA-256, plus separate and joined *post-hoc* tokenized streams. This reveals whether the third Q8/Q4 MTP ON run changed visible generation, or only aggregate draft acceptance. Raw response and `*.tokens.json` captures are required; the published `summary.csv` and `first-divergence.csv` are insufficient to establish this distinction.

Interpretation:
- `reason_exact=true` and `content_exact=true` with different draft counts => visible output stable, draft path differs (underlying reason still unknown).
- `reason_exact=false` => visible reasoning differs; do not infer whether numeric GPU nondeterminism, sampling, token boundaries, or verification logic caused it.
- `first_*_retoked` is a zero-based post-hoc re-tokenized index (or -1 for identical). This is NOT the internal sampled-token divergence index.
- Existing cap at 1024 means every published run ends `length`; there is no final-answer quality conclusion.

Keep original run directory and raw responses out of the public repository until privacy reviewed. Commit only reviewed aggregate CSV/JSON or a narrative report.
