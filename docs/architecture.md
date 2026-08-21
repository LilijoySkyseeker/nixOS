# Architecture

How this repo composes, one layer at a time. See `README.md` for the
quick structure guide; this is the deeper version. This describes the
**dendritic flake** structure (flake-parts + import-tree), adopted in
a repo-wide migration — see `docs/dendritic-migration-plan.md` for the
migration's own rationale/history if useful, though this document is
the current ground truth.

## The registration model

Every `.nix` file under `modules/` self-registers into
`flake.modules.nixos.<name>` or `flake.modules.homeManager.<name>`
instead of being manually listed in some other file's `imports`.
There is no central "list of every module" — the registry *is* the
file tree, discovered by `import-tree` walking `./modules` from a
single scan root in `flake.nix`:

```nix
flake-parts.lib.mkFlake { inherit inputs; } {
  imports = [
    inputs.flake-parts.flakeModules.modules
    (inputs.import-tree ./modules)
  ];
};
```

`flake.modules` only exists as an option because of that first
import (`inputs.flake-parts.flakeModules.modules`) — without it, every
file's `flake.modules.nixos.<name> = ...` definition collides on one
unmerged freeform key.

A module's file location and its registration key are independent —
see `docs/style-guide.md`'s "Registration key vs. filename" for
examples (`modules/profiles/PC.nix` registers as `"profile-pc"`, not
`"PC"`).

## Composition point: `modules/flake/hosts.nix`

This is the one file that actually answers "what does host X build."
`hosts/<name>/configuration.nix` no longer imports profiles or shared
modules by path — it's trimmed to genuinely host-local things only
(hostname, hardware config, disko, `./nvidia.nix` for thinkpad). The
shared modules a host pulls in are listed explicitly in
`modules/flake/hosts.nix`'s `flake.nixosConfigurations.<host>.modules`
list, referencing the registry (`nixosModules = config.flake.modules.nixos;`)
by key:

| Host | nixpkgs | Modules pulled in |
|---|---|---|
| `thinkpad` | unstable | `profile-pc`, `kde`, `pull-deploy`, `nfs-homelab-mounts` |
| `torrent` | unstable | `profile-pc`, `kde`, `pull-deploy`, `nfs-homelab-mounts`, `iso-autobuild` |
| `homelab` | stable | `profile-default`, `profile-server`, `auto-update`, `health-alerts`, `push-deploy`, `jellyfin`, `minecraft`, `factorio`, `octodns`, `nfs` |
| `vps` | unstable | `profile-default`, `profile-server`, `health-alerts` |
| `isoimage` | unstable | `copyparty-iso` |

`homelab`'s stable pin still means the same thing it always did: a
module option that exists in unstable may not exist yet in the pinned
stable release. `modules/flake/hosts.nix` handles this the same way
`flake.nix` used to — swapping `home-manager-stable` into `homelab`'s
`specialArgs.inputs` instead of the unstable `home-manager` every
other host gets, and giving `isoimage` a narrower `specialArgs` set
(no `inputs`) than the rest.

Per-host `specialArgs` divergence is written out explicitly per host
inside `hosts.nix`, not derived automatically — if a new host needs a
different arg set, it's a new block there, not a shared mechanism to
extend.

## Profiles: role-based layering

`modules/profiles/default.nix` registers as `"profile-default"` — the
universal base (sops-nix, tailscale, home-manager wiring, security
baseline, packages common to every host). It is not auto-applied;
every host that wants it is listed with `"profile-default"` in
`modules/flake/hosts.nix`.

Every host carrying `"profile-default"` (directly, or via `"profile-pc"`
which imports it — see below) also gets `comma`
(`programs.nix-index-database.comma.enable = true;`, same file): run
`comma <tool> [args]` (alias `,`) to fetch and run a tool from nixpkgs
in a throwaway shell without installing it — e.g. `comma lsusb -t` if
`lsusb` isn't already on the system. Fish's command-not-found handler
(`modules/home-manager/tooling.nix`) also auto-invokes `comma` when you
type an unknown command name directly. Not available on `isoimage` —
it doesn't import `"profile-default"` at all (its own minimal
`hosts.nix` module list is just `copyparty-iso`).

`modules/profiles/PC.nix` (`"profile-pc"`) and
`modules/profiles/server.nix` (`"profile-server"`) are role bundles:

