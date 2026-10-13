# Bonsai2 Think compare v0.1 (Windows / RX 9060 XT)

Self-contained benchmark for Default / Think OFF / Think ON with three fixed questions. It starts its own llama-server, saves machine-readable evidence, and terminates only the child process it created. It does not modify ports 8078 (Bonsai), 8081 (Gemma), or 8090 (Jina).

## Usage

1. Stop an existing Bonsai instance on RX 9060 XT first. A different port does not prevent competing allocations on the same GPU.
2. Edit config.json paths and optional parameters.
3. Double-click run.bat, or execute powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run.ps1.
4. Collect results/run_YYYYMMDD_HHMMSS/ for review. The results directory is gitignored.

Default GPU: Vulkan0; context 98304; K q8_0 / V q4_0; MTP explicitly disabled; flash-attn on. Dedicated port 18087. No admin rights required.

## Evidence

Each run saves environment.json (binary SHA256 and model path), models.json, trials.csv, per-case request/response JSON, response texts, server stdout/stderr, and errors. Questions run in the order Default, OFF, ON. Empty reasoning_content does not prove absence of model-internal reasoning. ON/OFF effectiveness requires evidence; identical outputs are inconclusive.

The benchmark requests reasoning_effort none/high together with chat_template_kwargs.enable_thinking false/true. These are test requests, not verified supported Bonsai2 settings. The model's low reasoning effort is documented as unsupported.

## Limitations

No automatic semantic quality grading. Fixed temperature=0 and seed=42 isolate the switches, not production decoding defaults. This does not run Vulkan kernel optimization or MTP comparisons. Requires Windows PowerShell 5.1+, local binary/model, and a free port 18087. Existing foreign processes are never terminated.
