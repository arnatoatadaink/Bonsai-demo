# MTP-02E-2: Target raw-logit Top-2

The personal llama.cpp research branch now samples raw Target logits **read-only before** `common_sampler_sample` and `common_sampler_sample_and_accept_n`. It writes `MTP_TRACE target_top2` records to the same per-run durable trace file as token IDs and verification events. This is a diagnostic and **not** the effective post-grammar/post-temperature probability distribution; raw logit argmax may differ from the selected token under active constraints.

For each verification round all `n_draft+1` logits rows are logged, including rows that might not be consumed after early rejection. These rows are available for inspection but should not be interpreted as accepted sampled outputs. The comparator reports the first different Top-2 sample; differences after the first emitted token divergence do not establish cause.

## Build and run

```powershell
Set-Location "D:\AI\PrismML\dev\llama.cpp"
git pull --ff-only origin research/mtp-token-trace-2026-10-12
$env:PATH="D:\msys64\ucrt64\bin;$env:PATH"
cmake --build build-vulkan-mtp-trace --target llama-server --parallel 8

Set-Location "D:\AI\PrismML\dev\Bonsai-demo"
git pull --ff-only origin research/bonsai2-mtp-kv-baseline-2026-10-12
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\experiments\bonsai2-rx9060xt\runner\run-divergence.ps1" -Mode full -TraceQ8Q4 -Server "D:\AI\PrismML\dev\llama.cpp\build-vulkan-mtp-trace\bin\llama-server.exe"
```

Then analyze the exact printed Output path with `python .\experiments\bonsai2-rx9060xt\runner\compare-mtp-traces.py <Output>`.

### Acceptance

- Diagnostic binary compiles; target_top2 records exist.
- Three runs have 1024 emitted IDs and 1011/516 Draft metrics with no trace errors, unless an actual divergence is detected.
- For stable runs, `first_different_target_top2_sample_zero_based` should be -1; there may be small numeric differences that merit further analysis even when token IDs remain identical.
- No updates to the stable binary, upstream, or model parameters.

Do not interpret raw-logit Top-2 alone as proof of Vulkan nondeterminism or KV corruption.
