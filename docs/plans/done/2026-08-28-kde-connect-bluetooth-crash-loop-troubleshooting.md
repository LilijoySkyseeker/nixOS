---
slug: kde-connect-bluetooth-crash-loop-troubleshooting
created: 2026-08-28
status: done
frozen: true
---

# KDE Connect Bluetooth crash-loop troubleshooting

## Original plan

User reported KDE Connect erroring out on `torrent` (this host). Diagnose
and fix.

`kdeconnect-indicator.service` was logging `dbus interface not valid`
every ~95s. That's a symptom: the real fault is `kdeconnectd` itself
SIGSEGV-ing on the same ~95s cadence (27 crashes observed in 43 minutes),
auto-relaunched each time by the desktop autostart, so the indicator kept
finding its D-Bus peer torn down mid-connection.

Crash backtrace (via `journalctl --user`, `Signal: 11 (SEGV)`, thread
`QThread`) bottoms out in:

```
QBluetoothSocketPrivateBluezDBus::clearSocket()
  <- connectToServiceReplyHandler(QDBusPendingCallWatcher*)
  <- QDBusPendingCallWatcher::finished
```

i.e. a use-after-free in Qt6Bluetooth's (`qtconnectivity-6.11.1`) BlueZ
D-Bus socket backend, triggered by KDE Connect's built-in Bluetooth link
provider (`kdeconnectd` links `libQt6Bluetooth.so.6` directly -- no
separate plugin `.so`, no runtime toggle found in the binary or in
`~/.config/kdeconnectrc`/`~/.config/kdeconnect/config`).

Trigger: a Bluetooth-paired device named "thinkpad"
(`4C:79:6E:89:A9:17`) was *also* a KDE-Connect-trusted device (same host,
`~/.config/kdeconnect/trusted_devices`, `type=desktop`). kdeconnectd
periodically retried a Bluetooth `connectToService()` to it, and every
retry's reply handler crashed the daemon.

## Progress
- [x] Reproduced and characterized the crash (95s-interval SIGSEGV,
      `coredumpctl`/`journalctl` backtrace)
- [x] Identified trigger device and confirmed via `bluetoothctl devices`
      + `~/.config/kdeconnect/trusted_devices`
- [x] Checked for a declarative/nixpkgs-level fix: `kdePackages.kdeconnect-kde`'s
      Nix derivation (`pkgs/kde/gear/kdeconnect-kde/default.nix` in the
      pinned nixpkgs) has no cmake flag to disable Bluetooth support --
      `qtconnectivity` is an unconditional `buildInputs` entry, so
      excluding it would need a source-level or packaging patch, not a
      simple `cmakeFlags` override (see D1)
- [x] Applied imperative fix: `bluetoothctl remove 4C:79:6E:89:A9:17`,
      then `pkill -x kdeconnectd` to clear the crash-looping instance
- [x] Verified fix: new `kdeconnectd` instance survived multiple ~95s
      retry cycles without crashing (`Cannot connect to profile/service`
      /`Couldn't connect to bluetooth socket` now logged as a handled
      error instead of segfaulting), `kdeconnect-indicator` stopped
      logging `dbus interface not valid`, all three
      `org.kde.kdeconnect*` D-Bus names stayed registered

## Decisions (D)
### D1 -- how to stop the crash-loop: unpair vs. package patch vs. leave it
**ANSWERED 2026-08-28:** user chose to unpair the "thinkpad" Bluetooth
device (`bluetoothctl remove`) rather than pursue a declarative
nixpkgs-level fix (patching out Qt6Bluetooth support at build time) or
just leave the crash-loop running. Reasoning offered: immediate,
reversible (can re-pair later), and KDE Connect's actual day-to-day
transport for this pairing is LAN, not Bluetooth, so no functional loss.

## Gotchas (G)
### G1 -- OS-level Bluetooth pairing state doesn't gate kdeconnectd's own retry loop
The first `bluetoothctl remove` did **not** immediately stop the crash:
the already-running `kdeconnectd` instance (started before the unpair)
crashed one more time afterward. KDE Connect's Bluetooth link provider
keeps its own notion of "trusted device" (`~/.config/kdeconnect/trusted_devices`,
independent of `bluez`'s paired-devices list) and will still attempt
`connectToService()` against a device by address even after it's been
unpaired at the OS level -- it just fails differently (`No uuids found`
instead of getting far enough to hit the buggy reply-handler path).
**A full `pkill -x kdeconnectd` restart after the unpair was required**
for the fix to take effect, not the unpair alone.

## Findings (F)
*(populated by security/docs-updater when invoked)*
