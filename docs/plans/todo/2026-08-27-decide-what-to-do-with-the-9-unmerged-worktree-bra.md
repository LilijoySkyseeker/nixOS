---
slug: decide-what-to-do-with-the-9-unmerged-worktree-bra
created: 2026-08-27
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# Decide what to do with the 9 unmerged worktree branches

## State

**2026-09-09: re-inventoried; the "9" in the title is now 20, and 17
merged worktrees have re-accumulated.** The 2026-08-27 snapshot in
"Original plan" is stale — kept as history. Current picture (`git
worktree list`, `git branch --merged/--no-merged origin/master`):

**36 worktrees on disk** under `.claude/worktrees/` (one is the active
`plan-bookkeeping` session doing this triage). Three buckets:

1. **17 fully-merged worktrees — safe to prune, nothing lost.** Their
   branches are entirely in `master`. From the *main checkout* (not an
   isolated session — the worktree-isolation guard blocks sibling git
   ops): `git worktree remove <path>` for each, which self-protects by
   refusing any that still hold uncommitted changes (no `--force`), then
   `git branch -d` the local branch. This is the bulk of the clutter and
   the clean automated step.
2. **9 unmerged AND local-only — the real risk, one `rm -rf` from lost.**
   No remote copy exists: `worktree-nix-cache` (10 commits, 2026-08-19),
   `worktree-distributed-build-todo` (7), `worktree-printer-setup` (5),
   `worktree-crowdsec-bouncer-fix` (3), `worktree-plan-cleanup` (3),
   `worktree-crowdsec-bouncer-docs` (2), `worktree-statusline-spacing-effort`
   (2), `worktree-sops-reorg` (1), `worktree-readme-human-style` (1).
   Recommended: `git push origin <branch>` each as a pure backup (additive,
   reversible) *before* any decision to rebase or abandon — so a decision
   can be taken later without a disk loss foreclosing it.
3. **~11 unmerged but pushed** — already backed up on `origin`; decide
   rebase-and-land vs. abandon at leisure, no urgency.

**Recommended order for the executing session:** (a) push the 9
local-only branches as backup, (b) prune the 17 merged worktrees, (c)
then, unhurried, triage the ~20 unmerged branches for
rebase-and-land vs. `plan-reject`-and-delete. Steps (a) and (b) are
mechanical and safe; (c) is the judgment this plan was filed for.

Verified to rung 2 (source: the git commands above, run 2026-09-09;
counts are commits ahead of `origin/master`). Not closing — the decision
in (c) is the actual work and is unstarted.

## Original plan

- [ ] **2026-08-27: decide what to do with the 9 branches left after the
      merged-worktree prune — 6 of them exist only on this machine and
      are one `rm -rf` away from being lost.** A cleanup pass removed 34
      merged worktrees (+ their local branches) and 18 merged remote
      branches; everything below was deliberately kept because it holds
      commits not in `master`. Counts are commits ahead of
      `origin/master` as of 2026-08-27.
      - **Local-only — never pushed, no remote copy anywhere.** This is
        the risk: pruning one of these worktrees, or losing the disk,
        loses the work outright. Worth pushing them to `origin` purely
        as a backup even if nobody intends to revive them soon.
        `worktree-nix-cache` (10 commits, last 2026-08-19),
        `worktree-distributed-build-todo` (7, 2026-08-19),
        `worktree-crowdsec-bouncer-fix` (3, 2026-08-25),
        `worktree-crowdsec-bouncer-docs` (2, 2026-08-25),
        `worktree-statusline-spacing-effort` (2, 2026-08-25),
        `worktree-sops-reorg` (1, 2026-08-20).
      - **Remote-only — no local worktree.** Their local worktrees were
        pruned as merged, which was correct for the *local* branch tip,
        but the remote tip carries extra commits that never landed. Easy
        to forget precisely because nothing on disk points at them:
        `worktree-vps-exit-node` (3 commits, last 2026-08-19),
        `worktree-auto-updater-rearchitect` (1, 2026-08-25),
        `worktree-jellyfin-gpu-accel` (1, 2026-08-18 — remote-only for
        longer than the others, no local worktree at any point in this
        pass).
      - Both `worktree-distributed-build-todo` and
        `worktree-fde-secureboot-plan` already have a fuller
        content-level review in the 2026-08-25 entry below; this entry
        is about the *inventory* (what exists where, and what is
        unbacked), not a re-review of those two.
      Not started — logged so the next session can decide push-as-backup
      vs. rebase vs. abandon per branch, rather than discovering a gap
      after something is already gone.

## Progress

- [ ] Decide push-as-backup vs. rebase vs. abandon for each of the 6 local-only branches (worktree-nix-cache, worktree-distributed-build-todo, worktree-crowdsec-bouncer-fix, worktree-crowdsec-bouncer-docs, worktree-statusline-spacing-effort, worktree-sops-reorg) and 3 remote-only branches (worktree-vps-exit-node, worktree-auto-updater-rearchitect, worktree-jellyfin-gpu-accel). *(2026-09-09: superseded by the re-inventory in State — see the three buckets and the recommended order there.)*
- [ ] (a) push the 9 local-only unmerged branches to origin as backup
- [ ] (b) prune the 17 merged worktrees + local branches from the main checkout
- [ ] (c) triage the ~20 unmerged branches: rebase-and-land vs. reject-and-delete


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