- `"profile-pc"` internally `imports` `"profile-default"` alongside
  other modules (`virtual-machines`, `tooling`, `wooting`, plus
  external flake inputs like `stylix`), via a `let` capturing
  `nixosModules = config.flake.modules.nixos;` at the *outer*
  flake-parts scope — see `docs/style-guide.md`'s config-shadowing
  gotcha before editing this pattern. It also adds desktop-specific
  config and defines the `lilijoy` user. Used by `thinkpad` and
  `torrent` (both list `"profile-pc"` directly in `hosts.nix`, not
  `"profile-default"` — `"profile-pc"` already pulls it in).
- `"profile-server"` does **not** import `"profile-default"` itself —
  it's meant to be combined with it separately, same as before the
  migration. Adds headless-role config (auditd, no interactive sudo,
  root's own home-manager profile). `homelab` and `vps` both list
  `"profile-default"` and `"profile-server"` side by side in
  `hosts.nix`, not through `"profile-server"`.

## Module-organization boundary

The directory-purpose split from before the migration still holds —
what changed is the wiring mechanism (registration key vs. file-path
import), not the boundary itself:

- **`modules/nixos/` and `modules/home-manager/`** — reusable option
  modules, each registering as `flake.modules.nixos.<name>` or
  `flake.modules.homeManager.<name>`. A module only takes effect if
  `modules/flake/hosts.nix` (or a profile it composes) actually lists
  its key — being present in the directory, or even being
  syntactically valid and picked up by `import-tree`, doesn't mean any
  host uses it. Some of these (`auto-update.nix`, `health-alerts.nix`,
  `iso-autobuild.nix`, `pull-deploy.nix`, `push-deploy.nix`) define a
  real `options`/`config` surface with an enable flag — see
  `docs/style-guide.md`'s `my<Name>` convention. Others (`kde.nix`,
  `wooting.nix`, most of `modules/home-manager/`) are plain config
  attrsets with no options surface inside their registration.
- **`modules/services/`** (was top-level `services/`) — one-off NixOS
  service configs for things a specific host runs (jellyfin,
  copyparty, factorio, minecraft, octodns, nfs), each registering as
  `flake.modules.nixos.<name>` and listed per-host in
  `modules/flake/hosts.nix`. No options surface. Reach for
  `modules/services/` over an inline host-config block once the config
  is substantial enough to warrant its own file, or could plausibly
  move to another host later.
- **`modules/profiles/`** — shared config bundled by machine *role*
  (PC vs server), pulled in wholesale by every host of that role via
  its registration key in `hosts.nix`. Not meant to be selectively
  reused piece by piece the way `modules/nixos/` is.
- **`modules/flake/`** — the flake-parts plumbing layer itself, not
  reusable NixOS/home-manager config: `vars.nix` (`flake.vars` — ssh
  keys, username, domain, shared gids, the impermanence persist-root
  path), `pkgs.nix` (`flake.pkgsUnstable`/`flake.pkgsStable`,
  pre-instantiated nixpkgs), `systems.nix`, `hosts.nix` (the
  composition point above), and `devshell.nix` (the dev shell, now a
  `perSystem` module rather than the bare `mkShell` function that used
  to live at repo root).

Two hosts are still structurally unusual, same as before the
migration:

- **`vps`** pulls in no `modules/services/*` modules. It's a
  tunnel/proxy endpoint (caddy, crowdsec, wireguard, NAT/DNAT
  forwarding), and that config is written directly inline in
  `hosts/vps/configuration.nix` rather than factored into
  `modules/services/`, since none of it is reused by another host.
- **`isoimage`** skips the profile hierarchy entirely — it only pulls
  in `"copyparty-iso"`, not the tailscale/sops/security baseline every
  other host gets.

## Navigating: "what does host X actually run?"

