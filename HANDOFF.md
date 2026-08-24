# Handoff — zrepl migration

Branch `worktree-zrepl-migration-plan`. Written 2026-08-24; updated the
same day by a third session, which **deployed homelab**.

**Delete this file once the branch is merged and all three hosts are
deployed.** It is session state, not documentation — durable knowledge
went into `docs/backups.md`, `hosts/homelab/README.md` and `TODO.md`.

## How to resume

Everything is committed and pushed; nothing is left in a dirty tree.

- Worktree: `/home/lilijoy/dotfiles/.claude/worktrees/zrepl-migration-plan`
  (enter it with the `EnterWorktree` tool, `path:` that directory — do not
  work from the main checkout).
- Branch `worktree-zrepl-migration-plan`, pushed to `origin`. The working
  tree was clean and `nixfmt --check` passed at handoff.
- The branch is **not merged to master**. master still has sanoid/syncoid.
- Sessions here run on `torrent`, which is where the builds were done.

One-sentence prompt to start the next session with:

> Continue the zrepl migration: enter the worktree at
> `.claude/worktrees/zrepl-migration-plan` (branch
> `worktree-zrepl-migration-plan`) and read `HANDOFF.md` first — homelab is
> deployed and its local replication was still running, so wait for that to
> finish, then reboot homelab to verify the new `boot.zfs.extraPools`
> import fix, and get my decision on freeing space on `zbackup` before
> deploying torrent.

## Read these, don't re-derive

- `docs/backups.md` — design, roles, retention, and the zrepl behaviours
  that are easy to get wrong. Each gotcha cites the zrepl source location.
  Two were added this session (pool import, property inheritance).
- `docs/procedures/backup-restore.md` — restore paths.
- `docs/procedures/vm-testing.md` — how to run/extend the VM test.
- `TODO.md` — status and the open incidents.

## State — homelab IS DEPLOYED

**homelab was switched at 2026-08-24 10:02 PDT** and is running zrepl.
torrent and thinkpad are **not** deployed and still run sanoid/syncoid.

Verified live on homelab after the switch:

- `zrepl.service` active (running), `configcheck` passed in `ExecStartPre`.
- sanoid/syncoid timers stopped; `syncoid`/`backup-recv` users and groups
  removed by activation.
- Six jobs loaded: `snapshots` (snap), `local-source`, `local-pull`,
  `torrent` (pull), `thinkpad` (pull), `_control`.
- First snapshots taken cleanly: three `zrepl_20260824_170228_000`
  snapshots, one per local dataset. **Zero errors in the journal.**
- Rollback point if needed: **generation 328**
  (`/nix/store/y29czmvha5chc1nfarfcjyzhvi8b1hhs-...`).

**Local replication has since been confirmed working in production**
(checked 13:45 PDT, ~3h45m after the switch). This was the first real run
of the local `source`+`pull` pair, which the VM test does not cover:

```
zbackup/backup/homelab/zdata/storage/storage-bulk   1.62T   (in flight)
```

It is still transferring `storage-bulk` (2.07T at source). `storage` and
`zroot/local/state` have not started yet — the job works one dataset at a
time. So the local pair is **proven**, but not yet **complete**.

**Last observed state, 2026-08-24 13:48 PDT** (the final reading before
this session ended — everything after this is unobserved):

```
zbackup                                            7.62T alloc / 3.29T free (69% cap)
zbackup/backup/homelab/zdata/storage/storage-bulk  1.64T   (still growing)
zrepl.service                                      active
flake-update-test / nixos-upgrade / push-deploy-vps timers   inactive
```

The `torrent` and `thinkpad` pull jobs **will fail** until those hosts are
deployed; they have no `sshd`/zrepl `serve` yet. That is expected, not a
regression.

## Two things this session found that were not in the plan

### 1. zbackup was never imported at boot — backups were dead for ~23h

Found by the handoff's own pre-deploy check. homelab rebooted
2026-08-23 10:45 (for the cable change below); `zbackup` did not come
back and every replication job since failed `dataset does not exist`.
The pool was fine throughout — ONLINE, importable, no data errors.

