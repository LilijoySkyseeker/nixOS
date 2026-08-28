---
slug: design-the-vm-testing-subagent-s
created: 2026-08-27
status: todo
frozen: false
---

# Design the vm-testing subagent(s)

## Original plan

Tabled during `2026-08-27-establish-the-workflow-and-plan-file-system.md`
(D2/D14 area, see that plan's Gotchas for the surrounding context): the
`workflow` skill hard-gates the cheap verification ladder (nixfmt, flake
check, targeted build — `docs/skills/workflow/scripts/verify-ladder`), but
VM-testing (`docs/procedures/vm-testing.md`'s `system.build.vm` boot-check
and `runNixOSTest`) is not yet part of the gated roster. A single
`vm-testing` subagent may be the wrong shape — it might need to be split
(boot-check vs. `runNixOSTest` are genuinely different tools answering
different questions), or folded into a broader verification agent
alongside the cheap ladder. Needs its own research/design pass, same rigor
as the rest of this system (check real behavior, don't assume) before
building.

## Progress

- [ ] Research whether a single subagent can reasonably own both
      `system.build.vm` boot-checks and `runNixOSTest` invocations, or
      whether the failure modes/turnaround times are different enough to
      want two.
- [ ] Design how it decides which check to run for a given change (see
      `docs/procedures/vm-testing.md`'s "when a VM test is worth its
      minutes" guidance).
- [ ] Decide whether it belongs in the `workflow` skill's hard-gated
      sequence at all, or stays a manual/on-request step given VM tests
      cost minutes (per `docs/procedures/testing-changes.md`'s note that
      the `pre-push` hook deliberately skips them for the same reason).

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
