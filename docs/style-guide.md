# Style guide

Conventions actually in use in this repo, not aspirational ones. See
`docs/architecture.md` for the dendritic module-organization boundary.

## Formatting

`nixfmt <file>` is the formatter of record — 2-space indent, trailing
commas, `with pkgs; [ ... ]` package lists. Run it before committing;
`statix check .` and `deadnix .` catch lint issues nixfmt doesn't.

## Module registration: `flake.modules.<class>.<name>`

Every `.nix` file under `modules/` self-registers into
`flake.modules.nixos.<name>` or `flake.modules.homeManager.<name>` —
see `docs/architecture.md` for the mechanics. Two separate conventions
live inside that one registration pattern:

### Custom options modules: the `my<Name>` convention

A handful of `modules/nixos/` files (`auto-update.nix`,
`health-alerts.nix`, `iso-autobuild.nix`, `pull-deploy.nix`,
`push-deploy.nix`) define a real NixOS options surface, not just plain
config. These follow one consistent shape:

```nix
{
  flake.modules.nixos."push-deploy" =
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
    };
}
```

- Option namespace is `my<CamelCaseModuleName>` (e.g. `myPushDeploy`,
  `myAutoUpdate`) — deliberately prefixed so it can't collide with an
  upstream NixOS/home-manager option of the same shape. This is
  unrelated to the `flake.modules.nixos.<name>` registration key —
  the registration key is how the module gets pulled into a host; the
  `my<Name>` option namespace is how that module exposes its own
  settings once included.
- Always gated behind `enable` via `lib.mkIf cfg.enable`, even when a
  host is the module's only consumer — keeps the module inert by
  default and the enable/disable surface explicit at the host/profile
  level instead of buried in the module.

Reach for this pattern only when the config is genuinely parameterized
(multiple hosts want it with different settings, or it needs an
enable/disable toggle). If a host is the config's only consumer and
there's nothing to parameterize, a plain `modules/services/*.nix` file
is simpler — see `docs/architecture.md`'s module-organization section.

Everything else — `modules/services/*.nix`, `modules/profiles/*.nix`,
`modules/home-manager/*.nix`, and most of `modules/nixos/` (`kde.nix`,
`wooting.nix`, etc.) — registers into `flake.modules.*` but is a plain
config attrset inside that registration, no custom options surface.
That's the default; don't add an options layer without a reason.

### Registration key vs. filename

The `flake.modules.nixos.<name>`/`flake.modules.homeManager.<name>`
key is what other files and `modules/flake/hosts.nix` actually
reference — it does not have to match the filename, and several don't:
`modules/profiles/PC.nix` registers as `"profile-pc"`,
`modules/profiles/default.nix` as `"profile-default"`,
`modules/profiles/server.nix` as `"profile-server"`,
`modules/nixos/nfs-homelab-mounts.nix` as `"nfs-homelab-mounts"`. When
a new module's registration key would diverge from its filename in a
non-obvious way, say so directly, in the file or in the owning
folder's README — a reader who greps by filename and finds nothing
shouldn't have to reverse-engineer the key from the file's contents.
See `AGENTS.md`'s "Navigating: what does host X actually run?" for how
this is used in practice.

## Inline "why" comments

Non-obvious only — a workaround, a surprising constraint, a tradeoff,
an incident the config is defending against. Skip comments that restate
what the code already says. Real examples from this repo:

- `modules/profiles/default.nix`, on `services.tailscale`: explains
  *why* `--ssh` is deliberately left disabled, with an incident
  reference — not just "disable ssh."
- `modules/profiles/PC.nix`, on `users.groups.flatpak.gid = 998`:
  cross-references `modules/nixos/nfs-homelab-mounts.nix` to explain a
  gid collision that forced a specific pinned value.
- `modules/profiles/PC.nix`, on `sops.age.sshKeyPaths` /
  `generateKey`: explains the boot-time identity resolution problem
  the specific config shape works around.
- `modules/nixos/push-deploy.nix`, on the `elevate` option: documents
  `nixos-rebuild-ng`'s actual `--sudo` behavior, including a note that
  a prior assumption about it was wrong.
- `AGENTS.md`'s dendritic Gotchas section, on `config` shadowing in
  `modules/services/jellyfin.nix` and
  `modules/nixos/nfs-homelab-mounts.nix`: documents a real mistake made
  during the migration (reusing `config` for both the outer
  flake-parts scope and the inner NixOS module scope silently read the
  wrong object) so it isn't repeated.

The pattern worth copying across all of these: when a comment exists
because an earlier assumption turned out to be false, say so — it
stops the same wrong assumption from being made again.

## Naming

- Host names are the literal hostname (`thinkpad`, `torrent`, `homelab`,
  `vps`, `isoimage`), matching `flake.nixosConfigurations.<name>` in
  `modules/flake/hosts.nix`.
- `modules/services/*.nix` files are named after the service they
  configure (`jellyfin.nix`, `factorio.nix`), not the host that runs
  it.
- Custom module option namespaces use `my<CamelCase>` as above — this
  is separate from the `flake.modules.<class>.<name>` registration key,
  which may or may not match the filename (see above).
