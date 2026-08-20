# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) and other AI
agents when working with code in this repository. It's a fast-load
summary — for the deeper *why* behind these rules, and for anything not
covered here, see `docs/`:

- `docs/architecture.md` — how hosts/profiles/modules/services compose.
- `docs/style-guide.md` — Nix conventions actually in use.
- `docs/agents.md` — the reasoning behind the rules in this file.
- `docs/procedures/` — runbooks (new host, new service, secret
  rotation, disaster recovery, keeping this documentation itself
  up to date).
- `docs/GIT_WORKFLOW.md` — git hooks/conventions.

## What this is

A flake-based NixOS/home-manager dotfiles configuration managing multiple
hosts (`thinkpad`, `torrent`, `homelab`, `vps`, `isoimage` — see
`nixosConfigurations` in `flake.nix`). Secrets are encrypted with sops-nix
(see `.sops.yaml`, `secrets/secrets.yaml`) — never commit plaintext secrets.

## Commands

Enter the dev shell first (`nix develop`, or `direnv allow` — `.envrc` is
already `use flake`); it also wires up git hooks (`core.hooksPath
.githooks`) and `pull.rebase true` via its `shellHook`.

- Build (never switch) a host to check it evaluates/compiles:
  `nixos-rebuild build --flake .#<host>` (e.g. `.#homelab`, `.#vps`,
  `.#thinkpad`, `.#torrent`). Use `dry-build` to skip realizing the
  closure. This is the closest thing this repo has to a test suite —
  there's no separate unit test runner.
- Whole-flake check: `nix flake check --no-build`.
- Lint: `statix check .` and `deadnix .`. Format: `nixfmt <file>`.
- Shell scripts (`.githooks/*`): `shellcheck` / `shfmt`.
- Readable diff between the current system and a built closure before
  ever switching: `nvd diff /run/current-system <new-closure-path>`.
- Remote installs: `nixos-anywhere --flake .#<host> root@<ip>` (see
  "Before making changes" below for build-locality caveats).

Never run `nixos-rebuild switch` or push a build to a live remote host
unprompted.

## Repo layout — dendritic flake organization

See `docs/architecture.md` for the full registration model, per-host
composition table, and module-organization boundary explained in
narrative detail — updated for the current dendritic structure.

This flake uses the **dendritic pattern** (flake-parts + import-tree):
every `.nix` file under `modules/` self-registers into
`flake.modules.nixos.<name>` or `flake.modules.homeManager.<name>` instead
of being manually listed in some other file's `imports`. There is no
central "list of every module" to scan — the registry *is* the file tree.

- `flake.nix` — thin entry point:
  `flake-parts.lib.mkFlake { inherit inputs; } { imports = [
  inputs.flake-parts.flakeModules.modules (inputs.import-tree ./modules)
  ]; };`. `import-tree` walks `./modules` and imports every `.nix` file it
  finds as a flake-parts module. There is no other flake.nix logic — if
  you're looking for where `vars`/`pkgs-unstable`/`nixosConfigurations`
  are defined, they're NOT here, they're one of the files below.
- `modules/flake/` — the flake-parts plumbing layer, not reusable
  NixOS/home-manager config:
  - `vars.nix` — sets `flake.vars` (ssh keys, username, domain, shared
    gids, the impermanence persist-root path). Read via
    `config.flake.vars` from other files.
  - `pkgs.nix` — sets `flake.pkgsUnstable` / `flake.pkgsStable`
    (pre-instantiated nixpkgs, replaces the old `pkgs-unstable`/
    `pkgs-stable` `let`-bindings that used to live in `flake.nix`).
  - `systems.nix` — flake-parts' `systems = [ "x86_64-linux" ]`.
  - `hosts.nix` — **the actual composition point.** Defines
    `flake.nixosConfigurations` by explicitly listing which
    `flake.modules.nixos.*` entries each of the 5 hosts pulls in, plus
    each host's divergent `specialArgs` (homelab's `home-manager-stable`
    swap, isoimage's narrower arg set). **This is the file to check when
    you need to know "what does host X actually build" — the answer is
    not in `hosts/<name>/configuration.nix` alone anymore.**
  - `devshell.nix` — the dev shell, now a `perSystem` module (was a bare
    `mkShell` function at repo root before the migration).
- `hosts/<name>/configuration.nix` — trimmed down to genuinely
  **host-local** things only: hostname, hardware-specific config, and
  `imports = [ ./hardware-configuration.nix ./disko.nix ... ]` (and
  `./nvidia.nix` for thinkpad). It no longer imports profiles or shared
  modules by path — those are supplied externally by `modules/flake/hosts.nix`.
- `modules/profiles/` (was top-level `profiles/`) — `default.nix`
  (universal), `PC.nix`/`server.nix` (role-specific). Each is now
  `flake.modules.nixos."profile-default"` /
  `"profile-pc"` / `"profile-server"`. `PC.nix` and `server.nix` pull in
  other modules via `config.flake.modules.nixos.*` /
  `config.flake.modules.homeManager.*`, captured in a `let` at the
  *outer* (flake-parts) scope — see "Gotchas" below before editing these.
