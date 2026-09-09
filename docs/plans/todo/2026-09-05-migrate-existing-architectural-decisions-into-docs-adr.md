---
slug: migrate-existing-architectural-decisions-into-docs-adr
created: 2026-09-05
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# migrate existing architectural decisions into docs adr

## State

**2026-09-05, not started.** `docs/adr/` contains ADR-0001 and a README
describing the practice and its relationship to plan files. Nothing has
been backfilled.

## Original plan

`docs/adr/` was started on 2026-09-05 with
[`0001-zfs-policy-tiers-and-the-mydatasets-registry.md`](../../adr/0001-zfs-policy-tiers-and-the-mydatasets-registry.md).
The repo already contains years of architectural decisions with no ADR:
some in `docs/architecture.md`, some only in frozen `docs/plans/done/`
files, some in nothing but commit messages. Backfill the ones that meet
the bar.

Deferred out of
`2026-09-05-adopt-zfs-policy-tiers-and-a-mydatasets-registry.md#D8`
(2026-09-05) so that adopting the ADR practice did not turn into a
documentation project blocking the log-monitoring work.

**Ordering.** Depends only on ADR-0001 existing, which it does. Does not
block anything. Best done incrementally rather than as one sweep.

## Progress

- [ ] inventory candidate decisions — see D1
- [ ] write ADRs for the ones that meet the bar
- [ ] point `docs/architecture.md` at the ADRs it is superseded by,
      without duplicating them — see D2
- [ ] decide whether frozen plan files get any back-reference — see D3

## Decisions (D)

### D1 — which existing decisions qualify?

The bar is all three of: hard to reverse, surprising without context, and
the result of a real trade-off. Obvious candidates from a first read:

- the dendritic `flake.modules.<class>.<name>` registration model
- the two-nixpkgs split (stable for homelab, unstable for the rest)
- zrepl replacing sanoid/syncoid, and homelab **pulling** rather than
  sources pushing
- impermanence as the default host shape
- CrowdSec replacing fail2ban
- no `sudo`, `run0` only
- dedicated service users plus the systemd hardening baseline

Not every one of these will qualify — several may be unsurprising enough
that no reader would ask why.

### D2 — what happens to `docs/architecture.md`?

It should not become a stub, and content should not be duplicated into
both places. Likely shape: `architecture.md` keeps describing *how the
system is built* and cites ADRs for *why a given shape was chosen*. Needs
deciding before the first backfill, or the two will drift.

### D3 — do frozen plan files get back-references?

Frozen plans cannot be edited, so a decision that graduates into an ADR
cannot be annotated in its originating plan. Either the ADR cites the
plan (one-directional, easy) or nothing links them. Probably the former,
but worth stating so it is consistent.

## Gotchas (G)

### G1 — append-only and freezing make this one-directional

`docs/plans/done/` files are checksummed and frozen; the pre-commit hook
rejects edits to them. Any linkage between an old decision and its new
ADR has to be written on the ADR side.

## Findings (F)
*(populated by security/docs-updater when invoked)*
