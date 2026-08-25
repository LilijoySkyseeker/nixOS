# Architecture

How this repo composes, one layer at a time. See `README.md` for the quick
structure guide; this is the deeper version. This describes the **dendritic
flake** structure (flake-parts + import-tree), adopted in a repo-wide
migration — see `docs/dendritic-migration-plan.md` for the migration's own
rationale/history if useful, though this document is the current ground
truth.

## The registration model

Every `.nix` file under `modules/` self-registers into
`flake.modules.nixos.<name>` or `flake.modules.homeManager.<name>` instead of
being manually listed in some other file's `imports`. There is no central
"list of every module" — the registry *is* the file tree, discovered by
`import-tree` walking `./modules` from a single scan root in `flake.nix`:

```nix
flake-parts.lib.mkFlake { inherit inputs; } {
  imports = [
    inputs.flake-parts.flakeModules.modules
    (inputs.import-tree ./modules)
  ];
};
```

`flake.modules` only exists as an option because of that first import
(`inputs.flake-parts.flakeModules.modules`) — without it, every file's
`flake.modules.nixos.<name> = ...` definition collides on one unmerged
freeform key.

A module's file location and its registration key are independent — see
`docs/style-guide.md`'s "Registration key vs. filename" for examples
(`modules/profiles/PC.nix` registers as `"profile-pc"`, not `"PC"`).

## Composition point: `modules/flake/hosts.nix`

This is the one file that actually answers "what does host X build."
`hosts/<name>/configuration.nix` no longer imports profiles or shared
modules by path — it's trimmed to genuinely host-local things only
(hostname, hardware config, disko, `./nvidia.nix` for thinkpad). The shared
modules a host pulls in are listed explicitly in
`modules/flake/hosts.nix`'s `flake.nixosConfigurations.<host>.modules` list,
referencing the registry (`nixosModules = config.flake.modules.nixos;`) by
key:

| Host | nixpkgs | Modules pulled in |
|---|---|---|
| `thinkpad` | unstable | `profile-pc`, `kde`, `pull-deploy`, `nfs-homelab-mounts`, `zrepl`, `zfs-space-guard` |
| `torrent` | unstable | `profile-pc`, `kde`, `pull-deploy`, `nfs-homelab-mounts`, `iso-autobuild`, `zrepl`, `zfs-space-guard` |
| `homelab` | stable | `profile-default`, `profile-server`, `auto-update`, `health-alerts`, `push-deploy`, `zrepl`, `jellyfin`, `minecraft`, `factorio`, `octodns`, `nfs`, `samba` |
| `vps` | unstable | `profile-default`, `profile-server`, `health-alerts` |
| `isoimage` | unstable | `copyparty-iso` |

`homelab`'s stable pin still means the same thing it always did: a module
option that exists in unstable may not exist yet in the pinned stable
release. `modules/flake/hosts.nix` handles this the same way `flake.nix`
used to — swapping `home-manager-stable` into `homelab`'s
`specialArgs.inputs` instead of the unstable `home-manager` every other
host gets, and giving `isoimage` a narrower `specialArgs` set (no `inputs`)
than the rest.

Per-host `specialArgs` divergence is written out explicitly per host inside
`hosts.nix`, not derived automatically — if a new host needs a different arg
set, it's a new block there, not a shared mechanism to extend.

## Profiles: role-based layering

`modules/profiles/default.nix` registers as `"profile-default"` — the
universal base (sops-nix, tailscale, home-manager wiring, security baseline,
packages common to every host). It is not auto-applied; every host that
wants it is listed with `"profile-default"` in `modules/flake/hosts.nix`.

Every host carrying `"profile-default"` (directly, or via `"profile-pc"`
which imports it — see below) also gets `comma`
(`programs.nix-index-database.comma.enable = true;`, same file): run
`comma <tool> [args]` (alias `,`) to fetch and run a tool from nixpkgs in a
throwaway shell without installing it — e.g. `comma lsusb -t` if `lsusb`
isn't already on the system. Not available on `isoimage` — it doesn't
import `"profile-default"` at all (its own minimal `hosts.nix` module list
is just `copyparty-iso`).

`modules/profiles/PC.nix` (`"profile-pc"`) and `modules/profiles/server.nix`
(`"profile-server"`) are role bundles:

- `"profile-pc"` internally `imports` `"profile-default"` alongside other
  modules (`virtual-machines`, `tooling`, `wooting`, plus external flake
  inputs like `stylix`), via a `let` capturing
  `nixosModules = config.flake.modules.nixos;` at the *outer* flake-parts
  scope — see `docs/style-guide.md`'s config-shadowing gotcha before editing
  this pattern. It also adds desktop-specific config and defines the
  `lilijoy` user. Used by `thinkpad` and `torrent` (both list `"profile-pc"`
  directly in `hosts.nix`, not `"profile-default"` — `"profile-pc"` already
  pulls it in).
