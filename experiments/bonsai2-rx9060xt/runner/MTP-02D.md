# MTP-02D: targeted three-run internal trace

First **stop** the previously running server on port 18080. This runs three *independent cold-start* Q8/Q4 MTP ON sessions using the same 32K / seed 42 / greedy 1024 tokens MTP-01 setup. The runner sets `LLAMA_TRACE=2` and writes server stderr/stdout to per-run files. The default mode and default binary remain unchanged.

```powershell
Set-Location "D:\AI\PrismML\dev\Bonsai-demo"
git pull --ff-only origin research/bonsai2-mtp-kv-baseline-2026-10-12
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\experiments\bonsai2-rx9060xt\runner\run-divergence.ps1" -Mode full -TraceQ8Q4 -Server "D:\AI\PrismML\dev\llama.cpp\build-vulkan-mtp-trace\bin\llama-server.exe"
```

The script displays the new `run_YYYYMMDD_HHMMSS` output directory. Then:

```powershell
python ".\experiments\bonsai2-rx9060xt\runner\compare-mtp-traces.py" "D:\AI\PrismML\benchmark-results\mtp-first-divergence\run_YYYYMMDD_HHMMSS"
```

Result: `mtp-trace-comparison.csv` and `mtp-trace-comparison.json`. Trace counts **must** match the API summary; mismatches indicate dropped logs and block acceptance of a result. Comparing verification-round structures is not equivalent to comparing the fully committed token stream, especially when speculative checkpoint replay occurs. Compare with original Run 3 only at the aggregate / visible-output level: the earlier run has no raw internal trace.

Keep full logs and raw model outputs private and outside Git. Do not change the stable build. No Target logit capture in this step.
