---
slug: fix-plan-gate-ci-bootstrap-failure-on-its-own-introducing-pr
created: 2026-08-28
status: done
frozen: true
---

# Fix plan-gate CI bootstrap failure on its own introducing PR

## Original plan

Discovered immediately after opening PR #30 (which landed
`2026-08-28-plan-file-rework-mutable-state-section-f-item-resolution-gating-and-a.md`,
now frozen -- this is a new plan rather than an edit to that one for
exactly that reason). The `plan-gate` CI check's F1 fix (pin the gate
script to the base branch, so a PR can't neuter its own gate) has a
bootstrap gap: the PR that *introduces* `plan-gate` for the first time has
no base-branch copy to pin to, since `origin/master` doesn't have the
script yet. `git show origin/$BASE_REF:docs/skills/workflow/scripts/plan-gate`
hard-fails with "path ... exists on disk, but not in 'origin/master'",
and the check reports a hard failure -- confirmed live on PR #30's own
first CI run (run 33219879312).

## State

**2026-08-28, done.** Fixed in the same PR (#30) this bug was found on:
the "pin the gate script" step now checks existence first
(`git cat-file -e`) and degrades to "nothing to gate" (exit 0, skip the
actual check step) if the base branch doesn't have `plan-gate` yet --
true only for this one bootstrapping PR. Every PR after this one merges
will have a real base-branch copy to pin against, so the gap is
self-limiting and doesn't recur. Re-pushed to PR #30; re-verifying the
check now reports green rather than crashing.

## Progress

- [x] fix the bootstrap crash in `.github/workflows/plan-gate.yml`
- [x] verify the fix live on PR #30

## Decisions (D)


## Gotchas (G)

### G1 -- pinning a CI enforcement script to the base branch has an inherent bootstrap gap on the PR that introduces it
Any "pin to base branch, don't trust the PR's own copy" mitigation (like
this rework's F1 fix) has this same one-time gap whenever the pinned
thing doesn't exist on the base yet -- there's no way around a chicken-
before-the-egg case for a genuinely first introduction. Worth remembering
if this pattern gets reused elsewhere (e.g. if a future gate script is
similarly pinned): design the failure mode as "degrade to skip" from the
start, not as an afterthought once the bootstrap PR's CI run fails.

## Findings (F)
*(populated by security/docs-updater when invoked)*