- `modules/nixos/` and `modules/home-manager/` (home-manager ones were
  already here; nixos ones moved from top-level `modules/nixos/`) —
  reusable option modules, each `flake.modules.nixos.<name>` /
  `flake.modules.homeManager.<name>`. A module only takes effect if
  `modules/flake/hosts.nix` (or a profile it composes) actually lists it
  — **the module existing in the tree does not mean any host uses it.**
  Check `modules/flake/hosts.nix`'s per-host module list, not just
  whether the file exists.
- `modules/services/` (was top-level `services/`) — NixOS service
  configs run on the homelab (jellyfin, copyparty, factorio, etc.), each
  `flake.modules.nixos.<name>`, listed per-host in `modules/flake/hosts.nix`.
- `files/` — static assets (keyboard layouts, EQ profiles, images). Many
  of these are consumed by external tools (VIA/Vial, Picard, monitor ICC
  profile loaders) rather than by Nix — don't assume "not referenced from
  a `.nix` file" means "unused."

### Navigating: "what does host X actually run?"

1. Start at `modules/flake/hosts.nix` — find the host's `modules = [ ... ]`
   list. That's the authoritative list of shared modules it pulls in.
2. Cross-reference `hosts/<name>/configuration.nix` for host-local
   settings (hostname, filesystems, host-specific `myPullDeploy`/
   `myAutoUpdate` option settings, etc.) not covered by any shared module.
3. For each module name in step 1, find its file — mostly
   `modules/{nixos,home-manager,profiles,services}/<name>.nix`, matched
   by the `flake.modules.nixos.<name>` / `flake.modules.homeManager.<name>`
   key inside it, **not necessarily the filename** (e.g.
   `modules/profiles/PC.nix` registers as `"profile-pc"`,
   `modules/nixos/nfs-homelab-mounts.nix` registers as
   `"nfs-homelab-mounts"` — grep for `flake.modules.nixos."?<name>"?` if
   the name and filename diverge).
4. Profile modules (`profile-default`, `profile-pc`, `profile-server`)
   themselves pull in further modules internally — check their own `let`
   block (`nixosModules = config.flake.modules.nixos;`) and `imports`.

### Adding a new module

1. Create the file wherever fits: `modules/nixos/<name>.nix`,
   `modules/home-manager/<name>.nix`, or `modules/services/<name>.nix`.
2. Wrap its content as `flake.modules.nixos.<name> = { ... }: { ... };`
   (or `flake.modules.homeManager.<name>` for a home-manager module). The
   *inner* function's arg list works exactly like a normal NixOS module
   (`{ config, lib, pkgs, ... }:`) — nothing changes there.
3. It is now discoverable (`import-tree` picks up any `.nix` file under
   `modules/`) but **not yet used by any host** — you still have to add
   it to the relevant host's (or profile's) module list in
   `modules/flake/hosts.nix` (or the profile file it should belong to).
   Creating the file is necessary but not sufficient.
4. If it needs `flake.vars`, other converted modules, or `pkgs-unstable`/
   `pkgs-stable`, see the Gotchas below for the closure-capture pattern.

### Gotchas — check these before touching `modules/`

