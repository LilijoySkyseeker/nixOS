---
slug: make-the-workflow-hooks-fail-closed-when-hook-lib-sh-is-missing
created: 2026-09-06
status: todo
frozen: false
---

# make the workflow hooks fail closed when hook-lib.sh is missing

## Original plan

All three `PreToolUse` hooks in `docs/skills/workflow/scripts/` source
`hook-lib.sh` unguarded:

- `plan-touch-guard` — blocks a commit with no plan touched
- `footer-guard` — blocks an AI-attribution footer
- `fresh-branch-guard` — enforces pull-before-branching

If `hook-lib.sh` is missing, the `.` returns 1, and because these scripts
run under `set -u` with no `set -e`, execution continues. The very next
call is `hook_json_str`, which is now command-not-found, so `tool_name`
comes back empty, the `[ "$tool_name" = "Bash" ] || exit 0` guard matches,
and the hook exits **0 — a silent allow**.

That is the worst available failure direction: the gate does not merely
fail, it reports success. For `plan-touch-guard` specifically, a broken
checkout silently permits exactly the unguarded `git commit` the hook
exists to prevent.

### Why this is not the same as F15

`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F15`
covered a `lib.sh` dependency that a single hook had briefly acquired,
and its resolution was to remove that dependency. `hook-lib.sh` is
different: it is not a convenience, it is where `hook_json_str`,
`hook_json_command`, `hook_anchored` and `hook_deny` live, so no hook can
drop it. It has to be guarded instead.

### The awkward part

`hook_deny` is defined in the file whose absence is being detected, so
the guard cannot use it. The check has to inline the deny JSON once per
hook, before the source:

```sh
[ -r "$SCRIPT_DIR/hook-lib.sh" ] || {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: hook-lib.sh missing beside this hook -- fix the checkout."}}\n'
  exit 0
}
```

Deliberately duplicated across the three hooks rather than factored out,
since factoring it into a shared file recreates the dependency being
guarded.

### Scope note

Found by `/simplify` on 2026-09-06 while reviewing the fix stage of
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md`.
It is pre-existing on `master` and affects files that plan's branch does
not otherwise touch, so it was filed here rather than recorded as a
finding on a diff it is not part of.

### Decide while working this

Whether `fresh-branch-guard` warrants the same treatment as the other
two. Its failure mode is a missed pull-before-branch rather than an
ungated commit, so denying every Bash call on a broken checkout may be
disproportionate — but an inconsistent trio is its own maintenance
hazard.

## State

Not started. Filed 2026-09-06 from a `/simplify` finding. Independent of
the channel-routing map; takeable any time.

## Progress

- [ ] confirm the silent-allow path by running each hook with
      `hook-lib.sh` temporarily moved aside
- [ ] add the inlined fail-closed guard to `plan-touch-guard` and
      `footer-guard`
- [ ] decide `fresh-branch-guard`'s treatment, as a `### D1`
- [ ] verify a healthy checkout is unaffected: non-commit Bash calls
      still pass silently

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
