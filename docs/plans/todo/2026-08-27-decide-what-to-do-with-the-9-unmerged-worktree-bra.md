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

**2026-09-15: steps (a) and (b) are done. Only (c), the actual judgement
call this plan exists for, is left.**

**(a) Backup — done.** All 9 local-only branches are now on `origin`, so
none of them is one `rm -rf` from gone: `worktree-nix-cache` (10
commits), `worktree-distributed-build-todo` (7),
`worktree-printer-setup` (5), `worktree-crowdsec-bouncer-fix` (3),
`worktree-plan-cleanup` (3), `worktree-crowdsec-bouncer-docs` (2),
`worktree-statusline-spacing-effort` (2), `worktree-sops-reorg` (1),
`worktree-readme-human-style` (1). Pure backup, no decision implied.

**(b) Prune — done.** 39 worktrees down to 18. 20 fully-merged
worktrees removed with `git worktree remove` (no `--force`, so the
command's own refusal was the safety net), plus their local branches via
`git branch -d`. 11 merged remote branches deleted:
`worktree-zfs-policy-tiers-mydatasets{,-rebased}`,
`worktree-worktree-security-audit-plan`, `security-audit-landing`,
`worktree-loki-grafana-alloy`, `worktree-flake-check-base16-ifd`,
`worktree-grafana-wire`, `loki-ingest-{measurement,correction}`,
`secrets-grafana`, `plan-state-refresh`.

Two self-protected and were left alone, correctly:
`worktree-doio-audio-switch-plasma-manager` still holds uncommitted
changes, and `origin/worktree-zfs-policy-tiers-mydatasets` carried one
commit not in master — checked before deleting, and its
`modules/nixos/datasets.nix` is byte-identical to master's, so it was
superseded rather than lost.

Every remaining worktree holds commits not in `master`. Two of them are
being landed separately and should not be pruned yet:
`worktree-backup-restore-test-tier1` (landed as #84, branch kept until
its worktree is dropped) and `worktree-homelab-obsidian-livesync`
(rebased, blocked on secrets).

**(c) Triage — still open, and still the point.** ~16 unmerged branches
now all have remote backups, so nothing is urgent and nothing is at
risk. Each needs a rebase-and-land or a `plan-reject`-and-delete
decision, which is a judgement call per branch, not a sweep.

Verified to rung 3 (ran it locally with output inspected): counts and
merge status from `git worktree list`, `git rev-list --count
origin/master..<branch>`, and per-branch remote checks run 2026-09-15.

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
