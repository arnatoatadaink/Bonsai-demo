# Bonsai2-27B 4-condition PP/TG test (Windows PowerShell 5.1)

Each of four combinations — RX 9060 XT or RX 9070 XT × MTP OFF or ON — is run three times. A new llama-server process is started and stopped for every trial. An identical 32K-token prefix is derived from the existing experimental prompt.

## Prerequisites

- PrismML llama-server.exe with both GPUs visible in `--list-devices`.
- A **Bonsai2-27B MTP-capable GGUF** that can load in both MTP ON and OFF modes. The non-MTP standalone PQ2_0 model may not support MTP ON.
- Original long-prompt data file `experiments/bonsai2-rx9060xt/distributed-summary-v01/dataset/prompt.txt` on the local PC. **This file is not yet tracked in the Git branch.** Do not substitute synthetic text when comparing to the original PP run.
- No other service listening on port 8078.

## Fetch from GitHub

```powershell
git fetch origin
git switch bench/bonsai2-rx9060xt-pp-batch-20261017
git pull --ff-only origin bench/bonsai2-rx9060xt-pp-batch-20261017
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

## Recommended: fixed local paths, one-time configuration

This approach is **manual configuration, not auto-discovery**. Paths are kept local and are not published in Git.

```powershell
Copy-Item .\experiments\bonsai2-rx9060xt\paths.example.psd1 `
          .\experiments\bonsai2-rx9060xt\paths.local.psd1
notepad .\experiments\bonsai2-rx9060xt\paths.local.psd1
```

Edit the three absolute paths (llama-server.exe, Bonsai2-27B **MTP-capable** GGUF, and the original prompt.txt). The expected relative location of the **local** input is `experiments/bonsai2-rx9060xt/distributed-summary-v01/dataset/prompt.txt` if that directory exists on your PC; Git does not contain that dataset.

Run from repository root:

```powershell
.\experiments\bonsai2-rx9060xt\start_4way_fixed.ps1
```

The launcher checks exactly the three paths you configured, then invokes `run_bonsai2_4way_pp_tg.ps1` with 3 repetitions. No file search, automatic downloads, or fallback model selection occurs. Preserve `paths.local.psd1` locally; do not commit it.

## Run (alternative: specify paths on each call)

```powershell
$server = '<path-to-PrismML-llama-server.exe>'
$model  = '<path-to-Bonsai2-27B-MTP-capable.gguf>'
$prompt = '<path-to-existing-distributed-summary-v01-dataset-prompt.txt>'

.\experiments\bonsai2-rx9060xt\run_bonsai2_4way_pp_tg.ps1 `
  -LlamaServer $server `
  -ModelPath $model `
  -PromptPath $prompt `
  -Repetitions 3
```

The script uses context 98,304, batch 4,096, ubatch 256, K q8_0, V q4_0, threads 4, Flash Attention ON, checkpoints 0, parallel 1, load-mode none. When MTP ON, draft-mtp with draft max 2 is added. These are the supplied `llama_bonsai2(2).ps1` settings, apart from GPU/MTP selection.

## Output

Under `experiments/bonsai2-rx9060xt/results_4way/<timestamp>/`: `manifest.json`, `fixed_prompt.txt`, `all_trials.csv`, `summary.csv`, and per-trial startup/API logs. Only three passing runs generate a COMPLETE average; failed runs remain visible with INCOMPLETE status. Save the entire result folder before changing model settings.

**Execution status:** committed as an untested automation script. Neither the 12 runs nor compatibility with the local fork have been verified on the Windows GPUs yet.