# Architecture

How this repo composes, one layer at a time. See `README.md` for the
quick structure guide; this is the deeper version.

## Import chain

```
flake.nix (nixosConfigurations.<host>)
  -> hosts/<host>/configuration.nix
       -> profiles/*.nix
            -> modules/nixos/*.nix, modules/home-manager/*.nix, services/*.nix
```

`flake.nix` defines one `nixosSystem` per host and pins each host to
either `nixpkgs-stable` or `nixpkgs-unstable`. That pin matters: a module
option that exists in unstable may not exist yet in the pinned stable
release. Current pins:

- `thinkpad`, `torrent`, `vps`, `isoimage` — `nixpkgs-unstable`.
- `homelab` — `nixpkgs-stable`. Because of this, `flake.nix` also swaps
  in `home-manager-stable` (the home-manager release matching
  `nixos-26.05`) for homelab's `specialArgs`, instead of the unstable
  `home-manager` every other host gets — a version mismatch between
  home-manager and nixpkgs would otherwise break homelab's build.

## Profiles: role-based layering

`profiles/default.nix` is the universal base — sops-nix, tailscale,
home-manager wiring, security baseline, packages common to every host.
It is not auto-applied; every host that wants it imports it explicitly.

`profiles/PC.nix` and `profiles/server.nix` are role bundles layered on
top:

- `PC.nix` imports `default.nix` itself, then adds desktop-specific
  config (stylix theming, gaming, waydroid, etc.) and defines the
  `lilijoy` user. Used by `thinkpad` and `torrent`.
- `server.nix` does **not** import `default.nix` — it's meant to be
  combined with it separately at the host level. It adds headless-role
  config (auditd, no interactive sudo, root's own home-manager profile).
  Used by `homelab` and `vps`, both of which import `default.nix` and
  `server.nix` side by side rather than through `server.nix`.

## Per-host composition

| Host | nixpkgs | Profiles | Notable imports |
|---|---|---|---|
| `thinkpad` | unstable | `PC.nix` | `modules/nixos/kde.nix`, `pull-deploy.nix`, `nfs-homelab-mounts.nix` |
| `torrent` | unstable | `PC.nix` | same as thinkpad, plus `modules/nixos/iso-autobuild.nix` |
| `homelab` | stable | `default.nix` + `server.nix` | `modules/nixos/{auto-update,health-alerts,push-deploy}.nix`, `services/{jellyfin,minecraft,factorio,octodns,nfs}.nix` |
| `vps` | unstable | `default.nix` + `server.nix` | `modules/nixos/health-alerts.nix`; no `services/*.nix` — see below |
| `isoimage` | unstable | none | only `services/copyparty-iso.nix` |

Two hosts are structurally unusual:

- **`vps`** imports no `services/*.nix` files. It's a tunnel/proxy
  endpoint (caddy, crowdsec, wireguard, NAT/DNAT forwarding), and that
  config is written directly inline in `hosts/vps/configuration.nix`
  rather than factored into `services/`, since none of it is reused by
  another host.
- **`isoimage`** skips the profile hierarchy entirely — it's a
  standalone ISO builder that only needs `services/copyparty-iso.nix`,
  not the tailscale/sops/security baseline every other host gets.

## `modules/` vs `services/` vs `profiles/`

Not written down anywhere in the code itself, so stated explicitly here
(inferred from usage, confirmed by what each directory actually
contains):

- **`modules/nixos/` and `modules/home-manager/`** — reusable option
  modules. A module only takes effect if some host or profile actually
  imports it; being present in the directory doesn't mean it's live.
  Some of these (`auto-update.nix`, `health-alerts.nix`,
  `iso-autobuild.nix`, `pull-deploy.nix`, `push-deploy.nix`) define a
  real `options`/`config` surface with an enable flag — see
  `docs/style-guide.md` for the pattern. Others (`kde.nix`,
  `wooting.nix`, most of `modules/home-manager/`) are plain config
  attrsets with no options surface, imported wholesale.
- **`services/`** — one-off NixOS service configs for things a specific
  host runs (jellyfin, copyparty, factorio, minecraft, octodns, nfs).
  No options surface, imported directly by whichever host needs it.
  Reach for `services/` over an inline host-config block once the
  config is substantial enough to warrant its own file, or could
  plausibly move to another host later.
- **`profiles/`** — shared config bundled by machine *role* (PC vs
  server), imported wholesale by every host of that role. Not meant to
  be selectively reused piece by piece the way `modules/` is.

## Secrets

Encrypted with sops-nix. `.sops.yaml` maps named recipient keys (one
per host/purpose, as YAML anchors) to a `path_regex` covering
`secrets/*.{yaml,json,env,ini}`. Never edit `secrets/secrets.yaml`
directly outside `sops secrets/secrets.yaml` — see
`docs/procedures/secret-rotation.md`.
