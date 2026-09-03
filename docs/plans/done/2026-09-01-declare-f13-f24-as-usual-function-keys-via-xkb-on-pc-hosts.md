---
slug: declare-f13-f24-as-usual-function-keys-via-xkb-on-pc-hosts
created: 2026-09-01
status: done
frozen: true
---

# Declare F13-F24 as usual function keys via XKB on PC hosts

## Original plan

User request, verbatim intent: in KDE System Settings -> Keyboard ->
Keyboard -> Key Bindings -> Function Keys, there is a checkbox "Use
F13-F24 as usual function keys". Declare that setting declaratively in
this config so both `torrent` and `thinkpad` get it, via the shared PC
module. Initial framing said "hopefully with plasma manager"; the user
later corrected that plasma-manager may not be the right mechanism and
asked for whatever the native way of managing this is (see D1). A
further correction moved the setting out of the KDE-specific module into
the general PC module, since it's a keyboard/XKB setting, not specific
to the KDE Plasma desktop environment (see D2).

## State

Implemented and committed. `services.xserver.xkb.options` set in
`modules/profiles/PC.nix` (the shared `profile-pc` NixOS module both
`torrent` and `thinkpad` import via `modules/flake/hosts.nix`), not via
plasma-manager and not in `modules/nixos/kde.nix`. Both hosts build
clean (`nixos-rebuild build`, not switched); pre-push hook also rebuilt
the whole fleet clean. Committed as `b4faed8` on branch
`worktree-plasma-manager-fkeys`, PR #42 opened, not yet merged. Not
switched on either live host -- that's the user's call, per repo
convention.

## Progress

- [x] Identify the underlying XKB option name/description from the
      pinned nixpkgs `xkeyboard-config` source (not assumed): group
      `fkeys`, option `fkeys:basic_13-24`, description "Use F13-F24 as
      usual function keys" -- exact match to the KDE System Settings
      checkbox text.
- [x] D1 -- plasma-manager vs. native NixOS mechanism
- [x] D2 -- module placement: KDE-specific vs. general PC profile
- [x] Set `services.xserver.xkb.options` in `modules/profiles/PC.nix`
- [x] G1 -- `types.commas` only merges definitions from *other* modules,
      not against its own module default; caught by inspecting the
      rendered `/etc/X11/xorg.conf.d/00-keyboard.conf`, fixed by keeping
      the prior default (`terminate:ctrl_alt_bksp`) explicit alongside
      the new option
- [x] `nixfmt` the changed file
- [x] `nixos-rebuild build --flake .#thinkpad` -- succeeds
- [x] `nixos-rebuild build --flake .#torrent` -- succeeds
- [x] Verify rendered `XkbOptions` line contains both options
- [x] D3 -- statix "repeated keys" warning on the new line
- [x] `/simplify` pass -- 4 parallel review agents (reuse, simplification,
      efficiency, altitude), nothing to fix on any axis
- [ ] Commit

## Decisions (D)

### D1 -- plasma-manager vs. native NixOS mechanism
Initial framing asked for plasma-manager. Investigated
`programs.plasma.input.keyboard.options` (plasma-manager's `modules/input.nix`,
fetched from `nix-community/plasma-manager` upstream) -- it writes the
same XKB option string into per-user `~/.config/kxkbrc`, requiring a new
flake input (`plasma-manager`, following `home-manager`/`nixpkgs-unstable`)
purely to toggle one XKB option. User then said: "this may not be through
plasma manager, use whatever is the native way of managing this."
**ANSWERED 2026-09-01:** use the native NixOS mechanism,
`services.xserver.xkb.options` -- no new flake input, applies system-wide
(SDDM greeter and any TTY included) rather than only once a Plasma
session has loaded its own per-user config.

### D2 -- module placement: KDE-specific vs. general PC profile
First placed the option in `modules/nixos/kde.nix` (reasoning: it's the
module both hosts already import that groups desktop/XKB-adjacent
settings, and it's what the System Settings KDE checkbox maps to). User
corrected: "this should not be in kde.nix. this should be set for all
desktop/PC systems, not just for kde plasma." **ANSWERED 2026-09-01:**
moved to `modules/profiles/PC.nix` (the `profile-pc` module), next to
the existing `hardware.keyboard.qmk.enable` line, since it's a
keyboard/XKB-level setting independent of which desktop environment (or
none) is running.

### D3 -- statix "repeated keys" warning on the new line
`docs/skills/workflow/scripts/verify-ladder` hard-blocked on a new statix
"repeated keys" diagnostic for the added
`services.xserver.xkb.options = ...;` line. `modules/profiles/PC.nix`
already has 9 pre-existing top-level `services.X = ...;`/`services.X = {
};` bindings scattered through the file (flatpak, udev.packages, pcscd,
printing, pulseaudio x2, pipewire, mullvad-vpn), each independently
already flaggable by the same lint -- statix emits one diagnostic per
occurrence rather than one per group, so the new line is unavoidably
"new" by verify-ladder's line-diff scoping regardless of where in the
file it's placed. Fully silencing it requires consolidating every
`services.*` binding in the file into one `services = { ... };` attrset
(statix's own suggested fix), which would uproot ~9 existing settings
from their current spots (each sits directly below its own topical
explanatory comment) into one contiguous block, scattering the file's
comment-adjacency organization for a change this task didn't ask for.
**ANSWERED 2026-09-01:** keep the diff minimal and on-topic; accept the
new line as a 10th instance of an already-9x-repeated pre-existing style
rather than doing the disruptive whole-file consolidation. The
`verify-ladder` statix step is expected to still report this one warning.

## Gotchas (G)

### G1 -- `xkb.options` (`types.commas`) does not merge against its own
module default
`services.xserver.xkb.options` is defined with
`default = "terminate:ctrl_alt_bksp";` in nixpkgs'
`nixos/modules/services/x11/xserver.nix`. `types.commas`' merge function
only combines multiple *explicit* definitions contributed by different
modules -- it does not fold the type's own default in once any module
sets an explicit value. First attempt set
`services.xserver.xkb.options = "fkeys:basic_13-24";` alone, which
silently dropped `terminate:ctrl_alt_bksp` (Ctrl+Alt+Backspace kill-X)
from the rendered config -- confirmed by inspecting the built
`/etc/X11/xorg.conf.d/00-keyboard.conf` derivation directly (`Option
"XkbOptions" "fkeys:basic_13-24"`, missing the terminate option). Fixed
by setting the full comma-joined string explicitly:
`"terminate:ctrl_alt_bksp,fkeys:basic_13-24"`. Verified in the rebuilt
derivation's rendered `XkbOptions` line.

## Findings (F)
*(populated by security/docs-updater when invoked)*
