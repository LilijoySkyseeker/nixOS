# modules/home-manager

Reusable home-manager modules, the user-level counterpart to
`modules/nixos/`. Same reachability caveat: a module only takes effect
if imported by some host/profile's home-manager config.

## Inventory

- `kitty.nix` — kitty terminal, configured to launch straight into
  tmux.
- `tmux.nix` — tmux config (vi keys, prefix `C-a`, resurrect/
  vim-navigator plugins); shared by every host including headless
  servers.
- `tooling.nix` — shared CLI tooling (helix editor, etc.) at the
  home-manager level.
- `virt-manager.nix` — desktop-only dconf wiring for virt-manager's
  default `qemu:///system` connection.

## Gotchas

- `virt-manager.nix` is deliberately kept separate from `tooling.nix`
  rather than folded in, because `tooling.nix` is also imported by
  `root@homelab` (headless) — don't merge them, or root@homelab picks
  up desktop-only virt-manager config it has no use for.
