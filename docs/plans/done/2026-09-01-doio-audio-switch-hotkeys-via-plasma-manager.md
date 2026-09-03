---
slug: doio-audio-switch-hotkeys-via-plasma-manager
created: 2026-09-01
status: done
frozen: true
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

Done and confirmed working on real hardware. Final key layout:
`doio.vil` row0 col2 (next to Lock) = `HYPR(KC_F2)` -> RC-505, row1
col2 (next to Sleep) = `HYPR(KC_F1)` -> Monitor, row2 col2 (next to
Reboot) = `HYPR(KC_F3)` -> AudioEngine; row3 (Shutdown) and all other
cells untouched. Bound to Hyper+F1-3, not the originally-chosen
Hyper+F13-15 (D2), after discovering (D4/G6) that this system's XKB
`evdev` rules remap the F13-F24 range to legacy XF86 multimedia-key
symbols rather than plain function-key symbols, so a
`kglobalshortcutsrc` binding on "...+F13" could never match a physical
F13 keypress. Getting Hyper+F1-3 free required clearing 3 legacy
per-app "launch this app" shortcuts (feishin/cider-genten/spotify) that
already sat on plain Meta+Ctrl+Alt+Shift+F1/F2/F3, orphaned from an old
macropad binding that no longer exists in any current keymap file.

All Nix-side pieces are final and build-tested (`nixos-rebuild build`
for both `torrent` and `thinkpad`; `thinkpad`'s store path stayed
byte-identical throughout every revision, confirming the `profile-pc`
scoping never leaked into it): `flake.nix`/`flake.lock` (re-added
`plasma-manager` input), `modules/home-manager/audio-switch.nix` (the
`audio-switch-output` script plus `programs.plasma.hotkeys.commands`
and the `programs.plasma.shortcuts` clear-block), and
`modules/flake/hosts.nix` (wires the module into torrent's own modules
list only). `nixos-rebuild switch` was applied twice on torrent (both
times on the user's explicit "switch now"), and the final live state
was confirmed, via the user testing the physical keys, to actually
switch PipeWire's default sink correctly for all three outputs. The
user did have to manually re-set the shortcuts once more in System
Settings and reload Vial's GUI after the second switch before
kglobalaccel picked up the corrected key bindings (G7) -- after that,
live state matches the Nix declaration with no drift, per the user:
"now everything is working, and also done declaratively."

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
- [x] `nixos-rebuild switch` on torrent (2026-09-01, user explicitly
      asked "switch now"); confirmed live `~/.config/kglobalshortcutsrc`
      now has all three `audio-output-*=Meta+Ctrl+Alt+Shift+F13/14/15`
      lines
- [x] Pressed each of the three keys on real hardware -- initially none
      worked (D4/G6: XKB remaps F13-F15 to legacy XF86 keys, not plain
      function-key symbols)
- [x] D4 -- switched `doio.vil` and the nix module from Hyper+F13/14/15
      to Hyper+F1/F2/F3 per user's request; cleared the 3 legacy
      per-app launch shortcuts occupying those keys (2 by the user via
      System Settings, 1 -- cider/genten -- declaratively via
      `programs.plasma.shortcuts`, verified against `data.json` to
      touch nothing else); re-verified `nixos-rebuild build` for
      torrent and thinkpad (thinkpad unchanged), `switch`ed on user's
      explicit "switch now"
- [x] G7 -- live key binding still stale after switch alone; user
      manually re-set the shortcuts in System Settings + reloaded Vial;
      user confirmed 2026-09-01: "now everything is working, and also
      done declaratively" -- live state matches the Nix declaration

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

### D4 -- Hyper+F13-15 turned out not to work at all; switched to Hyper+F1-3
After activation, all three keys did nothing. Diagnosed live (KWin's own
debug console, "Keyboard"/Input Events tab): pressing the physical keys
produced key symbols "Launch5"/"Tools"/"Launch6", never "F13"/"F14"/
"F15" -- this system's XKB `evdev` rules map Linux keycodes 183-185
(`KEY_F13..F15`) to the legacy MS-keyboard extra-keys range, not plain
function-key symbols, so a `kglobalshortcutsrc` entry for
"...+F13" can never match (see G6). This invalidates D2's premise
(D2 is left as-is, append-only; superseded here rather than edited).
User: "lets try swapping everything to hyper plus F1-F3. you will have
to clear out legacy keybinds that kde may allready have." Confirmed via
`doio.vil`'s own JSON that none of its macro slots 7-15 (the orphaned
Hyper+F1-F9 macros) are invoked from any key in the current layout, so
repurposing F1-F3 was safe from the keymap side. F1/F2/F3 were each
already occupied by a per-app "launch this app" global shortcut
(`[services][feishin.desktop]`, `[services][sh.cider.genten.desktop]`,
`[services][spotify.desktop]`, each `_launch=Meta+Ctrl+Alt+Shift+Fn`) --
user manually cleared feishin (F1) and spotify (F3) via System Settings
before asking me to check for leftovers; I found cider/genten (F2)
still set and cleared it declaratively via a new
`programs.plasma.shortcuts."services/sh.cider.genten.desktop"."_launch"
= [ ];` block (verified via the built `data.json` that this writes
`'none'` -- the same value KDE already used for the two the user'd
cleared by hand -- and touches nothing else in the file). User
confirmed afterward: "now everything is working, and also done
declaratively."


