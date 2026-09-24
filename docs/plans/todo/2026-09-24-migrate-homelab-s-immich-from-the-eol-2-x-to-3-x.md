---
slug: migrate-homelab-s-immich-from-the-eol-2-x-to-3-x
created: 2026-09-24
status: todo
frozen: false
kind: task
priority: high
blocked_by:
---

# Clean up after the stable move: immich 3.x, and the journald dual-spelling branch

*(Filename/slug stay immich-centric -- the file is already cited from
`docs/accepted-risks.md` AR-9 and from the flake-update plan, and bare-filename
citations are the stable handle. The journald item was folded in on 2026-09-24
because it is gated on the exact same event.)*

## State

Not started. Filed on 2026-09-24 out of the routine flake update, which is
shipping a knowingly-accepted insecure-package exemption in its place --
see
2026-09-24-routine-flake-update-2026-09-24-and-the-journald-extraconfig-removal.md#D1.

Two separate cleanups, both gated on homelab's nixpkgs-stable pin reaching
26.11. **Item 1 (immich) is the security-relevant one and carries the
priority; item 2 is cosmetic dead-code removal.** They are tracked together
only because the same event unblocks both -- do not let item 2's triviality
delay item 1, and do not treat the stable move alone as completing item 1.

## Original plan

nixpkgs-stable 26.05.10478 marks `immich-2.7.5` insecure: 2.x is EOL
upstream and carries CVE-2026-59258 and CVE-2026-82272. homelab runs it
(`modules/services/immich.nix`, tailnet-only). 3.x ships in 26.11.

The flake update landed a version-exact
`nixpkgs.config.permittedInsecurePackages = [ "immich-2.7.5" ]` scoped to
the immich module, so homelab currently runs a known-vulnerable EOL
service by explicit decision. That exemption is a holding action; this
plan is the actual fix.

Why it was not done inline: it is a major-version jump on a live photo
library with a real database migration, i.e. exactly the shape of change
that needs its own verified backup, a VM test and an observed switch --
not a bolt-on to a lockfile bump.

- [ ] Read immich's own 2.x -> 3.x upgrade notes and breaking changes
      (source and release notes, not assumption)
- [ ] Decide how 3.x arrives on a stable-pinned host: wait for stable to
      reach 26.11, or pull the package/module from unstable in the
      meantime, and whether the stable NixOS module can even drive 3.x
- [ ] Confirm a restorable backup of the immich database *and*
      `/storage/immich` before touching anything
      (docs/procedures/backup-restore.md)
- [ ] VM-test the migration, not just the build
      (docs/procedures/vm-testing.md)
- [ ] Deploy, observe, then remove the `permittedInsecurePackages` entry
      from `modules/services/immich.nix` and retire AR-9 in
      docs/accepted-risks.md -- and check `immich-machine-learning` moved
      too, since it is a separate derivation the exemption never named

## Item 2 -- remove the journald dual-spelling branch

`modules/nixos/alloy.nix` carries a `journalSizeCap` binding that picks
between `services.journald.settings.Journal.SystemMaxUse` (26.11) and
`services.journald.extraConfig` (26.05), because homelab and the
`loki-pipeline` test evaluate against stable while the other three hosts
are on unstable. See
2026-09-24-routine-flake-update-2026-09-24-and-the-journald-extraconfig-removal.md#G2.

Once *every* consumer is on 26.11, the `else` arm is dead. It is harmless
dead code, not a failure mode -- nothing breaks if this is never done --
but it is also invisible once it stops being taken, which is why it is
written down here rather than left to be noticed.

- [ ] Confirm nothing evaluating this module is still on 26.05 -- homelab's
      pin *and* the `loki-pipeline` test's `pkgs`
- [ ] Collapse `journalSizeCap` to the `settings.Journal` form and drop the
      `options` module argument if nothing else uses it. **Keep
      `Storage = "persistent"` when collapsing** -- it is a deliberate pin,
      not part of the compat shim, and is easy to delete by accident along
      with the branch (see
      2026-09-24-routine-flake-update-2026-09-24-and-the-journald-extraconfig-removal.md#G6)
- [ ] Re-run `nix flake check --no-build`; the test node is the easy one to
      forget

## Progress


## Decisions (D)


## Gotchas (G)

### G1 -- keep the `Storage` pin when collapsing the journald branch

Item 2's one real trap, given an anchor of its own so
`modules/nixos/alloy.nix` can cite it precisely rather than pointing at
this file as a whole.

The 26.11 arm of `journalSizeCap` carries two things that look alike and
are not: `SystemMaxUse`, which the branch exists to set on both trees,
and `Storage = "persistent"`, which is a deliberate pin added because
26.11 stopped emitting nixos's own default
(2026-09-24-routine-flake-update-2026-09-24-and-the-journald-extraconfig-removal.md#G6).

Collapsing the branch means deleting the `else` arm and the `options`
argument -- **not** the `Storage` line. Dropping it would silently hand
journal persistence back to systemd's compile-time default on every host
at once, which is exactly the inheritance the pin was added to stop.
Nothing would fail or warn; the file would simply stop saying it.


## Findings (F)
*(populated by security/docs-updater when invoked)*

_security finished 2026-09-24T08:46:54Z (code 348412538fbab592) -- see Findings above._
