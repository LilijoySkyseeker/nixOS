---
slug: flake-update-test-service-failing-on-homelab-root-
created: 2026-08-19
status: done
frozen: true
---

# `flake-update-test.service` failing on homelab — root has no git identity configured

## Original plan

- [x] **2026-08-19: `flake-update-test.service` failing on homelab —
      root has no git identity configured.** Found during a log trawl.
      The update-branch step fails with `fatal: unable to auto-detect
      email address (got 'root@homelab.(none)')` right after the flake
      inputs are bumped, because `git config --global user.email`/
      `user.name` were never set for root on homelab. Needs: set a git
      identity for root declaratively (e.g. via
      `home-manager.users.root.programs.git` in `profiles/server.nix`,
      alongside the existing root home-manager block) so
      `myAutoUpdate`'s commit step succeeds.

      **Confirmed live 2026-08-21** while deploying zfs-backup-push:
      the crash (2026-08-19 03:01) left homelab's `/etc/nixos` checkout
      on an orphaned `auto-update` branch with an uncommitted
      `flake.lock` bump — `nixos-rebuild switch` was blocked on this
      stale state until manually cleaned up (`git checkout master &&
      git reset --hard origin/master && git branch -D auto-update &&
      git clean -fd`, done live with the user's explicit go-ahead).

      **Landed 2026-08-25.** Root cause was `modules/home-manager/tooling.nix`
      hardcoding its git-identity include path to `/home/lilijoy`
      regardless of which user's home-manager profile imported it —
      root's `homeDirectory` is `/root`, so the include never resolved
      to anything on server hosts. Fixed by making the include path
      relative to `config.home.homeDirectory`, plus a matching
      sops-templated `git-identity` render for root in
      `profiles/server.nix` (reuses the `git_username`/`git_email`
      secrets already decryptable by every host's age key — no secret
      editing needed). Verified live on homelab: `git config user.name`/
      `user.email` now resolve correctly for root.
      **Still open**: whether the self-heal path (an orphaned
      `auto-update` branch getting reset-and-recreated cleanly by the
      next scheduled run) actually holds is unverified in practice —
      the next real `flake-update-test` run (Wed 03:00) is the first
      chance to observe it with the identity fix in place.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
