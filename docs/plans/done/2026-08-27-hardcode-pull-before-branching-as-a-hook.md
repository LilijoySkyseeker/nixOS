---
slug: hardcode-pull-before-branching-as-a-hook
created: 2026-08-27
status: done
frozen: true
---

# Hardcode pull-before-branching as a hook

## Original plan

User's follow-up after watching this session brand a whole workflow-system
branch off a stale local `master` and then need a large, careful rebase
(resolving real conflicts across 10+ files) once `origin/master` turned
out to be 57 commits ahead: "always pull before starting work" should be
hardcoded into the new system, not just documented. `docs/procedures/
workflow.md` already said this ("Pull first... before creating a new
branch or worktree") but it was pure convention -- exactly the kind of
rule the "hardcode with scripts, not agent judgment" tenet (see
`2026-08-27-establish-the-workflow-and-plan-file-system.md`) exists for.

## Progress

- [x] Built `docs/skills/workflow/scripts/fresh-branch-guard` (`PreToolUse`
      hook): blocks `git checkout -b`/`git switch -c`/`git branch <name>`
      when local `master` is behind `origin/master`, fetching first to
      check. Wired into `.claude/settings.json`.
- [x] Verified both paths live through the real harness: blocked a real
      branch-creation attempt while local master was genuinely 57 commits
      behind, then fast-forwarded local master and confirmed the same
      command succeeded afterward.
- [x] Documented in `docs/skills/workflow/reference.md`'s "Why a hook at
      all" section.

## Decisions (D)

## Gotchas (G)

### G1 — the hook can't distinguish "stale master" from "deliberately branching off something else"
`fresh-branch-guard` only checks whether local `master` is behind
`origin/master` -- it has no way to know if the new branch is intentionally
based on a different ref (another feature branch, a specific commit). This
is a known, accepted limitation stated in the hook's own denial message:
it's a narrow mechanical backstop for the specific "forgot to pull"
mistake, not a judgment call about branch strategy in general.

## Findings (F)
*(populated by security/docs-updater when invoked)*
