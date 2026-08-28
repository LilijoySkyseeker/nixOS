---
slug: decide-what-to-do-with-the-9-unmerged-worktree-bra
created: 2026-08-27
status: todo
frozen: false
---

# Decide what to do with the 9 unmerged worktree branches

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

- [ ] Decide push-as-backup vs. rebase vs. abandon for each of the 6 local-only branches (worktree-nix-cache, worktree-distributed-build-todo, worktree-crowdsec-bouncer-fix, worktree-crowdsec-bouncer-docs, worktree-statusline-spacing-effort, worktree-sops-reorg) and 3 remote-only branches (worktree-vps-exit-node, worktree-auto-updater-rearchitect, worktree-jellyfin-gpu-accel).


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