Cause: nothing in the config imported it. nixpkgs emits a
`zfs-import-<pool>.service` only for pools something references (a
`fileSystems` entry, or `boot.zfs.extraPools`). Every `zbackup` dataset is
`mountpoint = "none"` by design, so nothing referenced it. `zdata` gets a
unit only because `/storage` and `/storage-bulk` live on it. disko emits
no import units at all. The pool had been imported by hand historically,
which hid the gap.

Fixed in commit `416b140`: `boot.zfs.extraPools = [ "zbackup" ]`.
Verified in the built system (`zfs-import-zbackup.service` now present)
and started by the switch. **Still unverified: a real reboot.** The user
authorised rebooting homelab for testing — see "Next steps".

### 2. The USB cable was replaced — the throughput incident is resolved

All four enclosure drives now enumerate at **5000 Mbps (USB 3.0)** on bus
2 behind the ASMedia ASM107x hub, up from 480 Mbps shared. Zero
`uas_eh_*` / `stat urb: status -71` faults in the 23h since, vs. the
recurring multi-drive faults previously documented. `zpool status -x`:
all pools healthy.

**Measured under real load, 2026-08-24 13:45**, during homelab's local
replication: `zpool iostat -v zbackup` shows ~245-261 MB/s of aggregate
device bandwidth, i.e. **~122-130 MB/s of actual data** (each mirror disk
writes the full copy, so the pool row is the sum of the two). This agrees
independently with the dataset growth rate: 1.62T received in ~3h45m is
~124 MB/s.

Compare the old measurement in `TODO.md`: ~20MB/s per mirror disk,
~40MB/s aggregate. **That is roughly a 6x improvement**, and it is the
first hard number since the cable change.

This closes `TODO.md`'s 2026-08-21 throughput incident and means **the
~40h estimate for torrent's 3.13TB send is badly out of date.** At
~125 MB/s, ~3.13TB is on the order of **7-8 hours**, not 40. Treat that
as the new working estimate, still unproven for a remote (SSH-transported)
pull as opposed to this local one.

The 15m replication interval and tiered `archive` grid were chosen under
the old ceiling and are now conservative rather than forced; they have
deliberately **not** been re-tuned.

## BLOCKER — zbackup does not have room for both layouts

This is the most important thing on this page and it was not anticipated
in the original plan.

`zbackup` is 10.9T. At the moment of the switch it was 5.98T used / 4.80T
free, all of it the **old syncoid layout**:

```
zbackup/backup/homelab/{state,storage,storage-bulk}   2.90T
zbackup/backup/torrent/home                           3.08T   (stranded)
```

**This is getting worse in real time.** homelab's local replication is
writing the new layout alongside the old one right now — by 13:45 the pool
was already **7.60T alloc / 3.30T free**, down from 4.80T free at 10:02,
and `storage-bulk` was not finished. Expect roughly **2.0-2.2T free** once
homelab's local replication completes.

zrepl writes to **different paths** (`<root_fs>/<full source dataset
path>`), so it will not reuse any of that. It needs roughly:

```
homelab  zdata/storage/storage + storage-bulk + zroot/local/state  ~2.92T
torrent  zroot/local/{home,root}                                   ~3.13T
thinkpad zroot/local/{home,root}                                   unknown
                                                          total   ~6.05T+
```

**~6.05T needed vs ~4.80T free — it does not fit.** homelab's own local
replication alone (~2.92T) fits, and is completing now. torrent's ~3.13T
then has only ~2.0-2.2T to land in, so **torrent's first pull will fill
the pool and fail partway** unless space is freed first. Do not start
torrent before resolving this.

The old datasets must be destroyed to make room. That is a **destructive,
user-only decision** and was deliberately not done.

**The two halves carry very different risk — do not treat them alike:**

- `backup/homelab/{state,storage,storage-bulk}` (2.90T) is now an
  **orphan**. syncoid is gone from homelab, so nothing writes to it any
  more; it is frozen at its last syncoid run. Once the new-layout copies
  under `backup/homelab/zdata/...` and `.../zroot/local/state` are
  complete, it is genuinely redundant and safe to destroy. **Low risk.**
