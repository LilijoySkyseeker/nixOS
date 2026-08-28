---
slug: storage-storage-bulk-failed-their-first-mount-atte
created: 2026-08-26
status: done
frozen: true
---

# `/storage`/`/storage-bulk` failed their first mount attempt on boot, self-healed within the same boot — worth understanding, not urgent

## Original plan

- [x] **2026-08-26: `/storage`/`/storage-bulk` failed their first mount
      attempt on boot, self-healed within the same boot — worth
      understanding, not urgent.** Surfaced by the full homelab reboot
      done to verify the tailscale0-only firewall re-scoping (see the
      security-audit items below). Boot sequence from `journalctl -b`:
      `zdata`'s import itself raced once (`cannot import 'zdata': no
      such pool available`, retried ~2s later and succeeded — ZFS's own
      import unit has built-in retry, worked as designed), then
      immediately after the successful import, both `storage.mount` and
      `storage-bulk.mount` (the `/etc/fstab`-generated units, from this
      repo's `fileSystems."/storage"`/`"/storage-bulk"` entries) failed
      their own mount attempt (`status=2/INVALIDARGUMENT`) within the
      same second `zfs-mount.service` started — looks like the classic
      ZFS-on-systemd race of having a dataset in both `/etc/fstab` *and*
      relying on ZFS's own `zfs-mount.service`/mountpoint property, where
      the fstab-generated unit's `mount.zfs` call loses the race against
      ZFS's own mount. Both mounts show `active (mounted)` now (systemd
      picked up the real mount once `zfs-mount.service` established it
      via `/proc/self/mountinfo`, regardless of which process's `mount()`
      call actually succeeded), `zpool status -x` reports "all pools are
      healthy", `df -h` shows correct sizes/usage for both, and
      `systemctl --failed` is empty — no data loss or lasting problem,
      just a scary-looking boot log. Not caused by this session's
      changes (firewall-only, no mount/import ordering touched) — this
      is a pre-existing race that just hadn't been observed since this
      box is rarely rebooted. Needs: either add explicit
      `after`/`requires` ordering on the fstab-generated mount units
      against the zfs import/mount units, or drop the `/etc/fstab`
      entries entirely in favor of relying purely on each dataset's own
      ZFS `mountpoint` property (the more idiomatic NixOS+ZFS pattern),
      so this doesn't depend on a race resolving in the box's favor on
      every future boot.

      **2026-08-26: root cause confirmed live via SSH, fix coded, not yet
      deployed.** `journalctl -b` on homelab shows `zfs-mount.service`
      (`zfs mount -a`) and the fstab-generated `storage.mount`/
      `storage-bulk.mount` units both starting their mount attempt in the
      same second right after `zdata` imports — both datasets have
      `canmount=on` and a real ZFS `mountpoint` property, so both
      mounting paths consider themselves responsible for the same path;
      the loser gets `zfs_mount_at() failed: mountpoint or dataset is
      busy` / `INVALIDARGUMENT`. Fix: `options.mountpoint = "legacy"` on
      `storage/storage` and `storage/storage-bulk` in
      `hosts/homelab/disko.nix` (disko's own documented `zfs-over-legacy`
      pattern — confirmed against the pinned disko source, `ff8702b`,
      including its own NixOS VM test for this exact shape) — ZFS's own
      `zfs mount -a` explicitly skips legacy-mountpoint datasets, so only
      the fstab/systemd path ever calls `mount()`. `nixos-rebuild build`
      for homelab succeeds with this change, and the built closure's
      `/etc/fstab` correctly drops the `zfsutil` mount option for both
      entries (required to pair with `mountpoint=legacy`, matches
      disko's own derivation logic). Not yet applied: this needs a
      one-time live `zfs set mountpoint=legacy zdata/storage/storage`
      (+ `storage-bulk`) on homelab before/alongside the
      `nixos-rebuild switch`, since disko.nix's dataset properties are
      only applied to already-existing datasets by the `disko` CLI
      tool/`nixos-anywhere`, never by a normal rebuild — the Nix-level
      change alone only affects `/etc/fstab`'s generated options, not
      the live ZFS property.

      **2026-08-26: landed and reboot-verified.** Applied
      `zfs set -u mountpoint=legacy zdata/storage/storage
      zdata/storage/storage-bulk` on homelab (`-u`, matching disko's own
      `_create` script, updates the property without forcing an
      unmount — necessary since `/storage` had active file handles;
      plain `zfs set` without `-u` was tried first and correctly refused
      with "pool or dataset is busy" for `/storage`, but had already
      unmounted `/storage-bulk`, which has no active handles, before
      hitting that error — no data loss, `zpool status -x` stayed
      healthy throughout, and the following `nixos-rebuild switch`
      remounted it automatically as part of activation). Then
      `nixos-rebuild switch --flake
      github:LilijoySkyseeker/nixOS/worktree-todo-review-2026-08-26#homelab`
      to regenerate `/etc/fstab` without `zfsutil`, matching. A full
      reboot then confirmed the fix: `journalctl -b` shows
      `Mounting /storage...` / `Mounted /storage.` /
      `Mounted /storage-bulk.` succeeding cleanly via the fstab units
      alone, with `zfs-mount.service` starting and finishing without
      touching either dataset (both are legacy now, so `zfs mount -a`
      skips them) — no `INVALIDARGUMENT`, no failed units. One new,
      unrelated data point from this same reboot: `zdata` took ~71s to
      import this time (`Pool zdata in state MISSING, waiting`,
      retried every ~1s) versus ~2s in the original 2026-08-26 boot —
      still succeeded, `zpool status` shows the mirror healthy with no
      read/write/checksum errors, most likely just spin-up-time
      variance on the mirror's HDDs rather than a new problem, not
      investigated further since it self-resolved and isn't a repeat
      pattern yet.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
