# TODO / plans & goals

Running log of plans and goals discussed for this repo, so they can be
referenced across sessions. Not a replacement for host-specific docs
(e.g. `hosts/*/README.md`) — this is for higher-level, cross-host
or longer-horizon items.

Convention: add a dated entry when a new plan/goal is agreed on; check
items off or move them to "Done" as they land; prune stale/abandoned
items rather than letting them rot.

## Active

- [x] **2026-08-24: `zbackup` was never imported at boot — backups had
      been silently dead for ~23h. Fixed declaratively.** Found while
      running the zrepl migration's pre-deploy check. homelab rebooted
      Sun 2026-08-23 10:45 (for the USB cable change below); `zbackup`
      did not come back, and every replication job since failed with
      `dataset does not exist`. The pool itself was fine the whole time
      — ONLINE, importable, no data errors.

      **Cause:** nothing in the NixOS config ever imported it. nixpkgs
      only emits a `zfs-import-<pool>.service` for a pool something
      references — a `fileSystems` entry, or `boot.zfs.extraPools`.
      `zdata` gets one implicitly because `/storage` and `/storage-bulk`
      are mountpoints on it. Every `zbackup` dataset is
      `mountpoint = "none"` by design (it is a receive-only target that
      should mount nothing), so nothing referenced the pool and no unit
      was ever generated. Confirmed against the built system, not
      guessed: `ls result/etc/systemd/system/ | grep zfs-import` listed
      only `zdata`. disko is not a fallback here — it emits no import
      units at all (no `extraPools` anywhere in the pinned tree), and
      only creates datasets at *format* time.

      It survived earlier reboots only because someone had imported it
      by hand. That is why this went unnoticed for so long.

      **Fix:** `boot.zfs.extraPools = [ "zbackup" ];` in
      `hosts/homelab/configuration.nix`, on the zrepl migration branch.
      Verified: the rebuilt system now contains
      `zfs-import-zbackup.service`, and the pool imports on a real
      reboot.

      **Worth noting as a class of bug:** a receive-only ZFS pool with
      no mountpoints is invisible to every implicit import mechanism.
      Any future backup-target pool needs `boot.zfs.extraPools`
      explicitly. Also worth asking separately why ~23h of failed
      replication units did not produce an alert that got acted on —
      `myHealthAlerts` does cover failed units, so the gap is likely in
      noticing, not in detecting.

- [ ] **2026-08-24: `zrepl.service` can silently stay down after a reboot
      due to a `local-fs.target` race — needs a durable fix.** Found while
      rebooting homelab to verify the `boot.zfs.extraPools` fix above (the
      pool import itself worked correctly). `storage.mount` failed its
      first attempt at boot (`status=2/INVALIDARGUMENT`, a known ZFS
      mount-before-ready race unrelated to the zbackup fix), which failed
      `local-fs.target`, which `zrepl.service` hard-`Requires=` via
      `modules/nixos/zrepl.nix`'s systemd override. The mount self-healed
      a second later and `/storage` was fine, but systemd does not
      retry a unit whose start failed due to a dependency failure —
      `zrepl.service` sat `inactive (dead)` until manually started
      (`systemctl start zrepl.service`). Backups were down ~8 minutes
      this time (16:07-16:15 PDT), same failure class as the entry above
      but much smaller blast radius since it was caught immediately by
      the reboot test rather than discovered ~23h later.

      **Not yet fixed.** Candidate approaches: fix the underlying mount
      race so `local-fs.target` doesn't fail in the first place; relax
      zrepl's `Requires=local-fs.target` to `Wants=`+`After=` so a
      transient dependency failure doesn't permanently down it; or add
      some retry mechanism. Needs its own investigation — don't
      re-derive, this note plus the journal timestamps above is the
      starting point.

- [ ] **2026-08-23: replace sanoid+syncoid with zrepl repo-wide.** Code
      complete on branch `worktree-zrepl-migration-plan`; all three hosts
      build and pass `zrepl configcheck`. **homelab is deployed as of
      2026-08-24 10:02 PDT; torrent and thinkpad are not.**

      **BLOCKED on a user decision before torrent can proceed: `zbackup`
      has no room for both layouts.** The pool is 10.9T with 5.98T used /
      4.80T free, and all of that 5.98T is the *old* syncoid layout
      (`backup/homelab/{state,storage,storage-bulk}` 2.90T +
      `backup/torrent/home` 3.08T). zrepl writes to different paths and
      reuses none of it, needing ~2.92T for homelab plus ~3.13T for
      torrent — ~6.05T against 4.80T free. homelab's own local
      replication fits; torrent's first pull would fill the pool and fail
      partway. The old datasets have to be destroyed to make room, which
      also means explicitly accepting the loss of the stranded 3.08T
      `backup/torrent/home` (the incident below) — currently the only
      backup of torrent's home that exists. Deliberately not done.
      Suggested order in `HANDOFF.md`.

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

