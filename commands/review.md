---
description: Run only the Hydraia double code-review + security gate on the current branch
argument-hint: [optional focus, e.g. "the payin module"]
---

Invoke the **hydraia** skill but run ONLY Phase 5 (double code review) and the Phase 6 security gate on the current branch. Skip planning and execution — the code already exists.

Run the review panel at Level 3 depth (the judge `hydraia-reviewer` and `security-reviewer` on Opus; the diff-scoped language reviewers and `silent-failure-hunter` on Sonnet), the mandatory security gate (security-scan + security-review, plus the stack-specific security skill), and the pre-close secrets/deps scan (repo-scan + production-audit, report-only except secrets / high vulnerable deps). Verify every finding at its cited line, grade it (high / medium / low / false / maybe-false), and report only the verified ones, ranked. Treat verified high-severity security findings as blockers.

Optional focus: $ARGUMENTS

Run the panel and both security gates to completion without stopping; this route reports, it does not start a fix loop unless asked. End with the Hydraia credits line.
