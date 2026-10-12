#!/usr/bin/env python3
"""Compare MTP proposal / verification server traces across independent cold runs.

Logs can contain unverifiable terminal tails. Fail closed if incomplete.
Verification IDs are sampler outputs at the verification boundary, not a promise
that all IDs are committed when checkpoint replay is active.
"""
import argparse
import csv
import json
import re
from pathlib import Path

PROPOSE = re.compile(r"MTP_TRACE proposal: n_past=(\d+) sampled_anchor=(-?\d+) proposed_ids=\[([^\]]*)\]")
VERIFY = re.compile(r"MTP_TRACE verification: proposed=(\d+) accepted_prefix=(\d+) confirmed_ids=\[([^\]]*)\]")

def ints(value):
    return [int(x) for x in value.split(",") if x.strip()]

def read_run(root, stem):
    events = []
    direct = root / (stem + ".trace.log")
    extensions = ("trace.log",) if direct.exists() else ("stderr.log", "stdout.log")
    for extension in extensions:
        log = root / (stem + "." + extension)
        if log.exists():
            for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
                m = PROPOSE.search(line)
                if m:
                    events.append(("p", (int(m[1]), int(m[2]), ints(m[3]))))
                m = VERIFY.search(line)
                if m:
                    events.append(("v", (int(m[1]), int(m[2]), ints(m[3]))))
    pairs = []
    pending = None
    errors = []
    for kind, data in events:
        if kind == "p":
            if pending is not None:
                errors.append("two proposals without verification")
            pending = data
        else:
            if pending is None:
                errors.append("verification without proposal")
                continue
            n_past, anchor, proposal = pending
            n, accepted, verified = data
            if n != len(proposal) or not 0 <= accepted <= n or len(verified) != accepted + 1:
                errors.append("inconsistent lengths / acceptance")
            elif verified[:accepted] != proposal[:accepted]:
                errors.append("accepted token IDs mismatch proposals")
            pairs.append({"n_past":n_past, "anchor":anchor, "proposal":proposal,
                          "accepted":accepted, "verified":verified})
            pending = None
    if pending is not None:
        errors.append("unpaired trailing proposal")
    return pairs, errors

def first_difference(a, b):
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return i
    return -1 if len(a) == len(b) else min(len(a), len(b))

def main():
    p = argparse.ArgumentParser()
    p.add_argument("run_dir", type=Path)
    args = p.parse_args()
    root = args.run_dir
    rows = list(csv.DictReader((root/"summary.csv").open(encoding="utf-8-sig", newline="")))
    samples = []
    for row in rows:
        stem = row["id"]
        events, errors = read_run(root, stem)
        expected_draft = int(row.get("draft_n") or 0)
        expected_accept = int(row.get("draft_accepted") or 0)
        got_draft = sum(len(x["proposal"]) for x in events)
        got_accept = sum(x["accepted"] for x in events)
        if expected_draft != got_draft or expected_accept != got_accept:
            errors.append(f"count mismatch API={expected_draft}/{expected_accept} trace={got_draft}/{got_accept}")
        if row.get("status") != "OK":
            errors.append(f"run status={row.get('status')}")
        samples.append({"id":stem, "events":events, "errors":errors,
                        "draft_n":got_draft, "draft_accepted":got_accept})
    pairs = []
    for i, a in enumerate(samples):
        for b in samples[i+1:]:
            idx = first_difference(a["events"], b["events"])
            # Compare boundaries directly; do not concatenate verifier arrays as
            # checkpoints and previous anchors can make that misleading.
            reason = "identical" if idx == -1 else ("different event" if idx < min(len(a["events"]),len(b["events"])) else "different length")
            pairs.append({"a":a["id"], "b":b["id"], "first_different_verification_round_zero_based":idx,
                          "a_rounds":len(a["events"]), "b_rounds":len(b["events"]),
                          "difference_type":reason, "a_trace_valid":not a["errors"], "b_trace_valid":not b["errors"]})
    with (root/"mtp-trace-comparison.csv").open("w",encoding="utf-8",newline="") as f:
        w = csv.DictWriter(f,fieldnames=list(pairs[0]) if pairs else ["a","b"])
        w.writeheader()
        w.writerows(pairs)
    summary = {"runs":[{k:v for k,v in x.items() if k != "events"}|{"rounds":len(x["events"])} for x in samples],
               "comparisons":pairs,
               "caveat":"Trace contains proposal and verifier IDs, not target logits or independently audited committed tokens. Checkpoint replays require additional instrumentation."}
    (root/"mtp-trace-comparison.json").write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding="utf-8")
    print(json.dumps(summary,indent=2,ensure_ascii=False))
    return int(any(x["errors"] for x in samples))

if __name__ == "__main__":
    raise SystemExit(main())
