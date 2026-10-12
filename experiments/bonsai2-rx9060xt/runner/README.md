# MTP-01 Windows Native first-divergence runner

Prerequisite: known-good PrismML llama-server b10772 compiled under MSYS2 UCRT64, model accessible on disk, **port 18080 free**. This runner is independent of Bonsai-demo's normal launcher and uses the **personal fork** only.

Run from PowerShell (not the MSYS2 shell):

```powershell
Set-Location D:\AI\PrismML\dev\Bonsai-demo
git switch research/bonsai2-mtp-kv-baseline-2026-10-12
git pull --ff-only origin research/bonsai2-mtp-kv-baseline-2026-10-12
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\experiments\bonsai2-rx9060xt\runner\run-divergence.ps1 -Mode smoke
```

When smoke reports 4 OK rows (32K Q4/Q4 and Q8/Q4 × OFF/ON), run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\experiments\bonsai2-rx9060xt\runner\run-divergence.ps1 -Mode full
```

Full runs 3 independent cold server processes per condition = 12 tests for 32K. To add 64K use \`-Include64K\` with full; 24 tests total. Override \`-PromptFile\` for Q06 (UTF-8 plain text), and \`-MaxTokens\` if you need a completed long-form response. Default prompt is an intentionally nonprivate short access-control reasoning prompt; **do not silently label it the original Q06**. Default cap 1024 may end in \`length\`.

Files: \`manifest.json\`, \`prompt.txt\`, per-run API response \`*.json\`, per-run \`*.tokens.json\`, \`summary.csv\`, \`first-divergence.csv\`, and server stderr/stdout logs. The output root is outside Git by default.

**Interpretation:** Token sequences in this runner are **post-hoc re-tokenizations of text returned by the server**, not original sampled token IDs. Chat formatting, hidden boundaries between \`reasoning_content\` and \`content\`, and special tokens can cause off-by-one or missing-token effects. They indicate **candidate first visible-content divergence**, never exact internal token divergence. Raw token-ID or target logits verification requires separately instrumenting llama.cpp. Also ensure repeated runs in identical config give matching output before attributing a cross-config difference to MTP.

**Safety:** Do not run while an unrelated process is using port 18080. Runner stops only the child PID it started. Avoid publishing raw prompts/responses before privacy review. No \`git push\` or upstream modification is performed by the script. This is untested on the target Windows machine until the user executes it.