See `AGENTS.md`'s "Navigating" section for the full walkthrough
(`hosts.nix`'s module list -> the host's own `configuration.nix` for
local settings -> each module's file, matched by registration key not
filename -> profile modules' own internal `imports`). Not duplicated
here to avoid the two drifting out of sync — that section is the
canonical version.

## Backups (homelab)

Two independent, unrelated backup paths, both defined inline in
`hosts/homelab/configuration.nix` rather than factored into a module —
worth knowing since neither is where you'd expect to look based on the
module-organization boundary above:

- **Offsite: restic -> Backblaze B2, via rclone.**
  `services.restic.backups.backblazeWeekly` backs up a hardcoded
  dataset list (`zroot/local/state`, `zdata/storage/storage` —
  `storage-bulk` was dropped from this list, it's too large to be
  worth the offsite cost) weekly. Uses rclone rather than
  restic's native S3/B2 support because that combination didn't work
  reliably with both the systemd service and the CLI wrapper
  (`createWrapper = true`, for manual `restic-backblazeWeekly` runs).
  `backupPrepareCommand`/`backupCleanupCommand` mount the most recent
  ZFS snapshot of each dataset into `/tmp/restic` before the run and
  unmount after, so restic backs up a consistent snapshot rather than
  a live, possibly-changing filesystem. Runs at `Nice = 19` /
  `CPUSchedulingPolicy = "idle"` so it never competes with foreground
  work. The rclone remote is named `backblazeDaily` inside the
  `homelab_backblaze_rclone_config` sops secret even though this job
  is weekly — a leftover from before a rename, documented inline as a
  trap: don't "fix" the name without also updating the secret (secrets
  aren't edited directly — see `docs/procedures/secrets.md`).
- **Local replication: sanoid + syncoid, ZFS-native.** `sanoid` takes
  frequent/hourly/daily snapshots of the working datasets
  (`zroot/local/state`, `zdata/storage/{storage,storage-bulk}`) and a
  longer-retention set on `zbackup`. `syncoid` replicates hourly from
  the working datasets into `zbackup`, entirely independent of the
  restic/Backblaze path above — same source data, different
  destination and mechanism, no shared config between them. Needs
  `destroy` in its `localTargetAllow` zfs delegation (beyond the
  module's default set) so it can self-heal from a partial receive
  whose source snapshot has already been pruned, rather than failing
  every run forever.
- **Remote push replication: `torrent`/`thinkpad` -> `zbackup` over
  Tailscale, via `myBackupPush`** (`modules/nixos/backup-push.nix`).
  Each source host runs its own hourly `syncoid` push (dedicated
  `backup-push` user, `zfs allow`-scoped to `send,bookmark,hold,release`
  on just its own source datasets — never root) to a dedicated
  `backup-recv` user on homelab (`zfs allow`-scoped to just its two
  `zbackup/backup/<host>` subtrees, SSH key `restrict`-flagged). Uses
  `--create-bookmark` so a long-offline source (a laptop asleep for
  weeks, or a desktop off on vacation) doesn't force a full resend once
  local retention prunes past the last pushed snapshot — the bookmark
  preserves the incremental base independently. Gated by a
  Tailscale-reachability check so an offline source no-ops instead of
  failing. Paired with `myZfsSpaceGuard`
  (`modules/nixos/zfs-space-guard.nix`) on the source hosts, which
  auto-prunes oldest local snapshots under free-space pressure (both
  hosts carry large, churny game libraries under `zroot/local/home`)
  plus a manual `zfs-emergency-prune.service` escape hatch — safe
  alongside the bookmark above since local pruning doesn't affect
  replication continuity.

**`zbackup` dataset layout**: flat `zbackup/backup/<host>/<subdir>`
convention for everything — `homelab` (`storage`, `storage-bulk`,
`state`), `thinkpad`/`torrent` (`home`, `root`). No `backup`-vs-
`backup-bulk` split (an earlier iteration of this had one, removed:
the offsite restic job never reads from `zbackup` at all, so isolating
"not offsite-eligible" data there wasn't doing anything functional).
**Code merged 2026-08-21, not yet deployed to any real host** — see
`TODO.md` for the remaining live-pool sequencing (a dataset rename
that must land atomically with the deploy) and rollout checklist. A
separate branch is also refactoring the inline `services.sanoid` block
above into a dedicated `modules/nixos/zfs-snapshots.nix` module (same
behavior, different file location, not yet landed as of this writing)
— check which has landed before linking to specific line numbers.

**Restore is not yet documented** — see
`docs/procedures/backup-restore.md`, currently a placeholder pending
the layout above actually deploying (so it documents the real thing,
not one still in flux).

## Secrets

Encrypted with sops-nix. `.sops.yaml` maps named recipient keys (one
per host/purpose, as YAML anchors) to a `path_regex` covering
`secrets/*.{yaml,json,env,ini}`. Never edit `secrets/secrets.yaml`
directly outside `sops secrets/secrets.yaml` — see
`docs/procedures/secrets.md`. Unaffected by the dendritic
migration — `secrets/` didn't move.
