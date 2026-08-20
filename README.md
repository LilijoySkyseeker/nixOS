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

Every folder above has its own README with a full inventory. For how
it all fits together — import chains, a per-host breakdown, why
`services/` and `modules/` are split the way they are — see
[`docs/architecture.md`](./docs/architecture.md).
[`docs/style-guide.md`](./docs/style-guide.md) covers conventions
(formatting, when a custom NixOS options module is worth writing vs. a
plain config file). [`docs/procedures/`](./docs/procedures/) has
runbooks for adding a host, adding a service, rotating a secret.

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

- **Impermanence on `homelab`.** Root is wiped on every boot — every
  piece of state that survives is explicitly declared, not just
  whatever happened to be lying around.
- **Public edge, private origin.** `vps` fronts everything public
  (Caddy, crowdsec, Anubis proof-of-work against bots) and tunnels
  back to `homelab` over WireGuard. `homelab` itself is never directly
  reachable from the internet.
- **Zero-downtime remote deploys.** `homelab` builds and pushes
  `vps`'s closure over the tailnet — the VPS never compiles its own
  config, so a small droplet never has to risk OOMing mid-deploy.
- **Bare-metal to booted, unattended.** `nixos-anywhere` + `disko` take
  a fresh machine from a rescue/kexec environment straight to a
  running, secrets-decrypting NixOS install, partitioning included.
- **Two nixpkgs channels running side by side.** Desktops track
  bleeding-edge `nixpkgs-unstable`; `homelab` — running ZFS and
  long-lived game servers — is deliberately pinned to
  `nixpkgs-stable`, on purpose, in the same flake.
