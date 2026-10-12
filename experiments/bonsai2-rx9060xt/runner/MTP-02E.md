# MTP-02E first stage: emitted token IDs

Personal llama.cpp fork commit `55eab02` adds `MTP_TRACE emitted: id=<n>` immediately before `process_token` in the speculative output loop, after replay resolution. `compare-mtp-traces.py` now checks the emitted sequence and flags count discrepancies against API `predicted_n`.

The original full results and MTP-02D 3-run traces (prior to this commit) do not include emitted IDs and must not be represented as having passed this new test.

Build and run:

```powershell
Set-Location "D:\AI\PrismML\dev\llama.cpp"
git pull --ff-only origin research/mtp-token-trace-2026-10-12
$env:PATH="D:\msys64\ucrt64\bin;$env:PATH"
cmake --build build-vulkan-mtp-trace --target llama-server --parallel 8
Set-Location "D:\AI\PrismML\dev\Bonsai-demo"
git pull --ff-only origin research/bonsai2-mtp-kv-baseline-2026-10-12
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\experiments\bonsai2-rx9060xt\runner\run-divergence.ps1" -Mode full -TraceQ8Q4 -Server "D:\AI\PrismML\dev\llama.cpp\build-vulkan-mtp-trace\bin\llama-server.exe"
```

Then run the trace comparator against the **new** run directory. Expected successful runs should show `emitted_tokens=1024` and no errors. The `first_different_emitted_token_zero_based` reports a true internal token-ID position in the emitted output loop when both traces are complete. Unlike visible post-hoc tokenization, this requires no re-tokenization.

Caveat: this stage records tokens in the MTP server output loop only; other non-speculative, error, or early-termination paths are outside scope. Target logits/top-two score capture is a later stage, ideally armed around the first observed differing token.