- `"profile-server"` does **not** import `"profile-default"` itself — it's
  meant to be combined with it separately, same as before the migration.
  Adds headless-role config (auditd, no interactive sudo, root's own
  home-manager profile). `homelab` and `vps` both list `"profile-default"`
  and `"profile-server"` side by side in `hosts.nix`, not through
  `"profile-server"`.

## Module-organization boundary

The directory-purpose split from before the migration still holds — what
changed is the wiring mechanism (registration key vs. file-path import),
not the boundary itself:

- **`modules/nixos/` and `modules/home-manager/`** — reusable option
  modules, each registering as `flake.modules.nixos.<name>` or
  `flake.modules.homeManager.<name>`. A module only takes effect if
  `modules/flake/hosts.nix` (or a profile it composes) actually lists its
  key — being present in the directory, or even being syntactically valid
  and picked up by `import-tree`, doesn't mean any host uses it. Some of
  these (`auto-update.nix`, `health-alerts.nix`, `iso-autobuild.nix`,
  `pull-deploy.nix`, `push-deploy.nix`) define a real `options`/`config`
  surface with an enable flag — see `docs/style-guide.md`'s `my<Name>`
  convention. Others (`kde.nix`, `wooting.nix`, most of
  `modules/home-manager/`) are plain config attrsets with no options
  surface inside their registration.
- **`modules/services/`** (was top-level `services/`) — one-off NixOS
  service configs for things a specific host runs (jellyfin, copyparty,
  factorio, minecraft, octodns, nfs, samba), each registering as
  `flake.modules.nixos.<name>` and listed per-host in
  `modules/flake/hosts.nix`. No options surface. Reach for
  `modules/services/` over an inline host-config block once the config is
  substantial enough to warrant its own file, or could plausibly move to
  another host later.
- **`modules/profiles/`** — shared config bundled by machine *role* (PC vs
  server), pulled in wholesale by every host of that role via its
  registration key in `hosts.nix`. Not meant to be selectively reused piece
  by piece the way `modules/nixos/` is.
- **`modules/flake/`** — the flake-parts plumbing layer itself, not
  reusable NixOS/home-manager config: `vars.nix` (`flake.vars` — ssh keys,
  username, domain, shared gids, the impermanence persist-root path),
  `pkgs.nix` (`flake.pkgsUnstable`/`flake.pkgsStable`, pre-instantiated
  nixpkgs), `systems.nix`, `hosts.nix` (the composition point above), and
  `devshell.nix` (the dev shell, now a `perSystem` module rather than the
  bare `mkShell` function that used to live at repo root).

Two hosts are still structurally unusual, same as before the migration:

- **`vps`** pulls in no `modules/services/*` modules. It's a tunnel/proxy
  endpoint (caddy, crowdsec, wireguard, NAT/DNAT forwarding), and that
  config is written directly inline in `hosts/vps/configuration.nix` rather
  than factored into `modules/services/`, since none of it is reused by
  another host.
- **`isoimage`** skips the profile hierarchy entirely — it only pulls in
  `"copyparty-iso"`, not the tailscale/sops/security baseline every other
  host gets.

## Navigating: "what does host X actually run?"

1. Start at `modules/flake/hosts.nix` — find the host's `modules = [ ... ]`
   list. That's the authoritative list of shared modules it pulls in.
2. Cross-reference `hosts/<name>/configuration.nix` for host-local settings
   (hostname, filesystems, host-specific `myPullDeploy`/`myAutoUpdate` option
   settings, etc.) not covered by any shared module.
3. For each module name in step 1, find its file — mostly
   `modules/{nixos,home-manager,profiles,services}/<name>.nix`, matched by the
   `flake.modules.nixos.<name>` / `flake.modules.homeManager.<name>` key inside
   it, **not necessarily the filename** (e.g. `modules/profiles/PC.nix`
   registers as `"profile-pc"`, `modules/nixos/nfs-homelab-mounts.nix`
   registers as `"nfs-homelab-mounts"` — grep for
   `flake.modules.nixos."?<name>"?` if the name and filename diverge; see
   `docs/style-guide.md`'s "Registration key vs. filename").
4. Profile modules (`profile-default`, `profile-pc`, `profile-server`)
   themselves pull in further modules internally — check their own `let`
   block (`nixosModules = config.flake.modules.nixos;`) and `imports`.

## Adding a new module

1. Create the file wherever fits: `modules/nixos/<name>.nix`,
   `modules/home-manager/<name>.nix`, or `modules/services/<name>.nix`.
2. Wrap its content as `flake.modules.nixos.<name> = { ... }: { ... };` (or
   `flake.modules.homeManager.<name>` for a home-manager module). The
   _inner_ function's arg list works exactly like a normal NixOS module
   (`{ config, lib, pkgs, ... }:`) — nothing changes there.
3. It is now discoverable (`import-tree` picks up any `.nix` file under
   `modules/`) but **not yet used by any host** — you still have to add it
   to the relevant host's (or profile's) module list in
   `modules/flake/hosts.nix` (or the profile file it should belong to).
   Creating the file is necessary but not sufficient.
