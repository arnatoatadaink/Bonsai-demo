#!/usr/bin/env python3
"""Local OpenAI-compatible summary benchmark. No external Python dependencies."""
import argparse
import csv
import json
import re
import time
import urllib.request
from pathlib import Path

MODELS = {
    "bonsai8": {"path": r"D:\lmstudio_models\prism-ml\Ternary-Bonsai-8B-gguf\Ternary-Bonsai-8B-PQ2_0.gguf", "family": "bonsai", "modes": ["off", "on"]},
    "gemma12": {"path": r"D:\lmstudio_models\unsloth\gemma-4-12b-it-GGUF\gemma-4-12B-it-qat-UD-Q4_K_XL.gguf", "family": "gemma", "modes": ["normal"]},
    "qwen9": {"path": r"D:\lmstudio_models\unsloth\Qwen3.5-9B-MTP-GGUF\Qwen3.5-9B-UD-Q4_K_XL.gguf", "family": "qwen", "modes": ["off", "on"]},
}
LEVELS = {1: 1000, 2: 4000, 3: 12000, 4: 32000, 5: 60000}
FACTS = [
    "Project ID is ALPHA-417.",
    "The approved budget is 23.7 million yen.",
    "The audit deadline is November 19, 2026.",
    "The responsible lead is Sato.",
    "The unresolved risk is delayed supplier certification.",
]
FILLER = ("Internal progress notes: the team reviewed the schedule, revised the document index, "
          "and recorded observations without changing the approved budget. ")
FIELDS = ["model", "level", "mode", "status", "thinking_verified", "elapsed_s",
          "prompt_tokens", "completion_tokens", "reasoning_tokens", "tokens_per_s",
          "fact_exact_hits", "response_path", "error"]

