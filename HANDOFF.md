# Handoff — zrepl migration

Branch `worktree-zrepl-migration-plan`. Written 2026-08-24.

**Delete this file once the branch is merged and deployed.** It is session
state, not documentation — durable knowledge went into `docs/backups.md`.

## Read these, don't re-derive

- `docs/backups.md` — design, roles, retention, and the zrepl behaviours
  that are easy to get wrong. Every one of those gotchas cost real
  source-reading to establish; the file cites the zrepl source location for
  each so you can re-check rather than re-discover.
- `docs/procedures/backup-restore.md` — restore paths.
- `TODO.md` — status and the two open incidents this migration interacts
  with (torrent's stranded backup, zbackup's USB throughput).

## State

Code complete. All three hosts build; `zrepl configcheck` passes on each
(it runs at build time via `myZrepl.validateConfig`). **Nothing is
deployed** — no host has been switched.

Commits on the branch, oldest first:

| Commit | What |
|---|---|
| `8560c56` | plan recorded in TODO.md |
| `16ca86d` | the shared module, host configs, sanoid/syncoid removal |
| `32c832f` | retention unified at 5m, tiered archive, legacy-snapshot guard |
| `b788f12` | protect impermanence `@blank` snapshots |
| `c30de35` | per-host `snap` job; homelab local push+sink → source+pull |
| `c5c03f5` | documentation |

## What was decided, and why

Decisions the user made explicitly — don't relitigate without asking:

- **Full replacement**, not just swapping the replication half.
- **Pull topology**, push available per-host via `myZrepl.push`. Chosen
  after finding that a push client can call `DestroySnapshots` on its own
  subtree, so a compromised source could delete its own backup history.
- **`ssh+stdinserver` with a root SSH user.** Root here is not laziness;
  see the socket-permission reasoning in `docs/backups.md`. Transport is
  pluggable, so changing it later is a one-line edit.
- **Uniform 5m snapshots**; retention `source` / `ceiling` / `archive` as
  specified by the user directly.
- **A local `snap` job on every host**, not just the laptop, so no host
  depends on a peer to prune.

## Remaining work

1. **VM-test each host** before any real switch (repo convention —
   `docs/procedures/workflow.md`). Worth exercising specifically: the local
   `source`+`pull` pair on homelab, a forced-command SSH connection from
   homelab into a source, and an interrupted transfer leaving a resumable
   state.
2. **Deploy homelab first** — torrent and thinkpad need it reachable.
3. **Then torrent.** Its first pull is the fresh full send that resolves
   the stranded-backup incident in `TODO.md`. Expect it to take a long time
   (~40h was observed for ~3.13TB over this hardware).
4. **Then thinkpad.** Its existing backup sits at the old syncoid paths and
   will not be reused — either accept a fresh send or `zfs rename` into the
   new layout first.
5. **After burn-in**: set `myZrepl.preserveLegacySnapshots = false` and
   destroy the leftover `autosnap_*` snapshots by hand. Nothing ages them
   out while that guard is on.
6. **Delete this file**, and drop the "not yet deployed" caveats from
   `docs/backups.md`, `docs/architecture.md`, and
   `docs/procedures/backup-restore.md`.

## Watch for

- **The layout change is the most likely source of confusion.** Backups
  land at `zbackup/backup/<host>/<full source dataset path>`, so
  `.../torrent/zroot/local/home`, not `.../torrent/home`.
  `myHealthAlerts.backupStaleness` on homelab was updated to match; if you
  change one, change the other.
- **`myZrepl.protectRegexes` is load-bearing.** Without it zrepl destroys
  every snapshot it did not create, including thinkpad's `@blank`
  impermanence rollback points, which cannot be regenerated without
  reinstalling. Don't "simplify" the keep rules.
- **torrent and thinkpad now run `sshd`**, which they did not before. If
  that posture needs revisiting, the alternative is a `tcp` or `tls`
  transport over Tailscale — the module already supports both.
- **A long outage means a long catch-up.** zrepl replays every intermediate
  snapshot rather than jumping to the newest, so a host offline for weeks
  produces a chain of send steps on reconnect.
- **Deploying is not the same as verifying.** `TODO.md` records a prior
  incident where a fix was verified in isolation but never actually
  switched into the running system, and the broken service kept running for
  two days. Check the live unit, not just the build.

## Not done, deliberately

- No restore has been performed against the new layout, so
  `docs/procedures/backup-restore.md` is written from mechanics and flagged
  as unverified.
- `myZrepl.sink` and `myZrepl.push` are implemented but unused — they exist
  so a future roaming host can opt into push without reworking the module.
- The `tcp` and `tls` transports are wired but untested.
