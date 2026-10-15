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
python experiments/bonsai2-rx9060xt/benchimark-summary64k/run.py --model bonsai8 --acknowledge-server-settings
python experiments/bonsai2-rx9060xt/benchimark-summary64k/run.py --model gemma12 --acknowledge-server-settings
python experiments/bonsai2-rx9060xt/benchimark-summary64k/run.py --model qwen9 --acknowledge-server-settings
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
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\start_server.ps1 -Model bonsai8 -LlamaServer $server -GpuDevice Vulkan0
```

In **terminal 2** run the L1 smoke test:

```powershell
python experiments/bonsai2-rx9060xt/benchimark-summary64k/run.py --model bonsai8 --levels 1 --acknowledge-server-settings
```

Stop terminal 1 with Ctrl+C. Then repeat using the SAME device and settings:

```powershell
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\start_server.ps1 -Model gemma12 -LlamaServer $server -GpuDevice Vulkan0
# In second terminal:
python experiments/bonsai2-rx9060xt/benchimark-summary64k/run.py --model gemma12 --levels 1 --acknowledge-server-settings
```

```powershell
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\start_server.ps1 -Model qwen9 -LlamaServer $server -GpuDevice Vulkan0
# In second terminal:
python experiments/bonsai2-rx9060xt/benchimark-summary64k/run.py --model qwen9 --levels 1 --acknowledge-server-settings
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
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\auto_run.ps1 -LlamaServer $server -SmokeOnly
# after reviewing L1 output and logs:
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\auto_run.ps1 -LlamaServer $server
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
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\auto_run.ps1 -LlamaServer $server -OriginalSuite -SmokeOnly
# then full short+long replay:
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\auto_run.ps1 -LlamaServer $server -OriginalSuite
```

The runner auto-selects the one RX9070XT Vulkan device; the index is resolved on the actual host. Add `-Device VulkanN` only after verifying the device list. Logs and outputs are written under `summary-benchmark-results`.

**Two kinds of comparability:** (1) exact historical prompt+sampling parity, achievable here; (2) original full-execution parity, **not** achievable under the newly fixed RX9070XT/64K/KV Q8/Q8/MTP OFF requirements because the original 27B suite ran RX9060XT, context 98304, K Q8/V Q4 and an MTP-related model path. Report those environment differences explicitly; never label throughput values as same-condition GPU measurements. Prompt sets also include reasoning/security, so not every case is a summary task.

The previously developed BNS-LCTX-02 multi-hop dataset is a **different** suite in `experiments/bonsai2-rx9060xt/multihop-v01` and is not included in `-OriginalSuite`; its replay requires its own exact generator and scoring logic. The existing historical 27B/Gemma26B result files remain unchanged and must be joined separately for comparisons.


## Results folder normalization (2026-10-15)

Like the earlier `think-compare-v01` test, this runner now writes under a suite-local `results/run_YYYYMMDD_HHMMSS/` folder, not at the repository root. Each run contains `manifest.json`, `device-list.txt`, and one folder per new model:

```text
experiments/bonsai2-rx9060xt/benchimark-summary64k/
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
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\migrate_results.ps1
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\migrate_results.ps1 -Move
```

The migration source defaults to the old repository-root `summary-benchmark-results` folder, and the destination is `experiments/bonsai2-rx9060xt/benchimark-summary64k/results/run_imported_<timestamp>`. If the existing files are elsewhere, use `-Source "D:\path\to\summary-benchmark-results"`. If results only exist in a ZIP, extract them to the old root first; the migration helper moves folders, not ZIP files. Use `-DestinationName run_imported_previous` to choose a fixed name. Never move the earlier 27B/Gemma26B baseline results into the 8B suite unless explicitly preserving their source metadata; keep those legacy runs in their original experiment folders.

PowerShell policy block? Launch with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\experiments\bonsai2-rx9060xt\benchimark-summary64k\migrate_results.ps1` (or use `Set-ExecutionPolicy -Scope Process Bypass` in the current terminal).

The first automation version wrote `summary-benchmark-results/results.csv` and `*.stdout.log` side by side. Migration preserves this original internal layout in `run_imported_*` as historical evidence. New runs create per-model folders instead. Analysts should use the path and manifest to determine which schema applies.


## Legacy baseline test keys (exact original generators/prompts)

Found on `origin/bench/bonsai2-think-compare-v01`:

