# Handoff — zrepl migration

Branch `worktree-zrepl-migration-plan`. Written 2026-08-24, updated the
same day by a second session.

**Delete this file once the branch is merged and deployed.** It is session
state, not documentation — durable knowledge went into `docs/backups.md`.

## Read these, don't re-derive

- `docs/backups.md` — design, roles, retention, and the zrepl behaviours
  that are easy to get wrong. Every one of those gotchas cost real
  source-reading to establish; the file cites the zrepl source location for
  each so you can re-check rather than re-discover.
- `docs/procedures/backup-restore.md` — restore paths. Its clone-based
  file recovery is now exercised by the VM test below, so that much of it
  is known to work; the rollback and full-dataset paths still are not.
- `docs/procedures/vm-testing.md` — how to run and extend the VM test
  before you touch the module.
- `TODO.md` — status and the two open incidents this migration interacts
  with (torrent's stranded backup, zbackup's USB throughput).

## State

Code complete. All three hosts build; `zrepl configcheck` passes on each
(it runs at build time via `myZrepl.validateConfig`). **Nothing is
deployed** — no host has been switched.

Testing done since the first handoff:

- All three hosts build `system.build.vm` and boot to a login prompt with
  `zrepl.service` started. The only unit that fails in those VMs is
  `smartd` on every host, plus (on homelab) sops-dependent units,
  impermanence rollback, and the docker/wireguard units — all artifacts of
  a VM with no real pool, no host key, and no network, none zrepl-related.
  Those runs were one-off verification and left nothing behind.
- `tests/zrepl-replication.nix` is a new two-node NixOS VM test with real
  zpools, wired up as `checks.zrepl-replication` in
  `modules/flake/checks.nix`. Booting a host proves the daemon starts;
  this proves a pull actually moves data. Run it with
  `nix build .#checks.x86_64-linux.zrepl-replication` — all seven
  subtests pass. **Run it before touching the module**, and read
  `docs/procedures/vm-testing.md` first if you plan to extend it.

**The test found a real bug, now fixed.** Every receiving job was missing
`recv.placeholder.encryption`. Receiving `zroot/local/home` into
`zbackup/backup/torrent` requires zrepl to create `zroot` and
`zroot/local` as placeholder datasets first, and it refuses to unless
that property is set — zrepl's default is `unspecified`, which fails the
receive. `zrepl configcheck` accepts the config either way, so
`validateConfig` could never have caught it: **every remote pull would
have failed on first receive after deploy**, with sanoid/syncoid already
removed and no fallback. Fixed by `myZrepl.placeholderEncryption`
(default `off`; `zbackup` is unencrypted). See `docs/backups.md`'s
Gotchas.

Commits on the branch, oldest first:

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

1. ~~**VM-test each host**~~ — done, see State above. Two things the new
   test deliberately does *not* cover, because they need either a
   single-host pool pair or a way to sever a transfer mid-stream: the
   local `source`+`pull` pair on homelab, and an interrupted transfer
   leaving a resumable state. Both are still unexercised, so homelab's
   local replication gets its first real run at deploy time.
2. **Deploy homelab first** — torrent and thinkpad need it reachable.
   Before switching, confirm `zbackup/backup/{homelab,thinkpad,torrent}`
   all exist (`zfs list`). zrepl does not create `root_fs`, and disko
   only creates datasets when formatting a disk, so a container missing
   from an already-installed pool fails every pull for that remote with
   `root_fs does not exist`. The VM test caught this; see
   `docs/backups.md`.
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
   `docs/procedures/backup-restore.md`. Keep `tests/`,
   `modules/flake/checks.nix`, and `docs/procedures/vm-testing.md` —
   those are documentation and regression cover, not session state. The
   test in particular guards edits still on the roadmap (item 5 below,
   and the untested tcp/tls transports).

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
- **A valid zrepl config can still be wrong.** `zrepl configcheck` — and
  therefore `myZrepl.validateConfig` — only checks that the YAML parses
  into known keys. It accepted the missing `recv.placeholder.encryption`
  that would have failed every pull. Treat a green build as evidence
  about syntax only; for behaviour, run the VM test.
- **Deploying is not the same as verifying.** `TODO.md` records a prior
  incident where a fix was verified in isolation but never actually
  switched into the running system, and the broken service kept running for
  two days. Check the live unit, not just the build.

## Not done, deliberately

- No restore has been performed against *real* data. The VM test does
  exercise `backup-restore.md`'s clone-a-snapshot file recovery against
  the new layout and it works, but the rollback and full-dataset-restore
  paths remain written-from-mechanics and unverified.
- `myZrepl.sink` and `myZrepl.push` are implemented but unused — they exist
  so a future roaming host can opt into push without reworking the module.
- The `tcp` and `tls` transports are wired but untested.
