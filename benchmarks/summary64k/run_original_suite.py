#!/usr/bin/env python3
"""Run original think-compare question files against a pre-started local llama-server.
Fetches EXACT historic test inputs through git show, never regenerates or edits them.
No third-party Python packages. The server must be launched separately.
"""
import argparse
import csv
import json
import subprocess
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

REPO_REF = "origin/bench/bonsai2-think-compare-v01"
ROOT = "experiments/bonsai2-rx9060xt/think-compare-v01/"
SUITES = {"short": "questions.json", "long": "questions-long.json"}
FIELDS = ("suite", "id", "kind", "mode", "status", "prompt_tokens", "completion_tokens",
          "finish_reason", "content_chars", "reasoning_chars", "pp_tok_s", "tg_tok_s",
          "elapsed_sec", "error", "thinking_evidence")

def historical_json(name, ref):
    path = ROOT + SUITES[name]
    r = subprocess.run(["git", "show", f"{ref}:{path}"], capture_output=True, check=True)
    return json.loads(r.stdout.decode("utf-8-sig"))

def call(url, body, timeout):
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json; charset=utf-8"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.load(response)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", required=True, choices=["bonsai8", "gemma12", "qwen9"])
    p.add_argument("--suite", choices=["short", "long", "both"], default="both")
    p.add_argument("--base-url", default="http://127.0.0.1:18080")
    p.add_argument("--source-ref", default=REPO_REF)
    p.add_argument("--output", default="summary-benchmark-results/original-suite")
    p.add_argument("--max-tokens", type=int, default=2048)
    p.add_argument("--timeout", type=int, default=1200)
    p.add_argument("--smoke", action="store_true")
    args = p.parse_args()
    out = Path(args.output) / args.model / datetime.now(timezone.utc).strftime("run_%Y%m%d_%H%M%S")
    out.mkdir(parents=True, exist_ok=True)
    suites = ["short", "long"] if args.suite == "both" else [args.suite]
    modes = ["default", "off", "on"] if args.model != "gemma12" else ["default"]
    manifest = {"source_ref": args.source_ref, "source_path": ROOT, "suites": suites,
                "modes": modes, "model": args.model, "backend": args.base_url,
                "max_tokens": args.max_tokens, "sampling": {"temperature": 0, "top_k": 1, "seed": 42},
                "note": "Model path / actual hardware / KV cache are controlled externally. Thinking toggles may not be implemented by backend."}
    (out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    rows = []
    for suite in suites:
        questions = historical_json(suite, args.source_ref)
        if args.smoke: questions = questions[:1]
        for q in questions:
            for mode in modes:
                body = {"messages": [{"role": "user", "content": q["prompt"]}],
                        "max_tokens": args.max_tokens, "temperature": 0, "top_k": 1, "seed": 42}
                if mode == "off":
                    body.update(reasoning_effort="none", chat_template_kwargs={"enable_thinking": False})
                if mode == "on":
                    body.update(reasoning_effort="medium", chat_template_kwargs={"enable_thinking": True})
                prefix = f"{suite}_{q['id']}_{mode}"
                (out / (prefix + ".request.json")).write_text(json.dumps(body, ensure_ascii=False, indent=2), encoding="utf-8")
                start = time.perf_counter()
                row = {k: "" for k in FIELDS}
                row.update(suite=suite, id=q["id"], kind=q.get("kind", ""), mode=mode)
                try:
                    data = call(args.base_url.rstrip("/") + "/v1/chat/completions", body, args.timeout)
                    (out / (prefix + ".response.json")).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
                    choice = data["choices"][0]
                    msg = choice["message"]
                    content = str(msg.get("content") or "")
                    reasoning = str(msg.get("reasoning_content") or "")
                    (out / (prefix + ".response.txt")).write_text(content + "\n[REASONING_CONTENT]\n" + reasoning, encoding="utf-8")
                    usage = data.get("usage") or {}
                    timings = data.get("timings") or {}
                    rc = (usage.get("completion_tokens_details") or {}).get("reasoning_tokens")
                    row.update(status="OK", prompt_tokens=usage.get("prompt_tokens", ""),
                               completion_tokens=usage.get("completion_tokens", ""),
                               finish_reason=choice.get("finish_reason", ""),
                               content_chars=len(content), reasoning_chars=len(reasoning),
                               pp_tok_s=timings.get("prompt_per_second", ""),
                               tg_tok_s=timings.get("predicted_per_second", ""),
                               thinking_evidence="detected" if reasoning or (isinstance(rc, int) and rc > 0) else "unverified")
                except Exception as exc:
                    row.update(status="ERROR", error=str(exc))
                row["elapsed_sec"] = round(time.perf_counter() - start, 3)
                rows.append(row)
                with (out / "trials.csv").open("w", newline="", encoding="utf-8-sig") as fh:
                    writer = csv.DictWriter(fh, fieldnames=FIELDS)
                    writer.writeheader()
                    writer.writerows(rows)
                print(f"{prefix}: {row['status']} {row['elapsed_sec']}s", flush=True)
    print(f"Results: {out}")
    if any(r["status"] != "OK" for r in rows):
        raise SystemExit(1)

if __name__ == "__main__":
    main()
