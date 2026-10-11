# Deferred: KV precision pseudo-ensemble

Idea only; **not part of current MTP debugging**.

Use multiple inference runs of the same Bonsai 2 weights at different KV precision (Q4/Q4, Q8/Q4, optionally F16/F16 when memory safe) to probe decision-boundary sensitivity. Existing tests show changed reasoning lengths with largely unchanged conclusions; no ensemble accuracy gain has been established.

Potential future evaluation: compare single-run accuracy against (a) multiple sampling seeds, (b) KV-precision variants, (c) both; log answer disagreement and correlated wrong answers, not merely token trace diversity. Sequential runs are preferable before testing shared-memory multi-server residency on a 128 GB APU machine.

Do not modify llama.cpp for this experiment until the baseline runtime settings and MTP divergence investigation are complete.