4. If it needs `flake.vars`, other converted modules, or
   `pkgs-unstable`/`pkgs-stable`, see the Gotchas below for the
   closure-capture pattern.

## Gotchas — check these before touching `modules/`

- **`config` shadowing.** A file's outer function (`{ config, inputs, ... }:`)
  receives the _flake-parts_ `config` (so `config.flake.vars`,
  `config.flake.modules.nixos.*` work there). The _inner_ function you assign
  to `flake.modules.nixos.<name> = { config, ... }: { ... }` receives the
  NixOS module's own `config` instead — same name, different object. If you
  need the outer flake-parts `config` from inside the inner module body,
  capture it under a **different name** in a `let` before the inner function
  shadows it:
  ```nix
  { config, ... }:
  let
    vars = config.flake.vars;              # capture BEFORE shadowing
    nixosModules = config.flake.modules.nixos;
  in
  {
    flake.modules.nixos.foo = { config, ... }: {   # this `config` is NixOS's own
      users.groups.multimedia.gid = vars.gids.multimedia;  # use the captured name
      imports = [ nixosModules.tooling ];
    };
  }
  ```
  Reusing the name `config` for both would silently read the wrong object —
  this bit us once during the migration (`modules/services/jellyfin.nix`,
  `modules/nixos/nfs-homelab-mounts.nix`), and it fails loudly at eval time
  with an unrelated-looking error ("attribute 'flake' missing"), not a clear
  "you shadowed config" message.
- **`flake.modules` isn't a built-in flake-parts option.** It only exists
  because `flake.nix` imports `inputs.flake-parts.flakeModules.modules`
  explicitly. If that import is ever removed or a fresh flake-parts setup is
  copied from elsewhere without it, every `flake.modules.nixos.<name> = ...`
  definition across every file starts colliding on one unmerged freeform
  key, producing a confusing "multiple definitions for this option, use
  `lib.mkForce`" error that looks like a real option conflict but isn't —
  it's this import missing.
- **`import-tree` needs one scan root.** Don't split it into multiple
  `import-tree` calls combined with `[ ... ]` or `++` — both produce "Module
  imports can't be nested lists" / "expected a list but found a set" errors,
  because `import-tree <dir>` returns an already-structured module value,
  not a plain list. If you need to add a new top-level directory to the
  scan, move it under `modules/` rather than adding a second `import-tree`
  call.
- **A module only "counts" if `modules/flake/hosts.nix` lists it.** Deleting
  a file's _usage_ from a host means removing it from `hosts.nix`'s
  per-host list, not (necessarily) deleting the file — and conversely, a
  file existing under `modules/` proves nothing about which hosts run it.
  Always check `hosts.nix`, same as the old repo required checking each
  host's/profile's `imports` list.
- **Relative paths inside a converted file are still relative to that
  file's own location on disk**, exactly like before — moving a file (e.g.
  the `profiles/` → `modules/profiles/` move done in the migration) means
  updating any `../` path literals inside it (this repo hit this for
  `sops.defaultSopsFile` and the stylix background image path). Nix path
  literals don't become "relative to however the file is imported" under
  dendritic — this is a common misconception, not an actual behavior
  change from before.
- **Derivation hashes for a host can change even with zero functional
  difference.** Reordering which module declares a given
  `environment.systemPackages` (or similar list-typed option) entry first
  changes the final concatenated list order, which changes the built
  derivation's store hash — even though `nix store diff-closures` on the
  two outputs shows no actual content difference. Don't treat "the system
  closure hash changed" alone as proof of a functional regression; diff the
  actual built output (`nix store diff-closures`, or `diff -rq` on the
  realized store paths) before concluding something broke.
- Each host is still pinned to either `nixpkgs-stable` or
  `nixpkgs-unstable` (see the per-host table above) — check
  `modules/flake/hosts.nix` for which `inputs.nixpkgs-*.lib.nixosSystem` a
  host uses before assuming a module option exists on it.

