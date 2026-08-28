---
slug: design-a-provenance-system-for-d-f-resolution-markers
created: 2026-08-28
status: todo
frozen: false
---

# Design a provenance system for D/F resolution markers

## Original plan

From `2026-08-28-plan-file-rework-mutable-state-section-f-item-resolution-gating-and-a.md`'s
security review (F3): `**ANSWERED**`/`**FIXED**`/`**ACCEPTED**`/`**MOOT**`
markers are freeform text an agent can hand-write directly into a plan
file with a normal `Edit`/`Write` call -- `docs/skills/plan/SKILL.md`'s
"never hand-edit these mechanics" is a documentation convention only,
with no tool-level or hook-level enforcement (`.claude/settings.json` has
no `PreToolUse` matcher on file-editing tools for this). This was already
a known, accepted gap for `D`'s `ANSWERED` (identical shape, and `G22` in
`2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md` already
names the general class: a subagent's "read-only" intent similarly rests
on prompt-level trust, not tool-level enforcement). The stakes changed
with `F`-gating landing in the plan-file-rework plan above: the identical
unauthenticated-marker mechanism now also gates `plan-gate`, a required
GitHub status check on `master` -- a hand-typed `ACCEPTED` with no real
user sign-off is mechanically sufficient to let a PR merge over an
unresolved security Finding.

**User's decision on F3 (2026-08-28):** accept the gap as-is for now
(matches `D`'s existing, already-accepted precedent) and track building a
real provenance mechanism separately here, rather than block the
plan-file-rework plan on solving it inline.

## State

**2026-08-28, not started.** Just opened; no design work done yet.

## Progress

- [ ] survey what "non-forgeable evidence of user origin" could actually
      mean here -- session-bound tokens, a required human-in-the-loop
      confirmation step the harness itself enforces, git-commit-signing-
      style attestation, or something else entirely; this repo has no
      precedent for any of them today
- [ ] decide whether this generalizes to `D`'s `ANSWERED` too (same gap,
      arguably higher current stakes since more decisions gate more
      things) or stays scoped to `F` alone
- [ ] decide whether `plan-lint`/`plan-gate` should also anchor the
      marker match to line-start (closes the cheap "prose happens to
      contain the bold word" false-positive case) as a partial interim
      step, independent of solving real provenance


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
