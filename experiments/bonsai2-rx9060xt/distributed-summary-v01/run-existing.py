#!/usr/bin/env python3
"""Existing-server comparison. No server lifecycle or config changes."""
import argparse
import csv
import hashlib
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime

def request_json(url, body=None, timeout=15):
    if body is None:
        req = urllib.request.Request(url, headers={"Accept":"application/json"})
    else:
        payload=json.dumps(body,ensure_ascii=False,separators=(",",":")).encode("utf-8")
        req=urllib.request.Request(url, data=payload, headers={"Content-Type":"application/json; charset=utf-8"},method="POST")
    try:
        with urllib.request.urlopen(req,timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        details=e.read(4000).decode("utf-8","replace")
        raise RuntimeError(f"HTTP {e.code} at {url}: {details}") from e

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--model",choices=("bonsai","gemma"),required=True)
    ap.add_argument("--data-dir",default=None)
    ap.add_argument("--timeout",type=int,default=1200)
    args=ap.parse_args()
    root=pathlib.Path(__file__).resolve().parent
    data=pathlib.Path(args.data_dir) if args.data_dir else root/"dataset"
    port=8078 if args.model=="bonsai" else 8081
    base=f"http://127.0.0.1:{port}"
    out=root/"results"/(args.model+"_"+datetime.now().strftime("%Y%m%d_%H%M%S"))
    out.mkdir(parents=True,exist_ok=False)
    print("Results:",out,flush=True)
    try:
        prompt_bytes=(data/"prompt.txt").read_bytes()
        prompt=prompt_bytes.decode("utf-8")
        gold=json.loads((data/"gold.json").read_text(encoding="utf-8"))
        print(f"[1/5] Dataset loaded: {len(prompt)} chars, {len(prompt_bytes)} bytes",flush=True)
        if len(prompt)>80000:
            raise RuntimeError("Conservative 80k-character guard exceeded. Regenerate a smaller dataset.")
        print(f"[2/5] Checking existing server {base}",flush=True)
        health=request_json(base+"/health",timeout=10)
        if health.get("status")!="ok":
            raise RuntimeError(f"Server not ready: {health}")
        models=request_json(base+"/v1/models",timeout=10)
        (out/"models.json").write_text(json.dumps(models,ensure_ascii=False,indent=2),encoding="utf-8")
        print("[3/5] Creating UTF-8 JSON request (no /tokenize call)",flush=True)
        body={
            "messages":[{"role":"user","content":prompt}],
            "max_tokens":2048,
            "temperature":0,
            "top_k":1,
            "seed":42,
            "reasoning_effort":"none",
            "chat_template_kwargs":{"enable_thinking":False},
        }
        body_bytes=json.dumps(body,ensure_ascii=False,separators=(",",":")).encode("utf-8")
        (out/"request.json").write_bytes(body_bytes)
        print(f"Request JSON saved: {len(body_bytes)} bytes",flush=True)
        print(f"[4/5] Sending inference to {args.model}; waiting for response (timeout {args.timeout}s)",flush=True)
        began=time.monotonic()
        result=request_json(base+"/v1/chat/completions",body,timeout=args.timeout)
        elapsed=time.monotonic()-began
        (out/"response.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
        answer=str(result["choices"][0]["message"].get("content") or "")
        (out/"answer.txt").write_text(answer,encoding="utf-8")
        print("[5/5] Scoring structured facts",flush=True)
        parsed={}
        for line in answer.splitlines():
            match=re.match(r"^\s*\*{0,2}(F\d\d)\*{0,2}\s*[:：]\s*(.*?)\s*$",line)
            if match:
                parsed[match.group(1)]=match.group(2).strip(" 。.*")
        rows=[]
        for item in gold:
            observed=parsed.get(item["id"],"")
            expected=str(item["expected"])
            status="MISSING" if not observed else ("EXACT" if observed==expected else "REVIEW")
            rows.append({"id":item["id"],"expected":expected,"observed":observed,"status":status})
        with (out/"fact_checks.csv").open("w",encoding="utf-8-sig",newline="") as f:
            writer=csv.DictWriter(f,fieldnames=["id","expected","observed","status"])
            writer.writeheader()
            writer.writerows(rows)
        usage=result.get("usage",{})
        timings=result.get("timings") or {}
        summary={
            "model":args.model,"endpoint":base,"dataset_sha256":hashlib.sha256(prompt_bytes).hexdigest(),
            "prompt_characters":len(prompt),"actual_prompt_tokens":usage.get("prompt_tokens"),
            "generated_tokens":usage.get("completion_tokens"),
            "finish_reason":result["choices"][0].get("finish_reason"),
            "elapsed_seconds":round(elapsed,3),
            "pp_tok_s":timings.get("prompt_per_second"),
            "tg_tok_s":timings.get("predicted_per_second"),
            "exact":sum(x["status"]=="EXACT" for x in rows),
            "review":sum(x["status"]=="REVIEW" for x in rows),
            "missing":sum(x["status"]=="MISSING" for x in rows),
            "caveat":"Exact string equality only. REVIEW and MISSING need human review.",
        }
        (out/"summary.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
        for item in rows:
            print(f'{item["id"]}: {item["status"]}: {item["observed"][:50]}',flush=True)
        print("SUMMARY",json.dumps(summary,ensure_ascii=False,indent=2),flush=True)
        print("Results:",out,flush=True)
    except Exception as e:
        (out/"failure.txt").write_text(f"{type(e).__name__}: {e}\n",encoding="utf-8")
        print(f"ERROR: {e}",file=sys.stderr,flush=True)
        print("Results:",out,file=sys.stderr,flush=True)
        return 1
    return 0

if __name__=="__main__":
    sys.exit(main())