| Key | Existing path | Contents | Reuse |
|---|---|---|---|
| BNS-THINK-02 / GEM-THINK-02 | `think-compare-v01/questions-long.json` | Five evidence-faithfulness scenarios × default/off/on in legacy Bonsai runner | `-LegacySuite think02` |
| BNS-LCTX-01 | `distributed-summary-v01/generate.py` | 24 dispersed Japanese facts, strict F01–F24 answers | `-LegacySuite lctx01` |
| BNS-LCTX-02 | `multihop-v01/generate.py` | 40 cases in G1–G5, multi-hop links and evidence record IDs | `-LegacySuite lctx02` |

The new `run_lctx_legacy.py` fetches the old generators from Git verbatim and creates the same deterministic dataset parameters (LCTX01 target 65000 characters; LCTX02 target 80000). It reproduces the original request fields and exact-match screening. It stores raw requests/responses, computed datasets, scores and timing under each run. The original 27B/26B response/results folders are NOT modified or copied.

```powershell
git fetch origin bench/bonsai2-think-compare-v01
git switch bench/summary-rx9070xt-64k-20261015
git pull --ff-only origin bench/summary-rx9070xt-64k-20261015
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$server = "D:\AI\PrismML\dev\llama.cpp\build-vulkan-ucrt64\bin\llama-server.exe"
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\auto_run.ps1 -LlamaServer $server -LegacySuite all
```

Use `-LegacySuite think02`, `-LegacySuite lctx01` or `-LegacySuite lctx02` individually. `-SmokeOnly` shortens THINK-02 only; LCTX suites are not shortened so their baseline data remains identical.

Output paths: `results/run_<timestamp>/<model>/THINK-02/`, `.../LCTX01/`, `.../LCTX02/`, alongside each model's `server.stdout.log` and `server.stderr.log`. This is the same run-folder convention as prior tests. `fact_checks.csv` and `metrics.json` are emitted for LCTX-02; `fact_checks.csv`, `metrics.json`, `summary.json` for LCTX-01; `trials.csv` for THINK-02.

**Comparability:** input questions and strict scoring are preserved. 27B baseline's original RX9060XT/96K/K Q8 V Q4 environment is DIFFERENT from RX9070XT/64K/K Q8 V Q8, so compare answer quality within source tests, not throughput as same conditions. The ON/OFF request settings do not prove reasoning is actually toggled. Gemma12 uses default only. If full documents overflow real 64K capacity, record failure without shrinking inputs silently.

**Important:** the key-to-file attribution of THINK-02 is based on the existing documented faithfulness suite; compare historical run manifests before merging scores if the two original THINK-02 sessions used different revisions of the test.


## Qwen3.5 9B THINK-02 rerun (2026-10-15)

The prior Qwen9 ON/default test reached `max_tokens=2048` on L02-L05. For a narrow rerun **without changing the test prompts or previous results**, run only Qwen9 in ON mode with 8192 generated-token budget:

```powershell
git pull --ff-only origin bench/summary-rx9070xt-64k-20261015
$server = "D:\AI\PrismML\dev\llama.cpp\build-vulkan-ucrt64\bin\llama-server.exe"
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\auto_run.ps1 -LlamaServer $server -Model qwen9 -LegacySuite think02 -ThinkMode on -ThinkMaxTokens 8192
```

Only the five ON cases are executed, under a fresh `results/run_YYYYMMDD_HHMMSS/qwen9/THINK-02/` folder. The L01–L05 source prompts are unchanged; the sole request change is `max_tokens: 2048 -> 8192`. Do not merge these with the old 2048-token run without distinguishing output budgets. If the answer still ends with `finish_reason=length`, document it and assess whether to retry with 16384 tokens; that is a separate condition. This setting applies only to THINK-02; Context remains 65536, KV K/V q8_0, MTP OFF and RX9070XT target. Reasoning control effectiveness still requires inspection.


## Speed benchmark: baseline vs MTP (initial probe)

The committed `speed_probe.py` measures three workloads × 3 repetitions, recording llama-server `timings`, total wall clock, tokens, finish reason, and raw responses. **It does not launch the model or enable MTP**. First start the target model with the same fixed RX9070XT/65536/Q8+Q8/FA settings, then run the probe in another terminal.

Baseline:
```powershell
python experiments/bonsai2-rx9060xt/benchimark-summary64k/speed_probe.py --label qwen9_normal --output experiments/bonsai2-rx9060xt/benchimark-summary64k/results/speed_qwen9_normal
```

