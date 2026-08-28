---
slug: homelab-s-weekly-restic-to-backblaze-backup-has-no
created: 2026-08-18
status: done
frozen: true
---

# homelab's weekly restic-to-Backblaze backup has no safeguard against `myAutoUpdate`'s Thursday auto-switch killing a mid-run backup

## Original plan

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

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
