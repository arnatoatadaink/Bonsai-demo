# BNS-LCTX-02: multi-hop evidence comparison (40 cases)

Reproducible follow-up to BNS-LCTX-01. The original ZIP is preserved outside Git; the equivalent generator and runner are maintained here.

| Group | Questions | Depth | Distance | Revision |
| --- | ---: | --- | --- | --- |
| G1 | 8 | L1 | 4 near, 4 far | R0 |
| G2 | 8 | L2/L3 | far | R0 |
| G3 | 8 | L4/L6 | far | R0 |
| G4 | 8 | L2/L3 | far | R2 |
| G5 | 8 | L4/L6 | far | R2 |

Each hop follows a KEY -> VALUE mapping. Older VERSION records have lower precedence irrespective of where they occur in the document. Answers and ordered supporting record IDs are graded independently. The entire generated archive is supplied to both models for each of five groups, with eight questions per request.

## Prepare

Run `prepare.bat` once, or `py -3 generate.py --output dataset --target-chars 80000`. The output is deterministic; generated files are ignored by Git. Requires only Python 3 standard library.

## Run (existing servers only)

- `run-bonsai.bat`: localhost:8078
- `run-gemma.bat`: localhost:8081

No server is started, stopped or reconfigured. Both request Think OFF. Each group writes request/response and answer files plus cumulative fact_checks.csv and metrics.json. A run uses five separate long input requests; each may take time. The generated input is character-bounded, NOT token-bounded, so 64k context fit must be checked against the actual server/tokenizer separately. The server must have sufficient capacity.

## Scoring

Review answer_exact and evidence_exact by group, depth, distance and revision. Exact string equality screens output formatting as well as factual correctness; non-exact rows need manual review. The suite tests multi-hop evidence tracking, not natural prose summary quality. Do not infer model hardware efficiency from cross-GPU measurements.

No Windows/GPU model execution has been performed for this commit.
