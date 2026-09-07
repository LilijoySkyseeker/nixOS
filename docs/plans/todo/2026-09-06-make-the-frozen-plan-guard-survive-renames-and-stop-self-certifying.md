---
slug: make-the-frozen-plan-guard-survive-renames-and-stop-self-certifying
created: 2026-09-06
status: todo
frozen: false
---

# make the frozen-plan guard survive renames and stop self-certifying

## Original plan

`.githooks/pre-commit`'s frozen-plan guard compares each staged
`docs/plans/*/*.md` against the checksum `plan-freeze` recorded in
`docs/plans/.checksums`. Two weaknesses remain after
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F45`
moved the manifest read to the index.

### 1. It is keyed on the rename destination

`git diff --cached --name-only` reports the **destination** path for a
rename. The manifest keys on the path as it stood when the plan was
frozen. So `git mv` a frozen plan and edit it in the same staged change:
the destination has no manifest entry, `recorded` comes back empty, the
`continue` fires, and a frozen plan is rewritten with no output and exit
0.

Raised as
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F53`.

Widening the filter to `ACMRT` (F45) fixed the *secret scan's* rename
leg, verified — it buys nothing here, because the problem is not that
renames are filtered out but that the lookup key is wrong for them.

The fix needs `--name-status -z` parsing so the guard sees both the old
and new path of an `R` entry, then checks the manifest under the old
one. Worth doing carefully: the parsing is the fiddly part, and `-z`
output for renames is three NUL-separated fields, not two.

Note also that a legitimate `plan-move` is a rename — `in-progress/X.md`
to `done/X.md` — so any fix must not block the flow that creates frozen
plans in the first place. `plan_do_freeze` records the checksum under the
destination path, after the move, which is why this has not bitten yet.

### 2. The manifest is supplied by the commit it gates

Staging a rewritten `.checksums`, or `git rm --cached`-ing it, both pass
silently: the guard reads the manifest from the index, and the index is
what the committer controls. F45 made this strictly better — the
tampering is now *inside the diff*, so it is visible to review and to
CI — but the guard still certifies itself.

Raised as
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F54`.

Nothing anywhere validates the manifest: not the hook, not
`verify-ladder`, not `plan-gate`, not CI. A check that the manifest's
entries still match the committed plan files — and that no entry has
silently disappeared — belongs on the server side, where the committer
does not control the comparison. That is the same argument that puts
`plan-gate` in CI rather than only in a local hook.

### Sequencing

(2) is the more valuable of the two and is independent of (1). Both are
good candidates for the failure-mode harness proposed in
`2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md`,
since each is a two-line reproduction.

## State

Not started. Filed 2026-09-06 from `security`'s sixth pass on the
channel-routing branch, which found both while confirming F45's fixes.
Neither is a regression from that work: (1) predates it and (2) is a
property F45 improved without closing.

## Progress

- [ ] parse `--name-status -z` so the guard checks a rename's source path
- [ ] confirm `plan-move` + `plan-freeze` still work end to end afterwards
- [ ] decide where manifest validation belongs, as a `### D1` — almost
      certainly CI, for the reason plan-gate is there
- [ ] add both reproductions to the failure-mode harness

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
