---
slug: torrent-s-storage-bulk-nfs-automount-failed-once-at-boot-self-healed
created: 2026-09-01
status: done
frozen: true
---

# torrent's storage-bulk NFS automount failed once at boot, self-healed — tailnet-establishment race

## Original plan

- [x] **2026-09-01: `health-alerts` posted `[torrent] systemd units failed`
      for `home-lilijoy-storage\x2dbulk.mount`.** Investigated live on
      torrent (this box). Root cause confirmed via `journalctl -b`:
      torrent booted at 17:07:48, `tailscaled.service` started at
      17:08:00 and was still bringing the WireGuard interface up
      (`Creating WireGuard device...` / `Bringing router up...` in the
      same log window), and at 17:08:12 — 12s after tailscaled started —
      a KDE `KIO::WorkerThre` thread (same pattern seen on every prior
      *successful* mount in this unit's history, e.g. file-manager
      folder access) triggered the `x-systemd.automount` for
      `/home/lilijoy/storage-bulk`. `mount.nfs4` to `homelab:/storage-bulk`
      hung — tailnet path to homelab (100.98.142.41) likely not yet
      routable — until `x-systemd.mount-timeout=10` (set deliberately in
      `modules/nixos/nfs-homelab-mounts.nix`) killed it at 17:08:22,
      landing the unit in `failed (Result: timeout)`. Not a
      data-availability problem: `zpool status`/exports on homelab were
      unaffected, this is purely the *client*-side NFS automount racing
      the *client*-side tailnet coming up. This is a different race from
      the one in
      `2026-08-26-storage-storage-bulk-failed-their-first-mount-atte.md`
      (that one was homelab's own local ZFS-vs-fstab mount race, fixed by
      `mountpoint=legacy`; this one is torrent-as-NFS-client racing
      tailscaled at boot, unrelated code path).

      Confirmed self-healed and not a config bug: `ping homelab` and
      `showmount -e homelab` both succeeded immediately when checked
      ~8 minutes later, and manually touching a file under
      `/home/lilijoy/storage-bulk/` re-triggered the automount, mounted
      cleanly (`active (mounted)`), and `systemctl --failed` went back to
      empty on its own — no `systemctl reset-failed` needed, matching
      `health-alerts.nix`'s `clear_alert` on the next 15-minute poll that
      finds `systemctl --failed` empty.

      No code change proposed. The `retry=0` /
      `x-systemd.mount-timeout=10` mount options are an intentional
      trade-off already documented inline in
      `modules/nixos/nfs-homelab-mounts.nix` ("give up quickly rather
      than hang a process forever if the server disappears") — the
      failure mode being traded for is exactly this: an occasional
      false-positive alert when something touches the mount in the
      first ~15-20s after boot, before tailscaled has a live path to
      homelab. Self-heals on next access with no manual intervention.
      Logging this so a repeat isn't re-diagnosed from scratch, not
      because it needs fixing.

## State

Diagnosed and closed. One-off transient failure, root-caused to a
boot-time race between KDE's automatic folder access and tailscaled
establishing a route to homelab, not a config defect. Self-healed within
the same boot; verified fixed live on torrent. No further action planned
— revisit only if this starts recurring on *every* boot (which would
suggest tailscaled itself is slow to establish routes on this box, a
different problem) rather than as an occasional one-off.

## Progress

- [x] Root cause confirmed live via journalctl/systemctl on torrent
- [x] Self-heal verified (manual access remounted cleanly, alert
      condition cleared)


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
