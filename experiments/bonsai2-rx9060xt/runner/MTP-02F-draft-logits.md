# MTP-02F Draft head raw-logit diagnostic

First-path divergence in `run_20261013_133812`: verification round 109 proposed `[369,2136]` vs `[369,264]`; same anchor 1156, same n_past 342, same Target first-row logits, and same emitted 1024 IDs. Draft second candidate differs; the following two verification rounds should not be interpreted as Target nondeterminism without same-prefix and same-proposal alignment.

The personal `llama.cpp` research branch now records `MTP_TRACE draft_top2:` (raw logits read-only *before* common_sampler_sample), and `MTP_TRACE draft_choice:` (chosen draft candidate and candidate probability). This is only for `MTP_TRACE_FILE` and diagnostic binaries, not the stable version. Raw logits do not imply post-sampler probabilities.

Update/rebuild diagnostic server and runner:

```powershell
Set-Location "D:\AI\PrismML\dev\llama.cpp"
git pull --ff-only origin research/mtp-token-trace-2026-10-12
$env:PATH="D:\msys64\ucrt64\bin;$env:PATH"
cmake --build build-vulkan-mtp-trace --target llama-server --parallel 8
Set-Location "D:\AI\PrismML\dev\Bonsai-demo"
git pull --ff-only origin research/bonsai2-mtp-kv-baseline-2026-10-12
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\experiments\bonsai2-rx9060xt\runner\run-divergence.ps1" -Mode full -TraceQ8Q4 -TraceRepeats 10 -Server "D:\AI\PrismML\dev\llama.cpp\build-vulkan-mtp-trace\bin\llama-server.exe"
```

After the new Output path appears, run `compare-mtp-traces.py` on the full directory and `inspect-mtp-draft.py` against a differing run and matching baseline, e.g.:

```powershell
python ".\experiments\bonsai2-rx9060xt\runner\inspect-mtp-draft.py" $run --a 32768_q8q4_on_r1 --b 32768_q8q4_on_r2 --window 2
```

Run numbers are only an example; identify divergence from comparator first. If all ten match, mark as non-reproduced and do not extrapolate certainty. This instrumentation adds synchronous disk I/O and full-vocabulary scanning: do not use its timing as a performance benchmark.
