# RX 9070 XT / 64K summary comparison (draft)

This benchmark is intended for **Windows + RX 9070 XT**, one model per server process. It does not download weights, modify GPU power settings or silently load a second model.

## Models

- `bonsai8`: `D:\lmstudio_models\prism-ml\Ternary-Bonsai-8B-gguf\Ternary-Bonsai-8B-PQ2_0.gguf`
- `gemma12`: `D:\lmstudio_models\unsloth\gemma-4-12b-it-GGUF\gemma-4-12B-it-qat-UD-Q4_K_XL.gguf`
- `qwen9`: `D:\lmstudio_models\unsloth\Qwen3.5-9B-MTP-GGUF\Qwen3.5-9B-UD-Q4_K_XL.gguf`

Prior results for Bonsai-2-27B and Gemma-4-26B-A4B remain separate until the original logs and conditions can be checked.

## Required backend configuration

For **each model**, use an OpenAI-compatible llama-server with these verified settings:

- Radeon RX 9070 XT as the target inference GPU (confirm which Vulkan device was selected).
- `--ctx-size 65536` / `-c 65536`
- `--cache-type-k q8_0 --cache-type-v q8_0` (or `-ctk q8_0 -ctv q8_0`)
- Flash Attention enabled (`-fa on` where supported).
- GPU offloading enabled (typically `-ngl 99`, subject to VRAM).
- MTP/speculative decoding disabled. Do not provide a draft model or speculative decoding flags.
- Single request at a time. Retain the full server startup log.

**Important:** Bonsai PQ2_0 requires a compatible PrismML llama.cpp fork; stock llama.cpp or bundled LM Studio runtimes may reject this format. Verify the installed server's supported CLI flags with `llama-server --help` before running. A benchmark runner cannot set or independently prove KV types, context length, FA, Vulkan device, or MTP state over the generic OpenAI chat API.

Example *shape*, not a verified executable command for every binary:

```powershell
# Adapt the executable path for the actual Prism fork / Vulkan build.
.\llama-server.exe -m "D:\lmstudio_models\prism-ml\Ternary-Bonsai-8B-gguf\Ternary-Bonsai-8B-PQ2_0.gguf" -c 65536 -ctk q8_0 -ctv q8_0 -fa on -ngl 99 --host 127.0.0.1 --port 8080
```

Use an appropriate compatible backend for the Gemma 4 and Qwen models. If using LM Studio instead, configure K/V Q8, context 65536, Flash Attention and MTP OFF in its load options, and verify its logs. The runner only needs the `/v1/models` and `/v1/chat/completions` endpoints.

## Run

Python 3.10+; standard library only. Load **one** model in the backend first and confirm all required settings from the startup log.

```powershell
python benchmarks/summary64k/run.py --model bonsai8 --acknowledge-server-settings
python benchmarks/summary64k/run.py --model gemma12 --acknowledge-server-settings
python benchmarks/summary64k/run.py --model qwen9 --acknowledge-server-settings
```

If the server model ID is ambiguous, supply `--server-model-id <id>`. Change URL with `--base-url http://127.0.0.1:1234` for LM Studio. Short smoke test: `--levels 1`. The results append to `summary-benchmark-results/results.csv`; response JSON is saved separately. **Do not push raw logs containing sensitive test documents.**

## Conditions

- Qwen3.5-9B: thinking ON and OFF, each at L1-L5.
- Ternary Bonsai-8B: thinking ON and OFF, each at L1-L5.
- Gemma4-12B: normal instruction response, L1-L5.
- 5 conditions × 5 levels = **25 runs**.
- Target *approximate* input levels: L1=1K, L2=4K, L3=12K, L4=32K, L5=60K tokens.
- OFF output limit 2,048; ON output limit 8,192 tokens (thinking and final answer share the budget). Sampling is not guaranteed identical across families.
- Context is 65,536 total tokens, **including instructions, input, thinking, and answer**. The synthetic L5 may overflow depending on tokenizer and backend. If it fails, record the error, trim the source and rerun with recorded actual prompt token length; do not report the configured context as input token length.
- The synthetic English source provides 5 scattered anchor facts; it is a **smoke test**, not a calibrated benchmark for Japanese long-document summarization.
- `fact_exact_hits` is a literal English string-match diagnostic. Japanese paraphrases score zero; **do not use this column as quality score**. Human/reference-based fact adjudication is still required.
- `tokens_per_s` is completion tokens / wall-clock time: **not a pure TG speed measurement**. PP, TTFT, prefill time, decode TG, VRAM and temperature require backend telemetry. Record power settings and software versions alongside the benchmark.
- The runner sends `chat_template_kwargs.enable_thinking` on ON/OFF and Qwen's in-band `/think` or `/no_think`. Backend/template support is **not guaranteed**. Bonsai's OFF instruction is not proof of switching off internal thought.
- `thinking_verified=detected` proves reasoning surfaced. `unverified` means the API exposed no reasoning evidence; it **does not prove OFF was honored**. Inspect response JSON, server templates and traces manually before comparing ON vs OFF.

