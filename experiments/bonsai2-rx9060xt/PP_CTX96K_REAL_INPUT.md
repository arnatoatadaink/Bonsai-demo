# Real workload: 96k context / 32k fixed prefill

This is a **second, real-input validation**, separate from the existing `llama-bench` microbatch sweep.

## Dataset selection
Previous evaluation sessions referenced `questions-long.json` (THINK-02), `distributed-summary-v01/generate.py` (long-summary level 1), and `multihop-v01/generate.py`. These datasets were not present on this repository branch at integration time. Do not fabricate them. Use an **existing local generated text corpus** (plain UTF-8 .txt), keeping prompt structure unchanged when possible. The script uses the active server's `/tokenize` endpoint and sends exactly **32768 input token IDs** to `/completion`. JSON test suites need their already-generated textual prompt extracted to a .txt before testing. If insufficient length, it fails rather than padding silently; optional `-RepeatInput` is explicitly labeled artificial.

## Procedure
1. Start the Bonsai-compatible PrismML `llama-server` using the current local Bonsai2 model/GPU setup and **`-c 98304 -np 1`**, preserving K Q8 / V Q4 and Flash Attention. Change `-b` and `-ub` in the launch script for each configuration, restarting server between configurations. Never run the standalone `llama-bench` simultaneously.
2. Use real plain-text material from the earlier THINK-02 or Level-1 summary corpus. Confirm `/props` reports expected server settings or inspect the startup logs. `/props` field compatibility varies by build.
3. Run:

```powershell
pwsh -NoProfile -File .\experiments\bonsai2-rx9060xt\runner\test_bonsai2_pp_ctx96k.ps1 -InputPath "<existing-long-input.txt>" -ServerUrl "http://127.0.0.1:8080" -Repetitions 3
```

Replace the placeholder with the actual path to your generated input file. Results default to `experiments/bonsai2-rx9060xt/pp-batch-v01/results/run_YYYYMMDD_HHMMSS_ctx96k_pp32k/`; pass `-OutputDir` to override.

**Measurement caveats:** Response `timings.prompt_n` must be close to 32768 for a full-prefill result; responses with reused cache are flagged `CACHE_OR_SHORT_PREFILL`. Same model, commit, clocks, drivers and input hash should be used for all GPU/batch configurations. Startup context capacity and actual processed prompt length are different quantities. A single 1-token completion ensures server reports its prefill timings (not a TG benchmark). This test does not automatically vary batch: modify the server launch options and restart between runs.

Status: ready for user-run validation, **not measured in this environment**.
