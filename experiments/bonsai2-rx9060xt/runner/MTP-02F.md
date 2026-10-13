# MTP-02F: ten independent cold starts

MTP-02E-2 accepted on 2026-10-13: 3 runs showed 1024/1024 identical emitted IDs, 1519 identical raw Target Top-2 records, and 506 identical verification rounds. This confirms repeatability for the tested runs only, not an absence of occasional divergence.

Update Bonsai-demo and run a **10-repetition** Q8/Q4 MTP ON experiment with the existing diagnostic server. This preserves all raw per-run traces.

```powershell
Set-Location "D:\AI\PrismML\dev\Bonsai-demo"
git pull --ff-only origin research/bonsai2-mtp-kv-baseline-2026-10-12
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\experiments\bonsai2-rx9060xt\runner\run-divergence.ps1" -Mode full -TraceQ8Q4 -TraceRepeats 10 -Server "D:\AI\PrismML\dev\llama.cpp\build-vulkan-mtp-trace\bin\llama-server.exe"
```

After completion, replace the path with the exact `Output:` directory:

```powershell
$run = "D:\AI\PrismML\benchmark-results\mtp-first-divergence\run_YYYYMMDD_HHMMSS"
python ".\experiments\bonsai2-rx9060xt\runner\compare-mtp-traces.py" $run
```

The comparator reports all 45 pairwise comparisons and exact first differences in emitted token ID, verification event, and raw Target Top-2 sample. A difference at a raw Top-2 sample after emitted-token divergence is an effect, not necessarily a cause.

Before treating any differing run as a valid anomaly, verify its `errors=[]`, `emitted_tokens=1024`, and Draft totals match API. Compare the exact `manifest.json` to the validated baseline `run_20261013_131358` (including prompt, model, server SHA and parameters). If a real divergence is observed, preserve the entire directory and examine the first differing emitted token and preceding same-prefix raw logits. If no divergence occurs, preserve the negative result; ten identical repetitions cannot prove deterministic behavior for all executions.

All changes remain in personal research fork, without affecting stable binaries or upstream.
