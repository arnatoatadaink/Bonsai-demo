#!/usr/bin/env python3
"""Inspect the earliest MTP verification-path divergence with grouped target top2.

Reads existing MTP_TRACE_FILE logs. No server run is necessary.
Rows in one group belong to one speculative verification attempt; these are
raw pre-sampling logits, not probabilities. Compare only matched positions.
"""
import argparse
import json
import re
from pathlib import Path

PROPOSAL = re.compile(r"MTP_TRACE proposal: n_past=(\d+) sampled_anchor=(-?\d+) proposed_ids=\[([^\]]*)\]")
VERIFY = re.compile(r"MTP_TRACE verification: proposed=(\d+) accepted_prefix=(\d+) confirmed_ids=\[([^\]]*)\]")
TOP2 = re.compile(r"MTP_TRACE target_top2: phase=(\w+) ordinal=(\d+) batch_idx=(-?\d+) id1=(-?\d+) logit1=([^ ]+) id2=(-?\d+) logit2=([^ ]+) margin=([^ ]+)")
EMIT = re.compile(r"MTP_TRACE emitted: id=(-?\d+)")

def ints(s):
    return [int(x) for x in s.split(",") if x.strip()]

def parse(path):
    rounds, emitted = [], []
    current = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = PROPOSAL.search(line)
        if m:
            if current is not None:
                raise ValueError(f"Unpaired proposal in {path}")
            current = {"n_past":int(m[1]), "anchor":int(m[2]), "proposed":ints(m[3]), "top2":[]}
            continue
        m = TOP2.search(line)
        if m:
            data = {"phase":m[1], "ordinal":int(m[2]), "batch_idx":int(m[3]), "id1":int(m[4]),
                    "logit1":float(m[5]), "id2":int(m[6]), "logit2":float(m[7]), "margin":float(m[8])}
            if current is not None:
                current["top2"].append(data)
            continue
        m = VERIFY.search(line)
        if m:
            if current is None:
                raise ValueError(f"Unpaired verification in {path}")
            current["accepted_prefix"] = int(m[2])
            current["confirmed"] = ints(m[3])
            current["emitted_count_before_next_round"] = None
            rounds.append(current)
            current = None
            continue
        m = EMIT.search(line)
        if m:
            emitted.append(int(m[1]))
    if current is not None:
        raise ValueError(f"Trailing proposal in {path}")
    return rounds, emitted

def first_diff(a,b):
    for i,(x,y) in enumerate(zip(a,b)):
        if x != y: return i
    return -1 if len(a)==len(b) else min(len(a),len(b))

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("run_dir",type=Path)
    ap.add_argument("--a", default="32768_q8q4_on_r1")
    ap.add_argument("--b", default="32768_q8q4_on_r2")
    ap.add_argument("--window", type=int, default=2)
    args=ap.parse_args()
    a, ea=parse(args.run_dir/(args.a+".trace.log"))
    b, eb=parse(args.run_dir/(args.b+".trace.log"))
    first=first_diff([{k:v for k,v in x.items() if k!="emitted_count_before_next_round"} for x in a],
                     [{k:v for k,v in x.items() if k!="emitted_count_before_next_round"} for x in b])
    output={"a":args.a,"b":args.b,"rounds_a":len(a),"rounds_b":len(b),
            "emitted_a":len(ea),"emitted_b":len(eb),"first_emitted_diff":first_diff(ea,eb),
            "first_verification_round_diff":first,"context":[]}
    if first >= 0:
        for i in range(max(0, first-args.window), min(max(len(a),len(b)),first+args.window+1)):
            output["context"].append({"round":i,"a":a[i] if i<len(a) else None,"b":b[i] if i<len(b) else None})
    print(json.dumps(output,indent=2,ensure_ascii=False))
    return 0

if __name__=="__main__":
    raise SystemExit(main())
