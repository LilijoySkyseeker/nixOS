# Before making changes

Checks and hard-confirm rules that apply across most tasks in this repo,
consolidated in one place rather than scattered per-topic.

## Checks before you start

- **Pull first.** `git fetch origin master && git pull origin master` (or
  fast-forward local `master`) before creating a new branch or worktree, so
  it's cut from up-to-date `master`. See `docs/GIT_WORKFLOW.md`.
- **Check the nixpkgs channel.** A module option can exist on
  `nixpkgs-unstable` and not yet on `nixpkgs-stable` (`homelab`'s pin) — see
  `docs/architecture.md`'s per-host table before assuming a host has an
  option.
- **Before deleting a file**, `grep -rn` the whole repo for its path/name.
  Being unimported from `flake.nix`'s reachable graph counts as dead; being
  unreferenced _by Nix_ does not — files under `files/` are often consumed
  by external tools (VIA/Vial, Picard, an ICC profile loader) instead.
- **Validate with `nix flake check --no-build`** when feasible. Compare
  against `git stash`/the previous commit to rule out pre-existing failures
  before attributing a new one to your change. Full detail on which
  validation layer to reach for: `docs/procedures/testing-changes.md`.

## Hard-confirm actions — don't do these unprompted

- **Never `nixos-rebuild switch`**, or push a build to a live remote host.
  Build-only proves the config evaluates/compiles; switching changes what's
  running on a machine someone may be relying on right now. See
  `docs/agents.md` for why this is load-bearing here.
- **Never restart or reboot `torrent`** (the user's local daily-driver)
  without explicit confirmation, even to fix something like a crashed
  system service — work around it (e.g. build on a different host over SSH)
  or ask the user to restart it themselves. Same tier as `git push --force`
  or `rm -rf`.
- **Never install or invoke the real `sudo` binary/package** on any managed
  host — all hosts alias `sudo` to `run0`. See `docs/hardening.md`.
- Editing or decrypting `secrets/*` yourself — see
  `docs/procedures/secrets.md`.

## If you already made a destructive local mistake

Every host running `myZrepl` (`homelab`, `torrent`, `thinkpad` — see
`docs/backups.md`) snapshots its own datasets locally every **5 minutes**,
independent of whether replication to `zbackup` ever runs. That includes
`zroot/local/home`, so an accidental `rm -rf`/overwrite in a home directory
(e.g. this repo's own checkout, or a worktree under `.claude/worktrees/`) is
almost always recoverable from the same host, in under a minute, without
touching `zbackup` or another machine at all — the on-box `ceiling` preset
keeps roughly 32 days of these.

Recover with the same recipe as "Recovering a few files" in
`docs/procedures/backup-restore.md`: find the most recent snapshot from
*before* the mistake under `<mountpoint>/.zfs/snapshot/<zrepl_timestamp>/...`
(`zfs list -t snapshot <dataset>` to see what's available), then `cp -a` the
missing path back out and verify with `diff -rq` against the snapshot before
trusting it. This is read-only against the snapshot — it carries none of the
risk a `zfs rollback` would.

Still tell the user what happened and what you did to fix it — recoverability
doesn't change the "confirm before destructive actions" rule going forward,
it's a safety net for when that rule was missed, not a reason to be looser
about destructive commands.

## Remote installs and deploys

- **Test in a local VM before real hardware/cloud** when feasible
  (`nix build .#nixosConfigurations.<host>.config.system.build.vm`) — cloud
  installs are slow/costly to iterate on, a local VM boots in under a
  minute and reproduces most boot/activation/service behavior. Clean up VM
  scratch artifacts (qcow2/log files, leftover qemu processes) once done.
  Full guide, including which unit failures are just VM artifacts and can
  be ignored: `docs/procedures/vm-testing.md`.
- **Build locally, not on the remote target.** For `nixos-anywhere`, leave
  `--build-on-remote` unset; for `nixos-rebuild --target-host`, leave
  `--build-host` unset. Small/cheap remote targets (a VPS) can be memory- or
  disk-constrained enough that building the closure there risks hanging or
  OOMing mid-install.
- Full new-host steps (hardware-config generation, pre-generating an SSH
  host key so sops can decrypt on first boot, etc.):
  `docs/procedures/new-host.md`.

## Documentation hygiene

Noticed a documentation issue you're not fixing right now (spotted
mid-task, out of scope, or too big to fix inline)? Log it to `TODO.md`'s
Active section immediately, in the same session — don't leave it to
memory. See `docs/procedures/updating-documentation.md`'s "Flag issues
immediately" section for what to include.
