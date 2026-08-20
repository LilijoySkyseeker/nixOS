# Style guide

Conventions actually in use in this repo, not aspirational ones. See
`docs/architecture.md` for the module/service/profile boundary.

## Formatting

`nixfmt <file>` is the formatter of record — 2-space indent, trailing
commas, `with pkgs; [ ... ]` package lists. Run it before committing;
`statix check .` and `deadnix .` catch lint issues nixfmt doesn't.

## Custom modules: the `my<Name>` convention

A handful of modules in `modules/nixos/` (`auto-update.nix`,
`health-alerts.nix`, `iso-autobuild.nix`, `pull-deploy.nix`,
`push-deploy.nix`) define a real NixOS options surface rather than being
plain config. These follow one consistent shape:

```nix
{ config, lib, ... }:
let
  cfg = config.myPushDeploy;
in
{
  options.myPushDeploy = {
    enable = lib.mkEnableOption "...";
    # ...other options via lib.mkOption
  };

  config = lib.mkIf cfg.enable {
    # ...
  };
}
```

- Option namespace is `my<CamelCaseModuleName>` (e.g. `myPushDeploy`,
  `myAutoUpdate`) — deliberately prefixed so it can't collide with an
  upstream NixOS/home-manager option of the same shape.
- Always gated behind `enable` via `lib.mkIf cfg.enable`, even when a
  host is the module's only consumer — keeps the module inert by
  default and the enable/disable surface explicit at the host/profile
  level instead of buried in the module.

Reach for this pattern only when the config is genuinely parameterized
(multiple hosts want it with different settings, or it needs an
enable/disable toggle). If a host is the config's only consumer and
there's nothing to parameterize, a plain `services/*.nix` file is
simpler — see `docs/architecture.md`'s `modules/` vs `services/` split.

Everything else — `services/*.nix`, `profiles/*.nix`,
`modules/home-manager/*.nix`, and most of `modules/nixos/` (`kde.nix`,
`wooting.nix`, etc.) — is a plain config attrset setting NixOS/
home-manager options directly, no custom options surface. That's the
default; don't add an options layer without a reason.

## Inline "why" comments

Non-obvious only — a workaround, a surprising constraint, a tradeoff,
an incident the config is defending against. Skip comments that restate
what the code already says. Real examples from this repo:

- `profiles/default.nix`, on `services.tailscale`: explains *why*
  `--ssh` is deliberately left disabled, with an incident reference —
  not just "disable ssh."
- `profiles/PC.nix`, on `users.groups.flatpak.gid = 998`: cross-
  references `modules/nixos/nfs-homelab-mounts.nix` to explain a gid
  collision that forced a specific pinned value.
- `profiles/PC.nix`, on `sops.age.sshKeyPaths` / `generateKey`: explains
  the boot-time identity resolution problem the specific config shape
  works around.
- `modules/nixos/push-deploy.nix`, on the `elevate` option: documents
  `nixos-rebuild-ng`'s actual `--sudo` behavior, including a note that
  a prior assumption about it was wrong.

That last one is the pattern worth copying: when a comment exists
because an earlier assumption turned out to be false, say so — it stops
the same wrong assumption from being made again.

## Naming

- Host names are the literal hostname (`thinkpad`, `torrent`, `homelab`,
  `vps`, `isoimage`), matching `nixosConfigurations.<name>` in
  `flake.nix`.
- `services/*.nix` files are named after the service they configure
  (`jellyfin.nix`, `factorio.nix`), not the host that runs it.
- Custom module option namespaces use `my<CamelCase>` as above.