**ANSWERED 2026-09-01:** user: 'lets try swapping everything to hyper plus F1-F3. you will have to clear out legacy keybinds that kde may allready have.' Confirmed working afterward: 'now everything is working, and also done declaratively.'

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

### G5 -- kglobalaccel doesn't pick up new `.desktop`-based shortcuts without a logout
After `nixos-rebuild switch`, all three shortcuts were confirmed correct
at rest (`.desktop` file at
`/etc/profiles/per-user/lilijoy/share/applications/plasma-manager-commands.desktop`
has the right `Actions=`/`Exec=` lines; `~/.config/kglobalshortcutsrc`
has the right `Meta+Ctrl+Alt+Shift+F13/14/15` bindings) but none of the
three keys worked. `qdbus --literal org.kde.kglobalaccel /kglobalaccel
org.kde.KGlobalAccel.allComponents` showed no `plasma-manager-commands`
component registered at all. On this Plasma 6/Wayland session,
`org.kde.kglobalaccel` is answered by `kwin_wayland` itself (checked via
`dbus-send ... GetConnectionUnixProcessID` -> PID matched
`kwin_wayland`), which only scans `.desktop`-based global-shortcut
components at KWin/session startup -- there's no live-reload path for a
file that changed out from under it. plasma-manager's own README lists
"real-time updates of configuration without having to log out and back
in" under what's not well supported, confirming this isn't specific to
our setup. Logging out and back in (not attempted from this session --
restarting KWin in place on Wayland is itself disruptive/risky, closer
to a mini-crash than a clean reload) is the expected fix; no further
rebuild needed once that happens.

### G6 -- XKB's `evdev` rules remap KEY_F13-F24 to legacy MS-keyboard XF86 keys, not plain function-key symbols
Confirmed live via KWin's own debug console (`qdbus org.kde.KWin /KWin
org.kde.KWin.showDebugConsole`, Keyboard/Input Events tab): pressing
the physical Hyper+F13/F14/F15 keys produced key symbols
"Launch5"/"Tools"/"Launch6", not "F13"/"F14"/"F15". This system's XKB
rules are `rules: evdev, model: pc105, layout: us` (checked via
`setxkbmap -query` against the XWayland compat layer KWin also runs) --
under the standard `evdev` ruleset, Linux keycodes 183-194
(`KEY_F13..F24`) are historically aliased to the old
Microsoft-multimedia-keyboard extra-keys range (Launch1-8, Tools, My
Computer, etc.) rather than to plain `F13..F24` keysyms. A
`kglobalshortcutsrc` entry written as "...+F13" therefore can never
match what a physical F13 keycode actually produces on this host --
this isn't a bug in our config, it's this XKB ruleset's long-standing
behavior for that keycode range. Plain `F1..F12` don't have this
problem; only the F13-and-up extended range does. See D4.

### G7 -- kglobalaccel also doesn't live-reload an *already-registered* component's key value from a `switch` alone
Even after `nixos-rebuild switch` regenerated the `.desktop` file and
`kglobalshortcutsrc` with the corrected Hyper+F1/F2/F3 values (verified
on disk), `qdbus --literal org.kde.kglobalaccel
/component/plasma_manager_commands_desktop
org.kde.kglobalaccel.Component.allShortcutInfos` still reported the
*old* F13/F14/F15 key codes -- confirming this is a distinct gotcha
from G5 (G5 was about a component not existing in kglobalaccel's
registry at all; this is about an *already-active* component's bound
key not refreshing from a config-file change plus a service restart
alone, unlike G5's fix path). The System Settings "Apply" trick that
worked in G5 for making a brand-new component active did not, by
itself, force a re-read of the new key value for an already-known
component in this instance. What actually got it working: the user
manually re-set the three shortcuts' key combinations directly in
System Settings (not just re-Applying the same value) and reloaded the
keymap in Vial's GUI once more -- after which the live state matched
what's declared in Nix and stayed there (no drift), so no further Nix
change was needed.

## Findings (F)
*(populated by security/docs-updater when invoked)*
