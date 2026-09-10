---
slug: vm-verify-docker-userns-remap-for-the-game-server-containers
created: 2026-09-03
status: done
frozen: true
---

# VM-verify docker userns-remap for the game-server containers

## Original plan

Item 4 in `docs/audits/2026-08-26/RESUME.md`'s "Agent-doable, unblocked"
list (`F-P4-07`): `virtualisation.docker.daemon.settings` has no
`userns-remap`, so container uid 0 is host uid 0 on every bind mount for
`factorio-main` and `minecraft-vanilla-plus`. Unlike the other resource-
ceiling items in the same finding (already done, D15), this one was
flagged as needing its own VM test because it re-maps *existing* volume
ownership — get it wrong and the two live game servers lose access to
their own save data. Root-cause the mechanism, build a reusable module,
VM-test it with a real dockerd + real userns-remap + a pre-seeded bind
mount standing in for the real data, then it's the user's call whether
to deploy.

## State

**2026-09-03, `tests/docker-userns-remap.nix` fully green.**
`nix build .#checks.x86_64-linux.docker-userns-remap -L` passes all 7
subtests: dockremap's subuid range and dockerd's own
`userns` security option both render; a pre-seeded bind-mount tree
(standing in for `/srv/factorio/main`'s real 845:845) gets migrated to
`100845:100845`; the running container's own PID 1 is confirmed, from
the *host's* `/proc`, to be uid `100000` (not `0`); the container reads
its migrated pre-existing data and writes new data into the same
directory; a second run of the migration unit changes nothing
(idempotent); and the `plain` negative-control node -- identical
container and pre-seeded data, `myDockerUserns` never enabled --
confirms the vulnerability this item exists to fix (container root
really is host uid 0) and that its pre-seeded ownership is untouched.
Five real, distinct bugs found and fixed by iterating against actual
failures (G7-G9 plus two more folded into this State line: G7 a false
green from `tee` masking a real error, G8 a wrong assumption about where
NixOS puts `daemon.json`, G9 a wrong expected uid in the test's own
assertion -- not a module bug).

`modules/nixos/docker-userns-remap.nix` is wired into homelab
(`hosts/homelab/configuration.nix` sets only `myDockerUserns.enable =
true`; the two real migrations for `/srv/factorio/main` and
`/srv/minecraft/vanilla-plus` live in `factorio.nix`/`minecraft.nix`
themselves, moved there by the `/simplify` pass below, G10) and
build-verified on all five `nixosConfigurations`. **Not deployed
anywhere** — VM-verified is not
deployed, same rule as every other item in this audit; that is a
separate, explicit, still-open user decision. One real operational
consequence to flag before anyone says yes: per G4, enabling this
requires a full `dockerd` restart (not live-reloadable) and both game
containers will need to re-pull their images from the internet on first
activation, since Docker's storage path changes per remap user — this
is disruptive, not a quiet config flip, and the user should know that
going in.

## Progress
- [x] Root-cause how NixOS's docker module handles `userns-remap` (G1)
- [x] Confirm real on-disk ownership of both bind mounts on homelab (G3)
- [x] Confirm Docker's own documented behavior for storage/bind-mounts/
  restart-requirement (G4)
- [x] Write `modules/nixos/docker-userns-remap.nix`
- [x] Wire it into `hosts/homelab/configuration.nix` (build-verify only)
- [x] Write `tests/docker-userns-remap.nix`
- [x] Get it green
- [x] Update `docs/hardening.md` / `docs/audits/2026-08-26/RESUME.md`
- [x] Run `/simplify` (4 parallel reviews), apply real fixes, re-verify (G10)
- [x] Commit and push

## Decisions (D)

## Gotchas (G)

### G1 -- NixOS's docker module has zero special-case handling for userns-remap
Checked the pinned stable nixpkgs source directly
(`nixos/modules/virtualisation/docker.nix`, rev `e4bae1bd10c9c57b2cf517953ab70060a828ee6f`):
`daemon.settings` is a pure freeform passthrough to `daemon.json`
(`settingsFormat.generate`). There is no NixOS-level `userns-remap`
option, no automatic `dockremap` user, nothing. Whatever Docker itself
expects to find on disk has to be provided declaratively by this repo.

### G2 -- `userns-remap = "default"` is unreliable on a `mutableUsers = false` host; needs a real declared user
Docker's own "default" auto-provisioning writes a `dockremap` entry into
`/etc/subuid`/`/etc/subgid` at daemon startup. On NixOS with
`mutableUsers = false` (this repo's setting), those files are generated
declaratively from `users.users.<n>.subUidRanges`/`subGidRanges` on every
switch (confirmed in `nixos/modules/config/users-groups.nix`) --
anything Docker itself tried to write there would be clobbered on the
next switch, or fail outright since the file is regenerated, not
appended to. The reliable approach is a real `users.users.dockremap`
with explicit, fixed `subUidRanges`/`subGidRanges`, and
`userns-remap = "dockremap"` (a name, not `"default"`).

### G3 -- confirmed live: both bind mounts are single-owner trees, at exactly the uids their images bake in
Read directly off homelab (`stat`, not assumed): `/srv/factorio/main` is
uniformly `845:845` (the `factoriotools/factorio` image's baked-in uid,
matching the comment already in `factorio.nix`); `/srv/minecraft/vanilla-plus`
is uniformly `1000:1000` (itzg image default). Neither directory has any
file at a different owner. This matters for the migration design below
(G5) -- a `chown --from=<old> -R <new>` is both sufficient and safe here,
since there's nothing else at those trees to accidentally touch.

### G4 -- confirmed against Docker's own docs: enabling this is disruptive, not a quiet config flip
Fetched `docs.docker.com/engine/security/userns-remap/` directly rather
than assuming. Four load-bearing facts:
1. **Storage path changes per remap user** -- Docker stores
   images/containers under `/var/lib/docker/<uid>.<gid>/` once remap is
   active, which **masks existing pulled images**. Both
   `factoriotools/factorio:2.1.14` and `itzg/minecraft-server` will need
   re-pulling from the internet on first activation -- not a data-loss
   risk (they're public images, not the bind-mounted save data), but a
   real network dependency and a startup delay the VM test cannot
   exercise offline (see G6).
2. **Bind-mount ownership is never auto-adjusted.** Docker's own docs
   say so explicitly and recommend avoiding the combination entirely --
   this repo can't avoid it (both game servers need persistent bind
   mounts), so the migration in G5 is not optional, it is the whole
   point of this item.
3. **Not live-reloadable.** Changing `userns-remap` requires a full
   `dockerd` restart, which is what `nixos-rebuild switch` will do when
   the rendered `daemon.json` changes -- meaning both game containers go
   down and come back up as part of any real deploy of this change, not
   a graceful rolling update.
4. **Daemon-wide**, with a per-container `--userns=host` escape hatch
   this repo does not need (both containers should get the remap).

### G5 -- migration design: `chown --from=<old-uid>:<old-gid> -R <new-uid>:<new-gid> <path>`, not a blind recursive chown
`--from` scopes the chown to files currently owned by the given
owner:group and leaves everything else untouched -- both surgical (only
touches what actually needs migrating) and naturally idempotent (after
the first successful run, nothing on the tree still matches
`<old-uid>:<old-gid>`, so a second run is a real no-op, not just a fast
one). `<new-uid>`/`<new-gid>` are `<old> + subUidStart`/`<old> + subGidStart`,
derived from the module's own remap-offset config rather than
hand-computed per path, so the two can't drift independently.

### G6 -- the VM test cannot use the real game-server images (no network in the sandboxed test VM)
Same constraint that blocked `push-deploy-vps`'s VM test until a
declared `path:` input worked around it (see
`2026-09-01-vm-verify-push-deploy-vps-sandboxing-f-p7-06-wave-2-item-2-6.md`,
G2). `pkgs.dockerTools.buildImage` builds a minimal test image entirely
from the Nix store, no network required, `docker load`-able inside the
VM -- this is the standard NixOS-VM-test pattern for exercising real
`dockerd` behavior offline, and is what this test uses instead of the
real `factoriotools/factorio`/`itzg/minecraft-server` images.

### G7 -- `nix build ... | tee log` gave a false green: `tee`'s exit code, not the build's
First `nix build .#checks.x86_64-linux.docker-userns-remap -L | tee ...`
reported exit 0, but the log's only content was `error: Path
'tests/docker-userns-remap.nix' ... is not tracked by Git` -- flakes only
see git-tracked files, and the new test/module files hadn't been `git
add`ed yet. The shell reported the pipeline's exit status as `tee`'s
(always 0), not `nix build`'s -- the exact `if cmd | tail` trap already
documented in `docs/audits/2026-08-26/RESUME.md`'s "Rules and traps",
just with `tee` instead of `tail`. Fix: `git add` before building, and
redirect with `>` + a separate `echo "EXIT: $?"` rather than piping
through anything when the exit code itself matters.

### G8 -- NixOS never writes `/etc/docker/daemon.json`; it passes `--config-file=<store path>` on the unit's own ExecStart
First real VM-test failure: `cat /etc/docker/daemon.json` -> "No such
file or directory". Checked the pinned nixpkgs source rather than
guessing a different path: `docker.nix` renders the settings via
`settingsFormat.generate "daemon.json" cfg.daemon.settings` and passes
that store path straight to `dockerd --config-file=...` -- there is no
`/etc/docker` anywhere in the module. Fixed by asserting against
`docker info --format '{{.SecurityOptions}}'` instead (contains
`name=userns` when the remap is active) -- dockerd's own live view of
its effective config, which doesn't care where that config came from.

### G9 -- test assertion bug, not a module bug: the probe's PID 1 is container uid 0, not the bind-mount data's uid 845
Third real VM-test failure, but the fault was the test's own assertion,
not `docker-userns-remap.nix`: `host_uid_of_container` correctly read
back `100000`, and the assertion wrongly expected `100845`. The probe
script's `/bin/sh -c "..."` entrypoint never drops privileges, so it
*is* container root (uid 0) for its whole life -- that maps to
`0 + subIdStart = 100000`. `845` is only the bind-mount *data*'s uid,
unrelated to what uid the process itself runs as. Fixed the assertion,
not the module.

### G10 -- `/simplify`: two real fixes applied, two suggestions correctly declined
Four parallel reviews (reuse, simplification, efficiency, altitude).
Reuse found nothing (checked against `zfs-dataset-properties.nix`'s
oneshot shape, `vars.nix` for a shared uid/gid constant that doesn't
exist, and `docker-publish-guard.nix`'s inline-test-image pattern --
all already followed or genuinely not applicable).

**Applied:**
- **Efficiency** -- the migration oneshot re-ran a recursive `chown -R`
  on *every* boot forever, not just the one that needed it, and it sits
  on docker's serialized startup path (`before = docker.service`).
  Fixed with a per-path completion marker, kept in a `StateDirectory`
  rather than inside the migrated tree itself -- a marker inside e.g.
  `/srv/factorio/main` would be owned by real host root (outside any
  remap), and factorio's own entrypoint does its own `chown -R
  factorio:factorio` over the whole volume at every start, which would
  choke on a file outside its namespace's mapped range. New subtest
  confirms the marker exists and sits outside the migrated tree.
- **Altitude** -- `hosts/homelab/configuration.nix` hardcoded both
  migrations' path+uid/gid, disconnected from `factorio.nix`/
  `minecraft.nix`, which already own those exact paths and already
  state the "declare uid next to the path it protects, not the host
  file" rule for the *tmpfiles* rule on the same directories. Moved each
  migration entry into its owning service module, right next to the
  existing tmpfiles `z` rule -- NixOS's module system concatenates
  list-typed options (`myDockerUserns.migrations`) across modules
  automatically, so `hosts/homelab/configuration.nix` now only needs
  `myDockerUserns.enable = true;`.

**Declined, with reasons:**
- Simplification suggested deriving `uid`/`gid` from `stat` at migration
  time instead of declaring them, removing the submodule's two fields.
  Rejected: this breaks idempotency. A second run would `stat` the
  *already-migrated* owner and chown from that, compounding the offset
  on every subsequent run rather than being a no-op.
- Simplification suggested collapsing `subIdStart`/`subIdCount` into
  internal `let` constants since only one host currently sets them.
  Rejected: conflicts with this repo's own established convention --
  every other module here (`push-deploy.nix`, `zfs-dataset-properties.nix`)
  exposes real options regardless of current call-site count; removing
  them here would be inconsistent with the codebase's own idiom, not a
  genuine simplification.

Re-verified after both applied fixes: `tests/docker-userns-remap.nix`
green with 8 subtests (the new marker check added), full
`verify-ladder` clean (nixfmt, statix, deadnix, `nix flake check`, all
five `nixosConfigurations` build).

## Findings (F)
*(populated by security/docs-updater when invoked)*
