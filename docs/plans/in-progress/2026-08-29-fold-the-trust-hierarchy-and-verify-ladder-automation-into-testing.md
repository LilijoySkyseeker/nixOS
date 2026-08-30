---
slug: fold-the-trust-hierarchy-and-verify-ladder-automation-into-testing
created: 2026-08-29
status: in-progress
frozen: false
---

# Fold the trust hierarchy and verify-ladder automation into testing-changes.md

## Original plan

The user asked to fold the "trust hierarchy" (documentation → source →
local build → VM test → real switch) and the standing principle "a fix
that isn't declarative and reproducible is no fix at all" -- both named
when the user originally specified them while establishing the
workflow/plan system
(`establish-the-workflow-and-plan-file-system-2026-08-27.md`) -- into
`docs/procedures/testing-changes.md`, and to fix that doc's now-stale
"What's automated vs. what isn't" section: it currently claims `nix flake
check`, `statix`, and `deadnix` are "not automated at all," but
`docs/skills/workflow/scripts/verify-ladder` (built in that same plan) has
automated a diff-scoped version of all three as a hard gate since. Done
via the `workflow` skill per explicit request.

## State


## Progress

- [x] Added an intro paragraph to `testing-changes.md` cross-referencing
      `workflow.md`'s trust hierarchy, mapping layers 1-3/4/5-6 to the
      local-build/VM-test/real-switch rungs, and stating the
      declarative-and-reproducible corollary.
- [x] Replaced the stale "not automated at all" bullet with an accurate
      `verify-ladder` entry describing its diff-scoped automation of
      layers 1-3, distinct from `pre-push`.
- [x] Ran `verify-ladder` (G1: pre-existing failure, unrelated).
- [x] Applied docs-updater's F1 fixes (ambiguous phrasing in
      `testing-changes.md`, stale `AGENTS.md` docs-table row).
- [x] Fixed `docs/skills/workflow/SKILL.md` step 4's `nix flake check`
      mention to say `--no-build`, matching the actual script and the
      now-corrected `testing-changes.md` (surfaced by docs-updater as
      out-of-scope-for-its-diff but worth a follow-up fix; folded in here
      rather than opened as a separate plan since it's a one-line factual
      correction with no reasoning behind it to preserve).
- [x] Per explicit user direction, skipped `/simplify` for this docs-only
      change and recorded why in G41 of
      `known-weak-points-in-the-plan-file-and-workflow-sy-2026-08-27.md`
      instead: step 6 currently mandates `/simplify` unconditionally,
      with no content-type gate the way `docs-updater`/`security` have.

## Decisions (D)


## Gotchas (G)

### G1 — `nix flake check` already fails on master, unrelated to this change
`verify-ladder` blocks on `nix flake check --no-build` failing on
`checks.x86_64-linux.zrepl-replication` (a stale/invalid store path in
its `runNixOSTest` driver config). Confirmed identical on the unmodified
shared checkout, so pre-existing debt, not something this doc-only change
introduced. Already tracked in
`nix-flake-check-fails-on-zrepl-replication-test-pk-2026-08-28.md`; not
re-litigated here since no `.nix` file was touched by this plan.

## Findings (F)

### F1 — docs-verify pass: two stale/ambiguous spots fixed
Independent docs-accuracy check of this plan's diff found:

- `docs/procedures/testing-changes.md`'s new "Not automated at all" closer
  said "...neither a push nor **a pre-commit gate** is the right place to
  discover that." That phrase (lowercase, no backticks) sits right after
  the doc explicitly states `verify-ladder` is *not* a git hook, but the
  same section's earlier bullet uses "`pre-commit` hook" to name the
  actual git hook that blocks plaintext secrets — a reader could misread
  "a pre-commit gate" as that literal hook, undoing the accurate
  not-a-git-hook statement two sentences earlier. Fixed by dropping the
  ambiguous noun phrase: "...and neither is the right place to discover
  that."
- `AGENTS.md`'s docs table row for `docs/procedures/testing-changes.md`
  still described that doc as covering "what the git hooks already
  automate," which became incomplete once this plan's diff added the
  `verify-ladder` bullet (a skill-invoked script, explicitly not a git
  hook) and the trust-hierarchy intro paragraph to that doc. Updated the
  row to also mention the trust-hierarchy mapping and the `verify-ladder`
  gate, not just git hooks.

Both are direct fixes (stale/ambiguous text, not misplaced rationale), so
no separate `D`/`G` follow-up needed.

_docs-updater finished 2026-08-30T06:05:56Z -- see Findings above._
