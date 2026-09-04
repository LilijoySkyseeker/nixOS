---
slug: workflow-skill-close-plan-before-pr-merge-fold-trust-hierarchy-in
created: 2026-09-04
status: done
frozen: true
---

# workflow skill: close plan before PR merge, fold trust hierarchy in

## Original plan

Two explicit requests, both edits to the `workflow` skill:

1. "lets change the workflow to state that a plan must be moved to done
   before the pr is merged." Prompted by this session's own PR #59: the
   code committed, the PR merged, and *then* `plan-move ... done` happened
   as a separate follow-up commit/PR (#61) -- a two-PR dance the skill's
   step sequence didn't actually forbid. Reorder/reword steps 8-9 so
   closing the plan (when the branch's work is actually complete) happens
   in the same branch/PR, before it merges, not after.
2. "also, lets do some more changes to workflow as well. i want the trust
   hirarchy and the pharse next to it to be part of workflow." The Trust
   hierarchy section (`documentation -> source -> local build -> VM test
   -> real switch`) and its corollary ("a fix that is not declarative and
   reproducible is no fix at all") currently live in
   `docs/procedures/workflow.md`, only *referenced* (not stated) from
   `docs/skills/workflow/SKILL.md` step 9. Move the actual content into
   the `workflow` skill (`docs/skills/workflow/reference.md`, matching its
   progressive-disclosure role -- SKILL.md itself stays short per its own
   stated design), and point every other referrer
   (`docs/procedures/workflow.md`, `docs/procedures/testing-changes.md`,
   `docs/agents.md`, `AGENTS.md`'s docs table) at the new location instead
   of restating it, per this repo's cite-don't-restate convention.

Side finding while researching #2: `docs/plans/in-progress/2026-08-29-
fold-the-trust-hierarchy-and-verify-ladder-automation-into-testing.md`
already did the analogous fold into `testing-changes.md` -- its commit
(724b0b0, PR #32) is confirmed on `master`, every Progress item is
checked, no open `D`/`F` -- but the plan itself was never moved to
`done/` (empty `## State`, still sitting in `in-progress/`). Exactly the
gap request #1 is meant to close. Filling in `## State` and moving it to
`done/` as part of this session, alongside the new work, rather than
leaving it as a second dangling example.

## State

All edits made:
- `docs/skills/workflow/SKILL.md`: step 8 is now "Close or leave open,
  before committing" (`plan-move <file> done` in the same branch, before
  merge); step 9 is "Commit and merge" (folds in step 8's move if it
  happened). Step 1's "skip to step 8" updated to "skip to step 9" for
  trivial changes, since there's no plan to close in that path.
- `docs/skills/workflow/reference.md`: added a "Trust hierarchy" section
  (ladder + corollary, moved verbatim from `docs/procedures/workflow.md`)
  as the new first section, since it's what step 8 applies directly.
- `docs/procedures/workflow.md`: its old "Trust hierarchy" section is now
  a short pointer at `reference.md` instead of restating the content.
- `docs/procedures/testing-changes.md`, `docs/agents.md`, `AGENTS.md`
  (docs table row for `testing-changes.md`): all three cross-references
  repointed from `docs/procedures/workflow.md` to
  `docs/skills/workflow/reference.md`.
- Closed the stray `2026-08-29-fold-the-trust-hierarchy-...` plan (State
  filled in, moved to `done/`) -- its landed work is exactly what this
  plan's own new step 8 rule would have caught being left open.

verify-ladder passed clean (docs-only, no `.nix` touched), both before and
after the `/simplify` pass below.

`/simplify` (4 parallel reviews) findings and outcomes:
- Reuse: clean, no duplication -- the relocation left the ladder/corollary
  text in exactly one place.
- Simplification: SKILL.md step 8 restated "not a follow-up commit/PR"
  twice back to back -- trimmed the redundant second sentence.
- Efficiency: `docs/procedures/workflow.md` is read standalone per
  `AGENTS.md` ("read this before making any change"), so a pure pointer
  forced an extra hop on that path -- added back a one-line ladder capsule
  there, keeping the full ladder/corollary/rationale canonical in
  `reference.md`.
- Altitude, two findings:
  1. Step 8's "close before merge" rule was prose-only, unlike every other
     rule in this system (see reference.md's "Why a hook at all"), and
     `plan-gate` (the existing pre-merge CI gate) only checked unresolved
     Findings, never whether a cited plan was actually closed. A hard
     block was judged too rigid (step 8 itself allows legitimate
     multi-PR/still-open cases) -- instead extended `plan-gate` to print a
     non-blocking `NOTE:` when a cited plan is still under `todo/` or
     `in-progress/` at merge time. Smoke-tested against real history
     (`plan-gate HEAD~1 HEAD` in this worktree) -- correctly flagged this
     session's own still-open PR #59 plan.
  2. Suggested reverting the relocation entirely (keep the canonical
     ladder in `workflow.md`, only the corollary in `reference.md`).
     Rejected -- that's the opposite of what the user explicitly asked
     for ("I want the trust hierarchy ... to be part of workflow," i.e.
     the skill). The capsule from the efficiency fix already addresses
     the underlying "stranded standalone reader" concern without
     reverting the move.

## Progress

- [x] Reorder/reword `docs/skills/workflow/SKILL.md` steps 8-9: close the
      plan before committing/merging, not after.
- [x] Move the Trust hierarchy section (ladder + corollary) from
      `docs/procedures/workflow.md` into `docs/skills/workflow/
      reference.md`; repoint every other referrer.
- [x] Close the stray `2026-08-29-fold-the-trust-hierarchy-...` plan.
- [x] Run `/simplify` (4 parallel reviews) and apply its fixes: SKILL.md
      redundant-sentence trim, `workflow.md` ladder capsule, `plan-gate`
      non-blocking still-open warning.
- [x] Run verify-ladder (before and after `/simplify`).
- [ ] Close this plan (`plan-move ... done`) before committing, per its
      own new step 8 rule.
- [ ] Commit and open PR (no merge -- wait for explicit user go-ahead).

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
