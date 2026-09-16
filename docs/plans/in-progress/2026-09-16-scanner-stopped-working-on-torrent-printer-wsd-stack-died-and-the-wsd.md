---
slug: scanner-stopped-working-on-torrent-printer-wsd-stack-died-and-the-wsd
created: 2026-09-16
status: in-progress
frozen: false
kind: task
priority: normal
blocked_by:
---

# scanner stopped working on torrent -- printer WSD stack died, and the WSD URL is now captured

## State

Resolved, no repo change. Cause was device-side; a power-cycle fixed it.
Verified to rung 3 (ran it locally, output inspected) -- and for once
that includes an actual scanned page, which no previous plan here has.

Left in `in-progress/` for one reason only: G4 captures the WSD URL that
`2026-08-27-set-up-the-new-network-printer-scanner-brother-mfc.md#F1`
said was the blocker for pinning the device and turning discovery off.
That follow-up is now unblocked and is the open work (D1).

## Original plan

User: "i still cant reach the printer to scan with it." Printing was
being worked on separately
(`2026-09-16-ensure-printers-fails-every-boot-on-torrent-undeployed-fix-plus-no.md`);
this is the scanning half, which is a different stack -- sane-airscan and
WSD, not CUPS.

## Progress

- [x] Rule out the NixOS side: backend wiring, firewall rule, config dir
- [x] Establish the device's actual scan protocol surface (G2, G3)
- [x] Identify the cause: printer's WSD stack not serving (G3)
- [x] User power-cycled the printer; discovery and acquisition both recovered
- [x] Capture the WSD URL (G4)
- [ ] Decide whether to pin the device and disable discovery (D1)

## Decisions (D)

### D1 -- now that the WSD URL exists, should the device be pinned?

`2026-08-27-set-up-the-new-network-printer-scanner-brother-mfc.md#F1`
noted that sane-airscan runs on packaged defaults here (`discovery =
enable`, `ws-discovery = fast`) and that pinning the device in
`airscan.conf`'s `[devices]` needed a URL nobody had captured. Quoting
that finding's fix-risk note: *"the printer's WSD service path/port isn't
guessable the way eSCL's usually is ... `airscan-discover` would need to
be run once on the home LAN to get the exact URL before this can be
pinned."*

G4 has that URL now. Pinning would:

- drop WS-Discovery multicast probing from torrent's LAN entirely, which
  is the last live remnant of what D9 set out to remove;
- remove the ~20 s stall on every enumeration (G5);
- make scanning survive a discovery outage of the kind that caused this
  plan.

Against: it hardcodes a device-supplied URL, so a firmware update or an
IP change breaks scanning silently, in a way that discovery would have
healed. Same class of fragility as the hardcoded `32768:60999` range
already noted on the firewall rule.

Exact syntax, confirmed against `sane-airscan.5` for 0.99.38 -- note the
protocol token is required, since **omitting it defaults to eSCL**, which
this device does not speak (G6):

```ini
[devices]
"Brother MFC-L2740DW" = http://192.168.1.166:80/WebServices/ScannerService, WSD

[options]
discovery = disable
```

**Implementation cost is higher than it looks, and this is the part to
weigh.** nixpkgs' `mkSaneConfig`
(`pkgs/applications/graphics/sane/config.nix`) only walks
`etc/sane.d/*` at `-maxdepth 1 -not -type d`, plus `etc/sane.d/dll.d/`.
It does **not** handle the `etc/sane.d/airscan.d/` drop-in directory the
man page documents, so the clean drop-in route is silently discarded.
Pinning therefore means overriding `airscan.conf` wholesale via a
`writeTextFile` ordered after `sane-airscan` in `extraBackends`, and
accepting a build-time `conflict... Overriding` warning. That is a
sharper edge than a two-line config, and it is the main argument for
leaving discovery alone.

Cheaper alternative if the goal is only robustness and not closing the
multicast surface: `SANE_AIRSCAN_DEVICE="wsd:Name:URL"` as an environment
variable overrides all configured devices *and* disables discovery,
without touching the package.

Not decided -- this is the user's call and is the only open item here.

## Gotchas (G)

### G1 -- nothing was wrong on the NixOS side

Worth stating plainly, because the instinct was to look here first and
every check came back clean:

- firewall rule live and exactly right: `-A nixos-fw -s 192.168.1.166/32
  -i enp8s0 -p udp -m udp --dport 32768:60999 -j nixos-fw-accept`, and
  `net.ipv4.ip_local_port_range` is `32768 60999` -- an exact match, so
  the fragility flagged on that literal had not yet bitten;
- backend wired: `libsane-airscan.so.1` in `/etc/sane-libs`,
  `/etc/sane-config/dll.d/airscan` containing `airscan`;
- the prober ran on the right interface, per `SANE_DEBUG_AIRSCAN=4`:
  `WSDD: 192.168.1.162: started discovery, UDP port=37543` -- inside the
  firewall's accepted range, so replies would have been let in.

### G2 -- `/etc/sane.d` does not exist on NixOS; the config lives elsewhere

First diagnostic produced a false negative. `scanimage -L` from a bare
shell found only the webcam, and `/etc/sane.d/` does not exist, which
reads as "sane is not configured at all". Both are wrong. NixOS sets
`SANE_CONFIG_DIR=/etc/sane-config` and `LD_LIBRARY_PATH=/etc/sane-libs`
in `/etc/set-environment`, and those are *login-session* variables -- a
non-login shell does not have them, so `scanimage` silently falls back to
defaults and finds nothing.

