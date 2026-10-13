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

The benchmark requests reasoning_effort none/medium together with chat_template_kwargs.enable_thinking false/true. These are test requests, not verified supported Bonsai2 settings. The model's low reasoning effort is documented as unsupported.

## Limitations

No automatic semantic quality grading. Fixed temperature=0 and seed=42 isolate the switches, not production decoding defaults. This does not run Vulkan kernel optimization or MTP comparisons. Requires Windows PowerShell 5.1+, local binary/model, and a free port 18087. Existing foreign processes are never terminated.

## v0.1.1 correction (2026-10-14)

The first Windows run treated the questions array as a single value under Windows PowerShell 5.1. The runner now parses the JSON array directly and requires exactly three questions, resulting in nine trials. The ON request now uses medium rather than high reasoning effort; HTTP failures preserve their response body as a per-case .error.txt file. Prior run_20261014_045953 contained only three combined trials and must not be used for per-question quality comparison.

## Faithfulness suite (v0.2)

Run run-long.bat to execute 5 evidence-retention scenarios x 3 modes (15 requests). The server is launched and stopped using the same dedicated child-PID logic. The question source is questions-long.json and output includes suite.json to identify it. The scenarios cover:
- exact financial numbers and periods
- negated approvals vs draft claims
- region- and date-specific exceptions
- mutually contradictory source figures
- forecast revisions vs actual shipment

This is a controlled moderate-length screening suite (repeated neutral background, not a 90k context test); it deliberately has no automatic LLM-as-judge. Use expected_checks fields in questions-long.json to manually assess evidence retention, unsupported assertions, contradiction handling and omissions. Do not score output based only on reasoning_content length.

Run.ps1 accepts -QuestionsFile questions.json (default) or -QuestionsFile questions-long.json. Original run.bat remains unchanged. The 96k allocation, K Q8_0 / V Q4_0, MTP OFF and Vulkan0 settings remain fixed.
