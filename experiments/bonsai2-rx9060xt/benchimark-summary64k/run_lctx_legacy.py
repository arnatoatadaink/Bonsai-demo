#!/usr/bin/env python3
"""Faithful reuse of existing LCTX-01 and LCTX-02 data and strict scoring.
Requires original branch fetched as origin/bench/bonsai2-think-compare-v01.
Do not modify generators or prompts. Python standard library only.
"""
import argparse,csv,hashlib,json,re,subprocess,sys,time,urllib.request
from pathlib import Path
BASE="experiments/bonsai2-rx9060xt/"
REF="origin/bench/bonsai2-think-compare-v01"
def original(path):
    return subprocess.run(["git","show",f"{REF}:{BASE}{path}"],check=True,capture_output=True).stdout
def prepare(name,out):
    out.mkdir(parents=True,exist_ok=True)
    if name=="lctx01": src="distributed-summary-v01/generate.py"; goal=65000
    else: src="multihop-v01/generate.py"; goal=80000
    generator=out/("original_"+name+"_generate.py")
    generator.write_bytes(original(src))
    subprocess.run([sys.executable,str(generator),"--output",str(out/"dataset"),"--target-chars",str(goal)],check=True)
    return out/"dataset"
def request(url,body,timeout):
    req=urllib.request.Request(url+"/v1/chat/completions",data=json.dumps(body,ensure_ascii=False).encode(),headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req,timeout=timeout) as f:return json.load(f)
def send(url,prompt,out,prefix,timeout):
    body={"messages":[{"role":"user","content":prompt}],"max_tokens":2048,"temperature":0,"top_k":1,"seed":42,"reasoning_effort":"none","chat_template_kwargs":{"enable_thinking":False}}
    (out/(prefix+".request.json")).write_text(json.dumps(body,ensure_ascii=False,indent=2),encoding="utf-8")
    start=time.perf_counter()
    r=request(url,body,timeout)
    elapsed=time.perf_counter()-start
    (out/(prefix+".response.json")).write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding="utf-8")
    txt=r["choices"][0]["message"].get("content") or ""
    (out/(prefix+".answer.txt")).write_text(txt,encoding="utf-8")
    return txt,{"elapsed_sec":round(elapsed,3),"prompt_tokens":r.get("usage",{}).get("prompt_tokens"),"completion_tokens":r.get("usage",{}).get("completion_tokens"),"pp_tok_s":(r.get("timings") or {}).get("prompt_per_second"),"tg_tok_s":(r.get("timings") or {}).get("predicted_per_second"),"finish_reason":r["choices"][0].get("finish_reason")}
def savecsv(path,rows):
    with path.open("w",encoding="utf-8-sig",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
def lctx01(url,data,out,timeout):
    gold=json.loads((data/"gold.json").read_text(encoding="utf-8"))
    prompt=(data/"prompt.txt").read_text(encoding="utf-8")
    answer,metrics=send(url,prompt,out,"LCTX01",timeout)
    found={}
    for line in answer.splitlines():
        m=re.match(r"^\s*\*{0,2}(F\d\d)\*{0,2}\s*[:：]\s*(.+?)\s*$",line)
        if m:found[m[1]]=m[2].strip().rstrip(".* ")
    rows=[]
    for item in gold:
        actual=found.get(item["id"],"");exp=str(item["expected"])
        rows.append({"id":item["id"],"expected":exp,"observed":actual,"exact_match":actual==exp,"status":"MISSING" if not actual else ("EXACT" if actual==exp else "REVIEW")})
    savecsv(out/"fact_checks.csv",rows)
    metrics.update(exact=sum(z["exact_match"] for z in rows),questions=len(rows),prompt_sha256=hashlib.sha256(prompt.encode()).hexdigest())
    (out/"metrics.json").write_text(json.dumps(metrics,indent=2),encoding="utf-8")
    return metrics
def lctx02(url,data,out,timeout):
    doc=(data/"source.txt").read_text(encoding="utf-8")
    gold=json.loads((data/"gold.json").read_text(encoding="utf-8"))
    rows=[];metrics=[]
    for group in ["G1","G2","G3","G4","G5"]:
        subset=[x for x in gold if x["group"]==group]
        qs="\n".join(x["id"]+": ROOT="+x["root"] for x in subset)
        prompt="Use the mapping archive below. For each requested root, repeatedly follow the latest VERSION for each KEY until a terminal VALUE-XXXXXXXXXXXX is reached. Report each final value plus all supporting active record IDs in order. Avoid stale versions. Output one line each: G1_01: VALUE-XXXXXXXXXXXX | G1_01_H1,G1_01_H2. No extra prose.\nARCHIVE:\n"+doc+"\nQUESTIONS:\n"+qs
        answer,timing=send(url,prompt,out,group,timeout)
        found={}
        for line in answer.splitlines():
            m=re.match(r"^\s*\*{0,2}(G[1-5]_\d\d)\*{0,2}\s*[:：]\s*([^|\n]+)(?:\|\s*(.*))?",line)
            if m:found[m[1]]=(m[2].strip(" *。."),[x.strip(" *。.") for x in (m[3] or "").split(",") if x.strip()])
        for item in subset:
            val,ev=found.get(item["id"],("",[]))
            required=item["evidence_ids"]
            rows.append({"id":item["id"],"group":group,"depth":item["depth"],"distance":item["distance"],"revision":item["revision"],"expected":item["answer"],"observed":val,"answer_exact":val==item["answer"],"evidence_exact":ev==required,"expected_evidence":",".join(required),"observed_evidence":",".join(ev),"status":"MISSING" if not val else ("EXACT" if val==item["answer"] and ev==required else "REVIEW")})
        timing["group"]=group;metrics.append(timing)
        savecsv(out/"fact_checks.csv",rows)
        (out/"metrics.json").write_text(json.dumps(metrics,indent=2),encoding="utf-8")
    return {"questions":len(rows),"answer_exact":sum(x["answer_exact"] for x in rows),"evidence_exact":sum(x["evidence_exact"] for x in rows),"source_sha256":hashlib.sha256(doc.encode()).hexdigest()}
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--suite",required=True,choices=["lctx01","lctx02"])
    p.add_argument("--base-url",default="http://127.0.0.1:18080")
    p.add_argument("--output",required=True)
    p.add_argument("--timeout",type=int,default=1800)
    a=p.parse_args()
    out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
    data=prepare(a.suite,out)
    result=lctx01(a.base_url,data,out,a.timeout) if a.suite=="lctx01" else lctx02(a.base_url,data,out,a.timeout)
    (out/"summary.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    print(json.dumps(result,ensure_ascii=False))
if __name__=="__main__":main()
