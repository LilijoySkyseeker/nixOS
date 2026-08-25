# Handoff — zrepl migration

Branch `worktree-zrepl-migration-plan`. Written 2026-08-24 (rewritten
clean at end of day — prior revisions had accumulated a lot of resolved
detail; see `TODO.md` and `docs/backups.md` for the full history, this
file only carries what the next session actually needs).

**Status: homelab and torrent deployed and healthy; thinkpad is the only
host left.** homelab's local replication is complete and verified, its
boot race is fixed and reboot-verified. torrent was deployed today and
is mid-flight on its very first replication to `zbackup` — **checking on
that is the next session's first job**, not deploying thinkpad blind.

**Delete this file once the branch is merged and all three hosts are
deployed.** It is session state, not documentation — durable knowledge
lives in `docs/backups.md`, `hosts/homelab/README.md`, and `TODO.md`.

## One-sentence prompt to start the next session with

> Continue the zrepl migration: enter the worktree at
> `.claude/worktrees/zrepl-migration-plan` (branch
> `worktree-zrepl-migration-plan`) and read `HANDOFF.md` first — first
> check in on torrent's backup status, both its local snapshots and its
> replication progress onto `zbackup`, then deploy thinkpad if that
> looks healthy.

## How to resume

Everything is committed and pushed; nothing is left in a dirty tree.

- Worktree: `/home/lilijoy/dotfiles/.claude/worktrees/zrepl-migration-plan`
  (enter it with the `EnterWorktree` tool, `path:` that directory — do
  not work from the main checkout).
- Branch `worktree-zrepl-migration-plan`, pushed to `origin`. Working
  tree clean, `nixfmt --check` passes.
- The branch is **not merged to master**. master still has sanoid/syncoid.
- Sessions here run on `torrent` — that's "this local machine".

## Read these, don't re-derive

