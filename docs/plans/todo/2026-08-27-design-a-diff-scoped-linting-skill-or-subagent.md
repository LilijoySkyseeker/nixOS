---
slug: design-a-diff-scoped-linting-skill-or-subagent
created: 2026-08-27
status: todo
frozen: false
---

# Design a diff-scoped linting skill or subagent

## Original plan

User's own observation while reviewing `verify-ladder`'s design (see
`2026-08-27-establish-the-workflow-and-plan-file-system.md`'s G3): the
diff-scoped statix/deadnix logic (only fail on warnings whose line falls
inside the actual changed lines, never pre-existing debt elsewhere in a
touched file) is a real, non-obvious pattern that had to be built from
scratch (git diff hunk-range parsing cross-referenced against each tool's
JSON output). The same problem — "how do I scope a linter to a diff, not
a whole file" — will likely recur anywhere lint tooling gets added to a
future gate. Worth generalizing into its own skill (reusable diff-scoping
helper + convention) rather than re-solving it ad hoc each time.

## Progress

- [ ] Survey whether `verify-ladder`'s specific approach (hunk-range
      extraction via `git diff -U0`, JSON-output cross-referencing)
      generalizes cleanly to other lint tools, or whether each tool's
      output format needs enough bespoke handling that a shared skill
      would just be a thin wrapper with limited reuse.
- [ ] Decide whether this is a `plan`/`workflow`-adjacent skill (generic
      "diff-scoping" helper usable by any future gate) or something
      narrower.

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
