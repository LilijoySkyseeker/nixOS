---
slug: make-plan-gate-survive-a-pr-that-changes-the-fingerprint-algorithm-or
created: 2026-09-06
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# make plan-gate survive a PR that changes the fingerprint algorithm or its inputs

## State

Not started. Filed 2026-09-06 as the follow-up to
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F14`,
which the user accepted rather than fixed. Takeable once that branch has
merged, since reproducing the failure needs a base branch that already
runs the stamp check.

## Original plan

CI computes the current code fingerprint with the **pinned base-branch**
`lib.sh`, while the stamp being checked was written locally by the
**PR's own** `lib.sh`. When a PR edits `PLAN_CODE_GLOBS` or the
`plan_code_fingerprint` pipeline, those two disagree about the value for
one identical tree. The stamp then reads stale, re-running the agent
re-stamps with the PR's algorithm, and the block is unfixable in-system
on a non-frozen plan -- the cheapest escape being the `Plan:` trailer
drop recorded as
`2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md#F36`,
which disables the whole gate.

Raised as
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F14`
and **accepted there by the user on 2026-09-06**; this plan is the
follow-up that record points at.

### Why this is not the same as F1

`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F1`
named this instance explicitly, but its FIXED resolution only addressed
the *freeze* boundary: a stale stamp on a frozen plan degrades to a NOTE.
The base-vs-head algorithm disagreement is a different boundary and is
still fully open on non-frozen plans.

### Why it will fire

Not hypothetical. The branch that introduced the fingerprint changed the
algorithm again in its own working tree (dropping a post-hash `sort`
alters the emitted value for an identical tree), and the D7 restart-rule
note -- "agent definitions included, `.md` or not" -- is a standing
invitation to widen `PLAN_CODE_GLOBS`. Both were masked on that PR only
because the base branch had no stamp check yet and every stamp on it was
legacy per
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F12`.
The next such PR hits it for real. Note also that any PR touching
`lib.sh` necessarily obliges `security` and `docs-updater`, since
`lib.sh` is itself inside the code globs -- so the exposed set is exactly
the set that must be stamped.

### Candidate approaches

Not decided; this needs a D entry once worked.

1. **Version the fingerprint.** The stamp records an algorithm id
   alongside the hash; `plan-gate` compares only within a version and
   emits a named NOTE across versions. Explicit, and it keeps the
   staleness check live for every PR that does not touch the algorithm.
2. **Detect base/head disagreement.** `plan-gate` checks whether base and
   head differ on `lib.sh` (or on the glob array) and degrades staleness
   to a named NOTE for that range. Simpler, but it hands *any* PR
   touching `lib.sh` a staleness pass, so the missing-stamp arm must stay
   blocking.
3. **Compute both sides with the same `lib.sh`.** Closest to correct in
   principle, and it fights the pinning that exists so a PR cannot neuter
   its own gate -- so it probably cannot be adopted as stated.

### Verification

F14 is explicit that this must be tested with an **actual stacked PR**
against a base that carries the stamp check, not by reasoning about the
scripts. Reproduce the block first, then confirm the chosen fix clears it
while a genuinely stale stamp still blocks.

## Progress

- [ ] reproduce with a stacked PR that edits `PLAN_CODE_GLOBS` or the
      fingerprint pipeline
- [ ] decide between the candidate approaches, as a `### D1`
- [ ] implement, keeping the missing-stamp arm blocking
- [ ] verify a genuinely stale stamp still blocks after the fix

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
