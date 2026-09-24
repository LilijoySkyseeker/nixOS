---
slug: track-and-retire-the-untracked-manual-pins-and-temp-workarounds
created: 2026-09-24
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# Track and retire the untracked manual pins and TEMP workarounds

## State

Not started. Filed 2026-09-24 off the back of the routine flake update
(2026-09-24-routine-flake-update-2026-09-24-and-the-journald-extraconfig-removal.md),
after a sweep for manual pins found six with no removal condition recorded
anywhere. This plan is the missing record; it does not itself remove
anything.

## Original plan

The update added two deliberate pins, both tracked on the way in (AR-9 and
2026-09-24-migrate-homelab-s-immich-from-the-eol-2-x-to-3-x.md). That
prompted the obvious question -- what about the ones already here? A sweep
for `permittedInsecurePackages`, `allowBroken`, `mkForce`, cross-tree pins
and TEMP/FIXME/"until" comments turned up six items with no removal
condition in `docs/accepted-risks.md`, `docs/plans/` or anywhere else.

The pattern worth naming: two of them *were* found by the 2026-08-26 audit
and written up as findings, but a finding in a dated audit is not a
tracked task. Nobody promoted them, so they aged a month with no owner.
That is the gap this plan closes, independently of whether each item is
then kept or removed.

Each item below states what would retire it. None is urgent; the point is
that "decided to keep" and "nobody looked" stop being indistinguishable.

### 1. `modules/flake/pkgs.nix:13-15` -- stale `electron-39.8.10` permit

`permittedInsecurePackages = [ "electron-39.8.10" ]` on `pkgsUnstable`,
which every host draws from. Audit finding F-P8-20
(`docs/audits/2026-08-26/P8-supply-chain-secrets.md`) rated it PLAUSIBLE
that nothing consumes it any more. Never promoted out of the audit.

- [ ] Remove the entry, build all five hosts; if they build, it was dead
- [ ] If something does need it, name the consumer in a comment and move
      the entry next to it rather than leaving it fleet-wide

### 2. `modules/flake/pkgs.nix:22` -- `permittedInsecurePackages = [ "" ]`

An empty string matches no package. Same finding F-P8-20 calls it
meaningless outright. There is no version of "keep this" that is correct.

- [ ] Delete the line

### 3. `hosts/torrent/configuration.nix:55` -- `allowBroken` for r8125

`nixpkgs.config.allowBroken = true; # check on next stable release to see
if needed`. The comment states its own removal condition, and that
condition has now passed twice unactioned. `allowBroken` is host-wide: it
admits *any* broken package, not just the driver it was added for.

Checked against both trees pinned by this update -- `r8125`'s `meta`
(`pkgs/os-specific/linux/r8125/default.nix:41-47`) carries no
`broken = true` on either 26.05 or 26.11. Audit finding F-P5-15 reached
the same conclusion a month earlier. So the stated reason has expired on
the evidence; what is untested is whether something *else* in torrent's
closure now leans on it.

- [ ] Remove the line and `nixos-rebuild build --flake .#torrent`
- [ ] If it fails, record what actually needs it -- that is the thing
      worth knowing, and nobody currently knows it

### 4. `hosts/isoimage/configuration.nix:94-95` -- `allowBroken`, same driver

`# TEMP BYPASS FOR 'r8125' driver`. Same situation as item 3, but this one
the 2026-08-26 audit never saw -- isoimage was out of scope for the
workstation part, so it has no finding at all.

- [ ] Same test as item 3, against `.#isoimage`

### 5. `modules/profiles/default.nix:58` -- `zfs-prune-snapshots # TEMP, zfs needs module`

Fleet-wide package whose comment says it is standing in for a proper
module. Either the module is worth writing or the comment is stale; both
are fine answers, but the current state asserts an intent nobody is
tracking. Note this sits close to the zrepl/ZFS retention work, so decide
it *with* that rather than in isolation.

- [ ] Decide: write the module, or drop the TEMP claim and keep the
      package as a plain tool

### 6. `modules/nixos/tooling.nix:99` -- `theme = lib.mkForce "gruvbox_dark"; # TEMP`

Lowest stakes here by a wide margin -- a forced lualine theme, cosmetic,
no security or availability angle. Listed only so the sweep is complete
and the TEMP marker does not outlive whatever it was working around
(most likely a stylix interaction).

- [ ] Confirm whether stylix now themes lualine correctly; if so, drop the
      `mkForce`

## Progress


## Decisions (D)


## Gotchas (G)

### G1 -- an audit finding is not a tracked task

Items 1, 2 and 3 were all found by the 2026-08-26 audit and written up
properly. They still went a month with nobody owning them, because they
live in a dated audit directory that is read when someone goes looking,
not in `todo/`. `docs/audits/` is a point-in-time record by design, so
this is not a criticism of the audit -- it is a gap in the handoff
between the two.

Worth considering when the next audit closes out: anything rated
"needs-check" rather than fixed or accepted should leave the audit as a
`plan-new`, or it will sit exactly like these did. Item 4 is the sharper
version of the same point -- it was never audited at all, so no process
short of a fresh sweep would ever have surfaced it.

## Findings (F)
*(populated by security/docs-updater when invoked)*

_docs-updater finished 2026-09-24T09:00:34Z (code abd899e347743095) -- see Findings above._