MTP candidate: stop the original server, verify `llama-server --help` lists `draft-mtp` and the exact MTP model/sidecar is compatible. Start with the same ordinary flags **plus** `--spec-type draft-mtp --spec-draft-n-max 3` (or model-specific flags documented for that converted model). Inspect server startup and speculative acceptance metrics. Run:
```powershell
python experiments/bonsai2-rx9060xt/benchimark-summary64k/speed_probe.py --label qwen9_mtp_n3 --output experiments/bonsai2-rx9060xt/benchimark-summary64k/results/speed_qwen9_mtp_n3
```

No MTP availability is inferred from directory names containing `MTP`. With unsupported heads or model metadata, do not report an MTP gain. Compare per-case median tg_tok_s and total time, quality/finish reasons, prompt tokens, backend logs, accepted draft-token rate and VRAM. Compute gain = MTP / baseline for TG, or baseline_time / MTP_time for latency. Test n-max 1/3/5 only **after** establishing MTP actually activates; store each configuration separately. Qwen3.5-9B, Bonsai8, Gemma4-12B, Bonsai2-27B and Gemma4-26B have different compatibility; only confirmed supported configurations are eligible for an MTP-on measurement. Official Bonsai2-27B DSpark is not released as of this check; DSpark is a different draft mechanism from MTP.

As a first comparison, the probe uses Think OFF requests where supported to reduce hidden reasoning variability. A subsequent Think ON speed run needs identical max token and thought settings on both decoding modes. The benchmark intentionally does not change existing THINK/LCTX result files.


## Model-specific MTP startup (2026-10-15)

`start_mtp_speed.ps1` explicitly selects RX9070XT by local `--list-devices`, pins context 65536 / K,V q8_0, and allows `-Mode baseline` vs `-Mode mtp`. Targets: Qwen3.5 9B embedded NextN (no separate drafter); Gemma4 12B and 26B A4B QAT separate Q8_0 draft files. Check Gemma12 QAT target vs non-QAT assistant compatibility in runtime before trusting it.

```powershell
$server = "D:\AI\PrismML\dev\llama.cpp\build-vulkan-ucrt64\bin\llama-server.exe"
# Terminal 1: baseline, then Ctrl+C after benchmark
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\start_mtp_speed.ps1 -LlamaServer $server -Model qwen9 -Mode baseline
# Terminal 2:
python experiments/bonsai2-rx9060xt/benchimark-summary64k/speed_probe.py --label qwen9_baseline --output experiments/bonsai2-rx9060xt/benchimark-summary64k/results/qwen9_baseline
# Terminal 1: restart target in MTP mode
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\start_mtp_speed.ps1 -LlamaServer $server -Model qwen9 -Mode mtp -DraftNMax 4
# Terminal 2: run same probe, separate results:
python experiments/bonsai2-rx9060xt/benchimark-summary64k/speed_probe.py --label qwen9_mtp4 --output experiments/bonsai2-rx9060xt/benchimark-summary64k/results/qwen9_mtp4
```

Replace `qwen9` with `gemma12` or `gemma26` for corresponding model and MTP pair. A successful process launch does not establish MTP activation: verify speculative initialization, draft accepted rate and that selected Vulkan GPU is RX9070XT. Baseline and MTP must use the same backend binary and model path. Keep separate timing runs and note GPU memory pressure. These examples do not auto-start or stop the speed probe.


## One-command automatic speed run

Use `auto_speed.ps1` to launch/stop each llama-server configuration, and run `speed_probe.py` automatically. Existing servers on the same port are rejected; no external process is stopped. Baseline and MTP use the same target GGUF, RX9070XT Vulkan device, 65536 context, q8_0 K/V, Flash Attention and 3 repetitions per workload.

```powershell
git pull --ff-only origin bench/summary-rx9070xt-64k-20261015
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
$server = "D:\AI\PrismML\dev\llama.cpp\build-vulkan-ucrt64\bin\llama-server.exe"
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\auto_speed.ps1 -LlamaServer $server -Model qwen9 -Mode both -DraftNMax 4
# Then all three supported target configurations:
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\auto_speed.ps1 -LlamaServer $server -Model all -Mode both -DraftNMax 4
```

Output: `results/run_speed_YYYYMMDD_HHMMSS/manifest.json`, `device-list.txt`, and per-configuration `qwen9_baseline/`, `qwen9_mtp/`, `gemma12_*/`, `gemma26_*/`, each containing startup logs, argv, raw JSON, trials.csv and summary.json.

