---
name: workflow
description: Gate and orchestrate any non-trivial task in this repo through a citeable plan file (see the `plan` skill) and the relevant review subagents before it's committed. Trivial one-off changes (a typo fix, a single-line correction) skip this entirely -- see the triviality bar below. Use for anything else: new/changed modules, hosts, services, multi-step fixes, anything security- or secrets-adjacent, anything that will eventually be committed as more than a one-line diff.
---

Read `reference.md` in this skill's directory for the subagent-selection
table, worked trivial-vs-not examples, and the multi-session resume case --
this file stays short on purpose (progressive disclosure).

## The step sequence

1. **Triviality check.** Genuinely trivial (a typo, a one-line wording
   fix)? Run `docs/skills/workflow/scripts/mark-trivial "<reason>"`, then
   skip straight to step 8. Otherwise continue below. This is the one
   deliberately judgment-based step in the whole system -- everything
   else here is a hardcoded script or hook, not something to remember.
2. **Find or create the plan file** (see `docs/skills/plan/SKILL.md`).
   Grep `docs/plans/{todo,in-progress}/` for something already covering
   this task; `plan-move <file> in-progress` an existing `todo/` match,
   or `plan-new "<title>"` if nothing exists.
3. **Do the work**, following existing conventions unchanged
   (`docs/style-guide.md`, `AGENTS.md`'s hard-confirm rules).
4. **Run the cheap verification ladder**:
   `docs/skills/workflow/scripts/verify-ladder`. Hard-blocks on
   `nixfmt --check`, `nix flake check`, a targeted `nixos-rebuild build`,
   and any *newly introduced* statix/deadnix issue (pre-existing debt
   elsewhere in a touched file never blocks). This is independent of
   VM-testing, which is not yet part of this system -- see reference.md.
5. **Append to the plan as you go** -- `plan-tick`, new `### D<N>`/
   `### G<N>` entries, append-only.
6. **Invoke `security`/`docs-updater` where relevant** (reference.md has
   the selection table). Each appends findings into the *same* current
   plan file; a `SubagentStop` hook stamps proof it actually finished,
   independent of whether this skill's own sequencing "waited" for it --
   see reference.md, "Why a hook at all", for why that matters.
7. **Resolve `D*` items via `plan-decide`** -- `answered`, `discussed`, or
   `deferred`, exactly per `docs/skills/plan/reference.md`. Only on the
   user's actual input, never inferred.
8. **Commit** per `docs/GIT_WORKFLOW.md` -- short, human, Conventional
   Commits. A `Plan: <date>-<slug>.md` trailer is fine for traceability;
   never inline the plan's reasoning into the commit body. A
   `PreToolUse` hook blocks the commit unless step 1 or step 2 actually
   happened this session (`plan-touch-guard`); another blocks any
   AI-attribution footer outright (`footer-guard`) -- both fire
   regardless of whether you remember this file.
9. **Close or leave open** -- `plan-move <file> done` only once the work
   is actually landed and verified per the trust hierarchy in
   `docs/procedures/workflow.md` (this refuses if any `D*` is
   unresolved); otherwise leave it in `in-progress/`.
