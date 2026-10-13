# Distributed evidence summary / long-context quality comparison v0.1

**Preparation only:** No inference has been executed. This suite is independent of the previous short/medium summary tests. It intentionally tests factual accuracy, omissions, and unfounded substitutions, **not** stylistic summary quality.

## Goal
A single synthetic Japanese report contains 24 distinct, uniquely identified facts scattered across its entire length. The same document and 24 explicit questions are sent to both models. Facts include numbers, names, dates, exceptions, unapproved plans, missing reports, causes, and postponed launches. Answers are asked in the compact format `F01: value`.

## Preparation
Run `prepare.bat` once (requires Windows `py -3` and Python standard library). It creates gitignored dataset/source.txt, dataset/gold.json, dataset/prompt.txt with a deterministic random seed and common input for both models. No local model is loaded.

## Execution when ready (NOT part of preparation)
- Existing Bonsai2 server with MTP OFF: localhost:8078 => run-bonsai.bat
- Existing Gemma4 server: localhost:8081 => run-gemma.bat
- Servers are **never started/stopped/reconfigured** by this suite.
- Requires both models to use effective Think OFF; the request also asks for none and enable_thinking=false.
- Each run independently preflights /tokenize, refuses prompt >= 60000 estimated tokens, and caps generation at 2048 tokens.
- Keep same dataset/prompt.txt between models. Both result summaries record the SHA256.
- If either server is unavailable, execute only the available model later; no server must be stopped for preparation.
- A dedicated 64k context is required. The 60000-token ceiling is conservative but does not guarantee fit if chat-template overhead is extreme.

## Results
Each run writes results/{model}_{timestamp}/:
- models.json
- request.json
- response.json
- answer.txt
- fact_checks.csv (24 answers: EXACT, REVIEW, MISSING)
- summary.json (tokens, PP, TG, time and counts)
- failure.txt on error

`EXACT` compares literal expected answer strings, therefore equivalent rephrasings produce REVIEW, **not an error by themselves**. Manually judge REVIEW and MISSING, and inspect unsupported claims in answer.txt. Failure to emit parseable Fxx lines is scored MISSING. Compare failure rates only after review.

## Scope and caveats
- Synthesized document with repeated unrelated context, not a genuine 64k business document.
- Generator defaults to around 65000 **characters** (not tokens); actual tokenizer lengths differ.
- No claim of equivalent GPU/memory settings or comparable tokenizer token counts.
- Fixed temp=0, top_k=1, seed=42 to isolate models.
- Long-document summarization with dispersed facts is approximated by *structured extraction*, not a free-form natural summary.
- Re-run with harder distractors and 32k/50k token targets if this screening test yields a ceiling effect.

**Nothing in this suite has been executed on the user's Windows machines.**
