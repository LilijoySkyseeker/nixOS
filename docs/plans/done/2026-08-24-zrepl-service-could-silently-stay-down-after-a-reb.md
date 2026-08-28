---
slug: zrepl-service-could-silently-stay-down-after-a-reb
created: 2026-08-24
status: done
frozen: true
---

# `zrepl.service` could silently stay down after a reboot due to a `local-fs.target` race — fixed by relaxing the dependency

## Original plan

- [x] **2026-08-24: `zrepl.service` could silently stay down after a
      reboot due to a `local-fs.target` race — fixed by relaxing the
      dependency.** Found while rebooting homelab to verify the
      `boot.zfs.extraPools` fix above (the pool import itself worked
      correctly). `storage.mount` failed its first attempt at boot
      (`status=2/INVALIDARGUMENT`, a known ZFS mount-before-ready race
      unrelated to the zbackup fix), which failed `local-fs.target`,
      which `zrepl.service` hard-`Requires=` — that comes from
      **upstream** nixpkgs (`nixos/modules/services/backup/zrepl.nix`),
      not this repo; `modules/nixos/zrepl.nix` had no systemd override at
      all before this fix. The mount self-healed a second later and
      `/storage` was fine, but systemd does not retry a unit whose start
      failed due to a dependency failure — `zrepl.service` sat
      `inactive (dead)` until manually started
      (`systemctl start zrepl.service`). Backups were down ~8 minutes
      this time (16:07-16:15 PDT), same failure class as the entry above
      but much smaller blast radius since it was caught immediately by
      the reboot test rather than discovered ~23h later.

      **Fix:** `modules/nixos/zrepl.nix` now overrides
      `systemd.services.zrepl` with `requires = lib.mkForce [ ];`,
      `wants = [ "local-fs.target" ]; after = [ "local-fs.target" ];`.
      Same ordering in the normal case (zrepl still starts after
      local-fs.target's start job finishes), but a transient dependency
      failure no longer permanently downs the daemon — an unmounted
      dataset just makes that job's own next cycle fail and retry instead
      of the whole daemon never starting. Verified the rendered drop-in
      (`systemd.services.zrepl` override unit) shows `Wants=local-fs.target`
      with no `Requires=` and `After=zfs.target local-fs.target` intact.
      **Reboot-verified, with a caveat.** `nixos-rebuild switch` deployed
      to homelab, then rebooted three times in a row (16:49, 16:52, 16:55
      PDT). All three came up clean: `zrepl.service` active every time,
      `storage.mount`/`storage-bulk.mount` both mounted on the first
      attempt, zero failed units, and `zrepl status` showed
      `local-source`/`local-pull`/`snapshots` all cycling normally with
      snapshots continuing to land right through the reboots. **The
      `storage.mount` race itself did not reproduce in any of the three
      attempts** — it remains a single data point from the previous
      session. So this verifies the fix causes no regression on a clean
      boot, and confirms by construction (inspected the live unit via
      `systemctl show zrepl.service`: `Wants=local-fs.target`,
      `After=local-fs.target`, `local-fs.target` no longer in
      `Requires=`) that a dependency failure can no longer abort zrepl's
      start job — but does not directly observe zrepl surviving a live
      `storage.mount` failure, since none occurred to survive.

      **Still open, deliberately not fixed:** why `storage.mount` races
      at all (still only one data point total, now with three
      non-reproductions alongside it — looks more intermittent than
      reliably reproducible; does `storage-bulk.mount` share the root
      cause?). This fix removes the silent-outage symptom without
      touching that underlying race. If it recurs, check
      `systemctl is-active zrepl.service` — it should now come up on its
      own without manual intervention.

      **Moved here 2026-08-25** — these three were already marked `[x]`
      and fully resolved but had been left sitting in `TODO.md`'s Active
      section instead of moved, against this file's own convention.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
