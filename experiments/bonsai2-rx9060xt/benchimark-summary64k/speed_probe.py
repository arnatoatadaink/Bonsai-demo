#!/usr/bin/env python3
"""Decode-speed measurements on an already-running, separately-configured llama-server.
Run identical prompts once for baseline and once for MTP. Report timings without
claiming MTP is active; inspect server logs for speculative acceptance separately.
"""
import argparse,csv,json,statistics,time,urllib.request
from pathlib import Path
CASES={
 "short":"Summarize in Japanese in 150-250 Japanese characters. Facts: 2026-Q1 revenue 120 million, operating profit 14 million; 2026-Q2 revenue 135 million, operating profit 11 million. Q2 capex 22 million, eight million already approved. Q3 results unavailable.",
 "structured":"Create a structured 12-point Japanese briefing about why documented facts, forecasts, approvals and assumptions must be kept distinct in an audit. Give concrete examples and identify uncertainty.",
 "long_decode":"Write an approximately 1500-word detailed technical explanation in Japanese of KV cache quantization, prompt processing, autoregressive decoding, and speculative decoding. Distinguish demonstrated mechanisms from conjectures and give practical benchmark pitfalls."
}
def req(base,body,timeout):
 data=json.dumps(body,ensure_ascii=False).encode()
 r=urllib.request.Request(base.rstrip("/")+"/v1/chat/completions",data=data,headers={"Content-Type":"application/json; charset=utf-8"})
 with urllib.request.urlopen(r,timeout=timeout) as f:return json.load(f)
def main():
 p=argparse.ArgumentParser()
 p.add_argument("--base-url",default="http://127.0.0.1:18080")
 p.add_argument("--label",required=True,help="Unique model+decoding configuration, e.g. qwen9_mtp_n3")
 p.add_argument("--output",required=True)
 p.add_argument("--repeat",type=int,default=3)
 p.add_argument("--timeout",type=int,default=900)
 a=p.parse_args()
 out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
 rows=[]
 for key,prompt in CASES.items():
  for i in range(a.repeat):
   body={"messages":[{"role":"user","content":prompt}],"max_tokens":2048 if key=="long_decode" else 512,"temperature":0,"top_k":1,"seed":42,"reasoning_effort":"none","chat_template_kwargs":{"enable_thinking":False}}
   before=time.perf_counter()
   row={"label":a.label,"case":key,"repeat":i+1,"status":"ERROR"}
   try:
    response=req(a.base_url,body,a.timeout)
    elapsed=time.perf_counter()-before
    choice=response["choices"][0];tim=response.get("timings") or {}; usage=response.get("usage") or {}
    row.update(status="OK",elapsed_s=round(elapsed,4),prompt_tokens=usage.get("prompt_tokens"),
     completion_tokens=usage.get("completion_tokens"),pp_tok_s=tim.get("prompt_per_second"),
     tg_tok_s=tim.get("predicted_per_second"),finish_reason=choice.get("finish_reason"),
     text_chars=len(choice.get("message",{}).get("content") or ""))
    (out/f"{key}_{i+1}.json").write_text(json.dumps({"request":body,"response":response},ensure_ascii=False,indent=2),encoding="utf-8")
   except Exception as e:
    row["error"]=str(e)
   rows.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
 with (out/"trials.csv").open("w",encoding="utf-8-sig",newline="") as f:
  fields=list(dict.fromkeys(k for row in rows for k in row))
  w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(rows)
 summary={}
 for key in CASES:
  valid=[r for r in rows if r["case"]==key and r["status"]=="OK"]
  summary[key]={"completed":len(valid),"median_tg_tok_s":statistics.median([float(r["tg_tok_s"]) for r in valid if r.get("tg_tok_s") is not None]) if any(r.get("tg_tok_s") is not None for r in valid) else None,
  "median_elapsed_s":statistics.median([r["elapsed_s"] for r in valid]) if valid else None}
 (out/"summary.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
 if len(rows)!=sum(v["completed"] for v in summary.values()):raise SystemExit(1)
if __name__=="__main__":main()
