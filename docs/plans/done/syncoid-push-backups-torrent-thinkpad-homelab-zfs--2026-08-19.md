---
slug: syncoid-push-backups-torrent-thinkpad-homelab-zfs-
created: 2026-08-19
status: done
frozen: true
---

# syncoid push backups, torrent + thinkpad → homelab (zfs snapshot based, over Tailscale)

## Original plan

- [x] **2026-08-19: syncoid push backups, torrent + thinkpad → homelab
      (zfs snapshot based, over Tailscale).** Shared `myBackupPush`
      module (`modules/nixos/backup-push.nix`), used identically by both
      hosts, pushing `zroot/local/home` + `zroot/local/root` to a
      dedicated `backup-recv` user on homelab via `zfs allow`-scoped
      delegation. Uses syncoid `--create-bookmark` so long offline
      periods (esp. the thinkpad laptop, but torrent can also go dark on
      vacation) don't force a full resync once sanoid's short
      source-side retention (hourly=24/daily=1) prunes past the last
      pushed snapshot. Trigger: hourly systemd timer, `Persistent =
      true`, gated by a Tailscale-reachability `ExecCondition` so an
      offline host no-ops instead of alerting. `backupStaleness`
      thresholds set generously (336h/2wk) for both, for the same
      reason. Source-side runs as a dedicated `backup-push` user
      (zfs-allow-scoped, not root), and a paired
      `modules/nixos/zfs-space-guard.nix` (`myZfsSpaceGuard`) on both
      hosts auto-prunes oldest local snapshots under free-space pressure
      (torrent/thinkpad's game libraries under `zroot/local/home` churn
      heavily) plus a `zfs-emergency-prune.service` manual escape hatch
      (`zfs-space-guard`'s own testing/fate is its own entry above).
      **Follow-up once impermanence lands**: `zroot/local/root` will
      likely stop being the meaningful thing to back up — update
      `myBackupPush.datasets` on both hosts to point at whatever the new
      persist dataset ends up being called instead.

      **Final zbackup layout (simplified 2026-08-19)**: one flat
      `zbackup/backup/<host>/<subdir>` convention for everything — no
      more backup-vs-backup-bulk split. That split existed to keep
      large/churny data out of any future offsite job, but restic's
      offsite `backblazeWeekly` job reads an explicit hardcoded dataset
      list (`zroot/local/state zdata/storage/storage
      zdata/storage/storage-bulk`) and never touches `zbackup` at all —
      confirmed by reading the actual `backupPrepareCommand` — so the
      split wasn't doing anything functional. Current tree:
      ```
      zbackup/backup/homelab/{storage,storage-bulk,state}   (local syncoid pulls)
      zbackup/backup/thinkpad/{home,root}                    (remote syncoid push)
      zbackup/backup/torrent/{home,root}                     (remote syncoid push)
      ```
      `backup/legion`, `backup-bulk/legion`, `backup/other`,
      `backup-bulk/other` (all confirmed unreferenced placeholders) were
      dropped entirely. Sanoid's `"zbackup" = { use_template = "backup";
      recursive = "yes"; }` already covers the whole tree recursively —
      no per-dataset sanoid config needed for any of this.
      Code committed on branch `worktree-zfs-backup-push`; **not yet
      deployed to any real host.**

      **Merged onto master 2026-08-21** (commit `dff4450`, branch not
      yet pushed to origin): rebased this whole feature onto the
      dendritic flake-parts restructuring that landed on master in the
      meantime (`flake.nix` rewrite, `profiles/`/`services/` moved into
      `modules/`, host `imports` replaced by named-module wiring in
      `modules/flake/hosts.nix`). `backup-push.nix` and
      `zfs-space-guard.nix` converted to the
      `flake.modules.nixos."<name>"` wrapper format and wired into
      torrent's/thinkpad's module lists there. `hosts/homelab/disko.nix`
      and `hosts/homelab/configuration.nix` merged with **zero
      conflicts** — confirmed non-overlapping with the dendritic changes
      and with `zfs-pool-recovery-restore`'s LUKS work via an earlier
      dry-run merge test. Verified post-merge: `nixos-rebuild build`
      (not switch) succeeds for all three hosts, and `nix flake check`
      passes for the whole flake (all 5 nixosConfigurations).

      **New hard blocker from the merge**: `secrets/secrets.yaml` had a
      real conflict — both this branch (torrent/thinkpad backup-push
      keys) and master (a samba password from another branch) added new
      secrets in the same spot. The per-key encrypted values merged
      safely as a plain union (each is an independent ciphertext), but
      the file's `sops:` metadata (`lastmodified`/`mac` — a MAC over the
      *entire file's* contents) could not be hand-merged; master's copy
      was kept as a placeholder and was stale until `sops --ignore-mac
      --rotate --in-place` fixed it during the homelab deploy below.

      **Live pool note**: the storage-bulk rename
      (`zbackup/backup-bulk/homelab/storage-bulk` →
      `zbackup/backup/homelab/storage-bulk`) needed to land atomically
      with homelab's `nixos-rebuild switch` for this branch — done as
      part of the deploy below, confirmed intact (2.26T + full snapshot
      history) afterward. The `legion`/`other`/superseded-bulk-split
      placeholder datasets were confirmed unused and cleaned up
      alongside.

      Rollout: pushed and fast-forward merged into `master`
      (`7706eca..a03ce7c`, 2026-08-21). Both `torrent_backup_push_key`/
      `thinkpad_backup_push_key` ed25519 keypairs generated, added to
      `secrets/secrets.yaml`, and their public halves wired into
      homelab's `backup-recv.openssh.authorizedKeys.keys`. Deployed to
      homelab 2026-08-21: live deploy surfaced and fixed two real bugs
      build-only testing couldn't catch (`backup-recv-zfs-allow.service`
      needed a `zfs create -p` pre-step since `zfs allow` requires its
      target dataset to already exist; `health-check.service`'s
      `backupStaleness` loop needed `|| true` to tolerate a genuinely
      nonexistent dataset under `set -e -o pipefail`). Also found/fixed,
      separately: homelab's `/etc/nixos` checkout stuck on an orphaned
      `auto-update` branch from a crashed `flake-update-test` run
      (cleaned up live with explicit go-ahead — see this file's
      `flake-update-test.service`/git-identity entry), and the stale
      sops mac from the merge
      conflict (fixed via `sops --ignore-mac --rotate --in-place`,
      verified via a direct `sops-install-secrets` run against the built
      manifest before trusting it live).

      **Superseded 2026-08-25, before the rest of the rollout checklist
      (deploying torrent/thinkpad's push, confirming the
      Tailscale-`ExecCondition` behavior, wiring `backupStaleness` into a
      live alert) ever ran.** The zrepl migration (this file's "replace
      sanoid+syncoid with zrepl repo-wide" entry) deleted
      `backup-push.nix` and this entire syncoid-push mechanism,
      replacing it repo-wide with zrepl's pull-based topology — homelab
      now dials out to torrent/thinkpad instead of either pushing to it.
      Everything above (the `backup-recv`/`backup-push` user pair, the
      per-host push keys, the Tailscale-reachability gating, the flat
      `zbackup/backup/<host>/<subdir>` layout convention) either no
      longer exists or was carried forward and re-described fresh in the
      zrepl entry rather than incrementally amended here. Moved here as
      a completed record of what shipped and later got replaced, not
      because the rollout finished on its own terms.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