- `docs/backups.md` — design, roles, retention, and every non-obvious
  zrepl behaviour hit so far, each citing its zrepl/nixpkgs source
  location. Two new Gotchas from today: `zrepl.service`'s boot race fix,
  and `root_fs` needing to pre-exist (bit torrent's deploy).
- `docs/procedures/backup-restore.md` — restore paths (unexercised so far).
- `docs/procedures/vm-testing.md` — how to run/extend the VM test.
- `TODO.md`'s Active section — status and full incident writeups
  (root cause, timestamps, resolution) for everything summarized below.

## Checking on torrent — do this first

torrent's first-ever replication to homelab started 2026-08-24 17:28 PDT:
`zroot/local/home` (3.3 TiB) + `zroot/local/root` (23 GiB), full sends
since nothing existed on `zbackup` for it before today. `root` finished
in ~8 minutes; `home` was still running at session end, throughput
suggesting somewhere around a day to finish (this repo has hit slow
cross-network zrepl throughput before — see `TODO.md`'s torrent USB
throughput entry, though that was same-host/local, not this leg).

Check both sides:

```
# local: torrent's own snap job + sshd/zrepl health
systemctl is-active zrepl.service sshd.service
zfs list -t snapshot -r zroot/local/home zroot/local/root | tail

# remote: homelab's pull progress
ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes root@homelab \
  'zrepl status --mode dump | sed -n "/^Job: torrent$/,/^---/p"'
```

Look for: `Status: fan-out-filesystems` progressing (not stuck), no
`PlanErr`/`ExecErr`, and eventually `Status: Latest` once both
filesystems finish their first sync-up. `zpool list zbackup` should show
`FREE` shrinking roughly in line with progress (started at 8.29T with
2.61T alloc). If it stalled or errored, `journalctl -u zrepl -b` on
whichever side looks wrong is the next step — don't re-deploy anything
until you understand why.

## What's deployed and verified

- **homelab**: `zrepl.service` active, `local-source`/`local-pull`/
  `snapshots` jobs all healthy, local replication (homelab's own zdata +
  zroot/local/state) complete and verified. `boot.zfs.extraPools =
  [ "zbackup" ]` reboot-verified — the pool imports cleanly with zero
  manual intervention. `preserveLegacySnapshots = false` deployed;
  legacy `autosnap_*` snapshots destroyed.
- **The `zrepl.service` boot race is fixed.** Upstream nixpkgs
  hard-`Requires=local-fs.target`; a `storage.mount` first-attempt
  failure (a known ZFS mount-before-ready race) used to take
  `local-fs.target`, and therefore zrepl, down with it — permanently,
  since systemd doesn't retry a dependency-failed start job. Relaxed to
  `Wants=`+`After=` in `modules/nixos/zrepl.nix`; reboot-verified three
  times in a row (zrepl active every time, no regressions). **Caveat**:
  the actual race didn't recur in those three reboots, so what's
  verified is "no regression, and the dependency graph structurally
  can't fail this way anymore" — not "observed surviving a live race".
  Full writeup: `docs/backups.md` Gotchas, `TODO.md`.
- **torrent**: `zrepl.service` + `sshd` active, `snap` job taking
  snapshots, `pull-deploy.timer` stopped (doesn't persist across a
  switch/reboot — re-stop if you deploy again). First replication to
  homelab in progress, see above. Two deploy-time issues, both fixed —
  see `docs/backups.md` Gotchas:
  - `zbackup/backup/torrent` (zrepl's `root_fs` container) had been
    destroyed by mistake in an earlier session's capacity cleanup.
    zrepl never creates `root_fs` itself, only placeholders under it.
    Recreated by hand to match `disko.nix`'s declared properties.
  - homelab had never talked to torrent's `sshd` before, so the first
    pull attempt failed host-key verification (no TTY to TOFU-prompt).
    Fixed by pinning the real key via `programs.ssh.knownHosts.torrent`
    in `hosts/homelab/configuration.nix`.
- **thinkpad**: not deployed. Config is written and passes
  `configcheck`/build, same as torrent's was before today.

## Auto-updater timers — re-stop after every switch or reboot

`systemctl stop <timer>` does not persist; a switch or a reboot restarts
these. Check every time you deploy or reboot either host:

```
ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes root@homelab \
  'systemctl stop flake-update-test.timer nixos-upgrade.timer push-deploy-vps.timer'
```

On torrent, root actions need `run0` (interactive, one prompt per
invocation — minimize how many you issue, batch what you can):
`run0 systemctl stop pull-deploy.timer`.

## Deploying thinkpad

Once torrent's replication looks healthy (see above), deploy thinkpad
the same way torrent was deployed today:

```
export NIX_SSHOPTS="-i /home/lilijoy/.ssh/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes"
nixos-rebuild build --flake .#thinkpad   # cheap, catches eval errors first
nixos-rebuild switch --flake .#thinkpad --target-host root@thinkpad
```

Expect the same two issues torrent hit, and fix them the same way:

1. **Pin thinkpad's SSH host key** on homelab before its first pull
   attempt, or expect `Host key verification failed`. Get the real key
   directly from thinkpad (`/etc/ssh/ssh_host_ed25519_key.pub`), then add
   a `programs.ssh.knownHosts.thinkpad` entry in
   `hosts/homelab/configuration.nix` next to torrent's.
2. **Check `zbackup/backup/thinkpad` still exists** before the first
   pull (`zfs list zbackup/backup/thinkpad` on homelab) — it was
   confirmed present as of this session (its mountpoint was fixed to
   `none` last session), but re-verify since torrent's was found missing
   unexpectedly. If it's gone, recreate per the Gotchas entry in
   `docs/backups.md`.
3. Re-stop thinkpad's own auto-update timer after the switch, once you
   have root there (same `run0` pattern as torrent — thinkpad's timer
   name may differ, check `docs/architecture.md`'s host table).
4. `myZrepl.protectRegexes`'s default `^blank$` matters most here —
   thinkpad has impermanence `@blank` snapshots on both
   `zroot/local/root` and `zroot/local/home`. Don't touch
   `protectRegexes` without checking this first.

## After burn-in on torrent and thinkpad

Once each host's own zrepl history is established (some days of clean
replication), set `myZrepl.preserveLegacySnapshots = false` for it and
destroy its legacy `autosnap_*` snapshots — **carefully, checking the
computed destroy range is non-empty on both ends** (see the incident
below).

## Then, once all three hosts are deployed and burned in

1. **Delete this file.**
2. Drop the "not yet deployed" / "not yet exercised" caveats from
   `docs/backups.md`, `docs/architecture.md`, and
   `docs/procedures/backup-restore.md`.
3. Keep `tests/`, `modules/flake/checks.nix`,
   `docs/procedures/vm-testing.md` — those don't expire.
4. Merge the branch to master.

## Incidents worth remembering (full detail in TODO.md)

- **A destroy-range script wiped every snapshot on homelab's three
  source datasets**, not just the intended legacy ones — an unchecked
  empty `oldest`/`newest` turned `zfs destroy -r dataset@oldest%newest`
  into `zfs destroy -r dataset@%` ("all snapshots"). No data was lost
  (surviving cursor bookmarks meant a small incremental resend, not a
  full one), but **always check both ends of a computed snapshot range
  are non-empty before passing them to `zfs destroy`.**
- **`zbackup/backup/torrent` was destroyed along with the old syncoid
  data** in the same session's capacity cleanup, unlike its
  `backup/thinkpad` sibling. A `zfs destroy -r` on a parent takes
  everything under it — when destroying old-layout data under a zrepl
  `root_fs` container, destroy only the child, not the container itself.
- **Deploying is not the same as verifying; verifying is not the same as
  staying verified.** Multiple things this branch has hit (the boot
  race, the destroy-range bug, the missing `root_fs`) surfaced *after*
  something else was already verified working. Check the live
  unit/data again after any change.

## What was decided, and why (don't relitigate without asking)

- **Full replacement**, not just swapping the replication half.
- **Pull topology**, push available per-host via `myZrepl.push`. A push
  client can call `DestroySnapshots` on its own subtree, so a
  compromised source under push could delete its own backup history;
  pull keeps retention authority on homelab.
- **`ssh+stdinserver` with a root SSH user.** See the socket-permission
  reasoning in `docs/backups.md`.
- **Uniform 5m snapshots**; retention `source` / `ceiling` / `archive`.
- **A local `snap` job on every host**, so no host depends on a peer to
  prune.
- Destroying `backup/torrent/home` (accepting the unprotected window for
  torrent's home) and the orphaned old-layout homelab datasets, fixing
  thinkpad's mountpoint, and disabling `preserveLegacySnapshots` for
  homelab ahead of torrent/thinkpad burning in — all explicit sign-off
  from an earlier session.

## Watch for

- **The layout change is the biggest source of confusion.** Backups land
  at `zbackup/backup/<host>/<full source dataset path>` — e.g.
  `.../torrent/zroot/local/home`, not `.../torrent/home`.
- **`myZrepl.protectRegexes` is load-bearing.** Without it zrepl destroys
  any snapshot it did not create, including impermanence `@blank` points.
- **A long outage means a long catch-up.** zrepl replays every
  intermediate snapshot rather than jumping to the newest.
- **`configcheck` only checks the YAML parses**, not runtime behaviour —
  it accepted the missing `recv.placeholder.encryption` that would have
  failed every pull. For behaviour, run the VM test.
- **This machine's elevated actions go through `run0`, which prompts
  interactively per invocation.** Minimize how many you issue — build
  unprivileged first, batch what needs root into as few calls as
  possible (e.g. wrap a whole `nixos-rebuild switch` in one `run0` call
  rather than letting it internally re-elevate per step).
- **The auto-mode permission classifier blocks some routine remote root
  actions on homelab** (seen this session on both a `zfs create` and a
  `systemctl stop`) even when previously agreed. Expect this and just
  ask the user to confirm inline — it's quick.

## Not done, deliberately

- No restore against *real* data. The VM test covers clone-based file
  recovery; rollback and full-dataset restore remain unverified.
- `myZrepl.sink` and `myZrepl.push` are implemented but unused.
- The `tcp` and `tls` transports are wired but untested.
- Retention/interval re-tuning after homelab's USB upgrade.
- Root-causing the `storage.mount` boot race itself (only its
  consequence for zrepl is fixed).

## Commits on the branch, oldest first

| Commit | What |
|---|---|
| `8560c56` | plan recorded in TODO.md |
| `16ca86d` | the shared module, host configs, sanoid/syncoid removal |
| `32c832f` | retention unified at 5m, tiered archive, legacy-snapshot guard |
| `b788f12` | protect impermanence `@blank` snapshots |
| `c30de35` | per-host `snap` job; homelab local push+sink → source+pull |
| `c5c03f5` | documentation |
| `e93c78c` | first session handoff |
| `f32566e` | fix: `recv.placeholder.encryption` on receiving jobs |
| `0c65b39` | the two-node replication VM test |
| `77fd4ac` | placeholder-encryption and `root_fs` findings documented |
| `b6fe659` | VM-testing guide |
| `416b140` | fix: import zbackup at boot; USB cable change documented |
| `713824b` | homelab deploy, capacity blocker, and handoff recorded |
| `a8f705d` | local replication proven; ~6x throughput measured |
| `afe4a5a` | handoff: resume pointer, exact commands, destroy-risk split |
| `05a0c13` | docs: zrepl multi-filesystem send ordering explained |
| `682f022` | docs: correct the send-ordering gotcha (most_recent, not oldest) |
| `6fdd581` | docs: record the `zrepl.service`/`local-fs.target` boot race |
| `100517b` | feat: `preserveLegacySnapshots=false` for homelab |
| `2bb01ae` | docs: record and resolve the legacy-snapshot destroy incident |
| `d83f957` | fix: relax zrepl.service's local-fs.target dependency |
| `0db5b1e` | docs: record homelab reboot-verification of the boot-race fix |
| `9ae82a6` | feat: pin torrent's SSH host key; torrent deployed |
| `376e591` | docs: record pull-deploy.timer stopped on torrent |
