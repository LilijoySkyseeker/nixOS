# modules/profiles

Shared config layered onto multiple hosts by machine role. Each file
registers as `flake.modules.nixos.<name>`. See `docs/architecture.md`
for how these combine at each host and why `server.nix` doesn't import
`default.nix` itself.

## Inventory

- `default.nix` — registers as `"profile-default"`, the universal
  base: sops-nix, tailscale, home-manager wiring, security baseline,
  common CLI packages. Listed explicitly per host in
  `modules/flake/hosts.nix`.
- `PC.nix` — registers as `"profile-pc"`, desktop role: imports
  `"profile-default"` plus desktop-specific modules
  (virtual-machines, tooling, wooting), stylix theming, nvf. Defines
  the `lilijoy` user. Used by `thinkpad`, `torrent`.
- `server.nix` — registers as `"profile-server"`, headless role: locks
  down interactive nix use to root, disables sudo, enables auditd,
  adds root's own home-manager profile. Meant to be combined with
  `"profile-default"` at the host level, not through this file. Used
  by `homelab`, `vps`.

## Gotchas

- `"profile-server"` does not pull in `"profile-default"` — every
  server host's entry in `modules/flake/hosts.nix` must list both
  explicitly. Forgetting `"profile-default"` on a server host silently
  drops sops-nix/tailscale/security baseline rather than erroring.
- Registration keys don't match filenames (`PC.nix` -> `"profile-pc"`,
  not `"PC"`) — see `docs/style-guide.md`'s "Registration key vs.
  filename".
