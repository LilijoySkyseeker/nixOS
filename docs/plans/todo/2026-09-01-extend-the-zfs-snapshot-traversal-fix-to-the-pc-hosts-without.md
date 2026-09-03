---
slug: extend-the-zfs-snapshot-traversal-fix-to-the-pc-hosts-without
created: 2026-09-01
status: todo
frozen: false
---

# extend the .zfs snapshot-traversal fix to the PC hosts without breaking backup browsing

## Original plan

`zroot/local/state` on homelab got `snapdir=disabled` in
`2026-08-28-nix-state-zfs-snapshot-dir-is-world-traversable-ex.md`, closing
the world-traversable-`.zfs` exposure there (any local uid could read old
snapshot contents at old permissions by explicit path — proven live, and
how the factorio credentials leaked). torrent and thinkpad have the
identical mechanism on `zroot/local/home`/`zroot/local/root` and were
deliberately left alone: the user uses `.zfs/snapshot` directly to browse
their own backups on the PCs, and `snapdir=disabled` removes that
entirely rather than narrowing it. This plan is where that gets solved
properly instead of just staying unfixed indefinitely.

The mechanism to apply it, once a decision lands, already exists and
needs no new code: `modules/nixos/zfs-dataset-properties.nix`
(`myZfsDatasetProperties`) — set the option on torrent/thinkpad the same
way homelab does, or don't, depending on what D1 below decides.

## State

**2026-09-01, just opened, nothing decided yet.** Carried from the
parent plan's D2 so it doesn't rot silently un-tracked. No research done
yet on the options below beyond naming them.

## Progress

- [ ] D1 decide the mechanism for the PCs


## Decisions (D)

### D1 — how to close this on the PCs without losing backup browsing? UNDECIDED

Candidates, none evaluated yet:

- **Do nothing, accept the risk** — the exposure is real but the PCs'
  threat model may tolerate it differently than homelab's (homelab has
  jellyfin, the one internet-reachable service on that host, as a named
  path to exploit it; the PCs don't run anything comparable listening on
  a public/tailnet-reachable address today). Needs the same rigor as any
  other `accepted-risks.md` entry, not just "PCs are lower priority."
- **A narrower path than the whole dataset** — e.g. a *child* dataset for
  whatever the user actually browses via `.zfs`, left at `hidden`, with
  everything else (including any secrets-adjacent paths) on a sibling
  dataset at `disabled`. Only works if the two don't overlap in practice,
  which needs an actual inventory of what's under `zroot/local/home`
  today, not a guess.
- **A different access path entirely** — e.g. a script/alias that
  explicitly `mount -t zfs <dataset>@<snap> <target>`s a chosen snapshot
  on demand (same mechanism restic already uses, proven unaffected by
  `snapdir`), so browsing stays possible without leaving `.zfs` itself
  open to every local uid all the time.
- **Wait for the impermanence migration** — `zroot/local/root` mostly
  stops mattering once torrent/thinkpad are impermanent (see
  `2026-08-18-migrate-torrent-and-thinkpad-to-impermanence.md`), the same
  way homelab's own root already doesn't need this. Doesn't help
  `zroot/local/home`, which is the one the user actually browses.

## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

Carried from `2026-08-28-nix-state-zfs-snapshot-dir-is-world-traversable-ex.md#D2`:


Deliberately scoped out of D1. torrent and thinkpad hold the equivalent
exposure on `zroot/local/home` (and `zroot/local/root`) — the same
mechanism, same risk shape, just not the credential that happened to get
proven disclosed first. Not applied there now because the user uses
`.zfs/snapshot` directly to browse their own backups on the PCs, and
`snapdir=disabled` would remove that entirely, not just narrow it.


**DEFERRED 2026-09-01:** PCs excluded from this fix on purpose -- see the decision text. Carried to a new backlog plan rather than left to rot silently here.
