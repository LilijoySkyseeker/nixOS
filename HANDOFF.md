# Handoff — zrepl migration

Branch `worktree-zrepl-migration-plan`. Written 2026-08-24, sixth
revision this day. homelab is deployed, its local replication is
**complete and verified**, and the `zrepl.service` boot race fix is
**deployed and reboot-verified** (three reboots, zrepl came up active
every time, no regressions). **The next session's job is the original
rollout again: deploy torrent, then thinkpad.** One caveat carried
forward: the actual `storage.mount` race didn't recur across those three
reboots, so the fix's effect on a live race is inferred from the unit
dependency graph, not directly observed — see "PRIMARY TASK" below
before treating that as fully closed.

**Delete this file once the branch is merged and all three hosts are
deployed.** It is session state, not documentation — durable knowledge
went into `docs/backups.md`, `hosts/homelab/README.md` and `TODO.md`.

## How to resume

Everything is committed and pushed; nothing is left in a dirty tree.

- Worktree: `/home/lilijoy/dotfiles/.claude/worktrees/zrepl-migration-plan`
  (enter it with the `EnterWorktree` tool, `path:` that directory — do not
  work from the main checkout).
- Branch `worktree-zrepl-migration-plan`, pushed to `origin`. Working tree
  clean, `nixfmt --check` passes.
- The branch is **not merged to master**. master still has sanoid/syncoid.
- Sessions here run on `torrent`.

One-sentence prompt to start the next session with:

> Continue the zrepl migration: enter the worktree at
> `.claude/worktrees/zrepl-migration-plan` (branch
> `worktree-zrepl-migration-plan`) and read `HANDOFF.md` first — the
> `zrepl.service` boot race fix is deployed and reboot-verified on
> homelab, so deploy torrent and thinkpad next.

## Read these, don't re-derive

- `docs/backups.md` — design, roles, retention, and the zrepl behaviours
  that are easy to get wrong. Each gotcha cites the zrepl source location.
- `docs/procedures/backup-restore.md` — restore paths.
- `docs/procedures/vm-testing.md` — how to run/extend the VM test.
- `TODO.md` — status and the open incidents, including the two below in
  full detail (root cause, timestamps, resolution).

## State — homelab fully migrated and verified; torrent/thinkpad not deployed

- `zrepl.service` **active**, all three local jobs (`local-source`,
  `local-pull`, `snapshots`) healthy. `torrent`/`thinkpad` pull jobs
  correctly error with connection-refused — expected, those hosts aren't
  deployed yet.
