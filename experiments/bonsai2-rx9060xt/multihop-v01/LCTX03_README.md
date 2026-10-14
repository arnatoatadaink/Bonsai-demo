# BNS-LCTX-03: Placement and order sensitivity replication

This extension keeps the **same 40 answer values, root keys, and evidence identifiers** as BNS-LCTX-02. It changes evidence position and question order using three deterministic seeds (11, 29, 47), then compares the two existing servers.

Run `prepare-variants.bat` first (Python 3 required). Generated data are in `variants/seed_11`, `seed_29`, `seed_47` with SHA-256 hashes in variants/manifest.json.

Once ready, launch one comparison at a time with:

```bat
run-variant.bat bonsai 11
run-variant.bat gemma 11
run-variant.bat bonsai 29
run-variant.bat gemma 29
run-variant.bat bonsai 47
run-variant.bat gemma 47
```

Existing ports 8078 and 8081 are reused. No servers are created, stopped or reconfigured. Each run sends five grouped requests containing the same corpus and produces per-question final-answer and evidence-ID exact match columns. Questions are shuffled deterministically per group. Keep the same dataset seed and question seed for both models.

**Crucial caveats:** Evidence placements are randomized, but the previously labeled near/far factor is **not** strictly preserved across seed variants. Do not treat v01 labels as controlled distance strata in this follow-up. Distinguish model differences from content length, output truncation, order, and template differences. This only supports answer-mapping fidelity under randomized evidence positions, not general natural-document summarization.

The original `prepare.bat` and `run-bonsai.bat` / `run-gemma.bat` remain available for baseline replication. Windows GPU completion has not been verified for this extension.
