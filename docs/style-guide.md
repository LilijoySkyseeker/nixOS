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
there's nothing to parameterize, a plain `modules/*/*.nix` file
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
See `docs/architecture.md`'s "Navigating: what does host X actually run?"
for how this is used in practice.

## Why context: the plan file, not comments

Non-obvious rationale — a workaround, a surprising constraint, a
tradeoff, an incident the config is defending against — belongs in the
task's plan file (`docs/skills/plan/SKILL.md`), not an inline comment. A
one-line citation pointing at it is fine inline (`# plan:
<date>-<slug>.md#D2`) — that's a citation, not the rationale itself, and
is exempt from the "mechanics/labeling only" rule below. Anchor the
citation to the specific `D`/`G`/`F` id it's about, not just the bare
filename — a reader shouldn't have to search the whole plan to find the
one section that explains this line. For a trivial change that never got
a plan file, a short note in the commit message is still fine; see
`docs/agents.md` for why the plan file is the primary home for anything
that went through the `workflow` gate.

Inline comments (beyond a citation pointer) are for mechanics/labeling
only — see below.

## Inline comments

- Lowercase start, no terminal period, terse fragments over full
  sentences: `# DigitalOcean's only world facing interface`,
  `# zram instead to prevent secrets leakage`.
- Comment sits directly above the code it explains, no blank line
  between them; a blank line separates it from the previous unrelated
  block. Short annotations on a single value may trail on the same
  line instead (`sourcePort = 19132; # minecraft: geyser (bedrock
  edition)`, `51820 # wireguard`).
- Name the actual actor/constraint causing the behavior rather than
  describing generically: `# DigitalOcean's hypervisor virtual switch
  needs cloud-init to run and "register"/arm the droplet's network
  before it'll pass any traffic for that NIC`.
- A single-line comment can act as a section banner introducing a
  block of related settings, often `# tool: purpose` when the
  tool/subsystem isn't already obvious from the surrounding attribute
  names: `# crowdsec: watches sshd/caddy logs, bans abusive IPs via
  the firewall bouncer`.
- Multi-line embedded shell scripts get one comment per branch,
  phrased as what triggers it and naming the calling tool:
  `# nixos-rebuild's pre-activation sanity check`.
- Inline `# TODO:` marks known-incomplete config on the same line as
  the affected declaration: `sops.secrets.vps_caddy_env = { }; # TODO:
  populate with DNS provider API token if using DNS-01 challenges`.
- See `hosts/vps/configuration.nix` for a dense example of all of the
  above in one file.

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
