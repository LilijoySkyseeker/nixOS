---
slug: replace-sanoid-syncoid-with-zrepl-repo-wide
created: 2026-08-23
status: done
frozen: true
---

# replace sanoid+syncoid with zrepl repo-wide

## Original plan

- [x] **2026-08-23: replace sanoid+syncoid with zrepl repo-wide.** Code
      complete on branch `worktree-zrepl-migration-plan`; all three hosts
      build and pass `zrepl configcheck`. **homelab deployed 2026-08-24
      10:02 PDT (local replication complete, boot race fixed and
      reboot-verified); torrent deployed 2026-08-24 ~17:16 PDT (initial
      full send to homelab in progress, ~301 GiB/3.3 TiB as of 18:45 PDT,
      ETA roughly 05:00-07:00 PDT 2026-08-25); thinkpad not yet deployed.**

      **2026-08-24 ~18:20 PDT: fixed a recurring `local-pull` prune
      `ExecErr` on homelab** (`destroys failed ... it's being held`,
      firing on `zdata/storage/storage`, `storage-bulk`, and
      `zroot/local/state` on every ~15min cycle). Root cause, found by
      reading zrepl's own pruning source
      (`internal/pruning/retentiongrid/retentiongrid.go`,
      `internal/pruning/keep_grid.go`, `internal/pruning/pruning.go` in
      the pinned nixpkgs `zrepl.src`, nixpkgs rev `e4bae1bd`): a grid
      bucket without `keep=all` sorts its occupants youngest-first and
      removes the leading `removeCount` of them
      (`RemoveYoungerSnapsExceedingKeepCount`), i.e. it targets the
      *newest* snapshot in an over-full bucket for destruction, not the
      oldest. `Grid.FitEntries` also redefines "now" every prune run as
      the youngest matching snapshot's own timestamp. `retention.archive`
      (`"168x1h | 30x1d | 12x30d"`, no leading full-granularity bucket)
      combined with `local-pull`'s 15m interval against snapshots landing
      every 5m meant the just-received snapshot landed in an over-full
      bucket almost every cycle — and that snapshot is exactly the one
      zrepl's own endpoint had just placed its
      `zrepl_last_received_J_<job>` hold on, to guarantee a valid
      incremental base. The destroy failed loudly every cycle. Harmless
      (checked: receiver-side snapshot counts stayed bounded, older
      entries in the bucket pruned fine) but permanent log noise, and a
      sign the rule set was fighting zrepl's own bookkeeping — not a
      config mistake specific to homelab, since every receiving job
      shares this default.

      **Fix:** `retention.archive` gets a leading `1x15m(keep=all)`
      bucket (commit `6f6e4f3`), sized to the pull interval — `keep=all`
      short-circuits the grid's destroy-list logic for that bucket
      entirely (`if b.keepCount == RetentionGridKeepCountAll { return nil
      }`), so the newest snapshot can never collide with its own hold.
      Deployed to homelab (switch) and torrent (`run0`-wrapped local
      switch); verified via a clean `local-pull` cycle post-deploy
      (`Pruning Receiver: Status: Done`, actually destroying old
      snapshots, no `ExecErr`). Documented in `docs/backups.md` Gotchas.

      **Side effect, not a bug:** restarting `zrepl.service` on homelab
      (as any switch does) killed torrent's in-flight `home` full send
      mid-transfer at ~257 GiB. `SavePartialRecvState:true` meant a
      `receive_resume_token` survived on the receiver, so the next pull
      cycle resumed from ~257 GiB rather than restarting the 3.3 TiB send
      — confirmed via `zfs get receive_resume_token` before the resume
      and the dataset's `USED` growing steadily after. Worth remembering
      before any future homelab config change while a host's initial
      sync is still running: expect a pause-and-resume, not data loss.

      The capacity blocker below (`zbackup` had no room for both layouts)
      was resolved earlier this session by destroying the old syncoid-era
      datasets once the new layout's local copies were verified complete
      — see "Capacity fully resolved" in the prior handoff. One
      side-effect of that cleanup only surfaced deploying torrent today:
      the destroy took `backup/torrent` itself, not just
      `backup/torrent/home` underneath it (unlike `backup/thinkpad`,
      which survived as an empty container) — so torrent's first pull
      failed with zrepl's `root_fs does not exist` (`root_fs` is required
      to pre-exist; zrepl only auto-creates the placeholders *under* it,
      never `root_fs` itself —
      confirmed against `internal/endpoint/endpoint.go:658` in zrepl
      0.7.0). Fixed by recreating it to match `disko.nix`'s declared
      properties exactly (`mountpoint=none`,
      `com.sun:auto-snapshot=false`; `canmount` doesn't inherit in ZFS —
      it's dataset-local and defaults to `on`, so leaving it unset
      reproduces the siblings' actual `on` regardless of the pool root's
      `off` — confirmed by comparing property sources against
      `backup/homelab`/`backup/thinkpad` before recreating). User ran the
      `zfs create` directly since the auto-mode permission classifier
      blocked it when attempted via SSH, same friction the handoff
      predicted for homelab root actions.

      Also fixed as part of today's torrent deploy: `zrepl`'s
      `ssh+stdinserver` client has no TTY to TOFU-prompt on an
      unrecognized host key, so the very first pull attempt after
      torrent's `sshd` came up failed with "Host key verification
      failed" rather than connection-refused. Pinned torrent's actual
      host key declaratively via `programs.ssh.knownHosts.torrent` in
      `hosts/homelab/configuration.nix` rather than weakening to
      `StrictHostKeyChecking=accept-new` — thinkpad will need the same
      treatment once its host key is known.

      Design, retention, and the non-obvious zrepl behaviours are
      documented in `docs/backups.md` — read that rather than
      re-deriving. Restore steps in
      `docs/procedures/backup-restore.md`. Session handoff with the
      remaining steps in `HANDOFF.md`.

      Status in brief: one shared module (`modules/nixos/zrepl.nix`,
      `myZrepl`) replaced sanoid, syncoid and `backup-push.nix`. Topology
      is pull (homelab dials out; sources passive). Every host runs a
      local `snap` job so snapshotting and a prune ceiling never depend
      on a peer. `zbackup`'s layout changed to
      `zbackup/backup/<host>/<full source dataset path>`.

      VM-tested (2026-08-24): all three hosts boot with `zrepl.service`
      started, and a new two-node NixOS VM test
      (`nix build .#checks.x86_64-linux.zrepl-replication`) exercises a
      real pull over the forced-command SSH transport. That test found
      and fixed a bug `zrepl configcheck` cannot catch: receiving jobs
      were missing `recv.placeholder.encryption`, which would have failed
      every remote pull on first receive with no syncoid left to fall
      back on.

      Remaining: deploy homelab → torrent → thinkpad. Before switching
      homelab, confirm `zbackup/backup/{homelab,thinkpad,torrent}` exist
      — zrepl does not create `root_fs`, and disko only creates datasets
      when formatting a disk. torrent's first pull doubles as the fresh full send that
      resolves the stuck-backup incident below. thinkpad's existing copy
      sits at old paths and needs a fresh send or a manual `zfs rename`.
      Once burnt in, turn off `myZrepl.preserveLegacySnapshots` and clear
      the leftover `autosnap_*` snapshots by hand — nothing ages them out
      while it is on.

      **2026-08-25: all three hosts deployed; thinkpad's first sync
      completed clean.** thinkpad built+switched locally (`run0
      nixos-rebuild switch`, no `--target-host`, per the user's request
      for this host), its SSH host key pinned on homelab
      (`programs.ssh.knownHosts.thinkpad`, commit `5eb7858`). torrent's
      first-ever full send finished sometime before 2026-08-25 06:50 PDT
      (was ~1.8 TiB/3.1 TiB at 00:05, done and down to tiny incrementals
      by 06:50).

      Traced a recurring `dial_timeout of 10s exceeded` on thinkpad's pull
      job (self-healing every 15m retry, but frequent — correlated against
      every failure timestamp checked) to Tailscale's magicsock
      continuously flapping between candidate endpoints for the
      homelab↔thinkpad path, confirmed via `tailscaled` logs, even though
      both hosts share a LAN with a stable 1ms direct path available.
      Verified against zrepl v0.7.0's actual source
      (`internal/config/config.go`, fetched from the exact tagged commit
      the nix build uses) rather than the docs site, which undersold the
      mid-transfer failure mode: `dial_timeout` is a real per-connect-type
      field (`SSHStdinserverConnect`/`TCPConnect`/`TLSConnect`), default
      10s. Bumped to 60s universally in the shared `mkConnect` helper
      (commit `6bd1638`) rather than patching thinkpad alone, since this
      class of network flakiness is inherent to whatever LAN a host sits
      on. Deployed to homelab (the only dialer).

      `myZrepl.preserveLegacySnapshots` turned off for thinkpad and
      torrent (commit `a9bfed7`), matching homelab. thinkpad verified to
      already have zero legacy `autosnap_*` snapshots on
      `zroot/local/{root,home}` — deployed and confirmed live, a pure
      hygiene no-op there. **torrent's change is staged but NOT deployed**
      — the session doing this work ran on thinkpad, which has no
      shell/deploy access to torrent at all (not even via homelab, whose
      own `root@torrent` key is rejected at the publickey stage). Needs
      `nixos-rebuild switch --target-host root@torrent` (or run locally on
      torrent) from a session with real access. This is the one loose end
      left after `HANDOFF.md` was deleted and the branch merged to
      `master` — check `zfs list -t snapshot` on torrent for lingering
      `autosnap_*` entries once that switch lands.

      **Landed 2026-08-25 (confirmed via live triage session).** The one
      loose end above is resolved: torrent's live config has
      `preserveLegacySnapshots = false`, its `current-system` is a fresh
      build (`nixos-system-torrent-26.11.20260813.0e251e2`, same
      generation date as the other hosts), and `zfs list -t snapshot -r
      zroot/local` shows **zero** `autosnap_*` entries — the switch
      landed and the legacy cleanup is confirmed clean. All three hosts
      are on zrepl with nothing further outstanding from this migration.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