- `backup/torrent/home` (3.08T) is **not redundant**. torrent is still on
  sanoid/syncoid and undeployed, so no new-layout copy of it exists at
  all. Destroying it leaves **zero backup of torrent's home** for the
  duration of the fresh full send (~7-8h at the newly measured rate).
  That window is the real cost of the decision, and it is the user's to
  accept. **Genuine risk — get an explicit yes.**

Suggested order once the user decides:

1. Let homelab's local replication finish (it fits in current free space).
2. Verify the new-layout copies are complete and have snapshots
   (`zfs list -t snapshot -r zbackup/backup/homelab/zdata`).
3. Destroy the old `backup/homelab/{state,storage,storage-bulk}` — frees
   ~2.90T, low risk, and on its own may be enough for torrent.
4. Only if still short, and only with an explicit yes, destroy
   `backup/torrent/home` before starting torrent's first pull.

Step 3 alone takes free space to roughly **4.9-5.1T**, which already fits
torrent's ~3.13T. **So step 4 may not be necessary at all** — check the
numbers before asking the user to accept the risky half.

## Auto-updaters — paused, but the pause does NOT survive a switch

The user asked for these to be paused so they don't collide with the
migration. Current state:

| Host | Unit | Fires | State |
|---|---|---|---|
| homelab | `flake-update-test.timer` | Wed 03:00 | **stopped** |
| homelab | `nixos-upgrade.timer` | Thu 03:00 | **stopped** |
| homelab | `push-deploy-vps.timer` | Thu 03:15 | **stopped** |
| torrent | `pull-deploy.timer` | Thu 03:00 | **STILL ACTIVE** |
| thinkpad | `pull-deploy.timer` | Thu 03:00 | **STILL ACTIVE** |

Two traps here:

- **`systemctl mask` does not work on NixOS** — units are symlinks into
  the store, so mask fails outright. Only `stop` is available.
- **`nixos-rebuild switch` restarts them.** Confirmed empirically: the
  homelab switch listed `flake-update-test.timer`, `nixos-upgrade.timer`
  and `push-deploy-vps.timer` under "the following new units were
  started". They were stopped again afterwards. **Re-stop them after
  every switch, and after any reboot** — `stop` does not persist.

torrent/thinkpad could not be stopped from this session: it needs root
there, torrent has no `sshd` yet (the migration is what adds it), and
`run0` requires interactive authentication. Mitigating factor: both are
`operation = "boot"` with `autoReboot = false`, so a firing timer sets the
next boot entry rather than switching a running system — it cannot
interrupt a transfer in progress. It *would* mean the host comes up on
master (sanoid/syncoid) after a reboot.

To pause them, the user can run on each host:
`run0 systemctl stop pull-deploy.timer`

The durable fix is merging this branch to master, after which the
auto-updaters deploy the zrepl config rather than reverting it.

## Also outstanding

