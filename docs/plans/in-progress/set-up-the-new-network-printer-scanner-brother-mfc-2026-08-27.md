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
- [ ] Give the printer a static address (DHCP reservation on the router).
- [ ] Try driverless first: declare an ipp://<static-ip>/ipp/print queue, model everywhere, via hardware.printers.ensurePrinters -- use the IP not the ._ipp._tcp.local mDNS URI, since that would need avahi back and undo D9.
- [ ] Only if driverless fails, add a driver -- check brlaser actually lists this model before assuming.
- [ ] Scanning (separate from printing, not set up at all yet): prefer sane-airscan (driverless eSCL over the same static IP) over Brother's brscan4 blob.

## Decisions (D)

## Gotchas (G)

### G1 -- driverless queues added via the web UI/autodetection can silently fail to print
Known CUPS wrinkle: use `lpadmin -m everywhere` instead. If pages come out blank or jobs vanish, that's a queue-creation problem, not a network one -- check this first.

## Findings (F)
*(populated by security/docs-updater when invoked)*
