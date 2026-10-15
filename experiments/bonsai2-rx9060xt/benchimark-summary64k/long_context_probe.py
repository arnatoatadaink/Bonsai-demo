#!/usr/bin/env python3
"""Long-context, repeated MTP inference. Exact input size verified using /tokenize.
No third-party dependencies. Fail closed when tokenization is unsupported.
"""
import argparse,csv,json,time,urllib.request,urllib.error,hashlib,sys
from pathlib import Path

def post(base,path,body,timeout):
    data=json.dumps(body,ensure_ascii=False).encode("utf-8")
    req=urllib.request.Request(base+path,data=data,headers={"Content-Type":"application/json; charset=utf-8"})
    with urllib.request.urlopen(req,timeout=timeout) as r:return json.loads(r.read())
def token_count(base,content,timeout):
    obj=post(base,"/tokenize",{"content":content,"add_special":False},timeout)
    toks=obj.get("tokens")
    if not isinstance(toks,list):raise RuntimeError("/tokenize returned no tokens; refusing unverified long-context payload")
    return len(toks)
def corpus(units, iteration=0):
    # High-entropy-ish record identifiers, deterministic; many scattered factual records and revisions.
    return "\n".join(
      f"[REC-{i:06d}] SALT={hashlib.sha256(f\"{iteration}:{i}:loadtest\".encode()).hexdigest()[:16]} CASE={i%97:02d} REGION={['NORTH','EAST','SOUTH','WEST'][i%4]} "
      f"VERSION=2026-{(i%12)+1:02d}-{(i%27)+1:02d} "
      f"AMOUNT={((i*7919)%90001)+10000} STATUS={['PENDING','APPROVED','REVISED'][i%3]} "
      f"KEY=K{i:06d} VALUE=V{((i*8191)%999983):06d}"
      for i in range(1,units+1))
