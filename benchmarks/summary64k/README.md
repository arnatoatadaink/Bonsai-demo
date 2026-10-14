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
