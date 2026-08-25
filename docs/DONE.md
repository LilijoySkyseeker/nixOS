# Done

Completed items moved out of `TODO.md`'s Active section once landed, kept
for historical record rather than deleted outright. Entries are otherwise
unedited from their original `TODO.md` text — only a closing note is
appended once something lands, dated separately from the original entry.

Newest first.

- [x] **2026-08-18: homelab's weekly restic-to-Backblaze backup has no
      safeguard against `myAutoUpdate`'s Thursday auto-switch killing
      a mid-run backup.** During a full-bucket reset/re-test of the
      backup, we found homelab runs `nixos-rebuild switch` every
      Thursday 03:00 via `myAutoUpdate` (`hosts/homelab/configuration.nix`),
      and `switch-to-configuration` restarts any systemd unit whose
      definition changed — including `restic-backups-backblazeWeekly.service`
      (Type=oneshot, `TimeoutStartSec=1w`) if the restic module, its
      overrides, or a shared dep like `pkgs-stable` changes. A run in
      progress (backups have taken multiple days for the ~2.9TiB
      dataset) would be killed with no resumption. Worked around this
      time by manually pausing the `nixos-upgrade` timer for the
      duration of the manual run. Needs a permanent fix: either make
      the backup service resilient to being interrupted/restarted
      (state/resume support, or a `ConditionXXX`/lock that defers an
      auto-switch while a backup is active), or have `myAutoUpdate`
      skip switching while `restic-backups-backblazeWeekly.service` is
      active.

      **Landed 2026-08-25** as part of the auto-updater rearchitect
      (`modules/flake/deploy-guards.nix`'s `check_protected_units_inactive`,
      wired via `myAutoUpdate.protectedUnits` on homelab). A scheduled
      `auto-switch` run now skips (and retries next cycle) rather than
      switching while any configured protected unit is active, instead
      of a manual-pause workaround. Deployed and live on homelab.

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
