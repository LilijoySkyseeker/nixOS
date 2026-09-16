---
slug: run-docs-updater-last-so-it-documents-the-post-review-final-state
created: 2026-09-16
status: in-progress
frozen: false
kind: task
priority: normal
blocked_by:
---

# run docs-updater last so it documents the post-review final state

## State

Docs/scripts only, no host config. `verify-ladder` green (which includes
`gate-tests`, the thing most likely to encode the old order).

## Original plan

User: *"the docs updater should run last in the order of sub agents, since
it will update on the final state after all the other ones have
triggered."*

Move `docs-updater` from second to last in `PLAN_AGENT_ORDER`, so the run
order becomes `/simplify -> security -> spec-check -> docs-updater`.

## Progress

- [x] `PLAN_AGENT_ORDER` in `docs/skills/plan/scripts/lib.sh`
- [x] Run-order diagram and rationale in `docs/skills/workflow/reference.md`
- [x] Agent table in the same file (it is explicitly "listed in run order")
- [x] Stale ordering comment in `docs/skills/workflow/scripts/required-agents`
- [x] `verify-ladder`

## Decisions (D)

### D1 -- ordering by "who documents the final state", not "writers before readers"

The old order (`/simplify -> docs-updater -> security -> spec-check`) put
every writer ahead of every reader. The new one puts the documenter last.

The user's argument is the whole case: reviewer findings routinely cause
code edits, so a documenter that ran before the reviewers documents a
version that never ships. This session is the worked example -- `security`
found a missing `TimeoutStartSec` on
`2026-09-16-ensure-printers-fails-every-boot-on-torrent-undeployed-fix-plus-no.md`,
the fix landed afterwards, and anything `docs-updater` had written would
have described the pre-fix module.

`/simplify` stays first: it rewrites code, and the reviewers need to see
the code it leaves behind. The concurrency rules are untouched -- still
strictly serial, still no two in one batch.

## Gotchas (G)

### G1 -- the old order existed for a real reason that no longer applies

Nearly got this wrong. The first draft of this change justified itself by
reasoning about stamp staleness: `PLAN_STAMPABLE_AGENTS` covers both
`security` and `docs-updater`, the fingerprint covers `PLAN_CODE_GLOBS`
but not `PLAN_DOC_GLOBS`, so a `docs-updater` edit to a `.nix` comment
would invalidate `security`'s stamp and block the merge. All of that is
accurate about the *pre-2026-09-09* system and irrelevant now.

`plan-gate` settles it in its own header:

```
# merges when satisfied. Completion stamps are no longer read here at
# ...
# after the stamp-staleness block livelocked against its own review loop.
```

And ADR-0002's Consequences: *"Stamps still get written by
`subagent-stamp` but nothing reads them as locks; they are provenance,
and may be removed entirely later"*, plus *"the stamp-staleness machinery
[is] deleted, not archived"*.

So there is no gate consequence to weigh. The ordering is now a pure
question of who should see what, which is what D1 answers.

Worth keeping because the trap is live for anyone reading `lib.sh`:
`PLAN_STAMPABLE_AGENTS`, `plan_stamp_line`, `plan_stamp_fingerprint` and
`PLAN_CODE_GLOBS` all still exist and still *look* load-bearing. They are
provenance-only. `plan-gate` is the authority on what actually blocks.

### G2 -- the "stamping is being removed on a branch" lead was a dead end

Checked, because it would have changed the reasoning. It does not exist.
`origin/worktree-skill-rename-plan-file-task-gate` (the only branch whose
diff deletes stamp-related lines) is a **rename**, not a removal --
`plan` -> `plan-file`, `workflow` -> `task-gate`. `subagent-stamp`
survives at `task-gate/scripts/subagent-stamp`, and
`PLAN_STAMPABLE_AGENTS=("security" "docs-updater")` is still at
`plan-file/scripts/lib.sh:19`. The deleted lines were path changes.

The real answer is that the removal already happened, in master, on
2026-09-09 (G1) -- so the conclusion held even though the premise did
not. ADR-0002 does anticipate deleting the stamp writer too ("may be
removed entirely later"), which is probably the memory behind the lead.

### G3 -- `gate-tests` hardcodes the order string, and fails open when it drifts

Changing `PLAN_AGENT_ORDER` breaks `scripts/gate-tests` in a way worth
knowing about in advance. The test *"required-agents refuses an agent
missing from the order"* works by `sed`-ing the array to drop `security`,
and it matches the **entire literal array text**:

```sh
sed -i "s/PLAN_AGENT_ORDER=(\"\/simplify\" \"docs-updater\" \"security\" \"spec-check\")/..."
```

Reorder the array and that `sed` silently matches nothing. `lib.sh` is
left untouched, `required-agents` has no reason to refuse, and the
`expect_fail` assertion fails -- so the symptom is a *failing* test, but
the cause is a `sed` that quietly did nothing rather than anything about
the behaviour under test. Updated the literal to the new order.

Mildly ironic given the test's own category: it is in the "fail-open: a
gate must not report success over a check it could not make" block, and
its mutation step is itself capable of not making the mutation. It fails
loudly here only because `expect_fail` inverts the result. A future
cleanup could have the test assert the `sed` actually changed the file
before relying on it.


## Findings (F)
*(populated by security/docs-updater when invoked)*
