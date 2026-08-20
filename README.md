# Lilijoy's NixOS Machines

A flake-based NixOS/home-manager configuration for five machines
(`thinkpad`, `torrent`, `homelab`, `vps`, `isoimage`), managed from one
repo. Covers disko partitioning, sops-nix secrets, impermanence,
home-manager, and a distributed multi-host flake setup. `docs/` has
the reasoning behind how it's put together.

## Layout

```
flake.nix                    # inputs + one nixosSystem per host
hosts/<name>/configuration.nix   # host-specific config
profiles/{default,PC,server}.nix # shared config, layered by machine role
modules/{nixos,home-manager}/    # reusable option modules
services/                    # one-off service configs (jellyfin, etc.)
secrets/ + .sops.yaml         # sops-nix encrypted secrets
```

Every folder has its own README with a full inventory. The import
chains, per-host breakdown, and the reasoning behind the
`services/`/`modules/` split are in
[`docs/architecture.md`](./docs/architecture.md). Conventions
(formatting, when a custom options module is worth writing vs. a plain
config file) are in [`docs/style-guide.md`](./docs/style-guide.md).
Runbooks for adding a host, adding a service, or rotating a secret are
in [`docs/procedures/`](./docs/procedures/).

```bash
nix develop     # or: direnv allow
nixos-rebuild build --flake .#<host>
```

The dev shell wires up git hooks and `pull.rebase true` automatically.
See [`docs/GIT_WORKFLOW.md`](./docs/GIT_WORKFLOW.md).

## Hosts

| Host | Role | Purpose |
|---|---|---|
| `thinkpad` | Desktop | Secondary laptop. |
| `torrent` | Desktop | Primary desktop. |
| `homelab` | Server | Home server: media (Jellyfin), game servers, NFS, DNS automation, backups. |
| `vps` | Server | Public-facing edge: reverse proxy, WireGuard tunnel back to homelab, DDoS/bot mitigation. |
| `isoimage` | Standalone | Bootable recovery/install ISO, outside the normal profile hierarchy. |

Known issues and incident history per host live in each host's own
`hosts/<name>/README.md`.

## Interesting stuff

Root on `homelab` is wiped on every boot; state survives a reboot only
if it's explicitly declared with impermanence, nothing survives by
accident. `vps` fronts everything public (Caddy, crowdsec, Anubis
proof-of-work against bots) and tunnels back to `homelab` over
WireGuard, so `homelab` is never directly reachable from the internet.
Deploys to `vps` are built on `homelab` and pushed over the tailnet, so
the droplet never has to compile its own config and risk OOMing
mid-deploy. New machines go from a rescue/kexec environment to a
running, secrets-decrypting NixOS install with `nixos-anywhere` and
`disko`, partitioning included, no manual steps. And two nixpkgs
channels run side by side in the same flake: desktops track
bleeding-edge `nixpkgs-unstable`, while `homelab` — running ZFS and
long-lived game servers — is pinned to `nixpkgs-stable`.