## Acceptance and scoring

1. Confirm each model really loads at 64K, Q8/Q8, Flash Attention ON, MTP OFF on RX 9070 XT.
2. Run L1 first and inspect thinking control for both Bonsai and Qwen; reject ON/OFF comparisons when control cannot be verified.
3. Execute L2-L5 only after successful preflight.
4. Use the same real documents and explicit reference fact lists for final grading; score facts (30), coverage (25), hallucination (20), structure (15), concision (10) as a **proposed rubric**, not automatic scores.
5. Compare wall time, prompt/completion tokens, telemetry, output quality, and non-success cases independently.

This is a preliminary evaluation harness, **not** an assertion that all listed models/runtimes already work with the chosen flags or thinking controls.


## Ready-to-run Windows PowerShell launch commands

The helper `start_server.ps1` supplies exact local GGUF paths and common arguments. It deliberately requires an explicit GPU device rather than assuming Vulkan0 is RX 9070 XT.

In **terminal 1** (replace the executable path with your Prism Vulkan binary):

```powershell
$server = "D:\Bonsai-demo\bin\vulkan\llama-server.exe"
& $server --list-devices
# Select the entry whose name is AMD Radeon RX 9070 XT; Vulkan index is an example only:
.\benchmarks\summary64k\start_server.ps1 -Model bonsai8 -LlamaServer $server -GpuDevice Vulkan0
```

In **terminal 2** run the L1 smoke test:

```powershell
python benchmarks/summary64k/run.py --model bonsai8 --levels 1 --acknowledge-server-settings
```

Stop terminal 1 with Ctrl+C. Then repeat using the SAME device and settings:

```powershell
.\benchmarks\summary64k\start_server.ps1 -Model gemma12 -LlamaServer $server -GpuDevice Vulkan0
# In second terminal:
python benchmarks/summary64k/run.py --model gemma12 --levels 1 --acknowledge-server-settings
```

```powershell
.\benchmarks\summary64k\start_server.ps1 -Model qwen9 -LlamaServer $server -GpuDevice Vulkan0
# In second terminal:
python benchmarks/summary64k/run.py --model qwen9 --levels 1 --acknowledge-server-settings
```

Only after validating L1, rerun the appropriate Python command without `--levels 1` for all five levels. Each launch keeps the model process in the foreground so it can be stopped before loading the next model.

### Exact llama-server flags applied by the helper

```text
-m <selected absolute GGUF path>
--host 127.0.0.1 --port 8080
--device VulkanN -ngl 99 -sm none
-c 65536 --cache-type-k q8_0 --cache-type-v q8_0
-fa on -np 1 --jinja
```

There is **no MTP, draft-model or speculation argument**. Do not add `--reasoning-budget 0` globally: that would invalidate the ON measurements. The per-request ON/OFF switch remains provisional and must be checked in response and runtime logs. Verify the installed binary supports `--device`, `--jinja`, `-sm none`, and other flags via `--help`. Do not use a stock upstream binary for Bonsai PQ2_0.

With RX 9070 XT 16GB, 64K q8/q8 may still exceed available VRAM depending on model and other loads. If offload falls back to CPU or context is reduced, record it as a failed comparability condition instead of reporting it as an identical-GPU benchmark. Preserve the startup log.


## Automatic run: use the existing benchmark workflow

The Windows PowerShell orchestrator starts each model sequentially, waits for llama-server health, runs the summary tests, saves device listing, server stdout/stderr and CSV/JSON, then stops the process before the next model.

```powershell
git fetch origin
git switch bench/summary-rx9070xt-64k-20261015
git pull --ff-only origin bench/summary-rx9070xt-64k-20261015

$server = "D:\Bonsai-demo\bin\vulkan\llama-server.exe" # change to actual installed build
.\benchmarks\summary64k\auto_run.ps1 -LlamaServer $server -SmokeOnly
# after reviewing L1 output and logs:
.\benchmarks\summary64k\auto_run.ps1 -LlamaServer $server
```

If the device listing cannot be parsed, inspect `summary-benchmark-results/device-list.txt`. If it explicitly identifies RX 9070 XT under Vulkan1, run with `-Device Vulkan1`. The script **does not assume** a universal fixed GPU index. Current Vulkan indexes cannot be obtained remotely from your Windows host; GPU order depends on the local runtime.

This follows the project's prior `distributed-summary-v01` and `MTP-01` approaches: separate server lifecycle, raw logs, JSON/CSV and controlled backend knobs. It does **not** run MTP. The earlier suites have not been imported into this branch.

