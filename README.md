# Lilijoy's NixOS Machines

See [GIT_WORKFLOW.md](./docs/GIT_WORKFLOW.md) for git hooks/conventions used in
this repo (auto-configured by the flake's dev shell via direnv).

## Structure Guide

All configuration starts with [flake.nix](./flake.nix)

```bash
NixOS
└── flake.nix
```

where the inputs of the system, the different host configurations, and universal
variables are defined.

Then it progresses to each host with its base
[configuration.nix](./hosts/homelab/configuration.nix) (homelab as the example)

```bash
NixOS
└── hosts
    └── homelab
        └── configuration.nix
```

where the host specific configuration is held. Things like hostname, timezone,
system services, etc. Anything that only this hosts needs and is not shared is
defined here.

Some specific configuration is split into separate files to make organization
easier and is imported in the main
[configuration.nix](./hosts/homelab/configuration.nix).

```bash
NixOS
└── hosts
    └── homelab
        ├── configuration.nix
        ├── disko.nix
        └── hardware-configuration.nix
```

In this case, the
[hardware-configuration.nix](./hosts/homelab/hardware-configuration.nix) which
is auto generated during system installation is left alone. Alongside that is
[disko.nix](./hosts/homelab/disko.nix) which manages disk partitioning and
formatting using [disko](https://github.com/nix-community/disko/).

Then it progresses to the shared profiles by importing
[default.nix](./profiles/default.nix) and one or more of the others.

```bash
NixOS
└── profiles
    ├── default.nix
    ├── PC.nix
    └── server.nix
```

These profiles contain the configuration that is shared with other hosts,
[default.nix](./profiles/default.nix) in particular contains configuration that
is shared universally amongst all hosts. The other profiles are based on the
role the host is taking.

These profiles and the individual host
[configuration.nix](./hosts/homelab/configuration.nix) import modules and
services that have been split apart for organization.

```bash
NixOS
├── modules
│   ├── home-manager
│   │   ├── gnome.nix
│   │   ├── kde.nix
│   │   └── tooling.nix
│   └── nixos
│       ├── beets.nix
│       ├── copypartymount.nix
│       ├── gnome.nix
│       ├── kde.nix
│       ├── tooling.nix
│       ├── virtual-machines.nix
│       ├── winapps.nix
│       └── wooting.nix
└── services
    ├── copyparty.nix
    ├── factorio.nix
    ├── jellyfin.nix
    ├── minecraft.nix
    ├── nextcloud.nix
    ├── rss.nix
    ├── samba.nix
    └── webdav.nix
```

These are simply self contained collections of configuration for a specific
task. The [modules](./modules) are for local configuration. While
[services](./services) are for anything being served to LAN or WAN.

What's left is a section for custom packages, standalone files, and encrypted
secret management with [sops-nix](https://github.com/Mic92/sops-nix).

```bash
NixOS
├── custom-packages
│   └── tpm-fido
│       └── package.nix
├── files
│   ├── ffkbV4.vil
│   ├── gruvbox-dark-rainbow.png
│   └── S2721Q.icm
├── secrets
│   └── secrets.yaml
└── .sops.yaml
```

## Hosts

### Scheduled jobs (weekly timing)

The update/cache/backup cascade is deliberately staggered across the week so
nothing competes for the same host's CPU/disk/network at once. All times are
`America/Los_Angeles`, homelab's `time.timeZone`.

| Day | Time  | Host             | Job                                     | What it does |
|-----|-------|------------------|------------------------------------------|--------------|
| Tue | 03:00 | homelab          | `flake-update-test` (`myAutoUpdate`)     | Bumps `flake.lock` on a branch, build-tests it, merges to `master` only if it builds. |
| Wed | 03:00 | homelab          | `nixos-upgrade` (`myAutoUpdate`)         | Switches homelab to whatever's on `master`; reboots only if the kernel changed. |
| Wed | ~03:0x | homelab         | `push-deploy-vps` → `cache-warm-thinkpad` → `cache-warm-torrent` | Chained via `onSuccess` off `nixos-upgrade`, one at a time (not parallel): builds+pushes vps's closure over SSH, then build-only compiles thinkpad's and torrent's closures so their *entire* closures — not just paths shared with homelab's own config — land in the harmonia cache. |
| Thu | 03:00 | thinkpad, torrent | `pull-deploy` (`myPullDeploy`)          | Pulls `master`, build-tests, switches/boots. By now homelab has already built+cached this same `flake.lock` revision, so most/all of the closure substitutes from `http://homelab:5000` instead of building from source. |
| Fri | 03:00 | homelab          | `restic-backups-backblazeWeekly`         | Weekly ZFS-snapshot-based backup to Backblaze via rclone (`--transfers 32`) — network/I/O heavy. Kept a full day clear of the Thu cache-serving window on purpose. |
| daily | —   | all hosts        | `nh.clean` (`programs.nh.clean`)         | `--keep-since 7d --keep 7` — this is what bounds the binary cache to ~1 week: homelab's own kept generations GC-root everything a client could still substitute. |
| continuous | — | homelab       | sanoid (minutely) / syncoid (hourly)     | ZFS snapshot + replication, independent of the above. |
| `*:0/15` | — | homelab       | `health-check` (`myHealthAlerts`)        | Failed-unit/ZFS/SMART/backup-staleness checks → Discord webhook. |

vps is intentionally absent from the self-update rotation: homelab builds
and pushes its closure (`myPushDeploy`) rather than vps building itself.

## Interesting Stuff

- [Impermanence](./hosts/homelab/configuration.nix#L323) for `homelab` using
  [Impermanence](https://github.com/nix-community/impermanence)
- [tailscale-acl.json](./docs/tailscale-acl.json) is a reference copy of the
  tailnet ACL policy, which is actually managed in the Tailscale admin
  console (not applied by Nix) — keep it in sync manually when the console
  policy changes.
