---
slug: stop-a-pr-from-weakening-the-ci-gate-it-is-judged-by
created: 2026-09-06
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# stop a PR from weakening the CI gate it is judged by

## State

Not started. Filed 2026-09-06 from a `security` finding on the
channel-routing branch. Independent of that plan's remaining children;
takeable any time, and worth pairing with the threat-model question in
option 4 before writing any code.

## Original plan

`.github/workflows/plan-gate.yml` goes to real trouble to stop a PR
neutering its own gate: the workflow fetches `plan-gate`, `lib.sh` and
`required-agents` from the **base branch** and runs those pinned copies,
so editing the scripts in the PR changes nothing about how the PR is
judged.

The pinning protects the scripts. It cannot protect the workflow that
does the pinning. GitHub resolves a `pull_request` workflow from the
PR's own merge ref, so the YAML that runs is the YAML in the PR. A PR
that adds `continue-on-error: true` to the gate step, or flips its
`if:`, or renames the job, is judged by its own modified workflow.

Verified at the time of filing: the repository's branch rules require
exactly one status context, `plan-gate`, and that requirement is
satisfied by whatever job reports under that name — including one that
was made to always succeed.

Raised as
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F25`.

### Why widening PLAN_CODE_GLOBS did not fix it

That plan's G11 added `.github/workflows/*` to the reviewable-code set,
so a workflow edit now obliges `/simplify`, `security` and
`docs-updater`, and moves the stamp fingerprint. That is worth having —
the change gets reviewed and stamped — but review is not prevention. The
`.claude/settings.json` half of the same widening *is* enforcement,
because disabling the local stamp hook still leaves the server-side
missing-stamp check to block the merge. The workflow half has no such
backstop, since the server-side check is the thing being edited.

`reference.md` presented both halves as equivalent; that overclaim is
corrected in the same change that filed this plan.

### Candidate approaches

Undecided; needs a `### D1`.

1. **Required workflows at the org/repo ruleset level.** GitHub can
   enforce a workflow that the PR cannot override. Strongest option;
   check availability for this account tier.
2. **Move the gate to a `pull_request_target` workflow**, which resolves
   from the base branch. Solves the resolution problem and introduces
   the well-known `pull_request_target` hazard of running with elevated
   permissions in a context where PR content is present — would need the
   job to check out nothing from the PR except the diff it inspects.
3. **A second, minimal always-required check** whose only job is to
   assert that `.github/workflows/plan-gate.yml` matches the base
   branch's copy, failing if it differs without an explicit approval
   label. Recursive but shallow: the asserting workflow is itself
   editable, so this only raises the cost.
4. **Accept and document.** The threat model this system states is an
   agent that forgets a step, not one that edits CI to hide a bypass
   (see the same plan's F7 on stamps being a record, not proof). If that
   holds, prevention is out of scope and the reviewed-and-stamped
   property is the honest ceiling.

Note that (4) is a real candidate and may well be the answer, in which
case the deliverable is a written threat-model statement, not code.

### Verification

Whatever is chosen must be tested with an actual PR that modifies the
gate workflow, on a branch, observing what the required check reports.
Reasoning about GitHub's ref-resolution from documentation is not
sufficient — the resolution behavior is the whole subject.

## Progress

- [ ] confirm current branch-protection / ruleset configuration
- [ ] decide between prevention and documented acceptance, as a `### D1`
- [ ] implement, if prevention is chosen
- [ ] verify with a real PR that edits the gate workflow

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