- **`config` shadowing.** A file's outer function
  (`{ config, inputs, ... }:`) receives the *flake-parts* `config` (so
  `config.flake.vars`, `config.flake.modules.nixos.*` work there). The
  *inner* function you assign to `flake.modules.nixos.<name> = { config,
  ... }: { ... }` receives the NixOS module's own `config` instead — same
  name, different object. If you need the outer flake-parts `config`
  from inside the inner module body, capture it under a **different
  name** in a `let` before the inner function shadows it:
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
  Reusing the name `config` for both would silently read the wrong
  object — this bit us once during the migration
  (`modules/services/jellyfin.nix`, `modules/nixos/nfs-homelab-mounts.nix`), and
  it fails loudly at eval time with an unrelated-looking error ("attribute
  'flake' missing"), not a clear "you shadowed config" message.
- **`flake.modules` isn't a built-in flake-parts option.** It only exists
  because `flake.nix` imports `inputs.flake-parts.flakeModules.modules`
  explicitly. If that import is ever removed or a fresh flake-parts
  setup is copied from elsewhere without it, every
  `flake.modules.nixos.<name> = ...` definition across every file starts
  colliding on one unmerged freeform key, producing a confusing "multiple
  definitions for this option, use `lib.mkForce`" error that looks like a
  real option conflict but isn't — it's this import missing.
- **`import-tree` needs one scan root.** Don't split it into multiple
  `import-tree` calls combined with `[ ... ]` or `++` — both produce
  "Module imports can't be nested lists" / "expected a list but found a
  set" errors, because `import-tree <dir>` returns an already-structured
  module value, not a plain list. If you need to add a new top-level
  directory to the scan, move it under `modules/` rather than adding a
  second `import-tree` call.
- **A module only "counts" if `modules/flake/hosts.nix` lists it.**
  Deleting a file's *usage* from a host means removing it from
  `hosts.nix`'s per-host list, not (necessarily) deleting the file — and
  conversely, a file existing under `modules/` proves nothing about
  which hosts run it. Always check `hosts.nix`, same as the old repo
  required checking each host's/profile's `imports` list.
- **Relative paths inside a converted file are still relative to that
  file's own location on disk**, exactly like before — moving a file
  (e.g. the `profiles/` → `modules/profiles/` move done in the
  migration) means updating any `../` path literals inside it (this repo
  hit this for `sops.defaultSopsFile` and the stylix background image
  path). Nix path literals don't become "relative to however the file is
  imported" under dendritic — this is a common misconception, not an
  actual behavior change from before.
- **Derivation hashes for a host can change even with zero functional
  difference.** Reordering which module declares a given
  `environment.systemPackages` (or similar list-typed option) entry
  first changes the final concatenated list order, which changes the
  built derivation's store hash — even though `nix store diff-closures`
  on the two outputs shows no actual content difference. Don't treat "the
  system closure hash changed" alone as proof of a functional regression;
  diff the actual built output (`nix store diff-closures`, or `diff -rq`
  on the realized store paths) before concluding something broke.
- Each host is still pinned to either `nixpkgs-stable` or
  `nixpkgs-unstable` (unchanged by the migration) — check
  `modules/flake/hosts.nix` for which `inputs.nixpkgs-*.lib.nixosSystem`
  a host uses before assuming a module option exists on it.

## Before making changes

- Before creating a new branch or worktree, `git fetch origin master &&
  git pull origin master` (or fast-forward the local `master`) so the
  new branch/worktree is cut from up-to-date `master`, not a stale
  local copy.
- Check which `nixpkgs` channel (stable vs unstable) a host uses in
  `flake.nix` before adding a module option — options can exist in one
  and not the other.
- Before deleting a file, `grep -rn` the whole repo for its path/name to
  confirm it's genuinely unreferenced. A file only being unimported from
  `flake.nix`'s reachable graph counts as dead; being unreferenced *by
  Nix* does not automatically mean dead for things in `files/`.
- Validate changes with `nix flake check --no-build` when feasible. Note
  known pre-existing failures before attributing a new one to your
  change (e.g. compare against `git stash` / previous commit).
- Don't build or switch a live host's configuration remotely — that's
  the user's call, not something to run unprompted.
- When installing with `nixos-anywhere`, build on the local machine
  rather than the remote target whenever possible (leave
  `--build-on-remote` unset). Remote targets, especially small/cheap
  VPS instances, can be memory- or disk-constrained enough that
  building the closure there risks hanging or OOMing mid-install.
- Same for `nixos-rebuild --target-host <host>`: prefer building
  locally and pushing the closure (leave `--build-host` unset/local)
  rather than `--build-host <host>`, for the same reason.
- On a fresh `nixos-anywhere` install, pass
  `--generate-hardware-config nixos-generate-config <path>` (e.g.
  `hosts/<host>/hardware-configuration.nix`) so the real target's
  hardware config is captured instead of relying on a
  stale/scaffolded one. Point `<path>` at the checkout/worktree
  currently being worked on — not necessarily the main checkout — so
  the generated file lands where it'll actually get committed from.
- If the host's SSH access depends on a secret (e.g. Tailscale) that
  sops-nix decrypts at boot, pre-generate that host's SSH host key
  locally before install and pass it via `--extra-files` so its age
  key can be enrolled and secrets re-encrypted *before* first boot —
  otherwise sops can't decrypt anything (including the secret needed
  to reach the box at all) on a fresh install. See `hosts/vps/README.md`
  step 1. Never generate or stage that key material inside a tracked
  repo checkout, even gitignored — keep it entirely outside the repo.
- Full new-host runbook: `docs/procedures/new-host.md`. New service:
  `docs/procedures/new-service.md`. Secret rotation:
  `docs/procedures/secret-rotation.md`. Connecting to a remote host —
  key model, which hosts are Tailscale-only, the `vps-deploy` forced-
  command account: `docs/procedures/remote-access.md`. Keeping docs
  themselves in sync with the repo (routine updates, periodic audits,
  full rewrites after a structural refactor):
  `docs/procedures/updating-documentation.md`.
- Noticed a documentation issue you're not fixing right now (spotted
  mid-task, out of scope, or too big to fix inline)? Log it to
  `TODO.md`'s Active section immediately, in the same session — don't
  leave it to memory. See
  `docs/procedures/updating-documentation.md`'s "Flag issues
  immediately" section for what to include.

## Commit conventions

- Use [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, etc.) for the subject
  line.
- Write commit messages for **human readability**: explain *why* a change
  was made, not just what changed — the diff already shows what changed.
  Prefer short prose/bullets over restating file names.
- Only commit when the user explicitly asks for it.
- **After every commit, print the full commit message back to the user**
  (e.g. via `git show -s --format=%B HEAD` or by echoing what was just
  written) so they can review it without having to run git themselves.
- Once a branch's content has landed on `master`, prune it if safe (see
  `docs/GIT_WORKFLOW.md`'s "Day to day" section) — don't leave merged
  branches lying around.
