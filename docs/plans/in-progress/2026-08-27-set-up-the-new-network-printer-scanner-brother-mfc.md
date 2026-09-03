---
slug: set-up-the-new-network-printer-scanner-brother-mfc
created: 2026-08-27
status: in-progress
frozen: false
---

# Set up the new network printer/scanner (Brother MFC-L2740DW)

## Original plan

- [ ] **2026-08-27: set up the new network printer/scanner (Brother
      MFC-L2740DW).** The old USB Brother is gone. `modules/profiles/PC.nix`
      is currently in a deliberate **placeholder state**: CUPS is enabled
      with `drivers = [ ]` and no printer declared, and `services.avahi`
      has been removed entirely (audit decision D9 option c — a static
      printer address needs no discovery protocol, which is less surface
      than firewalling UDP 5353 open on a roaming laptop). So nothing
      prints today, by design, until this is worked through.

      Steps, in order:
      1. **Give the printer a static address** — a DHCP reservation on
         the router is fine and is the least surprising option.
      2. **Try driverless first.** The MFC-L2740DW supports IPP
         Everywhere/AirPrint, so a queue of the form
         `ipp://<static-ip>/ipp/print` with model `everywhere` should
         need no vendor driver at all — keeping `drivers` empty.
         **Use the IP, not the usual `._ipp._tcp.local` URI**: that form
         resolves through avahi, and re-adding avahi to make printing
         work would undo D9. Declare the queue declaratively
         (`hardware.printers.ensurePrinters`) rather than clicking
         through the CUPS web UI.
      3. **Only if driverless fails**, add a driver — `brlaser` covers
         many Brother lasers, but check it actually lists this model
         before assuming, per the repo's check-the-source rule.
      4. **Scanning is a separate problem from printing** and is not set
         up at all right now. Prefer `sane-airscan` (driverless eSCL over
         the same static IP) over Brother's `brscan4` blob for the same
         reason as above; verify against the pinned nixpkgs rather than
         from memory.
      5. Note there is a known CUPS wrinkle where driverless queues added
         through the web UI or autodetection can silently fail to print
         while ones added via `lpadmin -m everywhere` work. If pages come
         out blank or jobs vanish, that is the first thing to check —
         it is a queue-creation problem, not a network one.

      Build-verified as a placeholder on torrent and thinkpad; no
      switch. *(D9, F-P1-04, F-P5-06)*

## Progress

- [x] Placeholder state deployed and build-verified on torrent and thinkpad, not switched: CUPS enabled with drivers = [ ], no printer declared, services.avahi removed entirely (audit decision D9 option c).
- [x] Give the printer a static address (DHCP reservation on the router) -- 192.168.1.166.
- [x] Try driverless first: declared an ipp://192.168.1.166/ipp/print queue, model everywhere, via hardware.printers.ensurePrinters -- IP not the ._ipp._tcp.local mDNS URI, since that would need avahi back and undo D9.
- [ ] If driverless printing fails in practice, fall back to brlaser (confirmed to list MFC-L2740DW upstream) -- not needed unless G1 bites.
- [x] Scanning: declared hardware.sane.enable + extraBackends = [ sane-airscan ] (handles WSD, which is what this model actually speaks, not eSCL) -- driverless, no Brother blob.
- [x] Moved the printer queue + hardware.sane out of the shared profile-pc into nixosModules."brother-mfc-l2740dw" (modules/nixos/brother-mfc-l2740dw.nix), wired into torrent only -- see F1/F2.
- [x] Enable WSD scanning on the printer's own web console (off by default) -- see G2. User confirmed it was already enabled ("Web Services", Brother's UI name for WSD) -- discovery was still blocked by G3 (firewall), now fixed.
- [x] Build-verify the new printer/scan config on affected hosts before switching -- verify-ladder passed (nixfmt, statix/deadnix, flake check, targeted builds for torrent/thinkpad/homelab/vps/isoimage).
- [x] Switched torrent (this machine) and end-to-end verified: `lpstat` shows the print queue idle/default, `scanimage -L` finds `airscan:w0:Brother MFC-L2740DW series` -- see G3.

