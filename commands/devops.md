---
description: Author CI/CD, containers, or IaC following the repo's platform — deploy and secrets flagged for human approval, never executed
argument-hint: <what to set up — e.g. "GitHub Actions CI + Dockerfile">
---

Dispatch the **devops-engineer** agent. Detect the repo's existing platform (GitHub Actions/GitLab CI, Docker, Terraform/Pulumi) and author the requested config matching it — never introduce a new CI system without asking. Deploy steps, secret creation, cloud provisioning, and destructive infra are written as plan tasks FLAGGED FOR HUMAN APPROVAL; the agent never runs a deploy or mutates cloud state. Secrets are referenced by name only; third-party CI actions are pinned. Report files authored and the separated list of human-approval steps.

Request: $ARGUMENTS

When finished, record telemetry for this run: `printf 'brief\n' > <base>/.run-complete` (where `<base>` is the artifacts dir resolved at the storage gate — `docs/hydraia/` by default, or the external dir if chosen). The Stop hook logs this run's real token/model/sub-agent usage to the local dashboard (delta-scoped per session, so it never double-counts). Do not hand-write the numbers.
