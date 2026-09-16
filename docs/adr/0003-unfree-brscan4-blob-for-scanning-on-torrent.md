---
status: accepted
date: 2026-09-16
---

# Scanning on torrent uses Brother's unfree brscan4 blob

`torrent` scans through **brscan4**, Brother's closed-source, binary-only,
x86-only vendor backend (`license = lib.licenses.unfree`,
`sourceProvenance = binaryNativeCode`). It replaces the driverless
`sane-airscan`/WSD path the fleet used until now.

It is confined to one host, wired in at
`modules/nixos/brother-mfc-l2740dw.nix` and imported only by `torrent`
(`modules/flake/hosts.nix`). It should not spread to a second host
without revisiting this record.

It is *not* the fleet's first unfree package. `spotify`, `discord` and
`claude-code` are all unfree `binaryNativeCode` and already ship on both
PC hosts, under a block in `modules/profiles/PC.nix` that is itself
commented `# closed source`; `vscode-fhs`, `steam` and `obsidian` are
unfree too.
What is new here is not unfree-ness but **exposure**: those are
user-launched applications talking to servers over TLS, whereas this is a
library `dlopen`ed into a desktop process and fed unauthenticated input
by whatever answers at a bare LAN IP. That distinction, not novelty, is
what this record is about.

Decided in
`2026-09-16-switch-torrent-scanning-to-brother-s-closed-source-brscan-driver-for.md`,
which carries the measurements behind it.

## The problem this solves

The driverless path worked, and its own plan
(`2026-08-27-set-up-the-new-network-printer-scanner-brother-mfc.md#D1`)
chose it precisely to avoid this blob. What it could not do is scan above
**300 dpi**. sane-airscan against this device over WSD offers exactly
`--resolution 100|200|300dpi`. brscan4 offers
`100|150|200|300|400|600|1200|2400|4800|9600dpi`.

Worth stating plainly, because it is the obvious counter-argument: the
trigger for looking at this was double-sided scanning appearing broken,
and **WSD does support duplex**. It advertises
`--source Flatbed|ADF|ADF Duplex`, and a real duplex acquisition through
it succeeds. The duplex failure was in the desktop application, not the
driver. So "driverless cannot duplex" is *not* a reason for this decision
and should not be remembered as one.

The resolution ceiling is the honest reason, together with the user
having a known-good reference machine on Brother's drivers.

## Considered alternatives

- **Stay on sane-airscan/WSD.** Free, already working, no new trust.
  Rejected: capped at 300 dpi, which is the actual requirement that
  prompted the change.
- **brscan5 instead of brscan4.** Newer, still unfree, so no trust
  benefit. Rejected on evidence: brscan5 1.3.1 ships no entry for the
  MFC-L2740DW. `brsaneconfig5` registers it as `Unknown` and falls back
  to a generic profile that advertises features this hardware lacks
  (`--MultifeedDetection`, `--AutoDocumentSize`) and a wrong maximum scan
  width. brscan4's own table carries the model
  (`models4/ext_11.ini`: `0x0320,313,1,"MFC-L2740DW"`), and Brother
  offers only brscan4 for it.
- **Run both backends.** Verified to work -- `dll.conf` files are
  concatenated, not overwritten, so the device enumerates twice with
  distinct URIs. Rejected: two entries in every scan dialog, one of them
  silently limited, is a footgun rather than a fallback. It would also
  keep the WSD firewall rule and the multicast probing alive for
  something nobody should pick.
- **Keep driverless and fix the application.** Legitimate, and cheaper.
  Not chosen because it does not address the dpi ceiling.

## Consequences

- **A binary blob parses network input inside a root-equivalent session,
  and it is not a hardened binary.** This is the main cost, and it is
  worse than "an unaudited library." Measured on the pinned
  `libsane-brother4.so.1.0.7`: no `GNU_RELRO`, no stack protector (zero
  `__stack_chk_*`), no `_FORTIFY_SOURCE` `*_chk` imports, and it imports
  `strcpy`, `strcat`, `sprintf` and `popen`. SANE backends are
  `dlopen`ed in-process, so that code runs inside the scanning
  application in `lilijoy`'s desktop session — and `lilijoy` is in
  `wheel`, `docker` and `libvirtd`, each of which is a root-equivalent
  path. A hostile or spoofed device answering at `192.168.1.166:54921`
  therefore has a plausible route to host root that never passes a
  `run0` prompt.

  There is no daemon, no listening socket and no setuid binary — the
  bound is on *reachability*, not on what happens once it is reached.
  `users.groups.scanner.members` is empty, so no additional principal
  gains access.

  Accepted knowingly, for one host, on a home LAN, for a scanner the user
  wants. If this were ever to run on a host handling untrusted network
  neighbours, or as a service account, revisit it — the right mitigation
  would be confining the scan application rather than trusting the blob.
- **x86-64 only.** Scanning cannot follow this config to an aarch64 host.
- **Version drift is now a vendor problem.** nixpkgs pins brscan4
  0.4.10-1 against Brother's current 0.4.11-1. 0.4.10 contains the model
  and works. There is no source to patch if it ever does not.
- **No VM test.** nixpkgs has `nixos/tests/brscan5.nix` and a
  `passthru.tests` for brscan5; brscan4 has neither. Evidence for changes
  here tops out at rung 3 without writing one.
- **Inbound network surface goes down.** brscan4 makes ordinary outbound
  TCP connections to the printer's port 54921, so conntrack
  `ESTABLISHED` covers it and no inbound rule is needed. Deleting the WSD
  ephemeral-range accept removes the only inbound accept **on `enp8s0`**
  — `tailscale0` still accepts TCP 22 and 1714-1764, and `allowPing`
  stays true, so this is not "the last inbound accept on the host". It
  also ends WS-Discovery multicast from torrent, which was the last live
  remnant of what audit decision D9 set out to remove.

  The deleted rule is the subject of `...brother-mfc.md#F3`, which was
  **fixed** (narrowed from all-UDP to the ephemeral range) rather than
  accepted; `docs/accepted-risks.md` has no printer entry. This change
  retires the narrowed remainder — trusting a bare, on-link-claimable
  source IP across that range — rather than retiring an accepted risk.
- **`brscan-skey` stays out.** The scan-to-PC *button* daemon is not
  packaged in nixpkgs at all, and would require an inbound UDP 54925
  hole. Scanning is initiated from the PC, so it is not needed.
- **The device name changes**, and anything scripted against the old one
  breaks: `airscan:w0:Brother MFC-L2740DW series` becomes
  `brother4:net1;dev0`. The duplex source string changes vocabulary too,
  from `ADF Duplex` to
  `Automatic Document Feeder(left aligned,Duplex)`.
- **A udev rule and `brsaneconfig4` arrive with it.** `hardware.sane`
  puts every backend into `services.udev.packages`, so brscan4's
  `49-brother-libsane-type1.rules` lands in `/etc`. It matches
  `SUBSYSTEM=="usb"` on Brother's vendor id and is inert for a network
  device, but it is not nothing. `brsaneconfig4` also joins every user's
  `PATH`.

- **Unfree was already permitted**, so nothing was loosened to allow
  this: `nixpkgs.config.allowUnfree = true` is set fleet-wide at
  `modules/profiles/default.nix:188`, separately from
  `hardware.enableAllFirmware`, and the unfree desktop applications above
  already rely on it. The gate this decision passes is *this record*, not
  a config flag.
