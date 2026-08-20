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

- **Impermanence on `homelab`.** Root is wiped on every boot; anything
  meant to survive is explicitly opted in via
  [`environment.persistence`](./hosts/homelab/configuration.nix) —
  forgetting to add a new stateful path here means it silently
  vanishes on next reboot, not an error.
- **Two nixpkgs channels, on purpose.** Most hosts track
  `nixpkgs-unstable`; `homelab` is deliberately pinned to
  `nixpkgs-stable` because it runs stateful services (ZFS, game
  servers) where an unstable regression is costlier than missing a new
  option for a while. See `docs/architecture.md`.
- **The VPS is a decoy front, not the origin.** `vps` terminates public
  traffic (Caddy, crowdsec, Anubis proof-of-work for bots) and tunnels
  it back to `homelab` over WireGuard — `homelab` itself is never
  directly reachable from the internet.
- **Remote deploys build locally, not on the target.** Both
  `nixos-anywhere` installs and ongoing `push`/`pull` deploys build the
  closure on a beefier machine and ship it, rather than asking a small
  VPS to compile its own config and risk OOMing mid-deploy.
- **The Tailscale ACL is managed out-of-band.**
  [`docs/tailscale-acl.json`](./docs/tailscale-acl.json) is a reference
  copy of the tailnet policy actually configured in the Tailscale admin
  console — not applied by Nix, and not auto-synced. Update it by hand
  when the console policy changes.
