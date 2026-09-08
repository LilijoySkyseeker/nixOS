---
slug: enable-fingerprint-less-stamp-blocking-once-the-fingerprint-era-has
created: 2026-09-06
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# enable fingerprint-less stamp blocking once the fingerprint era has landed

## State

Half landed before this file was filed, which "Original plan" above
predates: `plan-gate` already routes `malformed` through `stamp_problem`,
so a stamp naming an *empty* fingerprint now BLOCKS on a non-frozen plan.
That half needed no entry condition — an empty `(code )` field cannot
come from the pre-fingerprint era, only from a truncated or hand-written
line, so re-running the agent always fixes it, and no legacy stamp on any
open plan reads as `malformed`.

Only the `legacy` arm remains, and it is what the entry condition and the
verification steps above are about. Blocked there until the fingerprint
work merges to master and the main checkout is pulled
(`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F12`).
Filed 2026-09-06 as the follow-up to
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F13`,
which the user accepted rather than fixed.

## Original plan

`plan-gate` treats a stamp with no `(code <fp>)` field as `legacy` and a
stamp with an empty one as `malformed`, and downgrades both to a
non-blocking NOTE regardless of whether the cited plan is frozen. A
missing stamp on a non-frozen plan, by contrast, blocks. So the
old-format line

```
_security finished <ts> -- see Findings above._
```

is one `printf`, needs no fingerprint computation, and satisfies the gate
on a live plan indefinitely -- strictly cheaper than the honest path,
which at least risks a staleness block.

Raised as
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F13`
and **accepted there by the user on 2026-09-06** rather than fixed,
because the fix is unsafe until the transition completes. This plan is
the follow-up that record points at.

### Why it could not be fixed at the time

Every stamp on the branch that introduced fingerprinting is itself
legacy, for the reason recorded in
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F12`:
a worktree session runs hooks from the main checkout, so the
fingerprint-writing `subagent-stamp` could not execute until that branch
merged and the main checkout was pulled. Blocking legacy stamps then
would have made the introducing PR unpassable -- the un-passable-gate
failure mode of
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#G5`,
and the bypass-teaching dynamic of
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F1`.

### The change

Route `legacy` and `malformed` through `plan-gate`'s `stamp_problem`
helper, which already resolves to NOTE when the plan is frozen and
BLOCKED otherwise. That closes the loophole without recreating F1: on a
non-frozen plan, re-running the agent is always satisfiable, and
`plan_stamp_fingerprint` reads the newest stamp (`tail -n 1`), so a fresh
run supersedes a legacy line rather than colliding with it.

### Entry condition

Do not start this until all three hold:

1. `master` carries the fingerprinting `subagent-stamp`, and the main
   checkout has been pulled, so live sessions actually write `(code ...)`
   stamps.
2. A stamp written by an ordinary session has been observed to carry a
   fingerprint -- verified, not assumed, since F12 is exactly the case of
   a mechanism that looked wired and was not.
3. Any plan still open and cited by a live range has had its obliged
   agents re-run at least once, so no in-flight work is blocked by the
   switch.

### Verification

Enabling this makes an in-progress plan spanning the transition block
until its agents re-run once -- one extra, satisfiable pass. Before
enabling, check which open plans carry legacy stamps and would be
affected. Test both arms: a legacy stamp on a frozen plan must still
NOTE, and on a non-frozen plan must now BLOCK.

## Progress

- [ ] confirm the entry condition holds (master's `subagent-stamp` is
      live, a real session's stamp carries a fingerprint, no open cited
      plan is stranded)
- [ ] survey open plans for legacy stamps and re-run their obliged agents
- [ ] route `legacy`/`malformed` through `stamp_problem` in `plan-gate`
- [ ] test both arms: frozen still NOTEs, non-frozen now BLOCKs

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