## Decisions (D)

### D1 -- driverless vs. vendor driver for print and scan
User first asked to skip driverless and use "Brother's driver from the
beginning" for both print and scan, then relaxed that to "do your own
research to find what the best way to do this is, whatever driver or
method." Research findings that resolved it:
- Printing: MFC-L2740DW has native AirPrint (IPP-based), so the
  `everywhere` driverless queue is expected to work as originally
  planned. `brlaser` (open-source, no unfree blob) explicitly lists this
  exact model in its upstream README as a tested fallback if the
  driverless queue has issues.
- Scanning: this model is WSD-only, not eSCL -- but `sane-airscan`
  auto-negotiates between eSCL and WSD, so it covers WSD devices too;
  no Brother blob (`brscan4`) needed. WSD scanning must be turned on via
  the printer's own web console first -- it's off by default on many
  Brother models.
Kept the original driverless-first, no-unfree-blob approach for both.


**ANSWERED 2026-09-02:** User delegated driver/method choice to research ('do your own research to find what the best way to do this is, whatever driver or method'); resolved to keep driverless-first + sane-airscan, both blob-free, per findings above.

## Gotchas (G)

### G3 -- WSD's multicast-probe/unicast-reply pattern gets silently dropped by the default-deny firewall
Confirmed live on torrent: `airscan-discover` found nothing even with WSD
enabled on the printer (G2) and the printer physically reachable (ping OK).
`tcpdump` showed the printer (192.168.1.166) replying to every WS-Discovery
probe -- the firewall was silently dropping the replies. Cause: the probe
goes out to the 239.255.255.250 multicast group from an ephemeral port, but
the reply comes back as *unicast* from the printer's own IP -- a different
source than the original packet's destination, so conntrack never marks it
RELATED/ESTABLISHED. Fixed with a source-IP-scoped `networking.firewall.
extraCommands` rule (`-s 192.168.1.166`, `-i enp8s0` only) in
`modules/nixos/brother-mfc-l2740dw.nix` -- not a dport-based
`allowedUDPPorts`, since the reply's destination port is whatever ephemeral
port `sane-airscan` bound that run, not a fixed one.

Separately: `scanimage -L` run directly (not in a real login session) will
show nothing even once the above is fixed -- `SANE_CONFIG_DIR`/
`LD_LIBRARY_PATH` are session variables set by the `hardware.sane` module
that only apply in an actual login session, not a bare shell. Not a bug;
confirmed by setting them manually (`SANE_CONFIG_DIR=/etc/sane-config
LD_LIBRARY_PATH=/etc/sane-libs scanimage -L`), which found
`airscan:w0:Brother MFC-L2740DW series`.

### G2 -- WSD scanning must be enabled on the printer itself
The MFC-L2740DW ships with WSD scan-to-PC off by default on some Brother
firmware. Before `sane-airscan`/`scanimage -L` will find it, enable WSD
scanning via the printer's own web console (its IP in a browser), not
just the NixOS side. Confirmed already enabled on the user's unit (Brother
labels the toggle "Web Services" in Web Based Management's Protocol page,
not literally "WSD").

### G1 -- driverless queues added via the web UI/autodetection can silently fail to print
Known CUPS wrinkle: use `lpadmin -m everywhere` instead. If pages come out blank or jobs vanish, that's a queue-creation problem, not a network one -- check this first.

## Findings (F)
*(populated by security/docs-updater when invoked)*
### F1 -- sane-airscan's default WS-Discovery probing undermines D9's no-discovery-protocol rationale on the roaming laptop

