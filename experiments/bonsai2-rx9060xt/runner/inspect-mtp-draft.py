#!/usr/bin/env python3
"""Compare chronological MTP Draft raw-logit Top-2 and sampler choices.

Read-only analysis of already generated *.trace.log. Draft decisions might be
generated in different speculative attempts after a path divergence.
"""
import argparse
import json
import re
from pathlib import Path

TOP = re.compile(r"MTP_TRACE draft_top2: seq=(-?\d+) step=(\d+) row=(-?\d+) id1=(-?\d+) logit1=([^ ]+) id2=(-?\d+) logit2=([^ ]+) margin=([^ ]+)")
CHOICE = re.compile(r"MTP_TRACE draft_choice: seq=(-?\d+) step=(\d+) id=(-?\d+) candidate_p=([^ ]+)")

def parse(path):
    vals=[]
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        t=TOP.search(line)
        if t:
            vals.append({"seq":int(t[1]),"step":int(t[2]),"row":int(t[3]),
                         "id1":int(t[4]),"logit1":float(t[5]),"id2":int(t[6]),
                         "logit2":float(t[7]),"margin":float(t[8])})
        c=CHOICE.search(line)
        if c:
            if not vals:
                raise ValueError(f"Choice without top2: {path}")
            last=vals[-1]
            if last["seq"]!=int(c[1]) or last["step"]!=int(c[2]) or "chosen" in last:
                raise ValueError(f"Misaligned choice: {path}")
            last["chosen"]=int(c[3])
            last["candidate_p"]=float(c[4])
    if not vals:
        raise ValueError(f"No draft_top2 traces: {path}. Rebuild diagnostic llama-server first.")
    if any("chosen" not in x for x in vals):
        raise ValueError(f"Incomplete draft decision in {path}")
    return vals

def diff(a,b):
    for i,(x,y) in enumerate(zip(a,b)):
        if x!=y:
            return i
    return -1 if len(a)==len(b) else min(len(a),len(b))

def main():
    p=argparse.ArgumentParser()
    p.add_argument("run_dir",type=Path)
    p.add_argument("--a",default="32768_q8q4_on_r1")
    p.add_argument("--b",default="32768_q8q4_on_r2")
    p.add_argument("--window",type=int,default=2)
    args=p.parse_args()
    a=parse(args.run_dir/(args.a+".trace.log"))
    b=parse(args.run_dir/(args.b+".trace.log"))
    index=diff(a,b)
    out={"a":args.a,"b":args.b,"draft_steps_a":len(a),"draft_steps_b":len(b),
         "first_different_draft_step":index,"context":[]}
    if index>=0:
        for i in range(max(0,index-args.window),min(max(len(a),len(b)),index+args.window+1)):
            out["context"].append({"step_index":i,"a":a[i] if i<len(a) else None,
                                    "b":b[i] if i<len(b) else None})
    print(json.dumps(out,ensure_ascii=False,indent=2))
if __name__=="__main__":
    main()