- **Local replication (homelab's own data) is complete and verified.**
  All three datasets landed under the new layout with matching sizes and
  snapshots:
  ```
  zbackup/backup/homelab/zdata/storage/storage        485G
  zbackup/backup/homelab/zdata/storage/storage-bulk    2.07T
  zbackup/backup/homelab/zroot/local/state             39.7G
  ```
- **Reboot-verified**: `boot.zfs.extraPools = [ "zbackup" ]` works.
  Rebooted homelab, `zfs-import-zbackup.service` imported the pool with
  zero manual intervention. This closes out the previous session's open
  item.
- **Capacity fully resolved.** `zbackup`: 10.9T size, 2.59T alloc,
  **8.32T free**, async reclaim finished (`freeing: 0`). Both
  destroy decisions from the last session were executed with your
  explicit sign-off: `backup/torrent/home` (3.08T, the risky half) and
  the orphaned old-layout `backup/homelab/{state,storage,storage-bulk}`
  (2.90T, the low-risk half, destroyed only after the new-layout copies
  were verified complete). Plenty of room for torrent's ~3.13T first
  pull whenever you deploy it.
- **Legacy sanoid-era `autosnap_*` snapshots destroyed.**
  `preserveLegacySnapshots = false` is deployed for homelab
  (`hosts/homelab/configuration.nix`); the 711 leftover snapshots across
  the three source datasets are gone. See the incident note below before
  writing anything similar again.
- **Leftover pool hygiene done**: empty placeholder containers
  (`backup-bulk/{homelab,legion,other,thinkpad}`, `backup/{legion,other}`)
  destroyed; `zbackup/backup/thinkpad` mountpoint fixed from
  `/backup/thinkpad` to `none` (was drifted from `disko.nix`'s intent,
  would have given thinkpad's received filesystems a real mountpoint on
  first receive).
- **Backblaze/restic offsite path confirmed unaffected** by the whole
  migration — it operates on homelab's own source datasets
  (`hosts/homelab/configuration.nix:96-143`), never touches `zbackup`,
  and its `zfs list -s name | tail -1` snapshot picker is naming-scheme
  agnostic, so it works the same with zrepl's `zrepl_*` snapshots as it
  did with sanoid's `autosnap_*`.
- **Auto-updater timers**: currently stopped
  (`flake-update-test.timer`, `nixos-upgrade.timer`,
  `push-deploy-vps.timer`). Both a `switch` and a `reboot` restart them —
  confirmed again this session. **Re-stop after every switch or reboot**,
  `systemctl stop <name>` does not persist:
  ```
  ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes root@homelab \
    'systemctl stop flake-update-test.timer nixos-upgrade.timer push-deploy-vps.timer'
  ```
  torrent/thinkpad's `pull-deploy.timer` could still not be stopped from
  here (no root access pre-deploy); same mitigations as before apply
  (`operation = "boot"`, `autoReboot = false`).

## PRIMARY TASK — fix the `zrepl.service` boot race (done)

**Fixed in `modules/nixos/zrepl.nix`** (the "relax `Requires=` to
`Wants=`+`After=`" candidate below): `systemd.services.zrepl` now
overrides `requires = lib.mkForce [ ];`, `wants`/`after` on
`local-fs.target`. Deployed to homelab via `nixos-rebuild switch`, then
**rebooted three times in a row** (2026-08-24 16:49/16:52/16:55 PDT):
`zrepl.service` active every time, both mounts clean, zero failed units,
all three local jobs (`local-source`/`local-pull`/`snapshots`) cycling
normally straight through. Live unit confirmed via
`systemctl show zrepl.service`: `Wants=local-fs.target`,
`After=local-fs.target`, no `local-fs.target` in `Requires=`.

**Caveat, don't lose this:** `storage.mount` did not race in any of the
three reboots, so what's verified is "no regression on a clean boot"
plus "the dependency graph structurally can't dependency-fail zrepl's
start job anymore" — not "observed zrepl surviving a live race", since
no live race occurred to survive. The race is looking intermittent (one
occurrence, then three non-occurrences) rather than reliably
reproducible, so further confidence will most likely come from it
happening again in the wild post-fix and zrepl visibly not going down,
not from more deliberate reboots. If you want more direct evidence
before fully trusting this, the VM test route from the original plan
below is still on the table but was not attempted this session.

The underlying `storage.mount` race itself is still uninvestigated; this
fix only removes the silent-outage consequence of it. See
`docs/backups.md`'s Gotchas entry and `TODO.md` for the full writeup.

Full detail on the original finding,
exact timestamps, and the failing unit's config are in `TODO.md`'s
"Active" section (top two entries) — read that before starting, this is
just the summary:

**What happens:** on boot, `storage.mount` (`/storage`, on `zdata`)
sometimes fails its first mount attempt
(`status=2/INVALIDARGUMENT` — a known ZFS mount-before-ready race,
unrelated to the `zbackup` import fix, which itself works correctly).
That failure cascades: `storage.mount` failing takes `local-fs.target`
down with it, and `zrepl.service`'s systemd override in
`modules/nixos/zrepl.nix` sets `Requires=local-fs.target`, so zrepl's
start job aborts with "Dependency failed". The mount self-heals a second
later (`/storage` ends up fine), but systemd does not retry a unit whose
start failed due to a dependency failure — `zrepl.service` just sits
`inactive (dead)` until someone runs `systemctl start zrepl.service` by
hand. Confirmed empirically this session: verified via
`journalctl -b -u storage.mount` and `systemctl status local-fs.target`
after a real reboot at 16:07 PDT; backups were silently down until
16:14:49 when caught and started manually.

**Why it matters:** this is the same *class* of bug as the
`boot.zfs.extraPools` finding from the previous session (backups
silently not running after a reboot) — just smaller blast radius this
time (~8 minutes, caught immediately by the reboot test) instead of
~23 hours. It will recur on every reboot until fixed, and nothing
currently alerts on it beyond `myHealthAlerts`' failed-unit / staleness
checks eventually noticing — the same detection gap noted in the first
incident.

**Not yet investigated:**
- Why `storage.mount` races at all — is it consistently reproducible on
  a clean reboot, or intermittent? Only observed once so far.
- Whether `storage-bulk.mount` (same symptom, seen in the same boot) has
  the same root cause or a different one.
- The right fix. Candidates, none evaluated yet:
  - Fix the underlying mount race (probably the more correct fix, but
    unclear what's actually racing against what at this point in boot —
    `zfs-mount-generator`? ordering against `zfs-import-zdata.service`?)
  - Relax zrepl's `Requires=local-fs.target` to `Wants=`+`After=` so a
    transient dependency failure doesn't permanently down it (easy, but
    papers over the mount race rather than fixing it, and changes
    zrepl's guarantee that it never starts before its filesystems are
    ready)
  - Some retry/remediation mechanism (a path unit, a periodic health
    check that restarts zrepl if it should be up but isn't)
- **Test via the VM test infrastructure first** (`docs/procedures/vm-testing.md`,
  `tests/zrepl-replication.nix`) if a reboot-race can be reproduced
  there — much cheaper than repeatedly rebooting homelab. If it can't be
  reproduced in the VM (timing-sensitive races often can't), a real
  homelab reboot is the only way to verify a fix, same as the
  `boot.zfs.extraPools` fix was verified.

## Incident this session — read before writing any zfs destroy command

**An unchecked-variable bug in a destroy-range script wiped every
snapshot on homelab's three source datasets**, not just the intended
711 legacy `autosnap_*` ones. Full root cause and resolution in
`TODO.md`'s top "Active" entry. Short version: the automatic prune
ceiling had already destroyed the legacy snapshots itself (once
`preserveLegacySnapshots=false` deployed) by the time a follow-up script
tried to compute a `zfs destroy -r dataset@oldest%newest` range from
them — `oldest`/`newest` came back empty, unchecked, and
`zfs destroy -r dataset@%` was interpreted as "all snapshots" rather
than erroring. **No data was lost** — live filesystems and `zbackup`'s
already-replicated copies were untouched, and the surviving
`#zrepl_CURSOR_*` bookmarks let `local-pull` recover with a small
incremental instead of a full resend. Verified healthy afterward.
**Lesson: always check both ends of a computed snapshot range are
non-empty before passing them to `zfs destroy`.**

## Also outstanding (unchanged from before, still true)

- **`preserveLegacySnapshots` is now `false` for homelab only.** torrent
  and thinkpad still default to `true` (unset), correctly — their own
  legacy snapshots shouldn't be touched until each host's own zrepl
  history is burned in post-deploy.
- **`myZrepl.protectRegexes` is load-bearing.** Without it zrepl destroys
  every snapshot it did not create, including thinkpad's `@blank`
  impermanence rollback point. Verified this session that homelab's own
  `zroot/local/root@blank` was never touched by the incident above (it's
  a different dataset than the three that got wiped) — but don't take
  that as reason to relax the regex anywhere.
- **Why did ~23h of failed units (the first incident) not raise an alert
  that got acted on?** Still open. `myHealthAlerts` covers failed units,
  so the gap is likely in noticing, not detecting. The boot-race finding
  above is the same open question again, at smaller scale.

## Next steps, in order

1. ~~Verify the `zrepl.service` boot race fix against a real reboot~~ —
   **done this session**, see "PRIMARY TASK" above for the caveat about
   the race not recurring during verification.
2. **Deploy torrent**, then **thinkpad**, per the original plan. Capacity
   and the pool-import fix are both verified — nothing else blocks this.
   Build locally and push (`nixos-rebuild switch --flake .#<host>
   --target-host root@<host>`, `NIX_SSHOPTS` carrying the key) — do not
   build on the target. Re-stop that host's `pull-deploy.timer` after the
   switch, once you have root there.
3. **After burn-in on torrent/thinkpad too**: set their
   `myZrepl.preserveLegacySnapshots = false` and destroy their legacy
   snapshots — **carefully, checking the range is non-empty**, unlike
   this session's incident.
4. **Delete this file**, drop the "not yet deployed" caveats from
   `docs/backups.md`, `docs/architecture.md`,
   `docs/procedures/backup-restore.md`. Keep `tests/`,
   `modules/flake/checks.nix`, `docs/procedures/vm-testing.md`.

## How to reach the hosts

homelab takes root SSH with the user's key — this is how everything above
was done:

```
ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes root@homelab
```

`lilijoy@homelab` is **not** authorised (publickey denied). torrent has no
`sshd` until it is deployed. homelab has **no `python3`** — parse JSON
locally or use shell tools there.

On `torrent` itself you are the unprivileged user `lilijoy`; there is no
root shell and `run0` needs interactive authentication, so anything
requiring root on torrent has to be done by the user. Suggest they run it
with a leading `!` in the prompt so the output lands in the session.

**Permission classifier note**: remote `systemctl stop`/`switch`
operations on homelab got blocked by the auto-mode permission classifier
this session even though they were previously-agreed, routine steps
(re-stopping timers, deploying an approved config change). Expect to hit
this again and just ask the user to confirm inline — it's quick.

### The exact deploy command that worked

Run from the worktree on torrent. Builds locally and pushes the closure —
`--build-host` is deliberately unset, per
`docs/procedures/workflow.md`'s build-locality rule.

```
export NIX_SSHOPTS="-i /home/lilijoy/.ssh/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes"
nixos-rebuild switch --flake .#homelab --target-host root@homelab
```

Substitute `torrent` / `thinkpad` for the later deploys. Build-only first
(`nixos-rebuild build --flake .#<host>`) is cheap and catches evaluation
errors before touching the host.

### Rolling homelab back

Generation 328 is the pre-migration system (sanoid/syncoid). Current
generation as of this handoff:
`/nix/store/yhspvcj18najyiwxa31vf179b4hp1fgk-nixos-system-homelab-26.05.20260814.02e0898`.

```
nixos-rebuild list-generations | head
/nix/var/nix/profiles/system-328-link/bin/switch-to-configuration switch
```

Note that rolling back restores sanoid/syncoid but does **not** re-export
`zbackup`, and generation 328 lacks the `boot.zfs.extraPools` fix — so a
rollback plus a reboot reintroduces the unimported-pool bug. It also
predates the `preserveLegacySnapshots=false` change and the legacy
snapshot destruction, which are irreversible regardless of what
generation is running.

## What was decided, and why

Decisions the user made explicitly — don't relitigate without asking:

- **Full replacement**, not just swapping the replication half.
- **Pull topology**, push available per-host via `myZrepl.push`. Chosen
  after finding that a push client can call `DestroySnapshots` on its own
  subtree, so a compromised source could delete its own backup history.
- **`ssh+stdinserver` with a root SSH user.** See the socket-permission
  reasoning in `docs/backups.md`.
- **Uniform 5m snapshots**; retention `source` / `ceiling` / `archive`.
- **A local `snap` job on every host**, so no host depends on a peer to
  prune.
- **This session**: destroy `backup/torrent/home` immediately (accepting
  the unprotected window for torrent's home), destroy homelab's orphan
  once verified, destroy leftover placeholders, fix thinkpad's
  mountpoint, and disable `preserveLegacySnapshots` for homelab now
  rather than waiting for torrent/thinkpad to also burn in.

## Watch for

- **The layout change is the most likely source of confusion.** Backups
  land at `zbackup/backup/<host>/<full source dataset path>`, so
  `.../torrent/zroot/local/home`, not `.../torrent/home`.
- **`myZrepl.protectRegexes` is load-bearing** — see above.
- **torrent and thinkpad will start running `sshd`**, which they do not
  today. The alternative is a `tcp`/`tls` transport over Tailscale — the
  module supports both, untested.
- **A long outage means a long catch-up.** zrepl replays every
  intermediate snapshot rather than jumping to the newest.
- **A valid zrepl config can still be wrong.** `configcheck` only checks
  that the YAML parses into known keys; it accepted the missing
  `recv.placeholder.encryption` that would have failed every pull. Green
  build = syntax only. For behaviour, run the VM test.
- **Deploying is not the same as verifying. Verifying is not the same as
  staying verified.** Two incidents this session alone (the boot race,
  the destroy-range bug) happened *after* things were already verified
  working. Check the live unit/data again after any change, don't trust
  a prior verification to still hold.
- **`zfs destroy` with a computed snapshot range needs its bounds
  checked.** See the incident above.

## Not done, deliberately

- No restore against *real* data. The VM test covers clone-based file
  recovery; rollback and full-dataset restore remain unverified.
- `myZrepl.sink` and `myZrepl.push` are implemented but unused.
- The `tcp` and `tls` transports are wired but untested.
- Retention/interval re-tuning after the USB upgrade.
- The `zrepl.service` boot race — this session's primary open item.

## Commits on the branch, oldest first (this session's additions at the end)

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