def main():
 p=argparse.ArgumentParser()
 p.add_argument("--base-url",required=True)
 p.add_argument("--output",required=True)
 p.add_argument("--repeat",type=int,default=20)
 p.add_argument("--target-tokens",type=int,default=32768)
 p.add_argument("--context",type=int,default=65536)
 p.add_argument("--max-tokens",type=int,default=512)
 p.add_argument("--timeout",type=int,default=900)
 p.add_argument("--tokenize-timeout",type=int,default=180)
 p.add_argument("--input-mode",choices=["fixed","vary"],default="fixed")
 a=p.parse_args()
 if a.target_tokens+a.max_tokens+1024 > a.context: p.error("Target + generation + reserve exceeds context")
 out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
 base=a.base_url.rstrip("/")
 # Exponential expansion then binary search by record count; deterministic prompt shared across all iterations.
 def assemble(n, iteration=0):
  return ("The following synthetic audit ledger is test data. Use only its records. "
   "Return exactly the KEY, VALUE, AMOUNT and STATUS from REC-000001, REC-000097 and "
   "REC-000193. If a record is absent, say MISSING. Output brief labeled lines.\n"
   "BEGIN LEDGER\n"+corpus(n,iteration)+"\nEND LEDGER\n"
   "QUESTIONS: REC-000001, REC-000097, REC-000193\n")
 cache={}
 def count(n):
  if n not in cache:cache[n]=token_count(base,assemble(n),a.tokenize_timeout)
  return cache[n]
 lo,hi=193,256
 while count(hi)<a.target_tokens:
  lo,hi=hi,hi*2
  if hi>400000:raise RuntimeError("Too many records")
 for _ in range(22):
  if hi-lo<=1:break
  mid=(hi+lo)//2
  if count(mid)<a.target_tokens:lo=mid
  else:hi=mid
 prompt=assemble(hi);exact=count(hi)
 if exact+a.max_tokens+1024>a.context:
  raise RuntimeError(f"Actual prompt {exact} tokens exceeds reserved context")
 (out/"prompt.txt").write_text(prompt,encoding="utf-8")
 meta={"target_tokens":a.target_tokens,"tokenize_tokens_without_template":exact,
  "context":a.context,"max_tokens":a.max_tokens,"prompt_sha256":hashlib.sha256(prompt.encode()).hexdigest(),
  "records":hi,"input_mode":a.input_mode,"note":"Actual chat-template tokens are separately recorded from response usage; /tokenize excludes chat-template wrappers."}
 (out/"long_input_manifest.json").write_text(json.dumps(meta,indent=2),encoding="utf-8")
 rows=[]
 for i in range(1,a.repeat+1):
  effective_prompt=prompt if a.input_mode=="fixed" else assemble(hi,i)
  effective_tokens=exact if a.input_mode=="fixed" else token_count(base,effective_prompt,a.tokenize_timeout)
  if effective_tokens+a.max_tokens+1024>a.context:
   raise RuntimeError(f"Iteration {i} exceeded context budget ({effective_tokens} tokens)")
  if effective_tokens < a.target_tokens*0.88:
   raise RuntimeError(f"Iteration {i} too short for comparable workload ({effective_tokens} tokens)")
  if a.input_mode=="vary":
   (out/f"prompt_{i:03d}.txt").write_text(effective_prompt,encoding="utf-8")
  body={"messages":[{"role":"user","content":effective_prompt}],"max_tokens":a.max_tokens,
   "temperature":0,"top_k":1,"seed":42,"reasoning_effort":"none","chat_template_kwargs":{"enable_thinking":False}}
  start=time.monotonic()
  row={"iteration":i,"status":"ERROR","prompt_tokens":"","completion_tokens":"","pp_tok_s":"","tg_tok_s":"","finish_reason":"","elapsed_sec":"","error":"","input_mode":a.input_mode,"tokenize_tokens":effective_tokens,"prompt_sha256":hashlib.sha256(effective_prompt.encode()).hexdigest()}
  try:
   res=post(base,"/v1/chat/completions",body,a.timeout)
   choice=res["choices"][0];tim=res.get("timings") or {};usage=res.get("usage") or {}
   (out/f"response_{i:03d}.json").write_text(json.dumps(res,ensure_ascii=False,indent=2),encoding="utf-8")
   row.update(status="OK",prompt_tokens=usage.get("prompt_tokens",""),completion_tokens=usage.get("completion_tokens",""),
    pp_tok_s=tim.get("prompt_per_second",""),tg_tok_s=tim.get("predicted_per_second",""),
    finish_reason=choice.get("finish_reason",""))
   if isinstance(row["prompt_tokens"],int) and row["prompt_tokens"]+a.max_tokens>a.context:
    row["status"]="INVALID_CONTEXT";row["error"]="Chat-template prompt exceeded context budget"
  except Exception as exc:
   row["error"]=repr(exc)
   (out/f"error_{i:03d}.txt").write_text(row["error"],encoding="utf-8")
  row["elapsed_sec"]=round(time.monotonic()-start,3)
  rows.append(row)
  with (out/"trials.csv").open("w",newline="",encoding="utf-8-sig") as f:
   w=csv.DictWriter(f,fieldnames=list(row));w.writeheader();w.writerows(rows)
  print(f"[long-input {i}/{a.repeat}] status={row['status']} prompt={row['prompt_tokens']} elapsed={row['elapsed_sec']}s",flush=True)
  if row["status"]!="OK":break
 summary={"attempted":len(rows),"passed":sum(x["status"]=="OK" for x in rows),"failed":sum(x["status"]!="OK" for x in rows),
          "requested":a.repeat,"target_tokens":a.target_tokens,"actual_tokenize_tokens":exact,"input_mode":a.input_mode}
 (out/"summary.json").write_text(json.dumps(summary,indent=2),encoding="utf-8")
 if summary["passed"]!=a.repeat:sys.exit(2)
if __name__=="__main__": main()
