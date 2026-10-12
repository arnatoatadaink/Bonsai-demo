#!/usr/bin/env python3
"""MTP-01: compare cold repetitions using saved local raw responses and token files."""
import argparse
import csv
import hashlib
import json
from pathlib import Path

def sha(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()

def diff(a, b):
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return i
    return -1 if len(a) == len(b) else min(len(a), len(b))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir", type=Path)
    args = ap.parse_args()
    root = args.run_dir
    rows = list(csv.DictReader((root / "summary.csv").open(encoding="utf-8-sig", newline="")))
    comparisons = []
    missing = []
    group = {}
    for row in rows:
        if row.get("status") != "OK":
            missing.append({"id": row["id"], "reason": "status not OK"})
            continue
        stem = row["id"]
        jp = root / (stem + ".json")
        tp = root / (stem + ".tokens.json")
        if not jp.exists() or not tp.exists():
            missing.append({"id": stem, "reason": "raw response/token capture missing"})
            continue
        response = json.loads(jp.read_text(encoding="utf-8-sig"))
        tokens = json.loads(tp.read_text(encoding="utf-8-sig"))
        msg = response["choices"][0]["message"]
        reason = msg.get("reasoning_content") or ""
        content = msg.get("content") or ""
        group.setdefault((row["context"], row["kv"]), []).append({
            "id": stem,
            "rep": int(row["rep"]),
            "reason": reason,
            "content": content,
            "tokens": tokens,
            "reason_sha256": sha(reason),
            "content_sha256": sha(content),
            "rendered_sha256": sha(reason + content),
            "draft_n": row.get("draft_n", ""),
            "draft_accepted": row.get("draft_accepted", ""),
            "predicted_tps": row.get("predicted_tps", ""),
        })
    for (ctx, kv), items in sorted(group.items()):
        items.sort(key=lambda v: v["rep"])
        for i, a in enumerate(items):
            for b in items[i + 1:]:
                first_reason = diff(a["tokens"]["reason"], b["tokens"]["reason"])
                first_content = diff(a["tokens"]["content"], b["tokens"]["content"])
                first_combined = diff(a["tokens"]["combined"], b["tokens"]["combined"])
                comparisons.append({
                    "context": ctx, "configuration": kv,
                    "a": a["id"], "b": b["id"],
                    "reason_exact": a["reason"] == b["reason"],
                    "content_exact": a["content"] == b["content"],
                    "first_reason_retoked": first_reason,
                    "first_content_retoked": first_content,
                    "first_combined_retoked": first_combined,
                    "a_rendered_sha256": a["rendered_sha256"],
                    "b_rendered_sha256": b["rendered_sha256"],
                    "a_draft_n": a["draft_n"], "b_draft_n": b["draft_n"],
                    "a_draft_accepted": a["draft_accepted"], "b_draft_accepted": b["draft_accepted"],
                    "a_tps": a["predicted_tps"], "b_tps": b["predicted_tps"],
                })
    fields = ["context", "configuration", "a", "b", "reason_exact", "content_exact",
              "first_reason_retoked", "first_content_retoked", "first_combined_retoked",
              "a_rendered_sha256", "b_rendered_sha256", "a_draft_n", "b_draft_n",
              "a_draft_accepted", "b_draft_accepted", "a_tps", "b_tps"]
    with (root / "within-condition-divergence.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(comparisons)
    report = {
        "source": str(root),
        "input_rows": len(rows),
        "compared_pairs": len(comparisons),
        "all_same_condition_outputs_identical": (all(x["reason_exact"] and x["content_exact"] for x in comparisons) if comparisons else None),
        "missing": missing,
        "unequal_pairs": [x for x in comparisons if not (x["reason_exact"] and x["content_exact"])],
        "note": "POST-HOC tokenization of visible response fields; not internal token IDs. No inference about target/draft logits or bug causality.",
    }
    (root / "within-condition-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if missing:
        return 2
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
