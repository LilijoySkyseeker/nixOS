# Lilijoy's NixOS Machines

A flake-based NixOS/home-manager configuration for four machines
(`thinkpad`, `torrent`, `homelab`, `vps`), managed from one
repo. Covers disko partitioning, sops-nix secrets, impermanence,
home-manager, and a distributed multi-host flake setup.

## Hosts

| Host | Role | Purpose |
|---|---|---|
| `thinkpad` | Desktop | Secondary laptop. |
| `torrent` | Desktop | Primary desktop. |
| `homelab` | Server | Home server: media (Jellyfin), photo/video backup (Immich, tailnet-only), game servers, NFS, DNS automation, backups. |
| `vps` | Server | Public-facing edge: forwards the game ports to homelab over WireGuard, rate-limited per source IP. |

## Interesting stuff

- Root on `homelab` is wiped on every boot. Every piece of state that
  survives is explicitly declared, not just whatever happened to be
  lying around.
- `vps` fronts everything public and tunnels back to `homelab` over
  WireGuard, which is never directly reachable from the internet itself.
- `homelab` builds and pushes `vps`'s closure over the tailnet. The
  VPS never compiles its own config, so a small droplet never has to
  risk OOMing mid-deploy.
- `nixos-anywhere` + `disko` take a fresh machine from a rescue/kexec
  environment straight to a running, secrets-decrypting NixOS install,
  partitioning included.
- `sops-nix` keys every secret to a specific set of hosts by age key,
  so `secrets/secrets.yaml` lives in git like any other file:
  encrypted, checked into history, unreadable without a host's own
  key. No shared master password, and no plaintext ever touches disk
  outside the host decrypting it at boot.
- Desktops track bleeding-edge `nixpkgs-unstable`. `homelab`, running
  ZFS and long-lived game servers, is pinned to a stable release
  instead (its own `nixpkgs-homelab` input), in the same flake.
- `homelab` runs periodic ZFS/SMART/systemd health checks and pages a
  Discord webhook the moment something looks wrong, instead of finding
  out about a failing disk or a dead service days later.
- Every machine, from partitioning to the services running on it, is
  described in Nix and reproduced from the flake. No host has hand-run
  setup steps that only exist in someone's memory.
