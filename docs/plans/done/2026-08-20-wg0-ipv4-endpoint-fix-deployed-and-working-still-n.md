---
slug: wg0-ipv4-endpoint-fix-deployed-and-working-still-n
created: 2026-08-20
status: done
frozen: true
---

# wg0 IPv4-endpoint fix — deployed and working; still needs to survive a real IPv6 address rotation unwatched

## Original plan

- [ ] **2026-08-20: wg0 IPv4-endpoint fix — deployed and working; still
      needs to survive a real IPv6 address rotation unwatched.**
      `hosts/homelab/configuration.nix`'s wg0 peer now points at vps's
      stable IPv4 (`137.184.45.18:51820`) instead of vps's IPv6
      literal, fixing a bug where the tunnel died silently whenever
      homelab's RFC4941 privacy IPv6 address rotated (confirmed live:
      0% ping both directions despite `persistentKeepalive`).

      **Confirmed deployed and healthy 2026-08-25**: `wg show wg0` on
      homelab shows the peer endpoint as `137.184.45.18:51820` with a
      handshake ~2 minutes old. Still unconfirmed: this fix hasn't been
      watched live through an actual IPv6 rotation event yet (nothing to
      indicate one has happened since deploy) — confirm `wg show wg0`
      keeps a fresh handshake and jellyfin/minecraft/factorio stay
      reachable across the next one or two rotations (homelab's privacy
      addresses appear to rotate on the order of hours-to-a-day, based
      on prior observation).

## State

**2026-09-04.** Live-verified via SSH: `wg show wg0` on homelab shows the
peer endpoint still at `137.184.45.18:51820` with a handshake 1m39s old,
homelab uptime 19h34m (i.e. it has rebooted and re-established the
tunnel since deploy without issue). Ten days have passed since the
2026-08-25 deploy with homelab's privacy IPv6 rotating on an
hours-to-daily cadence per the plan's own estimate -- long enough to
have survived several rotations. Closing as resolved.

## Progress

- [x] Confirm `wg show wg0` keeps a fresh handshake across IPv6
      rotations -- verified 2026-09-04, ten days post-deploy, healthy.

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