- **`zbackup/backup/thinkpad` has `mountpoint=/backup/thinkpad`**, not
  `none` as `disko.nix` declares. Because the module sets no
  `send.properties`, received datasets inherit their mountpoint from the
  container, so thinkpad's received filesystems would each get a real
  mountpoint. Fix before thinkpad's first receive:
  `zfs set mountpoint=none zbackup/backup/thinkpad`
  (attempted this session; blocked by the tooling's safety classifier).
- **Benign-looking prune errors during a long transfer.** The `snapshots`
  job logs `target could not destroy snapshots ... it's being held` for
  snapshots the in-flight replication holds
  (`zfs holds` shows tag `zrepl_STEP_J_local-source`). This is zrepl
  working as designed — the step hold stops the snapshotter's ceiling
  prune from destroying a snapshot mid-send — and it should clear once the
  transfer finishes and the hold is released. **Worth re-checking after
  homelab's local replication completes**; if the error persists with no
  transfer running, it is a stuck hold and needs looking at, not ignoring.
- **Leftover containers** slated for deletion in `TODO.md` still exist:
  `zbackup/backup-bulk/*`, `zbackup/backup/{legion,other}`. All 96K
  placeholders. Untouched — deletion is a user decision.
- **Why did ~23h of failed units not raise an alert that got acted on?**
  `myHealthAlerts` covers failed units, so the gap is likely in noticing
  rather than detecting. Worth a look.

## Next steps, in order

1. **Wait for homelab's local replication to finish.** It was mid-flight
   on `storage-bulk` at 13:45 and still had `storage` (486G) and
   `zroot/local/state` (170G) to go. Check:
   ```
   zfs list -r zbackup/backup/homelab
   zpool list -o name,alloc,free zbackup
   journalctl -u zrepl.service --since -1h | grep -iE 'error|fail'
   ```
   Done when all three new-layout datasets exist under
   `zbackup/backup/homelab/{zdata/storage/...,zroot/local/state}` and the
   pool write rate drops to idle.
2. **Reboot homelab** — the user authorised this specifically for testing.
   It proves `zfs-import-zbackup.service` imports the pool automatically,
   which is the *only* way to verify the fix for finding #1 and the one
   thing that remains unproven about it. **Deliberately deferred this
   session: do not reboot mid-transfer.** Do it once step 1 is done. After
   the reboot, verify `zpool list zbackup` shows the pool imported without
   manual intervention, then re-stop the three timers (a reboot restarts
   them, same as a switch).
3. **Get a decision on the capacity blocker above** before touching
   torrent. Nothing else can proceed without it, and it is now urgent —
   free space is being consumed as homelab's replication lands.
4. **Deploy torrent**, then **thinkpad**, per the original plan. Build
   locally and push (`nixos-rebuild switch --flake .#<host>
   --target-host root@<host>`, `NIX_SSHOPTS` carrying the key) — do not
   build on the target. Re-stop that host's `pull-deploy.timer` after the
   switch.
5. **After burn-in**: set `myZrepl.preserveLegacySnapshots = false` and
   destroy the leftover `autosnap_*` snapshots by hand.
6. **Delete this file**, drop the "not yet deployed" caveats from
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

Generation 328 is the pre-migration system. On homelab:

```
nixos-rebuild list-generations | head
/nix/var/nix/profiles/system-328-link/bin/switch-to-configuration switch
```

Note that rolling back restores sanoid/syncoid but does **not** re-export
`zbackup`, and the old generation lacks the `boot.zfs.extraPools` fix — so
a rollback plus a reboot reintroduces the unimported-pool bug.

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

## Watch for

- **The layout change is the most likely source of confusion.** Backups
  land at `zbackup/backup/<host>/<full source dataset path>`, so
  `.../torrent/zroot/local/home`, not `.../torrent/home`. The old
  syncoid-era `.../torrent/home` still exists alongside it — do not
  mistake one for the other.
- **`myZrepl.protectRegexes` is load-bearing.** Without it zrepl destroys
  every snapshot it did not create, including thinkpad's `@blank`
  impermanence rollback points. Don't "simplify" the keep rules.
- **torrent and thinkpad will start running `sshd`**, which they do not
  today. The alternative is a `tcp`/`tls` transport over Tailscale — the
  module supports both, untested.
- **A long outage means a long catch-up.** zrepl replays every
  intermediate snapshot rather than jumping to the newest.
- **A valid zrepl config can still be wrong.** `configcheck` only checks
  that the YAML parses into known keys; it accepted the missing
  `recv.placeholder.encryption` that would have failed every pull. Green
  build = syntax only. For behaviour, run the VM test.
- **Deploying is not the same as verifying.** `TODO.md` records a prior
  incident where a fix was verified in isolation but never switched in,
  and the broken service ran for two days. Check the live unit.

## Not done, deliberately

- No restore against *real* data. The VM test covers clone-based file
  recovery; rollback and full-dataset restore remain unverified.
- `myZrepl.sink` and `myZrepl.push` are implemented but unused.
- The `tcp` and `tls` transports are wired but untested.
- Retention/interval re-tuning after the USB upgrade.

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
| `f32566e` | **fix:** `recv.placeholder.encryption` on receiving jobs |
| `0c65b39` | the two-node replication VM test |
| `77fd4ac` | placeholder-encryption and `root_fs` findings documented |
| `b6fe659` | VM-testing guide |
| `416b140` | **fix:** import zbackup at boot; USB cable change documented |
| `713824b` | homelab deploy, capacity blocker, and handoff recorded |
| `a8f705d` | local replication proven; ~6x throughput measured |
| (this one) | final handoff: resume pointer, exact commands, destroy-risk split |
