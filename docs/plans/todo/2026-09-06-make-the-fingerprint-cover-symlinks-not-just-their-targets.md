---
slug: make-the-fingerprint-cover-symlinks-not-just-their-targets
created: 2026-09-06
status: todo
frozen: false
---

# make the fingerprint cover symlinks, not just their targets

## Original plan

`plan_code_fingerprint` in `docs/skills/plan/scripts/lib.sh` filters its
file list through `[ -f "$f" ]` before hashing. That test exists to skip
tracked-but-absent paths — a deletion staged but not committed is a
normal mid-work state, and passing a missing filename to `sha256sum`
would fail the hash.

It silently does a second job as well. `[ -f ]` dereferences symlinks, so
a symlink to a **file** passes and a symlink to a **directory** does not.
Four tracked symlinks fall in the second category:

```
.claude/skills/human-style-writing -> ../../docs/skills/human-style-writing
.claude/skills/plan                -> ../../docs/skills/plan
.claude/skills/security-audit      -> ../../docs/skills/security-audit
.claude/skills/workflow            -> ../../docs/skills/workflow
```

All four are mode 120000 in the index and all four match
`PLAN_CODE_GLOBS` via `.claude/skills/*`. So `plan_is_code_path` returns
true — a change to one obliges `/simplify` and `security` — while
`plan_code_fingerprint` never sees it. **Repointing
`.claude/skills/plan` at a different tree obliges review but leaves every
existing completion stamp valid.**

`.claude/agents/*.md` behave differently and are already covered: they
are symlinks to files, so `-f` follows them and the target's content is
hashed. The gap is exactly the four skill symlinks.

Raised as
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F31`,
whose documentation half was fixed at the time; this is the behavioural
half.

### Why it was not fixed inline

Two candidate fixes, both with real cost.

1. **Hash `git ls-files -s` mode+oid** instead of file content. Correct,
   and it makes the absent-but-tracked case impossible by construction
   rather than by filter. But it changes the emitted value for *every*
   file, which is precisely the trap
   `2026-09-06-make-plan-gate-survive-a-pr-that-changes-the-fingerprint-algorithm-or.md`
   is filed against — the pinned base-branch `lib.sh` and the PR's own
   copy would compute different values for one tree.
2. **Branch on `[ -L ]` and hash `readlink` output** for links, keeping
   `sha256sum` for regular files. Narrower, but it breaks the current
   pipeline shape: the hash is currently one batched
   `xargs -0 -r sha256sum` over the whole list, and a per-file branch
   means a fork per file. Measured baseline is ~6 ms for 112 files;
   a per-file loop is roughly an order of magnitude worse, on a function
   that runs at every `SubagentStop` and every `plan-gate` invocation.

Neither is a one-liner, and the exposure is narrow — review is still
obliged, so the change is seen by a human and by two agents; only the
stamp invalidation is missed.

### What to decide

- Whether the exposure justifies either cost at all. "Document the gap
  and move on" is a legitimate answer: `plan_is_code_path` already fires,
  so nothing goes unreviewed.
- If it is worth closing, sequence approach 1 behind the fingerprint-
  algorithm plan above, since it is the same class of change.
- Approach 2 could keep the batching by hashing the link targets in a
  second, separate `sha256sum` and combining the two digests — worth
  measuring before assuming the fork cost is unavoidable.

### Verification

Repoint one skill symlink, then confirm the fingerprint moves and
`plan-gate` reports the stamp stale. Confirm the unchanged case still
produces a stable value across locales, per
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#G10`.

## State

Not started. Filed 2026-09-06 from `docs-updater`'s F31, which fixed the
comment and deliberately left the behaviour to a decision. Narrow gap,
non-trivial fix, no urgency: review still fires on the affected paths.

## Progress

- [ ] decide whether to close the gap at all, as a `### D1`
- [ ] if closing, measure approach 2's two-digest variant before
      accepting the per-file fork cost
- [ ] verify by repointing a skill symlink and watching the stamp go
      stale

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
