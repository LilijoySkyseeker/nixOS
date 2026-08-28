---
slug: zbackup-was-never-imported-at-boot-backups-had-bee
created: 2026-08-24
status: done
frozen: true
---

# `zbackup` was never imported at boot — backups had been silently dead for ~23h. Fixed declaratively

## Original plan

- [x] **2026-08-24: `zbackup` was never imported at boot — backups had
      been silently dead for ~23h. Fixed declaratively.** Found while
      running the zrepl migration's pre-deploy check. homelab rebooted
      Sun 2026-08-23 10:45 (for this file's USB cable change entry);
      `zbackup`
      did not come back, and every replication job since failed with
      `dataset does not exist`. The pool itself was fine the whole time
      — ONLINE, importable, no data errors.

      **Cause:** nothing in the NixOS config ever imported it. nixpkgs
      only emits a `zfs-import-<pool>.service` for a pool something
      references — a `fileSystems` entry, or `boot.zfs.extraPools`.
      `zdata` gets one implicitly because `/storage` and `/storage-bulk`
      are mountpoints on it. Every `zbackup` dataset is
      `mountpoint = "none"` by design (it is a receive-only target that
      should mount nothing), so nothing referenced the pool and no unit
      was ever generated. Confirmed against the built system, not
      guessed: `ls result/etc/systemd/system/ | grep zfs-import` listed
      only `zdata`. disko is not a fallback here — it emits no import
      units at all (no `extraPools` anywhere in the pinned tree), and
      only creates datasets at *format* time.

      It survived earlier reboots only because someone had imported it
      by hand. That is why this went unnoticed for so long.

      **Fix:** `boot.zfs.extraPools = [ "zbackup" ];` in
      `hosts/homelab/configuration.nix`, on the zrepl migration branch.
      Verified: the rebuilt system now contains
      `zfs-import-zbackup.service`, and the pool imports on a real
      reboot.

      **Worth noting as a class of bug:** a receive-only ZFS pool with
      no mountpoints is invisible to every implicit import mechanism.
      Any future backup-target pool needs `boot.zfs.extraPools`
      explicitly. Also worth asking separately why ~23h of failed
      replication units did not produce an alert that got acted on —
      `myHealthAlerts` does cover failed units, so the gap is likely in
      noticing, not in detecting.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
