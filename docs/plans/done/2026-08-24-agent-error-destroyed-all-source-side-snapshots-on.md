---
slug: agent-error-destroyed-all-source-side-snapshots-on
created: 2026-08-24
status: done
frozen: true
---

# agent error destroyed all source-side snapshots on homelab during legacy-snapshot cleanup — recovered via the surviving replication cursor bookmark, no full resend needed

## Original plan

- [x] **2026-08-24: agent error destroyed all source-side snapshots on
      homelab during legacy-snapshot cleanup — recovered via the
      surviving replication cursor bookmark, no full resend needed.**
      While destroying the sanoid-era `autosnap_*` snapshots on
      `zdata/storage/storage`, `zdata/storage/storage-bulk`, and
      `zroot/local/state`, a script computed the oldest/newest
      `autosnap_` snapshot to build a `zfs destroy -r
      dataset@first%last` range, but didn't check that `first`/`last`
      came back empty — the automatic prune ceiling had already
      destroyed them itself moments earlier, once
      `preserveLegacySnapshots=false` deployed. The resulting
      `dataset@%` (empty on both sides) destroyed **every** snapshot on
      all three datasets, not just the legacy ones.

      **No data was actually lost.** The live filesystems were untouched
      (only snapshots were targeted), `zbackup`'s already-replicated
      copies were untouched (destination-side, not in scope), and
      crucially the `#zrepl_CURSOR_*` replication cursor bookmarks
      survived (bookmarks don't depend on their originating snapshot
      still existing). Once the next periodic snap-job cycle produced a
      fresh snapshot, `local-pull` used the surviving bookmarks to send
      small incrementals (tens of MiB) rather than a ~2.6TiB full resend.
      Verified via `zrepl status --mode dump` showing `DONE` with no
      errors on all three filesystems.

      **Lesson:** never build a `zfs destroy` snapshot range from
      shell-variable interpolation without checking both ends are
      non-empty first — `dataset@%` is apparently accepted as "all
      snapshots" rather than erroring.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
