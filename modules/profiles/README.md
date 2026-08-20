# profiles

Shared config layered onto multiple hosts by machine role. See
`docs/architecture.md` for how these combine at each host and why
`server.nix` doesn't import `default.nix` itself.

## Inventory

- `default.nix` — universal base, imported by every host: sops-nix,
  tailscale, home-manager wiring, security baseline, common CLI
  packages.
- `PC.nix` — desktop role: imports `default.nix` plus desktop-specific
  modules (virtual-machines, tooling, wooting), stylix theming, nvf.
  Defines the `lilijoy` user. Used by `thinkpad`, `torrent`.
- `server.nix` — headless role: locks down interactive nix use to
  root, disables sudo, enables auditd, adds root's own home-manager
  profile. Meant to be combined with `default.nix` at the host level,
  not through this file. Used by `homelab`, `vps`.

## Gotchas

- `server.nix` does not import `default.nix` — every server host must
  import both explicitly. Forgetting `default.nix` on a server host
  silently drops sops-nix/tailscale/security baseline rather than
  erroring.