- [ ] **2026-08-23: torrent's `backup-push-torrent.service` (`home`
      dataset) is now stuck — needs a decision, not further automated
      action.** The initial full send (below) finished transferring
      all ~3.13TB successfully, but the *same* syncoid invocation then
      tried to also send a trailing incremental to catch up to the
      latest snapshot, and that failed: the base snapshot it needed
      (`zroot/local/home@autosnap_2026-08-20_22:00:02_hourly`) had
      already been pruned by torrent's own local sanoid retention
      (`hourly=24` ≈ 24h) during the ~38-40h transfer — a run this
      long outlasts that retention window. Because the run didn't
      fully succeed, syncoid never reached its "create bookmark" step
      either (that only happens after a clean finish), so there's now
      **no bookmark and no matching snapshot** between source and the
      already-populated 3.08T target. Confirmed live: re-running the
      service now fails immediately with `Target zbackup/backup/
      torrent/home exists but has no snapshots matching with
      zroot/local/home! ... Cowardly refusing to destroy your existing
      target.` — syncoid won't auto-resolve this by design.
      **Needs a decision**: either force a full resend (syncoid would
      destroy the existing homelab-side target and re-transfer all
      ~3.13TB from scratch, another ~38-40h at the observed rate), or
      leave the Aug 20 snapshot as the backup state for now and decide
      later. Not resolved automatically — deliberately left for the
      user. The `root` dataset's push (second syncoid call in the same
      script, sequential after `home`) never even ran this attempt
      since the script failed on `home` first — its state is unknown/
      unattempted, not separately confirmed broken.
      **Underlying fix needed regardless of the decision above**:
      torrent's local sanoid retention (`hourly=24`, inline
      `services.sanoid.settings.template_working` in
      `hosts/torrent/configuration.nix` — still the pre-dendritic
      inline shape as of this writing, not yet the
      `modules/nixos/zfs-snapshots.nix` module) is too short for how
      long a large `myBackupPush` initial/catch-up send can take. The
      same trap will recur on any future large resend (e.g. after a
      forced full resend here, or on thinkpad's own first push) unless
      either the source retention window is widened well past the
      realistic worst-case transfer time, or `myBackupPush`/syncoid
      usage changes to guarantee a bookmark lands even when the
      trailing incremental step fails (e.g. splitting the full-send
      and incremental-catchup into separate syncoid invocations so a
      bookmark is created after the (more reliable) full send succeeds,
      independent of whether the smaller incremental afterward does).
      Also separately confirmed live (2026-08-23) during this
      troubleshooting: an earlier `run0 nixos-rebuild switch` deploy
      step for a prior fix (the `--sshoption` fix, see the fluctuation
      item below) was verified only via a manual bypass test and never
      actually switched into the running system — the live service
      kept running the old broken script for ~2 days until this was
      caught. Worth remembering as a process gotcha: manually verifying
      a fix in isolation is not the same as confirming it's actually
      deployed and taking effect through the real service path.

- [x] **2026-08-21: torrent's initial full backup send to homelab is
      throughput-limited to ~20-40MB/s — root-caused while it was
      in progress. RESOLVED 2026-08-23 in hardware.**

      **Resolution: the enclosure's USB cable was replaced.** All four
      drives now enumerate at **5000 Mbps (USB 3.0 SuperSpeed)** on bus
      2 behind the ASMedia ASM107x hub, up from 480 Mbps — confirmed
      2026-08-24 via `/sys/bus/usb/devices/*/speed` showing `5000` for
      all four `TerraMaster TDAS` entries. Cause #2's fault class is
      gone with it: **zero** `uas_eh_*` / `stat urb: status -71` events
      across the 23h since, versus the recurring multi-drive faults
      documented below, and `zpool status -x` reports all pools
      healthy. That single change addresses causes #1, #2 and #4 —
      exactly as the "if/when revisited" note below predicted. Cause #3
      (sanoid's minutely recursive walk) is moot: the zrepl migration
      removes sanoid entirely.

      **Measured 2026-08-24 13:45 under real load** (homelab's first
      zrepl local replication, ~1.62T transferred): `zpool iostat -v
      zbackup` shows ~245-261MB/s aggregate device bandwidth, i.e.
      **~122-130MB/s of actual data** — each mirror disk writes the full
      copy, so the pool row sums the two. Confirmed independently by
      dataset growth: 1.62T in ~3h45m ≈ 124MB/s. Against the old
      ~20MB/s-per-disk / ~40MB/s aggregate, that is **roughly 6x**.

      Consequence: **the old ~40h estimate for torrent's ~3.13TB is badly
      out of date.** At ~125MB/s it is on the order of 7-8h. Still
      unproven for a *remote* SSH-transported pull as opposed to this
      local one — torrent's first pull remains the honest datapoint for
      that.

      Not re-tuned: the 15m replication interval and tiered `archive`
      grid were chosen under the old ceiling and are now conservative
      rather than forced. Left as-is deliberately.

      Original diagnosis, kept for the record: Investigated live during
      torrent's first-ever `myBackupPush` run (3.13TB initial `zfs
      send`). Ruled out: network (confirmed direct LAN peer connection
      via `tailscale status --json`'s `CurAddr: 192.168.1.154:41641` —
      not relayed through DERP), CPU (modest usage on both ends), and
      raw disk bandwidth (`zpool iostat -v zbackup` showed each mirror
      disk only doing ~20MB/s, well under HDD capability). Actual
      causes, roughly by impact:
      1. **`zbackup`'s 2 disks (and `zdata`'s other 2) are all USB
         2.0 High-Speed (480 Mbps, confirmed via `lsblk -o TRAN` =
         `usb` and `/sys/bus/usb/devices/*/speed` = `480`), sharing
         one hub on a single upstream link** (`1-6.1`-`1-6.4`). That's
         a hard ~40-60MB/s ceiling across *all four* drives combined —
         not per-drive — which lines up almost exactly with the
         measured aggregate write rate. This is very likely the same
         physical enclosure/hub/cabling behind the pre-existing
         `hosts/homelab/README.md` "zdata pool: recurring I/O
         suspensions" known issue — same drives, same USB link, same
         symptom class (command timeouts/resets), not necessarily two
         separate problems.
      2. **Real USB-level faults recurring on the same link**:
         `dmesg` shows `uas_eh_abort_handler`/`uas_eh_device_reset_handler`
         and `stat urb: status -71` across multiple drives (`sdb`,
         `sdc`, `sdd`, `sde`) at multiple points in time (including
         within the hour, and again from 5+ days ago) — not a one-off.
         Worth a physical inspection of the enclosure/hub/cable at
         some point, separate from any software fix.
      3. **`services.sanoid.interval = "minutely"` recursively walking
         all of `zbackup`** (`"zbackup" = { use_template = "backup";
         recursive = "yes"; }`, `hosts/homelab/configuration.nix`)
         adds real seek contention on top of an already
         bandwidth-starved USB link — confirmed via `zpool iostat -w
         zbackup`'s latency histogram showing a real tail of read/write
         ops taking 2-8 *seconds*, not just milliseconds, consistent
         with interleaved random (sanoid's metadata enumeration) and
         sequential (the receive stream) I/O thrashing the same two
         physical disks. Even with `autosnap = "no"` on the backup
         template, sanoid still enumerates every existing snapshot
         every 60s to evaluate `autoprune` — real work against a tree
         that includes 168+ historical snapshots on `storage-bulk`
         alone.
      4. **Root cause of the hour-to-hour rate fluctuation, confirmed
         2026-08-21 ~21:00 via a temporary non-invasive correlation
         trace** (2-min samples of `zpool iostat`, cross-referenced
         with `systemctl status` on the local syncoid units — removed
         after the transfer, not left running): homelab's own three
         local `syncoid` jobs (`syncoid-zdata-storage-storage[-bulk]`,
         `syncoid-zroot-local-state`, all hourly) were confirmed
         **`active (running)` continuously for ~2 hours** (since
         19:01:26, still running at the 21:00 check) — competing with
         torrent's transfer for the same USB-bandwidth-capped pool the
         entire time. These are normally-fast incremental syncs that
         finish in seconds, but with the USB link already saturated by
         torrent's initial full send, they get starved too, run long
         enough to blow past their next hourly trigger, and end up
         running back-to-back instead of going idle between runs — a
         compounding effect where torrent's big transfer slows the
         local jobs, and the local jobs competing for bandwidth slows
         torrent right back. The aggregate pool write rate itself
         (~33-48MB/s, near the #1 USB ceiling) stayed fairly
         consistent throughout — what fluctuates is how that fixed
         bandwidth splits between torrent's stream and these 3
         concurrent local jobs.
      Not fixed — diagnosis only, explicitly requested not to change
      anything mid-transfer. If/when revisited: consider a real
      USB 3.0 (SuperSpeed) link or SATA/HBA passthrough for this
      enclosure (addresses #1, #2, and #4 all at once — the local-job
      contention only compounds because #1's ceiling is so low), and/or
      loosening `zbackup`'s sanoid cadence off the global `minutely`
      interval since it's a receive-only target that never autosnaps
      anyway (addresses #3) — but both are real infra/config changes
      that need their own separate decision, not bundled into this.

- [ ] **2026-08-18: migrate torrent and thinkpad to impermanence.**
      Agreed as a prerequisite for eventually shrinking their zfs-backup
      scope (see the zfs-backups item below) — both hosts currently
      keep `zroot/local/root` as durable state, impermanence would wipe
      root on boot and move real state to an explicit persist dataset.
      Needs its own disko layout changes + persist-path audit per host,
      and should be VM-tested before real hardware per
      `feedback_test_remote_deploys_in_vm`. Not started.

- [ ] **2026-08-19: syncoid push backups, torrent + thinkpad → homelab
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
      heavily) plus a `zfs-emergency-prune.service` manual escape hatch.
      **Follow-up once impermanence (above) lands**: `zroot/local/root`
      will likely stop being the meaningful thing to back up — update
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
      passes for the whole flake (all 5 nixosConfigurations). **Still
      not deployed/switched anywhere, and this branch is still
      unpushed** — only a local merge commit so far.

      **New hard blocker from the merge**: `secrets/secrets.yaml` had a
      real conflict — both this branch (torrent/thinkpad backup-push
      keys) and master (a samba password from another branch) added new
      secrets in the same spot. The per-key encrypted values merged
      safely as a plain union (each is an independent ciphertext), but
      the file's `sops:` metadata (`lastmodified`/`mac` — a MAC over the
      *entire file's* contents) could not be hand-merged; master's copy
      was kept as a placeholder and **is now stale**. Before trusting
      this file for anything (including the build steps below, which
      already worked because Nix doesn't verify the mac at eval time —
      but real secret *decryption* on a target host will fail once the
      mismatch is caught), the user must run
      `sops updatekeys secrets/secrets.yaml` themselves (not done here —
      never edit sops files directly) to produce a fresh valid mac.

      **Live pool note**: none of the above touches the live homelab
      pool — disko.nix is install-time only, and I'm not running zfs
      commands against a live host without you present. Two things need
      manual handling on your own schedule once you're ready:
      1. `zdata/storage/storage-bulk`'s syncoid target *renamed* from
         `zbackup/backup-bulk/homelab/storage-bulk` (old, this session's
         earlier layout, still the live/deployed path as of this
         writing) to `zbackup/backup/homelab/storage-bulk` (final, only
         in this branch's not-yet-deployed Nix config). **MUST happen
         atomically with deploying this branch to homelab (same
         maintenance window, rename immediately before or immediately
         after `nixos-rebuild switch` — not as a standalone action on
         its own schedule.)** Caught by a peer session
         (backblaze-homelab-reset) reviewing this: if the live `zfs
         rename` runs while homelab is still running the *currently
         deployed* config (which still points syncoid at the old path),
         the next hourly syncoid run looks for a dataset at the old path
         that no longer exists — best case it errors, worst case it
         auto-creates a fresh empty dataset there and starts a full
         ~2.26TiB reseed from scratch, the same failure mode that
         triggered that session's whole backblaze-homelab-reset task in
         the first place. If the old path already has live replicated
         data on homelab (check with `zfs list -r
         zbackup/backup-bulk/homelab`), rename it in place rather than
         losing the history:
         `zfs rename zbackup/backup-bulk/homelab/storage-bulk zbackup/backup/homelab/storage-bulk`
         — then the next syncoid run should pick up incrementally at the
         new target name with no re-send needed, *provided the deployed
         config already matches by the time that run fires*.
      2. Any of `zbackup/backup/legion`, `zbackup/backup-bulk/legion`,
         `zbackup/backup/other`, `zbackup/backup-bulk/other`,
         `zbackup/backup/thinkpad` (the old non-flattened container), or
         `zbackup/backup-bulk/thinkpad`/`zbackup/backup-bulk/torrent`
         (this session's earlier bulk-split layout, now also superseded)
         that exist live and are confirmed unused/empty can be destroyed:
         ```
         zfs list -r zbackup/backup zbackup/backup-bulk   # see what's really there first
         zfs destroy -r zbackup/backup/legion               # only if confirmed placeholder-only
         zfs destroy -r zbackup/backup-bulk/legion
         zfs destroy -r zbackup/backup/other
         zfs destroy -r zbackup/backup-bulk/other
         zfs destroy -r zbackup/backup/thinkpad             # only if empty (superseded, pre-flatten)
         zfs destroy -r zbackup/backup-bulk/thinkpad         # only if empty (superseded, pre-flatten)
         zfs destroy -r zbackup/backup-bulk/torrent          # only if empty (superseded, pre-flatten)
         ```
      I'll handle the live side whenever you're ready to walk through it
      together — not done automatically.

      Checklist to finish rollout:
      - [ ] **BLOCKING, do this first**: run `sops updatekeys
            secrets/secrets.yaml` to refresh the stale mac left by the
            master-merge conflict resolution above. Nothing that reads
            real secrets on a target host should be trusted until this
            is done — a `nixos-rebuild build` succeeding is not proof
            this is fine, since Nix doesn't verify the sops mac at eval
            time, only `sops`/`sops-install-secrets` do, at activation.
      - [x] Push this branch to origin and merge into `master`.
            (2026-08-21) Pushed `worktree-zfs-backup-push`, then fast-
            forward merged straight into `master` (`7706eca..a03ce7c`,
            no merge commit needed — this branch already contained all
            of master's history from the earlier rebase). The
            repo's pre-push hook build-tested every affected host
            (isoimage, torrent, vps, thinkpad, homelab) on both pushes;
            all succeeded. Still no `nixos-rebuild switch` run anywhere
            — code is live on `master` but not deployed to any real
            host yet. `zfs-pool-recovery-restore` can now rebase their
            branch on top whenever they're ready (small mechanical
            import-list conflicts expected, per the earlier dry-run).
      - [ ] Re-verify `nixos-rebuild build --flake .#{homelab,torrent,thinkpad}`
            and `nix flake check` one more time immediately before the
            actual deploy, in case anything else landed on master in
            the meantime.
      - [x] Generate `torrent_backup_push_key` and
            `thinkpad_backup_push_key` ed25519 keypairs. (2026-08-19)
      - [x] Add both private keys to `secrets/secrets.yaml` via `sops
            secrets/secrets.yaml` (never edit sops files directly).
            (2026-08-19, done by the user)
      - [x] Paste both public keys into
            `hosts/homelab/configuration.nix`'s
            `backup-recv.openssh.authorizedKeys.keys`, prefixed with
            `restrict `. (2026-08-19)
      - [x] Re-run `nixos-rebuild build --flake .#{homelab,torrent,thinkpad}`
            to confirm all three build clean once secrets exist. All
            three build clean end-to-end as of 2026-08-19 — no more
            code-side blockers.
      - [ ] Handle the live pool note above: the storage-bulk rename
            MUST land atomically with homelab's `nixos-rebuild switch`
            for this branch (see the detailed caution above) — the
            other dataset cleanup (legion/other/superseded placeholders)
            isn't time-sensitive and can happen whenever.
      - [x] Deploy homelab. **Done 2026-08-21.** Live deploy surfaced
            and fixed two real bugs the build-only testing couldn't
            have caught (both committed): `backup-recv-zfs-allow.service`
            failed because `zfs allow` needs its target dataset to
            already exist — `zbackup/backup/torrent` had never been
            created (no push has run yet), a chicken-and-egg problem on
            first deploy, fixed with a `zfs create -p` pre-step; and
            `health-check.service`'s `backupStaleness` loop crashed
            entirely under `set -e -o pipefail` the first time it hit a
            genuinely nonexistent dataset (vs. one that just has no
            snapshots yet), fixed with `|| true` to let the existing
            empty-string handling take over. Also found and fixed
            (separately, pre-existing, unrelated to this feature):
            homelab's `/etc/nixos` checkout was stuck on an orphaned
            `auto-update` branch from a crashed `flake-update-test`
            run — cleaned up live with explicit go-ahead (see the
            myAutoUpdate git-identity TODO item above) — and
            `secrets/secrets.yaml` needed a real `sops --ignore-mac
            --rotate --in-place` (plain `sops updatekeys` alone doesn't
            touch the mac) to fix the stale mac left by the earlier
            merge conflict resolution; verified by running
            `sops-install-secrets` directly against the built manifest
            before trusting it live. Post-switch: `systemctl --failed`
            clean, `current-system` matches the verified build,
            `backup-recv` user + `zfs allow` delegation on
            `zbackup/backup/{torrent,thinkpad}` confirmed correct,
            `storage-bulk` rename confirmed intact (2.26T + full
            snapshot history), unrelated services from the same merge
            (jellyfin, etc.) unaffected.
      - [ ] Deploy torrent and thinkpad; watch
            `systemctl status backup-push-torrent.service` /
            `journalctl -u backup-push-torrent` for the first real push
            (first run is a full send — expect it to take longer and
            transfer more than subsequent hourly incrementals).
      - [ ] On homelab, confirm snapshots are actually landing:
            `zfs list -t snapshot -r zbackup/backup/torrent` and
            `.../thinkpad`.
      - [ ] Confirm the Tailscale-reachability `ExecCondition` behaves
            as intended: stop tailscaled (or disconnect) on thinkpad,
            confirm `backup-push-thinkpad.service` reports as skipped/
            inactive rather than failed, then reconnect and confirm the
            next timer fire (or a manual `systemctl start`) catches up
            immediately (`Persistent = true`).
      - [ ] Sanity-check `zfs-space-guard.timer` on both hosts: manually
            drop a test dataset's free space (or just review the script
            logic against `zpool list -Hpo capacity`) and confirm the
            15%-free trigger and `keepMin = 2` floor behave as expected
            before trusting it under real pressure.
      - [ ] Confirm `systemctl start zfs-emergency-prune.service` works
            as a manual break-glass action on both hosts (dry-run reading
            the script's `zfs destroy` targets first, since it's
            destructive by design).
      - [ ] Once real backups exist, wire
            `myHealthAlerts.backupStaleness` values (already set) into a
            live check — confirm a Discord alert actually fires if a
            target dataset goes stale past 336h, e.g. by temporarily
            lowering the threshold for a smoke test.

- [ ] **2026-08-18: verify Android SMB share end-to-end** (homelab,
      `modules/services/samba.nix`, commits c5c0f0e..24c4913, moved to
      the dendritic `modules/services/` layout during the
      worktree-android-smb-share rebase). Added Samba alongside the
      existing NFS export (`modules/services/nfs.nix`) so
      Android — which has no usable native NFS client — can reach
      `/storage` and `/storage-bulk` read-write over the tailnet.
      Firewall/interface scoping mirrors nfs.nix (tailscale0 only, port
      445, nmbd/winbindd disabled, plus a `hosts allow`/`hosts deny`
      pair in smb.conf itself for defense-in-depth). Dedicated
      `android-smb` system user (multimedia group, no shell/login) is
      the SMB auth identity; smbd itself still runs as root since the
      upstream module gives it no user/group option and
      setuid-per-request is how Samba works — capability set is
      trimmed with the same always-safe systemd flags used elsewhere in
      this repo instead. `/var/lib/samba` added to homelab's
      impermanence persistence list so the SMB password survives
      reboot. The SMB password itself is now fully declarative: sops
      secret `homelab_samba_android_smb_password` (added by the user
      2026-08-19) plus an idempotent `samba-user-provision` oneshot
      that syncs it into passdb.tdb on every boot/activation before
      samba-smbd starts, auto-restarted on secret rotation via
      sops-nix's `restartUnits` — no manual `smbpasswd` step needed
      anymore. `server signing`/`smb encrypt` mandatory, `ntlm auth =
      ntlmv2-only`, spoolss/printer sharing disabled, and
      `wide links`/`follow symlinks = no` on both shares were added on
      top for defense-in-depth (commit c140108); `samba-user-provision`
      and `samba-smbd` both carry this repo's standard systemd
      hardening flags (`ProtectSystem=strict` on the provisioner,
      `NoNewPrivileges`/`Protect*`/`RestrictNamespaces`/`PrivateTmp` on
      smbd — full `ProtectSystem=strict` deliberately left off smbd
      itself, judged too likely to silently break auth/logging without
      enumerating every path it touches). **Deployed to homelab
      2026-08-21** (`nixos-rebuild switch --target-host root@homelab`)
      — see "homelab auto-update raced a manual deploy" incident note
      below for what happened during the first attempt. Testing done
      post-deploy (from `smbclient`, a real SMB3 client, run both
      locally on homelab and remotely over the tailnet — not yet from
      an actual Android device/app):
      - [x] `samba-user-provision.service` ran successfully
            (`Added user android-smb.` in its journal) and
            `samba-smbd.service` is active
            (`smbd: ready to serve connections...`).
      - [x] `smbclient -L localhost -U android-smb` authenticates with
            the sops-set password and lists both `storage` and
            `storage-bulk`.
      - [x] Read/write confirmed on `/storage`: created a dir + file,
            listed real existing share content (confirms it's serving
            the actual dataset, not empty), landed with
            `android-smb:multimedia` ownership, `0660`/`0770`+setgid
            masks — matches config exactly. Cleaned up afterward.
      - [x] `smb encrypt = mandatory`/`server signing = mandatory`
            didn't reject `smbclient` — since Samba refuses a
            connection outright if a client can't negotiate mandatory
            signing/encryption, successful read/write is direct proof
            both were in effect for this client.
      - [x] Tailnet-only lockdown smoke-tested for real (not just
            firewall-rule inspection): confirmed default-deny via
            `iptables -L nixos-fw` (`nixos-fw-log-refuse` catches
            everything not explicitly accepted) plus `-i tailscale0`
            scoping on both ports, then verified live from a separate
            LAN machine (`torrent`, also on homelab's 192.168.1.0/24) —
            explicit connections to homelab's **LAN IP**
            (`192.168.1.154`) on ports 445 and 2049 both timed out /
            unreachable; the same ports on homelab's **Tailscale IP**
            (`100.98.142.41`) connected successfully. (First attempt
            gave a false "reachable" result for the LAN IP — turned out
            to be a self-connect-via-loopback artifact when tested from
            homelab itself, `ip route get <own-LAN-IP>` resolved to
            `dev lo`; the LAN-vs-tailscale test from a genuinely
            separate host is the one that counts, and it passed.)
      - [x] Connected from an actual Android device — CX File Explorer,
            over Tailscale (`100.98.142.41:445`) — and confirmed
            genuine two-way read/write: created `test.txt` on-device,
            server-side `echo "hello world" > /storage/test.txt`
            (ownership stayed `android-smb:multimedia`, confirming the
            file was the same one the app created, not a new one), and
            the updated content showed up back on the device after
            refresh. End-to-end confirmed working.
            (Two FOSS clients were tried first and ruled out along the
            way, not app/config bugs: **Material Files** — connection
            attempts never reached the server at all, confirmed via
            zero smbd log entries and zero firewall packet/byte counts
            across multiple exact-timestamped retries; root cause
            unconfirmed, suspected app-side state bug, not a server
            config issue. **Ghost Commander** — correctly rejected by
            the server for being SMB1/2-only, real jcifs library, no
            SMB3 support; server's `server min protocol = SMB3` working
            as intended. **SambaLite** (Play Store + F-Droid, Apache
            2.0, SMBJ-based, explicit SMB2/3 support) was researched
            and recommended as the best remaining FOSS option but not
            yet tried, since CX File Explorer — proprietary, not
            FOSS — already confirmed the server side works correctly.
            Worth trying SambaLite for daily use if a FOSS client is
            wanted going forward.)
      - [ ] Still needed: rotate the password once (edit the sops
            secret — user does this, not Claude — then redeploy) and
            confirm `samba-user-provision.service` restarts
            automatically via sops-nix's `restartUnits` and the new
            password takes effect without a manual `smbpasswd` step.

      **Incident note (2026-08-21):** the first deploy attempt landed
      correctly, but `nixos-upgrade.service` (homelab's scheduled
      auto-update job, normally `Thu 03:00` — this run was off-schedule,
      cause unconfirmed) started *before* the manual deploy and finished
      *after* it, activating its own build from homelab's local
      `/etc/nixos` checkout (stale — predates even the dendritic
      migration) and silently reverting the manual switch. That
      auto-update run itself then failed (exit 4) once its own
      switch-to-configuration hit conflicting unit state. No data loss,
      no failed *service* beyond `nixos-upgrade.service` itself, no
      reboot needed — waited for it to fully finish, then redeployed
      cleanly. Separately worth noting: homelab's local `/etc/nixos` is
      still on an old commit (`e8b3458`) with uncommitted `flake.lock`
      changes and an untracked `hosts/android/` directory — worth
      reconciling so the next scheduled auto-update run doesn't build
      from stale/dirty state again.
- [ ] **2026-08-20: test the Geyser/Minecraft changes on homelab once
      deployed.** `services/minecraft.nix` (merged to master at
      `3270eae`, **not yet deployed**) now sets Geyser's
      `above-bedrock-nether-building: true` (fixes Bedrock players
      softlocking above the Nether roof — confirm with a live Bedrock
      client), `ENABLE_AUTOPAUSE`/`MAX_TICK_TIME=-1`/`--cap-add=NET_RAW`
      (confirm the container actually pauses when empty and resumes
      cleanly on the next connection, and that the watchdog doesn't
      fire on resume), and `VERSION = "LATEST"` instead of a pinned
      `26.2` (confirm the modded stack — Geyser, Floodgate,
      DistantHorizons, etc. — still starts cleanly on whatever version
      resolves, since none of `MODRINTH_PROJECTS` pins a mod version).
      None of this has been tested against the running container yet.

- [ ] **2026-08-20: deploy the wg0 IPv4-endpoint fix to homelab, then
      verify it survives a real IPv6 address rotation.**
      `hosts/homelab/configuration.nix`'s wg0 peer now points at vps's
      stable IPv4 (`137.184.45.18:51820`) instead of vps's IPv6
      literal, fixing a bug where the tunnel died silently whenever
      homelab's RFC4941 privacy IPv6 address rotated (confirmed live:
      0% ping both directions despite `persistentKeepalive`). Merged to
      master, **not yet deployed** — the real homelab host is still
      running the old (broken) config until this switch happens.
      Deploy plan: `nixos-rebuild switch --flake .#homelab` (or via
      whatever push-deploy path is standard now), then confirm `wg show
      wg0` shows a fresh handshake and jellyfin/minecraft/factorio are
      reachable through it. Testing (do after deploy, not before): the
      fix itself is straightforward (IPv4 doesn't rotate), but hasn't
      been watched through an actual homelab IPv6 address rotation yet
      — confirm `wg show wg0` keeps a fresh handshake and
      jellyfin/minecraft/factorio stay reachable across the next one or
      two rotations (homelab's privacy addresses appear to rotate on
      the order of hours-to-a-day, based on the two different addresses
      already observed during this investigation).

- [ ] **2026-08-20: deploy `new.factorio`** — merged to master
      (`c7796c9`), not yet deployed. A second Factorio server
      (`modules/services/factorio.nix`'s `factorio-new` container,
      floating `stable` tag, fresh random world) alongside the
      existing `old.factorio` (still pinned to the experimental
      2.1.14 line). Needs: `nixos-rebuild switch` on homelab (brings
      up the container) and vps (opens the 34198/udp DNAT/firewall/
      ratelimit rules), then an `octodns-sync` run (or its hourly
      timer) to push the new `old.factorio`/`new.factorio` A + SRV
      records to Cloudflare. See `hosts/vps/README.md`'s Status
      section. Once deployed, verify: `new.factorio` reachable by
      hostname alone (SRV lookup, untested — first real use of SRV
      records in this repo) and by `:34198`, `docker-factorio-new`'s
      preStart actually rsyncs `old.factorio`'s mods on a real start,
      and `old.factorio` (34197) still works unaffected.

      **2026-08-21: reported unreachable from an actual game client —
      needs investigation.** Everything checked so far looks healthy,
      which makes this confusing:
      - `factorio-new` container on homelab: up 7h, in-game
        (`ServerMultiplayerManager` state `InGame`), authenticated with
        Factorio's auth server, and registered on the public matching
        server (`MatchingServer.cpp: Matching server game '1232520' has
        been created`) at `97.206.73.106:34198` per its own logs.
      - `new.factorio.skyseekerlabs.net` resolves correctly to the vps
        (`137.184.45.18`), and a UDP probe (`nc -u -z -v`) to
        `:34198` got no ICMP unreachable back.
      - Despite both of the above, the user reports the client cannot
        actually connect/join.
      Not yet checked: whether the vps's DNAT/firewall/ratelimit rules
      for 34198 (`hosts/vps/configuration.nix`, added alongside 34197's)
      are actually correct and were deployed — the "needs
      `nixos-rebuild switch` on homelab and vps" step above may not
      actually be done yet despite the container running (the container
      could be up on homelab while the vps-side forwarding was never
      switched); the SRV-record lookup (`_factorio._udp.new.factorio`,
      first real use of SRV in this repo) is also still unverified and a
      plausible culprit if the client resolves via SRV rather than the
      plain A record; and a UDP `nc` probe getting no ICMP-unreachable is
      not proof the DNAT rule itself is forwarding traffic all the way
      through to homelab (only that *something* on the path isn't
      actively rejecting it). Needs real triage: confirm vps's
      `iptables`/DNAT rules for 34198 are live (`iptables -t nat -L
      PREROUTING`), confirm wg0 tunnel from vps to homelab is up and
      carrying this traffic, and test an actual client join rather than
      just a raw port probe.

- [ ] **2026-08-20: `docs/procedures/backup-restore.md` needs real
      content once the `zbackup` restructuring lands.** Currently a
      placeholder. `docs/architecture.md` now documents the two
      backup mechanisms that exist today (restic->Backblaze via
      rclone; sanoid/syncoid->`zbackup`), but restore steps were
      deliberately deferred — coordinated with the `zfs backups plus
      spaceguard` session, which is mid-restructure: renaming the
      `zbackup` dataset layout to a flat `zbackup/backup/<host>/<subdir>`
      convention and adding syncoid push-backups from `torrent`/
      `thinkpad` over Tailscale via a new scoped backup-recv/
      backup-push user pair. A separate `zfs-pool-recovery-restore`
      branch is also refactoring the inline `services.sanoid` block on
      homelab into a new `modules/nixos/zfs-snapshots.nix` module
      (same behavior, different file). Needs: once both land, write
      `docs/procedures/backup-restore.md` for real (restic restore via
      `restic-backblazeWeekly` wrapper; syncoid/zfs-receive restore
      from `zbackup`), and update `docs/architecture.md`'s Backups
      section to describe the final dataset layout instead of the
      current in-flux one.

- [ ] **2026-08-20: build+switch thinkpad and torrent after the
      dendritic migration** (see entry above) — only `vps`/`homelab`
      were fully built during the migration; `thinkpad`/`torrent` were
      evaluated only. Build (not switch) both before relying on them,
      then switch when ready.

- [ ] **2026-08-18: homelab's weekly restic-to-Backblaze backup has no
      safeguard against `myAutoUpdate`'s Thursday auto-switch killing
      a mid-run backup.** During a full-bucket reset/re-test of the
      backup (see this session), we found homelab runs
      `nixos-rebuild switch` every Thursday 03:00 via `myAutoUpdate`
      (`hosts/homelab/configuration.nix`), and `switch-to-configuration`
      restarts any systemd unit whose definition changed — including
      `restic-backups-backblazeWeekly.service` (Type=oneshot,
      `TimeoutStartSec=1w`) if the restic module, its overrides, or a
      shared dep like `pkgs-stable` changes. A run in progress (backups
      have taken multiple days for the ~2.9TiB dataset) would be killed
      with no resumption. Worked around this time by manually pausing
      the `nixos-upgrade` timer for the duration of the manual run.
      Needs a permanent fix: either make the backup service resilient
      to being interrupted/restarted (state/resume support, or a
      `ConditionXXX`/lock that defers an auto-switch while a backup is
      active), or have `myAutoUpdate` skip switching while
      `restic-backups-backblazeWeekly.service` is active.

- [ ] **2026-08-18: homelab backup/replication stack has several
      compounding risks if the box is powered off for an extended
      period (over a month), surfaced while reasoning through the full
      backup reset/re-test.** Grouped as one item since they share a
      root cause (everything below is `Persistent = true` and fires
      its one missed catch-up run right at boot, all at once):
      - **Boot-time contention pile-up**: sanoid (minutely), syncoid
        (hourly), the restic weekly timer, and both `myAutoUpdate`
        timers (fetch + switch) are all `Persistent = true` — after a
        long outage they all queue their catch-up run around the same
        time on boot, recreating (likely worse, since concentrated
        instead of spread out) the resource-contention throttling
        diagnosed live during this session (4 cores, load average
        12-14, multiple ZFS-heavy jobs + restic upload all competing).
      - **Compounds directly with the item above**: if the catch-up
        `nixos-rebuild switch` lands while the catch-up restic backup
        is still mid-run, the service gets killed and restarts from
        scratch — more likely right after a long outage than during
        normal weekly operation, since both are now racing on the same
        boot instead of being naturally staggered.
      - **Self-inflicted history loss from the `--keep-daily 2`
        retention** we set this session (disaster-recovery-only, not
        versioning, per explicit choice): once the first post-outage
        backup succeeds, its prune step drops straight to the 2 most
        recent backup-days, permanently discarding all pre-outage B2
        history at that point. Intentional given the retention
        philosophy, but worth having a documented awareness of before
        it surprises someone during an actual recovery.
      - **Syncoid resume-base pruning, same failure mode as before,
        longer fuse**: the widened retention from `fbf547f` (hourly
        168/7d, daily 14) gives a stuck syncoid target ~1-2 weeks of
        slack now instead of ~1 day, but a target stuck that long
        post-boot (plausible given the contention point above) would
        still hit the exact "resume base pruned, forced full reseed"
        failure that caused this whole reset project.
      - **Unverified**: whether the B2 application key
        (`homelab_backblaze_rclone_config` secret) has an expiration
        date set on Backblaze's side. Couldn't check without exposing
        the secret's contents; confirm on the B2 web console if this
        needs certainty.
      Needs: stagger/serialize the catch-up timers (e.g. `RandomizedDelaySec`
      spread, or explicit ordering) so they don't all fire at once on
      boot, and decide whether the auto-update-vs-backup conflict fix
      above should also gate against this boot-time race specifically.

- [ ] **2026-08-18: sops-nix `age.keyFile` fallback doesn't actually
      fire when `age.sshKeyPaths` fails during early boot** (torrent).
      `profiles/PC.nix` configures both `sops.age.sshKeyPaths = [
      "/home/lilijoy/.ssh/id_ed25519" ]` and `sops.age.keyFile =
      "/var/lib/sops-nix/key.txt"`, with `keyFile` explicitly intended
      as the early-boot fallback since `/home` isn't mounted yet during
      initrd-stage activation (see the comment there). On a real boot,
      the initrd-stage `sops-install-secrets` run failed entirely
      (`Cannot read ssh key '/home/lilijoy/.ssh/id_ed25519': ... no such
      file or directory` immediately followed by `Error getting data
      key: 0 successful groups required, got 0`) instead of falling
      back to `keyFile` — `/run/secrets` never got populated for the
      rest of that boot (git identity, and presumably other
      home/root-critical secrets, all missing) until manually re-run
      post-boot via `run0 sops-install-secrets ...` (which then
      succeeded immediately, confirming `key.txt` itself and its
      `.sops.yaml` registration were never the problem). Looks like a
      real sops-nix bug/limitation: a failed `sshKeyPaths` entry seems
      to poison the whole identity list rather than gracefully falling
      through to `keyFile`. Needs: check for a known upstream sops-nix
      issue/fix, or restructure so boot-critical secrets don't depend on
      an identity path that's guaranteed to fail during initrd (e.g.
      drop `sshKeyPaths` from the boot-time identity list entirely and
      rely on `keyFile` alone there). Not yet reproduced against a clean
      reboot (holding off per the no-unconfirmed-local-restarts rule).

- [ ] **2026-08-18: add IPv6 support for the vps's forwarded game
      ports** (Minecraft 25565/19132, Factorio 34197/34198 — the
      latter added 2026-08-20 for `new.factorio`, same treatment
      needed). Currently IPv4-only: `net.ipv6.conf.all.forwarding` is
      explicitly off on the vps and there are no `ip6tables` DNAT
      rules for these ports, so `minecraft`/`factorio`'s DNS records
      were made A-only (`modules/services/octodns.nix`) after a live
      bug where the AAAA records
      advertised IPv6 reachability that didn't exist, silently
      breaking any client (confirmed: a Bedrock client) that prefers
      IPv6 when a hostname resolves to both. The apex still has an
      AAAA record since Caddy on the vps itself is native IPv6, no
      forwarding needed — this item is specifically about the DNAT'd
      raw TCP/UDP game ports. Needs: enable IPv6 forwarding for wg0
      egress only (not blanket `net.ipv6.conf.all.forwarding`), add
      matching `ip6tables`/`nat` DNAT + FORWARD-accept rules alongside
      the existing IPv4 ones in `hosts/vps/configuration.nix`, an
      IPv6-capable SNAT equivalent so return traffic survives
      WireGuard's cryptokey routing (mirrors the existing IPv4
      POSTROUTING SNAT rule), then re-add the AAAA records.

- [ ] **2026-08-18: layer distributed builders across the tailnet**.
      vps's rebuilds are already offloaded off-box — homelab builds and
      pushes vps's closure via `myPushDeploy` (see
      `hosts/homelab/configuration.nix`), vps itself never
      evaluates/builds. This item is the optional
      follow-on, and applies beyond just vps: set
      `nix.distributedBuilds = true` + `nix.buildMachines` (pointing at
      other tailnet hosts, e.g. homelab/thinkpad/torrent as capacity
      allows) so actual compilation — not evaluation, which stays local
      to whichever machine initiates a given host's rebuild — fans out
      across the tailnet instead of always landing on one machine.
      Purely a build-time-distribution optimization, not required for
      any host's correctness.

- [ ] **2026-08-18: caddy hits a permission-denied race against the
      anubis unix socket right after vps reboots.** Found trawling
      vps's logs: from 03:18–03:47 (right after a 23:47 reboot), every
      request to `jellyfin.skyseekerlabs.net` 502'd with `dial unix
      /run/anubis/anubis-jellyfin/anubis.sock: connect: permission
      denied` (36 requests total), then self-resolved and hasn't
      recurred since (0 in the following ~13h). `caddy`'s `id` shows
      it *is* in the `anubis` group (`hosts/vps/configuration.nix`
      already has `users.users.caddy.extraGroups = [ "anubis" ]`,
      added for exactly this failure mode per the comment there) — so
      this looks like a boot-order race, not a missing-permission bug:
      caddy's group membership or the socket itself isn't ready by the
      time caddy starts serving. Needs: add an explicit
      `systemd.services.caddy.after`/`wants` (or similar ordering) on
      the anubis service/socket so caddy doesn't start accepting
      traffic until anubis's socket exists with the right group perms
      already applied.

- [ ] **2026-08-19: `octodns-sync.service` failing on homelab —
      transient DNS resolution error.** Found during a read-only log
      trawl through homelab (checked against exposed services in
      `hosts/homelab/configuration.nix`; no signs of compromise, SSH
      and service access all traced to known keys/tailnet/LAN). Job
      failed with `requests.exceptions.ConnectionError` /
      `NameResolutionError` trying to reach `api.cloudflare.com`
      (`Failed to resolve 'api.cloudflare.com' ... Temporary failure
      in name resolution`). Timer retries hourly so this may self-heal,
      but worth confirming it isn't recurring (e.g. flaky upstream
      resolver, or the service starting before network-online.target).

- [ ] **2026-08-19: `flake-update-test.service` failing on homelab —
      root has no git identity configured.** Found during the same log
      trawl. The update-branch step fails with `fatal: unable to
      auto-detect email address (got 'root@homelab.(none)')` right
      after the flake inputs are bumped, because `git config
      --global user.email`/`user.name` were never set for root on
      homelab. Needs: set a git identity for root declaratively (e.g.
      via `home-manager.users.root.programs.git` in
      `profiles/server.nix`, alongside the existing root home-manager
      block) so `myAutoUpdate`'s commit step succeeds.

      **Confirmed live 2026-08-21** while deploying zfs-backup-push:
      the crash (2026-08-19 03:01) left homelab's `/etc/nixos` checkout
      on an orphaned `auto-update` branch with an uncommitted
      `flake.lock` bump — `nixos-rebuild switch` was blocked on this
      stale state until manually cleaned up (`git checkout master &&
      git reset --hard origin/master && git branch -D auto-update &&
      git clean -fd`, done live with the user's explicit go-ahead).
      **Note for the eventual fix**: `modules/nixos/auto-update.nix`'s
      `flake-update-test.service` script does `git fetch origin; git
      checkout master; git reset --hard origin/master` *before*
      creating the `auto-update` branch each run, which should already
      self-heal past a prior crash's leftover branch/lockfile diff on
      its own next scheduled run (`git checkout master` + `reset
      --hard` discards it) — but confirm that actually holds once the
      git-identity fix lands, rather than assuming; the crash observed
      here happened before that reset-and-recreate sequence ever got
      a chance to run again (the timer's next fire would have hit the
      exact same git-identity failure and stayed stuck), so it's
      unverified whether the self-heal path was ever actually
      exercised successfully.


## Done

