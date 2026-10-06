# torrent

Primary desktop.

## Hardware

- CPU: Ryzen 7 9800x3D 8x, AMD
- GPU: RX 7900XTX 24 GB, XFX SPEEDSTER MERC 310
- RAM: 96 GB (2x48GB) DDR5 6000MHz CL30, CORSAIR VENGEANCE
- SSD: 4 TB M.2, SAMSUNG 990 PRO
- Motherboard: X870 ATX LGA 1718, GIGABYTE AORUS ELITE ICE
- CPU Cooler: NH-D15 G2, Noctua
- Thermal Paste: PTM 7950
- Power Supply: 1000W ATX 80 PLUS PLATINUM, Super Flower Leadex VI
- Case: Torrent Black Solid, Fractal Design
- Monitors: 1x 27" 4K 60Hz, Dell S2721QS
- Keyboard (Gaming): WOOTING TWO HE
- Mouse: MM710 PMW3389, Cooler Master
- Headphones: WH-1000XM4 (Wired), Sony
- Speakers: A5+, Audioengine
- Microphone: AT2020, Audio-Technica
- Interface: RC-505MKII, BOSS

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

The impermanence migration has not happened on this host yet, and unlike
thinkpad it has no `@blank` snapshots to preserve.

## Agent user

This host (only) runs `agent-user`: an `agent` Unix user whose
`claude-remote-control` service runs agent sessions with no permission
prompts. It sees only `~/Documents/Vault/Research` (bindfs-mounted at
`/home/agent/research`) and can't reach the LAN or tailnet. Its
`agent-egress` chain is also jumped for `gid nixbld`, so **your own**
fixed-output builds on this host can't fetch from LAN/tailnet addresses or
over IPv6 either. After a reinstall, or to check it's healthy, run
**`run0 agent-setup`**: it checks every piece the module can't declare (the
logins, the first-run consent, the GitHub side) and walks you through only
what's missing. `--check` only reports. The original one-time steps are Task 6 of
`2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md`;
mechanics in [`docs/hardening.md`](../../docs/hardening.md) ("The `agent`
user").
