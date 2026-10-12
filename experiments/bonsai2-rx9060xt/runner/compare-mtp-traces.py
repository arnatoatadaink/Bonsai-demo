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
EMITTED = re.compile(r"MTP_TRACE emitted: id=(-?\\d+)")
VERIFY = re.compile(r"MTP_TRACE verification: proposed=(\d+) accepted_prefix=(\d+) confirmed_ids=\[([^\]]*)\]")

def ints(value):
    return [int(x) for x in value.split(",") if x.strip()]

def read_run(root, stem):
    events = []
    emitted = []
    direct = root / (stem + ".trace.log")
    extensions = ("trace.log",) if direct.exists() else ("stderr.log", "stdout.log")
    for extension in extensions:
        log = root / (stem + "." + extension)
        if log.exists():
            for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
                e = EMITTED.search(line)
                if e:
                    emitted.append(int(e[1]))
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
    return pairs, emitted, errors

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
        events, emitted, errors = read_run(root, stem)
        expected_draft = int(row.get("draft_n") or 0)
        expected_accept = int(row.get("draft_accepted") or 0)
        got_draft = sum(len(x["proposal"]) for x in events)
        got_accept = sum(x["accepted"] for x in events)
        if expected_draft != got_draft or expected_accept != got_accept:
            errors.append(f"count mismatch API={expected_draft}/{expected_accept} trace={got_draft}/{got_accept}")
        if row.get("status") != "OK":
            errors.append(f"run status={row.get('status')}")
        if emitted and len(emitted) != int(row.get("predicted_n") or 0):
            errors.append(f"emitted count differs: trace={len(emitted)} API={row.get(\'predicted_n\')}")
        samples.append({"id":stem, "events":events, "emitted":emitted, "errors":errors,
                        "draft_n":got_draft, "draft_accepted":got_accept})
    pairs = []
    for i, a in enumerate(samples):
        for b in samples[i+1:]:
            idx = first_difference(a["events"], b["events"])
            # Compare boundaries directly; do not concatenate verifier arrays as
            # checkpoints and previous anchors can make that misleading.
            reason = "identical" if idx == -1 else ("different event" if idx < min(len(a["events"]),len(b["events"])) else "different length")
            tok_diff = first_difference(a["emitted"], b["emitted"]) if a["emitted"] and b["emitted"] else None
            pairs.append({"a":a["id"], "b":b["id"], "first_different_emitted_token_zero_based":tok_diff,
                          "a_emitted_tokens":len(a["emitted"]), "b_emitted_tokens":len(b["emitted"]),
                          "first_different_verification_round_zero_based":idx,
                          "a_rounds":len(a["events"]), "b_rounds":len(b["events"]),
                          "difference_type":reason, "a_trace_valid":not a["errors"], "b_trace_valid":not b["errors"]})
    with (root/"mtp-trace-comparison.csv").open("w",encoding="utf-8",newline="") as f:
        w = csv.DictWriter(f,fieldnames=list(pairs[0]) if pairs else ["a","b"])
        w.writeheader()
        w.writerows(pairs)
    summary = {"runs":[{k:v for k,v in x.items() if k not in ("events", "emitted")}|{"rounds":len(x["events"]), "emitted_tokens":len(x["emitted"])} for x in samples],
               "comparisons":pairs,
               "caveat":"Trace includes emitted token IDs from the speculative output path, not target logits. Compare API predicted_n count and verify no truncation."}
    (root/"mtp-trace-comparison.json").write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding="utf-8")
    print(json.dumps(summary,indent=2,ensure_ascii=False))
    return int(any(x["errors"] for x in samples))

if __name__ == "__main__":
    raise SystemExit(main())