**MTP verification gate**: The requested MTP flag and successful API output alone do not confirm a functioning MTP kernel; inspect the startup logs and speculative acceptance counters. Existing baseline logs showing `blk.32.nextn.* -- ignoring` prove NextN tensors are present but unused in baseline mode. This is expected. Mark MTP runs unverified until actual speculative draft activity appears. If MTP launch fails (unsupported binary, incompatible Gemma QAT target, or VRAM limit), record failure and do not fabricate speedup ratios. The helper currently collects evidence and measurements; acceptance-rate verification remains manual.


## Gemma4 MTP crash triage (2026-10-15)

Reported: `Starting gemma12 / mtp / Vulkan1` followed by llama-server crash. Similar upstream reports: llama.cpp issues #25873 (Gemma4 12B drafter warmup assertion), #24492 (wrong draft backend / cross-context shared KV), and #24795 (loader regression). **No definite cause until stderr is inspected**.

`auto_speed.ps1` now:
- Selects `--spec-draft-model` vs `--model-draft` based on `llama-server --help`.
- Adds `--spec-draft-device VulkanN` where supported to pin the drafter to the RX9070XT.
- Pins drafter GPU layers when supported.
- Has `-DiagnosticShortContext` for c=4096, to distinguish memory demand from early loader failures. This run does **not** match 64K speed benchmark conditions; do not include it in speed tables.

**First test only Gemma12 MTP**, leaving already-collected baseline intact:

```powershell
git pull --ff-only origin bench/summary-rx9070xt-64k-20261015
$server = "D:\AI\PrismML\dev\llama.cpp\build-vulkan-ucrt64\bin\llama-server.exe"
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\auto_speed.ps1 -LlamaServer $server -Model gemma12 -Mode mtp -DraftNMax 2 -Repeat 1 -DiagnosticShortContext
```

After crash, inspect `results/run_speed_*/gemma12_mtp/argv.txt`, `server.stderr.log`, and `failure.txt`. A crash even before the model is loaded is different from `invalid vector subscript` or `pre-allocated tensor ... NONE` during MTP warmup. Do not retry all models until this diagnosis is resolved. If the short-context run works, rerun without `-DiagnosticShortContext` for comparable 64K test. On repeated launch crash, prefer a separate compatible llama.cpp build over randomly toggling KV/Flash-Attention flags.


## MTP load/restart reliability test (10× per model)

`auto_mtp_restart.ps1` is independent of speed benchmarks. It sequentially starts Gemma4-12B and Gemma4-26B A4B with their user-specified Q8_0 MTP drafts, waits for `/health`, optionally sends a tiny inference probe, and stops *only the child process it created*. Each model gets 10 attempts and each attempt has its own argv, stderr/stdout, optional probe, and error result. Failures are recorded and the next attempt continues.

**Stability settings are mandatory:** `--ctx-checkpoints 0 --fit off`; RX9060XT is default; RX9070XT may be specified. To reduce VRAM pressure during initial **loader-only** verification, context defaults to 4096. It is **not equivalent to the 65536-context production test**. Before a 64K run, confirm the 9060XT has enough VRAM/system memory for target+MTP drafter+KV. The test writes `results/run_mtp_restart_YYYYMMDD_HHMMSS/{manifest.json,trials.csv,summary.json,gemma12/restart_01/...,gemma26/restart_10/...}`. Driver version should be recorded externally (26.3.1 as tested). The process is force-stopped (Windows Stop-Process), so this is a startup/reallocation stress test **not** a graceful shutdown regression test.

```powershell
git pull --ff-only origin bench/summary-rx9070xt-64k-20261015
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
$server = "D:\AI\PrismML\dev\llama.cpp\build-vulkan-ucrt64\bin\llama-server.exe"
.\experiments\bonsai2-rx9060xt\benchimark-summary64k\auto_mtp_restart.ps1 -LlamaServer $server -Model all -Gpu 9060 -Repeat 10
```

For RX9070XT loader runs: change `-Gpu 9060` to `-Gpu 9070`. For production-like 64K, explicitly add `-Context 65536`, but monitor memory pressure. `-ProbeInference` performs a 16-token test to exercise MTP beyond startup; omitted by default for the narrow load-failure question. No performance number is claimed from this diagnostic. `summary.json` success means API readiness and model list, not that drafting token acceptance occurred; acceptance requires inspection of runtime logs or an inference probe.
