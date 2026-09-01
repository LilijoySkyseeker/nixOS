---
slug: unify-myzfsdatasetproperties-and-disko-so-one-declaration-covers-both
created: 2026-09-01
status: todo
frozen: false
---

# unify myZfsDatasetProperties and disko so one declaration covers both install and live-switch

## Original plan

Follows directly from
`2026-08-28-nix-state-zfs-snapshot-dir-is-world-traversable-ex.md`#D1
(`snapdir=disabled` via the new `modules/nixos/zfs-dataset-properties.nix`
module) and `2026-09-01-...disko...` — the disko `rootFsOptions`/root-SSD
consolidation commit `718c396`.

**The gap this closes.** `disko.nix`'s `datasets.<name>.options.<prop>`
and `myZfsDatasetProperties."<pool>/<dataset>".<prop>` are two
independent declarations of the same fact today. Disko's `options` is
install-time only — `disko-install`/`nixos-anywhere` turn it into
`zfs create -o prop=value` once, and it plays no role in an ordinary
`nixos-rebuild switch` (not re-read, not re-applied). The
`zfs-dataset-properties` oneshot is the opposite: live, idempotent,
reapplied every boot/switch, no install-time role. Nothing keeps them in
sync — the same property has to be hand-written in two places today,
exactly the drift class this session's disko consolidation was about
closing everywhere else.

**The design, already talked through, not yet built.** Both `disko.nix`
and the `zfs-dataset-properties` module evaluate inside the same NixOS
`config`, so `disko.nix` can read `config.myZfsDatasetProperties."<pool>/<dataset>"`
directly when building that dataset's `options` block instead of
hand-writing a separate literal. One declaration, two consumers:

- **Disko** reads it to seed the property at creation time on a fresh
  install — meaning a newly-installed host gets e.g. `snapdir=disabled`
  from the dataset's very first mount, with **no** "already-cached
  automount" window at all (see the parent plan's G1/D1 for why that
  window exists on an already-installed host).
- **The systemd oneshot** keeps reading the identical value to
  self-heal an already-installed host (homelab's actual situation
  today) without needing a reinstall.

**What this does not remove:** both mechanisms still need to exist.
Disko's contribution is one-time, at creation; the live oneshot is what
makes an already-installed host self-healing rather than a one-time
guarantee that quietly erodes if something ever flips the property back.

## State

**2026-09-01, not started.** Design agreed with the user in conversation
(not yet written into code). Picking this up cold: read `myZfsDatasetProperties`'s
current shape in `modules/nixos/zfs-dataset-properties.nix` and
`hosts/homelab/configuration.nix`'s `zroot/local/state` entry, plus
`hosts/homelab/disko.nix`'s current `datasets."local/state"` block, before
writing anything — the wiring needs disko.nix to depend on the
zfs-dataset-properties module being imported (new coupling; check import
order in `modules/flake/hosts.nix` doesn't already assume the reverse).

## Progress

- [ ] D1 — implementation approach (see Decisions below), confirm no
      surprises before writing code
- [ ] wire `disko.nix`'s dataset `options` to read from
      `config.myZfsDatasetProperties` for datasets that have an entry
- [ ] decide how disko-specific dataset keys (`mountpoint`,
      `postCreateHook`, etc.) that are NOT zfs properties compose with
      the shared value — they must stay disko-only, not leak into the
      live-reapply oneshot's `zfs set` loop
- [ ] build-verify all three ZFS hosts, confirm no unintended closure
      changes (same "byte-identical store path" check used for the
      disko consolidation, where applicable — this change does alter
      disko.nix's *evaluated* `options`, so an identical-hash check
      isn't the right verification here; verify by reading the rendered
      `options` attrset instead)
- [ ] update `2026-08-28-nix-state-zfs-snapshot-dir-is-world-traversable-ex.md`
      and `RESUME.md` once implemented

## Decisions (D)

### D1 — should these two mechanisms share one declaration?

**ANSWERED 2026-09-01:** yes — the user agreed to the design in
conversation and asked for this to be queued as the next item. Not yet
implemented; the how (exact composition of disko-only keys vs shared zfs
properties) is Progress work, not a separate decision, unless something
unexpected turns up while implementing.

## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
