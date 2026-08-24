# thinkpad

Primary laptop.

## Hardware

- Chasis: ThinkPad P1 Gen 3, Lenovo
- CPU: Core i7-10750H 6x, Intel
- GPU: Quadro T1000 4GB Max-Q, NVIDIA
- RAM: 64 GB (2x32GB) DDR4 3200
- SSD1: 500 GB M.2, Samsung 970 EVO Plus
- SSD2: 256 GB M.2, INTEL SSDPEKKW256G8L
- Display: 15" 1080p 60Hz

## Backups

Snapshots and replication are handled by zrepl — see
[`docs/backups.md`](../../docs/backups.md).

**This host now runs `sshd`, which it did not before.** It exists solely to
carry zrepl's `ssh+stdinserver` transport, because homelab *pulls* from
this host rather than being pushed to. It is locked down accordingly:
tailnet-only (`openFirewall = false` plus a `tailscale0` firewall rule),
`PermitRootLogin = "forced-commands-only"`, and the only key in root's
`authorized_keys` is a forced command pinned to
`zrepl stdinserver homelab`. Don't add unrestricted root keys here without
reconsidering that posture.

This host has `@blank` snapshots on **both** `zroot/local/root` and
`zroot/local/home` (created once by disko's `postCreateHook`), which are
also the two datasets it serves to homelab. They are protected from zrepl's
pruner by `myZrepl.protectRegexes`; without that guard the first prune
would destroy them, and they cannot be regenerated without reinstalling.
