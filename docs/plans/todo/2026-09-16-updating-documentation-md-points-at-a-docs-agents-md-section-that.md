---
slug: updating-documentation-md-points-at-a-docs-agents-md-section-that
created: 2026-09-16
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# updating-documentation.md points at a docs/agents.md section that does not exist

## State

Not started. Spotted and logged, not fixed.

## Original plan

`docs/procedures/updating-documentation.md:61-62` describes `AGENTS.md`
as "a docs table plus the handful of rules that matter most (see
`docs/agents.md` for why it's kept this lean)". `docs/agents.md` has no
section on why `AGENTS.md` is kept lean -- the pointer goes nowhere.

Found by `docs-updater` while reviewing
`2026-09-16-codify-that-subagents-and-the-full-toolset-are-allowed-in-this-repo.md`
(its F6), and left alone there as out of scope.

Either outcome is fine, and it is a genuine choice rather than a typo
fix:

- Write the section. There *is* a real rationale to record -- `AGENTS.md`
  is the file every agent loads first, so its length is a tax on every
  session, and the map/territory split exists to keep that tax low. The
  2026-09-16 grant was trimmed on exactly this reasoning, which had to be
  restated from scratch because it was written down nowhere.
- Or drop the parenthetical and let `AGENTS.md`'s own opening line
  ("a **map, not the territory**") carry it.

Worth noting the pointer has been dangling for a while; nothing depends
on it, so this is tidy-up, not a bug.

## Progress

- [ ] Decide: write the section, or drop the pointer
- [ ] Apply


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
