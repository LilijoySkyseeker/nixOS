---
slug: nix-state-zfs-snapshot-dir-is-world-traversable-ex
created: 2026-08-28
status: todo
frozen: false
---

# /nix/state/.zfs is world-traversable, exposing every secret that ever touched a persisted directory

## Original plan

Split out 2026-08-28 from
`fix-srv-permissions-stop-three-systems-fighting-ov-2026-08-28.md`, whose
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

## Progress

- [ ] D1 decide the mechanism — `.zfs` mode, `snapdir`, or unit sandboxing
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
