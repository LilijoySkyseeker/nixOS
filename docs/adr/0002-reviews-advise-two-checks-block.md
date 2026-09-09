---
status: accepted
date: 2026-09-09
---

# Reviews advise; two checks block

Review agents, lint scripts and completion stamps are advisory. Exactly
two mechanical rules block work from landing:

1. **No merge while a cited plan carries an unresolved CRITICAL- or
   HIGH-severity security finding.** Enforced by `plan-gate` (locally and
   as the one required CI check).
2. **Nothing under `docs/plans/done/` or `docs/plans/rejected/` is ever
   modified or deleted.** Frozen means *residence in those folders*;
   enforced by `.githooks/pre-commit`, `verify-ladder`, and `plan-gate`'s
   range check, with git history as the integrity record.

Everything else the tooling says — an unresolved MEDIUM finding, a stale
or missing review stamp, a lint report, a dangling citation — is
information for a human who merges when satisfied. A finding below the
blocking bar may be parked indefinitely with a note.

Decided in
`2026-09-09-dismantle-the-blocking-gate-tier-and-keep-the-plan-corpus.md`,
after a commissioned first-principles assessment of the previous
gate system.

## The problem this solves

The previous design blocked merges on unresolved findings *and* on review
stamps whose code fingerprint had to match the current tree. Findings
could not be parked, so every finding forced a fix; every fix moved the
fingerprint; a moved fingerprint staled both stamps and forced another
review round. With LLM reviewers — which have a positive floor rate of
findings on any nontrivial surface — this loop is structural, and it was
observed live: three rounds (11, then 10, then 3 findings), stopped only
by hand, over a PR nobody was blocked on.

Making the gates blocking also forced them to be highly reliable, which
grew a tower under them: a 1,432-line test suite for the gates, a
60-entry mutation catalogue testing the test suite, and a checksum
manifest guarding frozen files — a subsystem that produced the largest
defect cluster in the repo's own finding log while duplicating integrity
git already provides. On the branch that finished that work, all 81
recorded findings concerned the apparatus itself and none concerned the
fleet.

The outside evidence points the same way: DORA's research finds formal
change-approval gates buy no stability for real throughput cost, and the
code-review literature (Bacchelli & Bird 2013; Sadowski et al. 2018)
finds review's value is mostly knowledge transfer — which in this repo is
the plan corpus itself, not the blocking.

## What stays, and why

- **The plan corpus and its D/G/F notation.** Anchors stay citeable,
  `**ANSWERED**` keeps meaning "the user confirmed this", and security
  findings keep their `### F<N>` + `**Severity:**` shape — rule 1 parses
  exactly that. The notation is the house convention; only the mandatory
  drainage is gone.
- **`plan-move … done` still refuses** without an honest `## State`, a
  `Verified to rung N` declaration, or with an unresolved CRITICAL/HIGH
  finding. Closing a plan is a claim about reality; those three are the
  claim's substance. Everything else warns.
- **The review agents themselves.** `security` and `docs-updater` are
  invoked because they find things (the first `security` run found real
  fleet exposure), not because a stamp is owed.
- **Host builds, flake checks, diff-scoped lints, VM testing** — the
  automation that guards the actual fleet, untouched.

## Considered alternatives

- **Keep blocking, fix the livelock locally** (e.g. exempt comment-only
  fixes from the fingerprint). Rejected: treats the symptom; the floor
  rate of reviewer findings makes non-termination the expected case, and
  the reliability tower stays load-bearing.
- **Delete everything including the corpus.** Rejected: the corpus is
  real operational memory and the one part of the apparatus with outside
  evidence in its favor (agent-context files measurably help; no
  comparable repo has anything like it).
- **No blocking rules at all.** Rejected: the two rules kept are cheap,
  mechanical, and guard against silent regret (an exposed fleet, a
  quietly rewritten record) rather than against imperfection.

## Consequences

- A PR can merge with open findings on record. That is deliberate; the
  parked list prints in plan-gate's output so it is seen, not lost.
- Stamps still get written by `subagent-stamp` but nothing reads them as
  locks; they are provenance, and may be removed entirely later.
- The pre-2026-09-09 checksum manifest, `plan-repair`, the mutation
  catalogue and the stamp-staleness machinery are deleted, not archived;
  their history is in git and their post-mortem lives in the dismantle
  plan.
- If reviews stop being run at all without the forcing function, the
  correct response is a warn-only nag, not a restored block — re-litigate
  against the dismantle plan's G4 baseline before rebuilding anything.
