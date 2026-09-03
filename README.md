# Lilijoy's NixOS Machines

A flake-based NixOS/home-manager configuration for five machines
(`thinkpad`, `torrent`, `homelab`, `vps`, `isoimage`), managed from one
repo. Covers disko partitioning, sops-nix secrets, impermanence,
home-manager, and a distributed multi-host flake setup. `docs/` has
the reasoning behind how it's put together.

## Layout

This flake uses the **dendritic pattern**
([flake-parts](https://flake.parts/) + [import-tree](https://github.com/vic/import-tree)):
every `.nix` file under `modules/` registers *itself* into
`flake.modules.nixos.<name>` or `flake.modules.homeManager.<name>`, instead
of being manually added to some other file's `imports`. There's no single
"list of every module" to keep in sync — the file tree under `modules/` *is*
the registry.

```
flake.nix                          # thin entry point: flake-parts + import-tree ./modules
modules/flake/                     # vars, pkgs, systems, and hosts.nix (composes all 5 hosts)
hosts/<name>/configuration.nix     # host-local config only (hardware, hostname, disko)
modules/profiles/{default,PC,server}.nix # shared config, layered by machine role
modules/{nixos,home-manager,services}/   # reusable modules, one file = one flake.modules.* entry
secrets/ + .sops.yaml               # sops-nix encrypted secrets
```

`modules/flake/hosts.nix` is the file to check for "what does host X
actually run" — it lists, per host, which `flake.modules.*` entries get
pulled in. A module existing under `modules/` doesn't mean any host uses
it; that's still decided by `hosts.nix`. For how it all fits together — see
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
| `homelab` | Server | Home server: media (Jellyfin), photo/video backup (Immich, tailnet-only), game servers, NFS, DNS automation, backups. |
| `vps` | Server | Public-facing edge: reverse proxy, WireGuard tunnel back to homelab, DDoS/bot mitigation. |
| `isoimage` | Standalone | Bootable recovery/install ISO, outside the normal profile hierarchy. |

Known issues and incident history per host live in each host's own
`hosts/<name>/README.md`.

## Interesting stuff

- Root on `homelab` is wiped on every boot. Every piece of state that
  survives is explicitly declared, not just whatever happened to be
  lying around.
- `vps` fronts everything public (Caddy, crowdsec, Anubis proof-of-work
  against bots) and tunnels back to `homelab` over WireGuard, which is
  never directly reachable from the internet itself.
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
  ZFS and long-lived game servers, is pinned to `nixpkgs-stable`
  instead, in the same flake.
- `homelab` runs periodic ZFS/SMART/systemd health checks and pages a
  Discord webhook the moment something looks wrong, instead of finding
  out about a failing disk or a dead service days later.
- Every machine, from partitioning to the services running on it, is
  described in Nix and reproduced from the flake. No host has hand-run
  setup steps that only exist in someone's memory.