- **File:** `modules/profiles/PC.nix:340-343` (`hardware.sane = { enable = true; extraBackends = [ pkgs-unstable.sane-airscan ]; }`, no `[devices]`/`[options]` override shipped)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (default behavior; the exact interface-enumeration/response-handling internals of `airscan-wsdd.c` were not read, so treat the specific spoofing/SSRF-style chain below as PLAUSIBLE)
- **Axis:** hardening
- **Reachability:** Any device on the same L2 broadcast domain as `thinkpad` (coffee-shop/hotel/guest Wi-Fi it roams onto, per D9's own stated threat model) can observe, and potentially respond to, WS-Discovery UDP multicast probes sent by `sane-airscan` whenever the user opens a scanning application (`sane_get_devices()` triggers discovery). This fires on every network the laptop joins, not just the home LAN where `192.168.1.166` actually lives.
- **Rule:** violates the documented rationale for D9 (`docs/accepted-risks.md` D9; plan text: "a static printer address needs no discovery protocol at all, which is strictly less surface than firewalling one") -- that rationale was applied to printing (literal IP, no avahi) but not carried through to scanning.
- **Finding:** `hardware.sane.enable = true` with `extraBackends = [ pkgs-unstable.sane-airscan ]` and no `airscan.conf` (`[devices]`, `discovery = disable`, or `ws-discovery = off`) leaves sane-airscan on its packaged defaults. Verified against the exact pinned `nixpkgs-unstable` rev (`0e251e24a4f24e036a084b6b4b2d2491af4167f4`, matching `flake.lock`) source: `sane-airscan` 0.99.38's own `airscan.conf`/`sane-airscan.5` man page default `[options]` block is `discovery = enable` and `ws-discovery = fast`. WS-Discovery is implemented independently of Avahi (`airscan-wsdd.c`, separate from `airscan-mdns.c`) -- it is a raw UDP multicast SOAP prober, so D9's removal of `services.avahi` (which only kills the eSCL/DNS-SD half of discovery) does **not** disable it. eSCL/DNS-SD auto-discovery is comparably inert here since avahi is gone (its lookups need the running daemon), but WSD auto-discovery is not: this plan's own Decisions section (D1) says the printer is WSD, not eSCL, so the one discovery path left enabled is exactly the one this device uses. The plan text frames the static-IP choice as deliberately avoiding "any discovery protocol at all" but only wired that through `hardware.printers.ensurePrinters`' `deviceUri`, not through sane's config, so the scanning half quietly reintroduces network-wide device discovery on the same host D9 was written to protect.
- **Fix risk:** Adding a `[devices]`/`SANE_AIRSCAN_DEVICE` pin (or `environment.etc."sane.d/airscan.conf"` with `discovery = disable`) to force a static WSD URL, or at minimum `ws-discovery = off`, needs to be tested against this exact model/firmware -- the printer's WSD service path/port isn't guessable the way eSCL's usually is (per sane-airscan's own README: "Discovering WSD URLs [manually]... is much harder... very difficult to guess TCP port and URL path"). `airscan-discover` would need to be run once on the home LAN to get the exact URL before this can be pinned; until then, disabling discovery outright would likely break scanning entirely rather than degrade gracefully.


**FIXED 2026-09-02:** Moved hardware.sane (sane-airscan/WSD discovery) out of the shared profile-pc into a new nixosModules."brother-mfc-l2740dw" (modules/nixos/brother-mfc-l2740dw.nix), wired into torrent only (modules/flake/hosts.nix). thinkpad no longer enables hardware.sane at all, so no WS-Discovery UDP multicast probing happens on networks it roams onto.

### F2 -- static printer IP is a common default LAN address, so the roaming laptop's default print queue can silently resolve to a different device on other networks

