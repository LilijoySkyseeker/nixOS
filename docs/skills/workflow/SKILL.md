---
name: workflow
description: Gate and orchestrate any non-trivial task in this repo through a citeable plan file (see the `plan` skill) and the relevant review subagents before it's committed. Trivial one-off changes (a typo fix, a single-line correction) skip this entirely -- see the triviality bar below. Use for anything else: new/changed modules, hosts, services, multi-step fixes, anything security- or secrets-adjacent, anything that will eventually be committed as more than a one-line diff.
---

Read `reference.md` in this skill's directory for the trust hierarchy that
governs step 8's close-out decision, the subagent-selection table, worked
trivial-vs-not examples, and the multi-session resume case -- this file
stays short on purpose (progressive disclosure).

## The step sequence

1. **Triviality check.** Genuinely trivial (a typo, a one-line wording
   fix)? Run `docs/skills/workflow/scripts/mark-trivial "<reason>"`, then
   skip straight to step 9. Otherwise continue below. This is the one
   deliberately judgment-based step in the whole system -- everything
   else here is a hardcoded script or hook, not something to remember.
2. **Find or create the plan file** (see `docs/skills/plan/SKILL.md`).
   Grep `docs/plans/{todo,in-progress}/` for something already covering
   this task; `plan-move <file> in-progress` an existing `todo/` match,
   or `plan-new "<title>"` if nothing exists. Grep `docs/plans/done/`
   too -- never to reuse a frozen plan, but because one often already
   records why this was tried, shaped this way, or undone.
3. **Do the work**, following existing conventions unchanged
   (`docs/style-guide.md`, `AGENTS.md`'s hard-confirm rules). Write
   comments right the first time -- lowercase, terse, mechanics-only,
   citing the plan by anchored id (`# plan: <date>-<slug>.md#D2`) for any
   "why" rather than inlining the reasoning -- rather than leaning on
   `docs-updater` to clean it up afterward; that subagent is a backstop
   for what slips through, not the primary mechanism.
4. **Run the scriptable verification floor**:
   `docs/skills/workflow/scripts/verify-ladder`. Hard-blocks on
   `plan-citations` (any plan citation that no longer resolves),
   `scripts/gate-tests` (the gate scripts' own failure-mode tests --
   a gate that no longer refuses what it must, or no longer passes an
   honest sequence), `plan-lint` on the active plan (duplicate or
   non-sequential `D`/`G`/`F` ids, a `Progress` line citing a heading
   that does not exist), `nixfmt --check`, `nix flake check --no-build`,
   a targeted `nixos-rebuild build`, and any *newly introduced*
   statix/deadnix issue
   (pre-existing debt elsewhere in a touched file never blocks). This is
   independent of VM-testing, which is not yet part of this system -- see
   reference.md.
5. **Append to the plan as you go** -- `plan-tick`, new `### D<N>`/
   `### G<N>` entries, append-only.
6. **Run every agent
   `docs/skills/workflow/scripts/required-agents` names**, in the order
   it prints them, one at a time -- never two in the same parallel
   batch. *Which* agents comes from the diff, the order from
   `PLAN_AGENT_ORDER`; nothing here is a judgment call. Apply the
   findings once the read-only reviewers have reported, and if that fix
   changed code, run the whole sequence again.
   `security`/`docs-updater` append findings into the
   *same* current plan file. See reference.md, "Order, and the loop"
   for the restart rule and why nothing runs concurrently, "What a
   completion stamp proves" for what the `SubagentStop` hook does and
   does not establish, and "Why a hook at all" for why this skill's own
   sequencing is not what makes it work.
7. **Resolve `D*` items via `plan-decide`** -- `answered`, `discussed`, or
   `deferred`, exactly per `docs/skills/plan/reference.md`. Only on the
   user's actual input, never inferred.
8. **Close or leave open, before committing.** `plan-move <file> done`
   now, in this same branch, if the work is actually complete and
   verified per the trust hierarchy in `reference.md` (this refuses if
   any `D*`/`F*` is unresolved, or if `## State` has no paragraph
   *opening* with the fixed phrase `Verified to rung <N>` -- see
   `docs/procedures/testing-changes.md`, "Declaring the rung") -- not as
   a follow-up commit or a second PR after this one merges. Leave it in
   `in-progress/` only when the task genuinely isn't finished yet (e.g.
   still needs a real host switch or other later verification), and
   still commit and open the PR either way.
9. **Commit and merge** per `docs/GIT_WORKFLOW.md` -- short, human,
   Conventional Commits, including step 8's plan-file move if it
   happened. A `Plan: <date>-<slug>.md` trailer is fine for traceability;
   never inline the plan's reasoning into the commit body. A
   `PreToolUse` hook blocks the commit unless step 1 or step 2 actually
   happened this session (`plan-touch-guard`); another blocks any
   AI-attribution footer outright (`footer-guard`) -- both fire
   regardless of whether you remember this file.