## Backups

Three independent paths, none of them factored into `modules/services/` —
worth knowing since that's where you'd expect to look based on the
module-organization boundary above.

- **Offsite: restic -> Backblaze B2 via rclone**, inline in
  `hosts/homelab/configuration.nix`. Weekly, from mounted ZFS snapshots.
- **Local replication on homelab**: its own datasets -> `zbackup`, over
  zrepl's in-process `local` transport.
- **Remote replication**: `torrent`/`thinkpad` -> `zbackup` over SSH.
  homelab **pulls**; the source hosts are passive and hold no credential
  for homelab.

The latter two are both zrepl, configured by one shared module
(`modules/nixos/zrepl.nix`, registered `"zrepl"`, listed for all three
hosts). It replaced sanoid + syncoid and the former
`modules/nixos/backup-push.nix`.

**Full detail — roles, retention, the zrepl behaviours that are easy to get
wrong, and offline behaviour — is in [`docs/backups.md`](backups.md).**
Restore steps are in
[`docs/procedures/backup-restore.md`](procedures/backup-restore.md).

Two things worth knowing before touching anything nearby:

- `zbackup`'s layout is `zbackup/backup/<host>/<full source dataset
  path>` — zrepl extends `root_fs` with the whole source path, so it is
  deeper than the old syncoid names (`.../torrent/zroot/local/home`, not
  `.../torrent/home`). `myHealthAlerts.backupStaleness` keys off these.
- zrepl destroys any snapshot it did not create unless a `regex` keep rule
  matches it. `myZrepl.protectRegexes` (default `^blank$`) is what keeps
  the impermanence rollback snapshots alive. See `docs/backups.md`'s
  Gotchas before changing any retention rule.

## Auto-update & deploy

Three `modules/nixos/` options-surface modules, one shared safe-switch
guard, no manual "did anyone build this" step for any of the four real
hosts:

| Host | Module | What it does |
|---|---|---|
| `homelab` | `myAutoUpdate` | `flake-update-test` (branch, bump `flake.lock`, build-test, merge to master if it builds) + `auto-switch` (fetch+switch on a schedule) as two separate jobs |
| `thinkpad`, `torrent` | `myPullDeploy` | fetch+build+switch/boot on a schedule, from each host's own local checkout |
| `vps` | `myPushDeploy` | homelab builds vps's config and pushes+activates it over SSH — vps never builds locally (too resource-constrained) |

All three share one safe-switch core (`modules/flake/deploy-guards.nix`,
a plain shell fragment, not a derivation, so it's usable regardless of
which pkgs variant a host is pinned to) before any of them will
build/switch:

- **dirty/branch check + fetch+ff-only-merge** — always builds from
  verified-fresh `origin/master`, never trusts whatever's already
  checked out. This is what a 2026-08-21 incident was missing: a
  scheduled switch built from a stale/dirty local checkout and silently
  reverted a manual deploy (see `docs/DONE.md`).
- **`minSwitchInterval`** (default 7 days) — skips if
  `/nix/var/nix/profiles/system`'s own mtime (not dereferenced — the
  symlink itself is recreated fresh on every switch/boot, so its mtime
  *is* the last-activation time, no new state needed) is more recent
  than the threshold. A manual or push-deployed switch counts too, so
  it defers the next scheduled one.
- **`protectedUnits`** — skips (retries next cycle) rather than
  build/switch while any listed unit is active, so a scheduled switch
  can't kill a long-running job mid-run (homelab:
  `restic-backups-backblazeWeekly.service`, whose runs can take days).

homelab additionally exposes `auto-switch-now` — same build/switch
logic, manual-trigger only (`systemctl start --wait
auto-switch-now.service`), deliberately skipping the interval/protected-
unit guards since those exist to protect an *unattended* run, not to
silently no-op a human asking for a deploy right now.

A service running as root against a *user*-owned `flakeDir` (both PC
hosts: root has no home-manager profile there at all, unlike server
hosts) needs two things a root-owned `/etc/nixos` checkout gets for
free, both handled inside the shared guard/module: `git config --global
--add safe.directory`, and (via `myPullDeploy.sshKeyPath`) an SSH
identity to fetch with, since root has none of its own.

## Secrets

Encrypted with sops-nix. `.sops.yaml` maps named recipient keys (one per
host/purpose, as YAML anchors) to a `path_regex` covering
`secrets/*.{yaml,json,env,ini}`. Never edit `secrets/secrets.yaml` directly
outside `sops secrets/secrets.yaml` — see `docs/procedures/secrets.md`.
Unaffected by the dendritic migration — `secrets/` didn't move.
