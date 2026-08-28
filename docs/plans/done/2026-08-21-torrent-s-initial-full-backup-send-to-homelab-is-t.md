---
slug: torrent-s-initial-full-backup-send-to-homelab-is-t
created: 2026-08-21
status: done
frozen: true
---

# torrent's initial full backup send to homelab is throughput-limited to ~20-40MB/s — root-caused while it was in progress. RESOLVED 2026-08-23 in hardware

## Original plan

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

      **Moved here 2026-08-25** — was already marked `[x]` and fully
      resolved but had been left sitting in `TODO.md`'s Active section
      instead of moved, against this file's own convention.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
