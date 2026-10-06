---
name: workflow
description: The step sequence for any non-trivial change in this repo -- verify, review, record the why in git, and hand off cleanly if the work spans sessions. Trivial one-off changes (a typo fix, a single-line correction) skip straight to committing. Use for anything else: new/changed modules, hosts, services, multi-step fixes, anything security- or secrets-adjacent.
---

Read `reference.md` in this skill's directory for the trust hierarchy,
the review agents and their order, the handoff-note format, and worked
trivial-vs-not examples.

## The step sequence

1. **Triviality check.** A typo or one-line wording fix goes straight to
   step 6.
2. **Pick up or start.** Look for a handoff note in `docs/plans/*.md`
   (top level) covering this task. If the work will outlive this
   session, or the user makes a decision worth keeping, start one (see
   reference.md, "Handoff notes"). Older plans under
   `docs/plans/{todo,in-progress,done,rejected}/` are a read-only
   archive: grep them for history, never edit them.
3. **Do the work**, following `docs/style-guide.md` and `AGENTS.md`'s
   hard-confirm rules. Comments say what the code does, tersely. The
   reasoning behind it goes in the commit message, not the comment.
4. **Run the verification floor**:
   `docs/skills/workflow/scripts/verify-ladder`. Blocks on
   `scripts/gate-tests`, `nixfmt --check`, `nix flake check --no-build`,
   a targeted `nixos-rebuild build`, and any *newly introduced*
   statix/deadnix issue.
5. **Run the review agents `required-agents` names**, in the order it
   prints them, one at a time. They are advisory: apply what's worth
   applying, mention anything you knowingly leave in the PR description,
   and run a second pass only if the fixes were substantial. Never loop
   until zero findings. A CRITICAL/HIGH `security` finding gets fixed or
   explicitly accepted by the user before you open the PR.
6. **Commit and open the PR** per `docs/GIT_WORKFLOW.md`. The commit body
   and PR description carry the why: decisions the user made, what was
   tried, what's left. Say in the PR how far the change was verified
   (see `docs/procedures/testing-changes.md`). If a handoff note exists
   and the work is finished, fold its goal and decisions into the PR
   description and delete the note in the same PR; if not finished,
   update its State and Next.
