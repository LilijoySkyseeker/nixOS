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

### F3 -- the new printer firewall rule accepts all UDP dest ports from a spoofable/claimable LAN IP, reopening the exact KDE Connect port range D9 deliberately confined to the tailnet

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:52-54` (new `networking.firewall.extraCommands` rule); `modules/profiles/PC.nix:264-299` (kdeconnect's UDP 1714-1764 forced off the default/LAN interface and onto `tailscale0` only, per D9)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the firewall-level widening (verified against the pinned `nixpkgs-unstable` rev via `nix repl` on `flake.nixosConfigurations.torrent.config.networking.firewall`: `allowedUDPPorts`/`allowedUDPPortRanges`/`allowedTCPPorts`/`allowedTCPPortRanges` all render `[]` on the default interface, `interfaces` only has `podman0`/`tailscale0` keys -- i.e. before this commit, literally nothing besides ESTABLISHED/RELATED was ever accepted inbound on `enp8s0`; `backend = "iptables"`, confirming `extraCommands` is not silently inert here; the rendered `extraCommands` string itself contains exactly one non-tailscale-NAT-cleanup line, `iptables -A nixos-fw -i enp8s0 -p udp -s 192.168.1.166 -j nixos-fw-accept`, with no `--dport` at all). PLAUSIBLE for the app-level consequence -- whether `kdeconnectd` actually processes/responds usefully to a packet arriving this way wasn't verified against its source, only inferred from PC.nix's own comment that the NixOS `programs.kdeconnect` module gives "no say" in scoping and that firewall-interface-scoping was the *only* available control (`nixos/modules/programs/kdeconnect.nix`, per that comment, not independently re-read here).
- **Axis:** hardening
- **Reachability:** Any device that can get UDP traffic onto torrent's LAN segment (`enp8s0`) with a source address of `192.168.1.166` -- either by spoofing that source IP (requires raw-socket/CAP_NET_RAW-level code execution on some device already on the LAN) or, with a materially lower bar, by simply self-configuring that IP on its own interface (e.g. if the printer is briefly powered off, unplugged, or its DHCP reservation lapses/is edited) -- gets accepted through `nixos-fw` on **every** UDP destination port, not just whatever ephemeral port a live WSD reply happens to use. Before this commit `cfg.allowedUDPPortRanges`/`allowedUDPPorts` were forced to `[]` host-wide specifically so kdeconnect's UDP 1714-1764 range would reach torrent only over `tailscale0` (PC.nix:264-281, citing D9); this new rule re-admits that exact range (and everything else) on `enp8s0` for any packet claiming to be from the printer's IP, undoing that scoping for one spoofable/claimable address.
- **Rule:** extends the caution in `docs/hardening.md` rule 5 ("a rule justified by a belief about the network... is a rule that will silently become wrong") from interface-trust to source-IP-trust; also conflicts with this repo's own documented decision D9 (recorded at `modules/profiles/PC.nix:264-281`), which this same host (`torrent`) is subject to.
- **Finding:** The commit message and code comment justify the all-ports scope purely on the grounds that WSD's reply port is ephemeral and unpredictable, which is true, but the fix reaches for "no destination-port restriction at all" rather than "restrict to the OS's ephemeral port range" (`net.ipv4.ip_local_port_range`, unmodified/default on this host -- not independently verified at the kernel-sysctl level here, so treat the exact bounds as PLAUSIBLE, but it is a bounded subset of 65535, not all of it). The gap between "ephemeral, so unpredictable" and "every port including ones with real listeners" is exactly where the kdeconnect exposure lives: nothing in the new rule excludes 1714-1764, so the specific protection D9 put in place for that range on the LAN-facing interface is undone for one source IP. The rule is correctly interface-scoped (satisfies the literal text of hardening.md rule 5) and correctly uses `extraCommands` rather than a nonexistent structured "source IP allow" option (no NixOS firewall option supports `-s`-based scoping; `extraCommands` is the documented escape hatch for exactly this, and the pinned-source check above confirms the `iptables` backend applies here, so it is not the "renders but does nothing" failure mode rule 9 warns about) -- the port breadth, not the mechanism or the interface scoping, is the issue.
- **Fix risk:** Narrowing `-p udp` to a `--dport` range (either the measured ephemeral range from a live `tcpdump` capture of the actual reply, or the kernel's configured `ip_local_port_range`) needs to be re-verified end-to-end (`scanimage -L` finding the scanner via WSD) since a too-narrow range would silently reintroduce G3's original symptom; the printer's own outbound source port for the WSD reply should be captured again rather than assumed, since sane-airscan's actual socket-binding behavior wasn't read from its source here.

_security (b7d447e firewall-fix review) finished 2026-09-02 -- see F3 above._

**Checked and clean:** Reviewed `b7d447e` (`git show b7d447e`, diffed against `b569f6a`) in full, plus the current content of `modules/nixos/brother-mfc-l2740dw.nix` and everything it interacts with. Confirmed via `nix repl` against `flake.nixosConfigurations.torrent.config` (pinned `nixpkgs-unstable` rev `0e251e24a4f24e036a084b6b4b2d2491af4167f4`) that `networking.firewall.backend = "iptables"` on torrent (not nftables), so `extraCommands` actually takes effect rather than silently no-op'ing (hardening.md rule 9) -- this addresses the reviewer's second question directly: `extraCommands` is sound here because no structured NixOS firewall option supports source-IP-scoped accept rules (only destination-port-based `allowedTCP/UDPPorts(Ranges)` per interface exist), so there is no narrower built-in option being passed over. The rule is correctly interface-scoped (`-i enp8s0`, satisfying hardening.md rule 5's literal text) and IPv4-only (`iptables`, not `ip46tables`), so it doesn't also open an IPv6 hole. Checked `firewall-iptables.nix` at the pinned rev directly: the `nixos-fw` chain is fully flushed (`-F`/`-X`) and rebuilt on every firewall-start/reload, so `extraCommands`' `-A` is not additive across activations/switches -- no rule-duplication or unbounded chain growth. Checked for other `networking.firewall.extraCommands` definitions repo-wide: this module is the only one, so no multi-definition ordering/interaction risk. Checked `hosts/torrent/hardware-configuration.nix`'s auto-generated (and inert, since `useDHCP` is global) `enp7s0` comment against the `enp8s0` interface named in the new rule -- a plausible mismatch on paper, but the plan's own G3 end-to-end verification (`scanimage -L` finding the scanner after switching this exact change) confirms `enp8s0` is in fact torrent's live LAN interface, so this is not a real defect. Did not decrypt or read `secrets/*`. The one substantive issue found is F3 above (all-UDP-ports-from-one-IP re-opening the LAN-facing KDE Connect range D9 closed) -- everything else about the mechanism, scoping, and idempotency of this change is sound.

_security finished 2026-09-03T01:31:38Z -- see Findings above._

**FIXED 2026-09-02:** Narrowed the extraCommands rule from all-UDP-ports to just the kernel's ephemeral port range (--dport 32768:60999, matching /proc/sys/net/ipv4/ip_local_port_range on torrent) so it no longer re-opens KDE Connect's 1714-1764 range (or anything else below the ephemeral range) for a spoofed/claimed 192.168.1.166. Re-verified live: scanimage -L still finds the scanner after the switch.