def post_json(url, data, timeout):
    req = urllib.request.Request(url, data=json.dumps(data).encode("utf-8"),
                                 headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return json.load(res)

def get_json(url, timeout=10):
    with urllib.request.urlopen(url, timeout=timeout) as res:
        return json.load(res)

def fixture(level):
    """Synthetic input, approximate token length only; actual usage must be checked."""
    target = LEVELS[level]
    # English prose approximated at 4 chars/token. Never claim exact token count.
    total_chars = 4 * target
    paragraphs = []
    for idx, fact in enumerate(FACTS):
        chunk = (FILLER * (max(1, total_chars // (len(FACTS) * len(FILLER))) + 2))
        paragraphs.append(f"Section {idx + 1}. {fact}\n" + chunk[:total_chars // len(FACTS)])
    return "\n".join(paragraphs)

def messages_for(text, mode, family):
    system = ("Summarize this document in Japanese, using concise bullet points. "
              "Preserve all important facts, dates, numbers, people and risks. "
              "Do not invent information. Output only the final summary.")
    # Explicit templates are not assumed to be supported across backends.
    directive = ""
    if family == "qwen":
        directive = "\n/no_think" if mode == "off" else "\n/think"
    elif family == "bonsai":
        directive = "\nAnswer without reasoning traces." if mode == "off" else ""
    return [{"role": "system", "content": system},
            {"role": "user", "content": text + directive}]

def thinking_status(response, mode):
    # APIs may hide reasoning internally; no field is NOT proof that thinking was off.
    choice = (response.get("choices") or [{}])[0]
    msg = choice.get("message") or {}
    reasoning = msg.get("reasoning_content") or msg.get("reasoning") or ""
    usage = response.get("usage") or {}
    details = usage.get("completion_tokens_details") or {}
    reasoning_count = details.get("reasoning_tokens")
    if reasoning or (isinstance(reasoning_count, int) and reasoning_count > 0):
        return "detected"
    return "unverified" if mode in ("on", "off") else "not_applicable"

def run_one(base_url, model_id, key, level, mode, timeout, max_tokens, output_dir):
    cfg = MODELS[key]
    payload = {
        "model": model_id,
        "messages": messages_for(fixture(level), mode, cfg["family"]),
        "stream": False,
        "max_tokens": max_tokens if mode == "on" else 2048,
        "temperature": 0.7 if mode == "off" else 1.0,
    }
    # llama.cpp accepts chat_template_kwargs on supporting templates.
    # Servers can ignore this option: inspection of reasoning evidence is mandatory.
    if mode in ("off", "on"):
        payload["chat_template_kwargs"] = {"enable_thinking": mode == "on"}
    if cfg["family"] == "bonsai" and mode == "on":
        payload["top_p"] = 0.95
    t0 = time.perf_counter()
    record = dict.fromkeys(FIELDS, "")
    record.update(model=key, level=level, mode=mode)
    try:
        answer = post_json(base_url.rstrip("/") + "/v1/chat/completions", payload, timeout)
        elapsed = time.perf_counter() - t0
        msg = (answer.get("choices") or [{}])[0].get("message") or {}
        content = msg.get("content") or ""
        usage = answer.get("usage") or {}
        completion = usage.get("completion_tokens")
        details = usage.get("completion_tokens_details") or {}
        filename = f"{key}_L{level}_{mode}.json"
        (output_dir / filename).write_text(json.dumps({"request_settings": {
            "model": model_id, "mode": mode, "max_tokens": payload["max_tokens"],
            "temperature": payload["temperature"], "chat_template_kwargs": payload.get("chat_template_kwargs")},
            "response": answer}, ensure_ascii=False, indent=2), encoding="utf-8")
        record.update(status="ok", thinking_verified=thinking_status(answer, mode),
                      elapsed_s=round(elapsed, 3),
                      prompt_tokens=usage.get("prompt_tokens", ""),
                      completion_tokens=completion or "",
                      reasoning_tokens=details.get("reasoning_tokens", ""),
                      tokens_per_s=round(completion / elapsed, 2) if completion else "",
                      fact_exact_hits=sum(x.lower() in content.lower() for x in FACTS),
                      response_path=str(output_dir / filename))
    except Exception as exc:
        record.update(status="error", error=str(exc), elapsed_s=round(time.perf_counter() - t0, 3))
    return record

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", choices=MODELS, required=True, help="One model loaded on server per run")
    ap.add_argument("--server-model-id", default="", help="Actual model ID from /v1/models; auto-detected if omitted")
    ap.add_argument("--base-url", default="http://127.0.0.1:8080")
    ap.add_argument("--levels", default="1,2,3,4,5")
    ap.add_argument("--output", default="summary-benchmark-results")
    ap.add_argument("--timeout", type=int, default=1200)
    ap.add_argument("--on-max-tokens", type=int, default=8192)
    ap.add_argument("--acknowledge-server-settings", action="store_true",
                    help="Confirm server log shows ctx=65536, K/V q8_0, FA enabled, MTP disabled and RX9070XT")
    args = ap.parse_args()
    if not args.acknowledge_server_settings:
        ap.error("Verify backend settings, then pass --acknowledge-server-settings")
    output_dir = Path(args.output)
    output_dir.mkdir(exist_ok=True, parents=True)
    models = get_json(args.base_url.rstrip("/") + "/v1/models")
    available = [x["id"] for x in models.get("data", [])]
    model_id = args.server_model_id or (available[0] if len(available) == 1 else None)
    if not model_id or model_id not in available:
        ap.error(f"Specify --server-model-id; available: {available}")
    selected = [int(x.strip()) for x in args.levels.split(",")]
    if any(x not in LEVELS for x in selected):
        ap.error("Levels must be 1-5")
    path = output_dir / "results.csv"
    exists = path.exists() and path.stat().st_size > 0
    with path.open("a", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        if not exists:
            writer.writeheader()
        for level in selected:
            for mode in MODELS[args.model]["modes"]:
                result = run_one(args.base_url, model_id, args.model, level, mode,
                                 args.timeout, args.on_max_tokens, output_dir)
                writer.writerow(result)
                f.flush()
                print(json.dumps(result, ensure_ascii=False))
    print(f"Results: {path}")

if __name__ == "__main__":
    main()
