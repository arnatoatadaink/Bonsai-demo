# Next task: first divergent token — MTP ON vs OFF

**Question:** Under the same model, prompt, context and target KV precision, what is the first output-token position where `draft-mtp` ON and OFF differ?

## Step A — Bonsai-demo: non-invasive API-level experiment
1. Re-run the same Q06 input, and a shorter *non-private* reproduction prompt, with **32K Q4/Q4**, **32K Q8/Q4**; repeat at 64K if stable.
2. Compare `MTP OFF` vs `MTP ON (draft2)`; run each condition **at least three independent cold sessions** in addition to prior one-off results.
3. Lock GGUF hash, runtime hash, model parameters, full *effective* sampler settings (temperature=0 is not sufficient by itself), seed, prompt serialization/chat template, max output, prefix/cache conditions, batch, GPU backend.
4. Capture raw completion and `reasoning_content` separately plus `finish_reason`. Never assume `reasoning_content` is every internal model decision. If available, collect token IDs from a supported endpoint; otherwise tokenize offline with the *same model tokenizer*. String-character diff is preliminary only, not the token divergence index.
5. Align **generated** token IDs, report first mismatch, common-prefix token count, and whether mismatch is in reasoning or final. Record output-sha256, draft acceptance, PP/TG and GPU usage.
6. Make a compact public reproduction prompt before posting upstream. Q06 synthetic fixture can be included only after confirming no private content.

## Step B — llama.cpp fork: instrumentation, separate from baseline harness
If Step A verifies a stable mismatch with identical decoding parameters, add **diagnostic-only** trace logging (off by default):
- target-token candidate ID and best competing logits at divergence vicinity;
- MTP draft IDs, accepted/rejected lengths, fallback token ID;
- per-step sequence/prefix and target/draft K/V configurations;
- batching/verification path flags where possible.
Keep numerical outputs and secret prompts out of normal logs, avoid performance perturbations, and never commit model weights or inference captures with private context.

## Interpretation
- A different trace at temp 0 does **not** alone prove a speculative decoding correctness bug.
- The goal is to isolate the *first* divergence and its cause, not to claim MTP improves accuracy because output is shorter.
- Separate Q4/Q4↔Q8/Q4 effect with MTP OFF from OFF↔ON effect under the *same KV*.
- If truly strict greedy decoding is established, compare the per-step target logits at the shared prefix; this is the core correctness check.
