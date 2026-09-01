---
slug: nix-state-zfs-snapshot-dir-is-world-traversable-ex
created: 2026-08-28
status: todo
frozen: false
---

# /nix/state/.zfs is world-traversable, exposing every secret that ever touched a persisted directory

## Original plan

Split out 2026-08-28 from
`2026-08-28-fix-srv-permissions-stop-three-systems-fighting-ov.md`, whose
finding F1 proved this while reviewing an unrelated permission fix. That
plan fixes one directory's mode; this is the mechanism underneath, and it
is broader than any single service.

**The finding.** `/nix/state/.zfs` is mode **0777**. `snapdir=hidden`
hides it from `readdir` but does **not** block traversal by an explicit
path, so any local uid can walk
`/nix/state/.zfs/snapshot/<name>/...` and read file contents *as they
were at snapshot time* — at the permissions they had at snapshot time.

Verified live on homelab: reading
`/srv/factorio/main/config/server-settings.json` (mode 0644, containing
the factorio.com account token and game password) as uid 65534 via
`setpriv`, through one of 57 retained `zroot/local/state` snapshots.

**Why this is worse than one bad file mode.** Tightening a directory
today does nothing about the snapshots already taken. Every secret that
has ever sat in a persisted directory at a readable mode is still
readable through the snapshot path for as long as that snapshot is
retained — and `zroot/local/state` is one of the two datasets restic
pushes to Backblaze, so those copies are offsite too.

**Why it is reachable, not theoretical.** `jellyfin` (uid 999) is the one
internet-reachable service on homelab (vps Caddy + Anubis → wg0 → 8096),
and its pinned unit sets `ProtectSystem = true` rather than `"strict"`,
so `/nix/state` is fully readable from inside its sandbox. Code execution
in jellyfin reads any of it.

## State

**2026-09-01.** D1 answered and implemented: `snapdir=disabled` on
`zroot/local/state` (homelab only), via the new
`modules/nixos/zfs-dataset-properties.nix` module, build/VM-test-verified
(`tests/zfs-dataset-properties.nix`), not yet deployed. D2 (extend to the
PCs) deferred and carried to
`2026-09-01-extend-the-zfs-snapshot-traversal-fix-to-the-pc-hosts-without.md`.
Remaining open items are the two Progress bullets below — auditing for
other secrets that sat in persisted dirs at readable modes, and rotating
whatever that turns up.

## Progress

- [x] D1 decide the mechanism — `.zfs` mode, `snapdir`, or unit sandboxing
- [ ] audit which other secrets have sat in persisted dirs at readable
      modes; factorio's is the one that has been *proven*, not
      necessarily the only one
- [ ] rotate whatever that audit turns up — see rotation item 12 for the
      factorio half, already agreed

## Decisions (D)

### D1 — what actually fixes this? UNDECIDED

Candidates, none evaluated properly yet:

- **`chmod 0700 /nix/state/.zfs`** — direct, but the `.zfs` control
  directory is synthetic and ZFS may reassert or ignore the mode. Needs
  testing rather than assuming.
- **`snapdir=hidden` is already set and is not sufficient** — established
  above. Do not let a future reader conclude it protects anything; it is
  a `readdir` convenience, not a boundary.
- **Tighten the consuming units instead** — `ProtectSystem = "strict"`
  plus explicit `ReadWritePaths` on jellyfin and anything else with a
  network-facing attack surface. Narrows the blast radius without
  touching ZFS semantics, and is aligned with `docs/hardening.md`. Does
  not help against a local shell.
- **Reduce snapshot retention on `zroot/local/state`** — shortens the
  window but does not close it, and trades against the backup guarantees
  those snapshots exist to provide. Probably not the lever.

The honest framing: the mode is the mechanism, but the *durable* fix is
that secrets should never be written into persisted directories in
plaintext at readable modes in the first place. They belong in
`/run/secrets` (tmpfs, 0400 root), which sops-nix already provides. Where
a service insists on materialising them into its own config file — as
factorio's container does with `server-settings.json` — that file's
directory must be 0700 *before* the first snapshot, not after.


**ANSWERED 2026-09-01:** Use snapdir=disabled on the affected server datasets (zroot/local/state on homelab), not chmod on .zfs and not unit sandboxing alone. Chosen after empirically testing all candidates live on homelab (throwaway datasets, destroyed after): chmod 0700 on .zfs works but does NOT persist -- .zfs is synthesized fresh on every mount, resets to 0777 on unmount/mount, would need a custom reapply-on-mount unit to mean anything. snapdir=disabled is real dataset metadata: survives a full unmount/mount cycle with the block intact, blocks ALL access including root's own (ENOENT, not just a permission check, on a dataset whose .zfs was never touched before disabling), and needs no custom mechanism -- it is a native property. Verified no regression to restic's offsite backup: it mounts snapshots via explicit 'mount -t zfs <snap> <target>', a completely separate mechanism from the .zfs virtual directory, confirmed unaffected by snapdir either way. One real caveat, also verified empirically: if .zfs was already accessed before the property flips to disabled, that specific already-mounted snapshot view stays reachable until the dataset is unmounted+remounted or the host reboots -- flipping the property alone does not retroactively close an existing automount. Implemented as a new reusable module, modules/nixos/zfs-dataset-properties.nix (myZfsDatasetProperties option), applied via a systemd oneshot hooked to zfs-mount.service, so it self-heals every boot/switch rather than being a one-off manual command -- this also means the mount-cycle caveat above is covered on every normal reboot going forward, just not retroactively for access that happened before the first deploy. Servers only (homelab) -- PCs need easy .zfs-based backup browsing per the user, see D2.

### D2 — extend snapdir=disabled (or an equivalent) to the PC hosts?

Deliberately scoped out of D1. torrent and thinkpad hold the equivalent
exposure on `zroot/local/home` (and `zroot/local/root`) — the same
mechanism, same risk shape, just not the credential that happened to get
proven disclosed first. Not applied there now because the user uses
`.zfs/snapshot` directly to browse their own backups on the PCs, and
`snapdir=disabled` would remove that entirely, not just narrow it.


**DEFERRED 2026-09-01:** PCs excluded from this fix on purpose -- see the decision text. Carried to a new backlog plan rather than left to rot silently here.


**CARRIED 2026-09-01:** see `2026-09-01-extend-the-zfs-snapshot-traversal-fix-to-the-pc-hosts-without.md`

## Gotchas (G)

### G1 — this is the same shape as F-P7-02, and the audit already got that one half-wrong

`F-P7-02` (zrepl key in `/tmp` on torrent) is the same pattern: a secret
written to a normal path, then captured by automatic snapshots. That
finding claimed the copies reached Backblaze; they do not, because restic
only mounts `zroot/local/state` and `zdata/storage/storage` and never
`zbackup/*` — corrected 2026-08-27.

This one is the reverse: `zroot/local/state` **is** in restic's set, so
these copies genuinely are offsite. Do not carry the F-P7-02 correction
over to this item and conclude it is contained.

## Findings (F)
*(populated by security/docs-updater when invoked)*
