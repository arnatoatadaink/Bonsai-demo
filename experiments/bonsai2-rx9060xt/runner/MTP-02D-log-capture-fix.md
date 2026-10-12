# MTP-02D direct trace persistence amendment

The 2026-10-12 20:26 three-run baseline reports API 1011/516 in all cases but captured just 748-762 draft proposal IDs in redirected server logs. The differences at round 374/380 are **EOF differences, not token divergence**. These three runs must be marked invalid for full trace comparison; retain as evidence of log-capture failure.

The companion llama.cpp research branch now supports opt-in `MTP_TRACE_FILE` for immediately flushed per-event disk writes. The runner automatically sets a unique file for each process when `-TraceQ8Q4` is used. The parser prioritizes `*.trace.log` and never concatenates duplicate console logs.

Update both personal forks and rebuild *only* diagnostic binary:

```powershell
Set-Location D:\AI\PrismML\dev\llama.cpp
git pull --ff-only origin research/mtp-token-trace-2026-10-12
$env:PATH="D:\msys64\ucrt64\bin;$env:PATH"
cmake --build build-vulkan-mtp-trace --target llama-server --parallel 8
Set-Location D:\AI\PrismML\dev\Bonsai-demo
git pull --ff-only origin research/bonsai2-mtp-kv-baseline-2026-10-12
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\experiments\bonsai2-rx9060xt\runner\run-divergence.ps1" -Mode full -TraceQ8Q4 -Server "D:\AI\PrismML\dev\llama.cpp\build-vulkan-mtp-trace\bin\llama-server.exe"
```

Compare the new Output folder with `python .\experiments\bonsai2-rx9060xt\runner\compare-mtp-traces.py "<OUTPUT>"`.

Safeguard: `MTP_TRACE_FILE` is opt-in, opened and closed on each trace event (slower but durable). Logs may contain model token IDs revealing prompt/output; do not publish full logs without privacy review. This patch does not instrument final committed token stream or Target logits.
