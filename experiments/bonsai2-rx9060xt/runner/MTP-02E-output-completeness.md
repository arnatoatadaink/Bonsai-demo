# MTP-02E complete-output trace verification

The previous Q8/Q4 three-run experiment logged 1022 of 1024 token IDs per run: the speculative output loop alone does not capture the non-speculative sampling branch. The llama.cpp research fork commit `76a7836` adds emitted-ID recording in that branch without changing sampling logic.

The comparator now requires an emitted-token count match even if no emitted records were found. Its `errors` list must be empty for every run; only then should emitted-ID equality be accepted.

Update llama.cpp and rebuild only the diagnostic binary:

```powershell
Set-Location "D:\AI\PrismML\dev\llama.cpp"
git pull --ff-only origin research/mtp-token-trace-2026-10-12
$env:PATH = "D:\msys64\ucrt64\bin;$env:PATH"
cmake --build build-vulkan-mtp-trace --target llama-server --parallel 8

Set-Location "D:\AI\PrismML\dev\Bonsai-demo"
git pull --ff-only origin research/bonsai2-mtp-kv-baseline-2026-10-12
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\experiments\bonsai2-rx9060xt\runner\run-divergence.ps1" -Mode full -TraceQ8Q4 -Server "D:\AI\PrismML\dev\llama.cpp\build-vulkan-mtp-trace\bin\llama-server.exe"
```

Take the exact `Output:` path printed at completion:

```powershell
$run = "D:\AI\PrismML\benchmark-results\mtp-first-divergence\run_YYYYMMDD_HHMMSS"
python ".\experiments\bonsai2-rx9060xt\runner\compare-mtp-traces.py" $run
```

Replace `YYYYMMDD_HHMMSS` with the actual timestamp. Accept iff every run reports `emitted_tokens: 1024`, `errors: []`, draft counts match the API and each comparison uses complete traces. Do not publish private raw prompts or traces without review. Target logits not yet instrumented.