Always run scanner diagnostics as:

```
SANE_CONFIG_DIR=/etc/sane-config LD_LIBRARY_PATH=/etc/sane-libs scanimage -L
```

Same trap as `2026-08-27-set-up-the-new-network-printer-scanner-brother-mfc.md#G3`,
which is why that plan's user-facing fix was "log out and back in". It is
also the exact shape `AGENTS.md` warns about under "Missing tooling is a
bug" -- a command that prints nothing because the environment is wrong,
not because the thing is absent.

### G3 -- the device's WSD stack had silently stopped serving

This was the actual cause. The printer was up and healthy on every other
protocol while WSD was dead:

- reachable, and `80 / 443 / 515 / 631 / 9100 / 54921-54923` all open;
- its own web console showed **Web Services**, **Network Scan**, **mDNS**
  and **AirPrint** all ticked -- so G2 of the 2026-08-27 plan ("WSD must
  be enabled in the console") was satisfied and is not the answer here;
- but a hand-built WS-Discovery `Probe` got no reply, sent both unicast
  to `192.168.1.166:3702` and multicast to `239.255.255.250:3702` bound
  to source port 37000 (inside the accepted range, so not the firewall);
- and `airscan-discover` returned an empty `[devices]`.

A power-cycle of the printer fixed it completely. Ping latency before the
restart was ~26 ms and ~2.5 ms after, so it had been in a deep sleep state
it was not fully waking from.

The lesson for next time: **a ticked "Web Services" checkbox is not
evidence the WSD service is running.** Probe it. And this is a
non-declarative dependency sitting underneath a declarative config --
nothing in this repo can assert or restore it.

### G4 -- the WSD URL, captured at last

```
$ airscan-discover
[devices]
  Brother MFC-L2740DW series = http://192.168.1.166:80/WebServices/ScannerService, WSD
```

Note the port: **80**, not 5357. 5357 is the conventional WSDAPI port and
was closed on this device throughout, including after the successful
restart -- so "5357 is closed" is not a WSD health signal for this model,
and chasing it was a red herring. Brother serves the scanner endpoint off
the ordinary web port.

This is the value `...brother-mfc.md#F1` needed and never had. See D1.

### G5 -- sane-airscan stalls ~20 s on avahi that is deliberately gone

Every enumeration logs:

```
MDNS: AVAHI_CLIENT_CONNECTING
zeroconf: device_list wait: DNS-SD not finished...
zeroconf: device_list wait: timeout
```

D9 removed avahi fleet-wide, so the DNS-SD half of discovery can never
complete and always burns `ZEROCONF_READY_TIMEOUT` (5000 ms). Measured
`scanimage -L` wall time is **8.5 s**. Harmless for a WSD device -- the
WSD half finishes and returns the scanner -- and it would be removed as a
side effect of D1.

One non-obvious dependency underneath this, worth recording because it is
a latent single point of failure nothing else documents: `airscan_init()`
calls `mdns_init()` *before* `wsdd_init()` and aborts the whole backend if
it fails. `mdns_init()` calls `avahi_client_new(..., AVAHI_CLIENT_NO_FAIL,
...)`, which tolerates a missing avahi *daemon* -- that is why WSD still
works here -- but it still needs the **D-Bus system bus**. If
`avahi_dbus_bus_get()` fails, `mdns_init()` returns NULL and sane-airscan
dies entirely, WSD included. `dbus.service` is active on torrent, so this
is fine today; but it means scanning on this host has a dependency on
D-Bus that is invisible in the module and survives only by accident of
ordering. Pinning the device per D1 removes it.

### G6 -- the "WSD-only, not eSCL" claim is now confirmed empirically

`...brother-mfc.md#D1` asserted this with no cited source, and F1 of that
plan leaned on it as load-bearing. It is correct. Two independent probes:

- `GET /eSCL/ScannerCapabilities` returns **HTTP 404** on both port 80 and
  port 443 (Brother's own error page, so the web server answered);
- the device's own DNS-SD service list contains no `_uscan._tcp` --
  querying it directly times out, while the advertised list is
  `_pdl-datastream._tcp`, `_printer._tcp`, `_ipp._tcp`, `_scanner._tcp`,
  `_http._tcp`, `_privet._tcp`.

`_scanner._tcp` resolves to `Brother MFC-L2740DW series` and is Brother's
*proprietary* network-scan service, matching the open `54921-54923` --
i.e. the `brscan4` path. So the device offers exactly two scanning
routes: WSD (blob-free, what is in use) and Brother's proprietary
protocol (needs the non-free blob). Confirms the original driverless
choice was the right one, and there is no third option to reach for if
WSD dies again.

### G7 -- first recorded end-to-end scan in this repo

Every prior scanning claim was device *enumeration* (`scanimage -L`
printing a device string) plus a user report that Skanpage worked. No
plan records an actual acquisition. This one does:

```
$ scanimage -d 'airscan:w0:Brother MFC-L2740DW series' \
    --format=png --resolution 150 -o scan-test.png
$ file scan-test.png
scan-test.png: PNG image data, 1700 x 2340, 8-bit/color RGB, non-interlaced
```

30242 bytes, exit 0. That is the evidence that was missing.


## Findings (F)
*(populated by security/docs-updater when invoked)*