**Limitations of this first automation:** It checks declared CLI options, GPU device listing, model file existence, HTTP readiness and request completion, but cannot prove that the runtime actually retained 65536 context, q8/q8 allocation, full GPU offload, or valid ON/OFF thinking. Those conditions require inspection of saved runtime logs and output. Passing `--acknowledge-server-settings` is an automation bypass of the runner's human confirmation gate, **not a successful configuration audit**. Synthetic fixture input size is approximate and quality remains unscored.

If backend startup fails, check `*.stderr.log` for unsupported flags, memory fit or PQ2_0 compatibility. Do not silently reduce context or KV precision to get a passing result.


## Historical 27B vs new-model apples-to-apples prompt replay

Original test source: Git branch `bench/bonsai2-think-compare-v01`, directory `experiments/bonsai2-rx9060xt/think-compare-v01/`. Replay loads the **exact committed** `questions.json` (3 short questions: summary, logic, security) and `questions-long.json` (long-form suite) through `git show`. Prompts are not regenerated. The original harness used `default/off/on` requests with `temperature=0`, `top_k=1`, `seed=42` and 2048 output tokens. This replay keeps those settings for Bonsai8 and Qwen9; Gemma12 runs default only. It stores raw requests/responses, trial-level timing and manifest. It does not change the original committed test sources.

```powershell
git fetch origin bench/bonsai2-think-compare-v01
git switch bench/summary-rx9070xt-64k-20261015
git pull --ff-only origin bench/summary-rx9070xt-64k-20261015

$server = "D:\AI\PrismML\dev\llama.cpp\build-vulkan-ucrt64\bin\llama-server.exe"
# PowerShell execution policy is local-session only; or invoke powershell.exe -ExecutionPolicy Bypass -File ...
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\benchmarks\summary64k\auto_run.ps1 -LlamaServer $server -OriginalSuite -SmokeOnly
# then full short+long replay:
.\benchmarks\summary64k\auto_run.ps1 -LlamaServer $server -OriginalSuite
```

The runner auto-selects the one RX9070XT Vulkan device; the index is resolved on the actual host. Add `-Device VulkanN` only after verifying the device list. Logs and outputs are written under `summary-benchmark-results`.

**Two kinds of comparability:** (1) exact historical prompt+sampling parity, achievable here; (2) original full-execution parity, **not** achievable under the newly fixed RX9070XT/64K/KV Q8/Q8/MTP OFF requirements because the original 27B suite ran RX9060XT, context 98304, K Q8/V Q4 and an MTP-related model path. Report those environment differences explicitly; never label throughput values as same-condition GPU measurements. Prompt sets also include reasoning/security, so not every case is a summary task.

The previously developed BNS-LCTX-02 multi-hop dataset is a **different** suite in `experiments/bonsai2-rx9060xt/multihop-v01` and is not included in `-OriginalSuite`; its replay requires its own exact generator and scoring logic. The existing historical 27B/Gemma26B result files remain unchanged and must be joined separately for comparisons.


## Results folder normalization (2026-10-15)

Like the earlier `think-compare-v01` test, this runner now writes under a suite-local `results/run_YYYYMMDD_HHMMSS/` folder, not at the repository root. Each run contains `manifest.json`, `device-list.txt`, and one folder per new model:

```text
benchmarks/summary64k/
  results/
    run_YYYYMMDD_HHMMSS/
      manifest.json
      device-list.txt
      bonsai8/
        server.stdout.log
        server.stderr.log
        results.csv
        bonsai8_L1_off.json ...
        original-suite/     # when -OriginalSuite
          manifest.json
          trials.csv
          short_Q01_summary_off.request.json ...
      gemma12/
      qwen9/
    run_imported_YYYYMMDD_HHMMSS/
      ... previous summary-benchmark-results contents (unmodified)
```

All `results/` output is ignored by Git. A separate run folder is created for each invocation. Existing results will not be overwritten.

To relocate the previous results **without rewriting any filenames or CSV**, first preview and then move:

```powershell
.\benchmarks\summary64k\migrate_results.ps1
.\benchmarks\summary64k\migrate_results.ps1 -Move
```

The migration source defaults to the old repository-root `summary-benchmark-results` folder, and the destination is `benchmarks/summary64k/results/run_imported_<timestamp>`. If the existing files are elsewhere, use `-Source "D:\path\to\summary-benchmark-results"`. If results only exist in a ZIP, extract them to the old root first; the migration helper moves folders, not ZIP files. Use `-DestinationName run_imported_previous` to choose a fixed name. Never move the earlier 27B/Gemma26B baseline results into the 8B suite unless explicitly preserving their source metadata; keep those legacy runs in their original experiment folders.

PowerShell policy block? Launch with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\benchmarks\summary64k\migrate_results.ps1` (or use `Set-ExecutionPolicy -Scope Process Bypass` in the current terminal).

The first automation version wrote `summary-benchmark-results/results.csv` and `*.stdout.log` side by side. Migration preserves this original internal layout in `run_imported_*` as historical evidence. New runs create per-model folders instead. Analysts should use the path and manifest to determine which schema applies.