- **File:** `modules/profiles/PC.nix:325-333` (`hardware.printers.ensurePrinters` deviceUri `ipp://192.168.1.166/ipp/print`, `ensureDefaultPrinter = "Brother_MFC_L2740DW"`)
- **Severity:** MEDIUM
- **Confidence:** PLAUSIBLE (CUPS/IPP's lack of any host-identity check on a plain `ipp://` URI is well-known protocol behavior, but this wasn't verified against `cupsd`'s IPP client code at the pinned version, and real-world collision requires a listener at that exact address on the other network)
- **Axis:** hardening
- **Reachability:** `192.168.1.0/24` is one of the most common default LAN ranges for consumer routers. On `thinkpad` (shared `profile-pc`, roams onto untrusted networks per D9's own threat model), any print job sent while connected to a network that also hands out `.166` in that block -- and that happens to have something answering IPP/port 631 there, e.g. another user's device, a captive-portal box, or an adversary who has claimed that address on a hotel/guest network -- would be sent by CUPS to that device with no host-identity verification, since the printer is referenced by bare `ipp://<ip>/...` with no TLS and no certificate/host pinning. `ensureDefaultPrinter` makes this the OS-wide default, so this isn't a queue the user has to knowingly select -- ordinary "print" from any app routes here. This is a smaller-probability variant of exactly the risk D9 was written to avoid (a printer identity that isn't actually verified), just via a different mechanism (static-IP address-space collision instead of mDNS spoofing).
- **Rule:** new-rule candidate -- extends D9's own logic (avoid trusting network-supplied identity for a printer on a roaming host) to the case where the "static" identity itself is address-space-ambiguous across networks.
- **Finding:** The plan and D9 both frame the literal-IP `deviceUri` as strictly safer than mDNS resolution because it removes reliance on untrusted-network-supplied name resolution. That's true relative to mDNS, but it does not make the queue network-independent: `PC.nix` is shared by both `torrent` (stationary, always on the home LAN where `.166` is the real printer) and `thinkpad` (roams). Nothing in this profile scopes the printer queue, or gates printing, to the home network specifically -- e.g. there's no check against the default gateway/SSID, and CUPS has no way to know "IP `192.168.1.166`" only means the right device when the active network is the home one.
- **Fix risk:** Any fix (per-host override so `thinkpad` doesn't get `ensureDefaultPrinter`/the queue at all, or a network-detection gate) needs testing that legitimate printing from the laptop while it's actually on the home LAN still works, and should be weighed against whether the user actually wants to print from the laptop at all -- if not, the simplest fix is moving this out of the shared `profile-pc` and into `torrent`'s own host config instead of gating on IP.

_docs-updater finished 2026-09-03T00:51:54Z -- see Findings above._

**Checked and clean:** Verified against the pinned `nixpkgs-unstable` rev (`0e251e24a4f24e036a084b6b4b2d2491af4167f4`, matching `flake.lock`) that `services.printing.listenAddresses` (default `["localhost:631"]`), `browsing` (default `false`), `openFirewall` (default `false`), and `browsed.enable` (defaults to `services.avahi.enable`, which is false/unset here) are all untouched by this diff -- CUPS still binds loopback-only and `networking.firewall` gets no new rule from `services.printing`, on either host. `hardware.sane.enable = true` alone (`services.saned.enable` left at its default `false`) does not start the `saned@`/`systemd.sockets.saned` unit that would bind `0.0.0.0:6566`, and `hardware.sane.openFirewall` (default `false`, untouched) means no UDP 8612 hole either -- confirmed against `nixos/modules/services/hardware/sane.nix` at the same pinned rev. `hardware.printers.ensurePrinters`/`ensureDefaultPrinter` render to a root `lpadmin`/`-m everywhere` oneshot against the local `/run/cups/cups.sock` (confirmed against `nixos/modules/hardware/printers.nix`), matching the plan's own G1 guidance (`-m everywhere` rather than autodetection) and introducing no network surface of its own. Confirmed `services.avahi` is absent repo-wide (not just this file), so D9 hasn't been silently undone elsewhere. Did not touch `secrets/*` (nothing in this diff references a secret). No unused/dead config: both new option blocks (`ensurePrinters`, `hardware.sane`) are actively wired to the printer this plan is about, nothing dangling.

_security finished 2026-09-03T00:52:51Z -- see Findings above._

**FIXED 2026-09-02:** Same fix as F1: hardware.printers.ensurePrinters/ensureDefaultPrinter moved into nixosModules."brother-mfc-l2740dw", torrent-only. thinkpad no longer gets the printer queue or default-printer setting at all, so there's no static-IP-collision risk on other networks it joins.
