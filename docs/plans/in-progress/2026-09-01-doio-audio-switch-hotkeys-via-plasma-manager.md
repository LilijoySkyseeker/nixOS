---
slug: doio-audio-switch-hotkeys-via-plasma-manager
created: 2026-09-01
status: in-progress
frozen: false
---

# doio audio-switch hotkeys via plasma-manager

## Original plan

User request: wire the DOIO macropad (`files/doio.vil`) up to switch this
machine's (torrent's) audio output device, using plasma-manager
declaratively, checking git history for how plasma-manager was used and
removed before. Three physical outputs: the monitor's HDMI connection,
a Boss RC-505MK2 looper, and an AudioEngine A5+ speaker pair connected
via an Apple USB-C-to-3.5mm dongle. This plan is filed retroactively --
the work below was done and build-tested in the same session before the
plan file existed, per the repo's workflow gate.

## State

In progress -- all Nix-side and keymap-file work is done and
build-verified, but nothing has been flashed or activated on real
hardware yet, so treat this as unproven until that happens (see below).

`flake.nix`/`flake.lock` (re-added `plasma-manager` input),
`modules/home-manager/audio-switch.nix` (new, torrent-only
home-manager module), and `modules/flake/hosts.nix` (wires the module
into torrent's own modules list, not `profile-pc`) are final.
`files/doio.vil`'s cell placement went through one revision after D3:
final layout is row0 col2 (next to the Lock key) = `HYPR(KC_F14)`
(RC-505), row1 col2 (next to Sleep) = `HYPR(KC_F13)` (Monitor), row2
col2 (next to Reboot) = `HYPR(KC_F15)` (AudioEngine); row3 (Shutdown)
and all other cells untouched. Build-tested via `nixos-rebuild build`
for both `torrent` and `thinkpad` after the D3 rework (thinkpad's store
path stayed byte-identical throughout, confirming `profile-pc` scoping
never leaked into it -- and torrent's store path was unchanged
before/after the D3 keymap-cell move too, since `doio.vil` isn't
consumed by Nix at all). Verified past the build step, via the actual
built home-manager activation package's `data.json`, that
`~/.config/kglobalshortcutsrc` will get `Meta+Ctrl+Alt+Shift+F13/14/15`
bound to the three `plasma-manager-commands.desktop` actions, whose
`Exec=` lines correctly invoke the built `audio-switch-output` script
with each target's `node.name`.

Remaining real-world steps (not doable from this session): flash
`files/doio.vil` to the physical DOIO macropad via the Vial GUI;
`nixos-rebuild switch` (or the usual pull-deploy path) on torrent so
the KDE shortcuts actually land in the live session; then confirm by
pressing each of the three new keys that the right output actually
becomes PipeWire's default sink.

## Progress

- [x] G1 -- checked git history for plasma-manager's prior use/removal
      (commits a78bb55 "plasma manager config", 6afd3fe "disable plasma
      manager", 700e727 removed it entirely; ef8767c/e513827 show a later
      unrelated re-add+revert for a kitty-terminal shortcut) before
      reintroducing it
- [x] Read real PipeWire state on torrent (`wpctl status`, `wpctl
      inspect <id>`) to get each target sink's stable `node.name`
      (D2's alternative considered and rejected: matching by numeric id
      or by `node.description`, both less stable/unique than
      `node.name`)
- [x] D1 -- confirmed with user: dedicated key per output, not a cycle
- [x] D2 -- confirmed with user: Hyper+F13-24 keyspace, not bare F13-15
- [x] Re-added `plasma-manager` flake input (`nixpkgs`/`home-manager`
      both `.follows`, matching the historical wiring)
- [x] Wrote `modules/home-manager/audio-switch.nix`: a
      `writeShellApplication` (`audio-switch-output <node.name>`)
      resolving the live numeric id via `pw-dump | jq` before `wpctl
      set-default`, plus three `programs.plasma.hotkeys.commands`
      entries bound to `Meta+Ctrl+Alt+Shift+F13/14/15`
- [x] Wired the module into `modules/flake/hosts.nix`'s `torrent` stanza
      only (not `profile-pc`, which `thinkpad` also uses -- these three
      devices live on this desk only)
- [x] Edited `files/doio.vil`: `HYPR(KC_F13)`/`HYPR(KC_F14)`/
      `HYPR(KC_F15)` into the three previously-`KC_NO` column-0 cells of
      layer 0's first three row-groups; diffed old vs new to confirm
      only those 3 cells changed
- [x] G2/G3 found and fixed via `nixos-rebuild build` failures (see
      Gotchas) before the build succeeded
- [x] `nix flake lock --update-input plasma-manager`,
      `nixos-rebuild build --flake .#torrent` and `--flake .#thinkpad`,
      `nix flake check --no-build`, `nixfmt`/`statix`/`deadnix` on
      touched files
- [x] Verified the actual generated `kglobalshortcutsrc` data and
      `.desktop` Exec= lines from the built home-manager activation
      package (see State)
- [x] D3 -- asked user for physical key placement instead of assuming;
      reworked `files/doio.vil` to row0/row1/row2 col2 = RC-505/Monitor/
      AudioEngine per their answer; re-verified `nixos-rebuild build`
      for torrent afterward
- [x] Flash `files/doio.vil` onto the physical DOIO macropad (Vial GUI)
      -- done by the user, confirmed loaded (2026-09-01); this step is
      the user's to do, not this session's -- never attempted here
- [ ] `nixos-rebuild switch` (or pull-deploy) on torrent to activate the
      KDE shortcuts in the live session
- [ ] Press each of the three keys on real hardware and confirm the
      right output becomes PipeWire's default sink

## Decisions (D)

### D1 -- dedicated key per output, not a cycle key
User said "it should not be a cycle, it should be dedicated."
Implemented as three independent `hotkeys.commands` entries, each
hardcoding one target `node.name`, rather than one key cycling through
sinks in some order.


**ANSWERED 2026-09-01:** user: 'it should not be a cycle, it should be dedicated.'

### D2 -- Hyper+F13-24 keyspace, not bare F13-15
User said "lets use hyper plus f13-24 as the keybinding space to avoid
conflicts." torrent's live `~/.config/kglobalshortcutsrc` already has
`Meta+Ctrl+Alt+Shift+F1` through `F12` registered (karousel
desktop-move shortcuts, launcher macros already in `doio.vil`'s own
macro slots 7-15) -- Hyper+F13-24 is otherwise-untouched keyspace on
both the KDE and QMK/Vial side, and `HYPR(kc)` (confirmed via QMK's own
keycode docs: "Hold Left Control, Left Shift, Left Alt and Left GUI and
press `kc`") already appears as a bare keycode wrapper elsewhere in
this same `doio.vil` file (`HYPR(KC_R)`, `HYPR(KC_S)`), so
`HYPR(KC_F13..15)` follows the file's existing convention rather than
introducing a new one.


**ANSWERED 2026-09-01:** user: 'lets use hyper plus f13-24 as the keybinding space to avoid conflicts.'

### D3 -- which physical macropad keys
Initially placed unilaterally at col0 of rows 0-2 without asking; user
then asked to be consulted on this specifically. Asked via
AskUserQuestion with three preset layouts plus a free-text option; user
chose free-text and specified: "the 3 keys next to the current
lock/sleep/reboot/shutdown line. it should be in rc505/monitor/
audioengine order, next to the first 3 of the previousl list." Layer
0's col3 sequence is `LGUI(KC_L)`/`LGUI(KC_S)`/`HYPR(KC_R)`/
`HYPR(KC_S)` = Lock/Sleep/Reboot/Shutdown (rows 0-3; confirmed Reboot
and Shutdown against this host's live `~/.config/kglobalshortcutsrc`,
which has "Reboot Without Confirmation=Meta+Ctrl+Alt+Shift+R" and "Halt
Without Confirmation=Meta+Ctrl+Alt+Shift+S"). "Next to" = col2,
immediately adjacent to col3 on the same row. Final placement: row0
col2 (next to Lock) = RC-505, row1 col2 (next to Sleep) = Monitor, row2
col2 (next to Reboot) = AudioEngine; row3 (Shutdown) untouched. The
`HYPR(KC_F13)`=Monitor / `HYPR(KC_F14)`=RC-505 / `HYPR(KC_F15)`=
AudioEngine mapping itself (and the whole Nix side) didn't need to
change -- only which physical cell each of those three keycodes sits
in.


**ANSWERED 2026-09-01:** user: 'the 3 keys next to the current lock/sleep/reboot/shutdown line. it should be in rc505/monitor/audioengine order, next to the first 3 of the previousl list.'

## Gotchas (G)

### G1 -- local flake evaluation only sees git-tracked files
Adding a brand new file (`modules/home-manager/audio-switch.nix`)
without `git add`-ing it first produced `error: attribute
'audio-switch' missing` from `import-tree`/`flake.modules.homeManager`
-- not a Nix syntax error, just silent non-inclusion. Nix's local-path
flake evaluation for a git working tree only sees paths present in
`git ls-files`; edits to *already-tracked* files are picked up
immediately without re-staging, but a new file must be `git add`-ed
(doesn't need a commit) before the flake can see it at all.

### G2 -- `programs.plasma.hotkeys.commands` silently no-ops without `programs.plasma.enable = true`
Every historical use of this repo's plasma-manager config
(`a78bb55`'s `kde.nix`, `ef8767c`'s `terminal.nix`) set
`programs.plasma.enable = true` explicitly alongside `shortcuts`/
`hotkeys.commands`. Omitting it does **not** error -- the option still
type-checks and the build succeeds -- but none of plasma-manager's
activation machinery runs: no `plasma-manager-commands.desktop`
derivation, no `kglobalshortcutsrc` data, nothing. Caught only by
diffing two builds' output-path hashes (byte-identical despite a real
config change) and then grepping the built closure for expected
strings and finding none.

### G3 -- `hotkeys.commands.<name>.command` is a Desktop Entry `Exec=` value, not a shell command
plasma-manager renders each `hotkeys.commands` entry into a
`plasma-manager-commands.desktop` file's `Exec=` line under freedesktop
Desktop Entry syntax, which is **not** shell syntax -- a bare `'`
(apostrophe) is a reserved character there unless already inside that
format's own (different) quoting rules. Shell-style single-quoting an
argument (`'alsa_output...'`) failed the build with `contains a
reserved character ''' outside of a quote`. Fix: don't shell-quote;
since none of these three `node.name` values contain whitespace, the
unquoted bare string works and Desktop Entry's own argument-splitting
handles it correctly. An argument that *did* contain a space would need
Desktop Entry's own quoting (double quotes with its specific escaping
rules), not bash-style single quotes.

### G4 -- PipeWire node ids are session-scoped; `node.name` is the stable key
`wpctl status`'s numeric sink ids (and hence `wpctl set-default <id>`)
are reassigned on reconnect/replug and are not safe to hardcode. Each
target's `node.name` (read via `wpctl inspect <id>` on the live system:
`alsa_output.pci-0000_03_00.1.hdmi-stereo-extra1` for the monitor,
`alsa_output.usb-BOSS_RC-505MK2_USB_Audio-00.analog-stereo` for the
RC-505MK2, `alsa_output.usb-Apple__Inc._USB-C_to_3.5mm_Headphone_Jack_Adapter_DWH524406HK2FN3AR-00.analog-stereo`
for the AudioEngine A5+) is the stable identifier, built from device
topology/serial rather than assigned at runtime. `audio-switch-output`
resolves `node.name` -> current id via `pw-dump | jq` each time it
runs, immediately before calling `wpctl set-default`.

## Findings (F)
*(populated by security/docs-updater when invoked)*
