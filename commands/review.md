---
description: Run only the Hydraia double code-review + security gate on the current branch
argument-hint: [optional focus, e.g. "the payin module"]
---

Invoke the **hydraia** skill but run ONLY Phase 5 (double code review) and the Phase 6 security gate on the current branch. Skip planning and execution — the code already exists.

Run both review passes (Superpowers reviewer + ECC reviewers, all on Opus 4.8), the mandatory security gate (security-scan + security-review, plus the stack-specific security skill), and the pre-close secrets/deps scan (repo-scan + production-audit). Triage and report findings ranked by severity. Treat high-severity security findings as blockers.

Optional focus: $ARGUMENTS

Run both review passes and both security gates to completion without stopping. End with the Hydraia credits line.
