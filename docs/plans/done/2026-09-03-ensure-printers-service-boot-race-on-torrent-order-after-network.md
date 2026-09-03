---
slug: ensure-printers-service-boot-race-on-torrent-order-after-network
created: 2026-09-03
status: done
frozen: true
---

# ensure-printers.service boot race on torrent -- order after network-online.target

## Original plan

- [ ] **2026-09-03: `health-alerts` posted `[torrent] systemd units failed`
      for `ensure-printers.service`.** Diagnosed live on torrent (this
      box). `journalctl -u ensure-printers.service -b`: torrent booted at
      18:37:39 (2026-09-02), `NetworkManager.service` started at
      18:37:52, and `ensure-printers.service` ran its `lpadmin -p
      Brother_MFC_L2740DW -v ipp://192.168.1.166/ipp/print -m everywhere`
      call at that exact same second -- `lpadmin: Unable to connect to
      192.168.1.166:631: Host is down`. The printer itself was never
      down: confirmed reachable (ping + port 631) minutes into the
      investigation, 18+ hours after the failed boot.

      Root cause: `hardware.printers.ensurePrinters`
      (nixpkgs `nixos/modules/hardware/printers.nix`) only sets `wants`/
      `after = [ "cups.service" ]` on `ensure-printers.service`, not
      `network-online.target`. `-m everywhere` (IPP Everywhere) makes
      `lpadmin` do a live IPP Get-Printer-Attributes against the device
      at setup time, unlike a static PPD, so it genuinely needs the
      network up first. Torrent uses NetworkManager, which wires
      `NetworkManager-wait-online.service` into `network-online.target`
      (confirmed in the pinned nixpkgs source), so this is fixable.
      It's `Type=oneshot`/`RemainAfterExit=true` with no restart policy,
      so unlike the NFS-automount boot race
      (`2026-09-01-torrent-s-storage-bulk-nfs-automount-failed-once-at-boot-self-healed.md`)
      it does not self-heal -- stays `failed` until manually restarted.

      Fix: add `after`/`wants = [ "network-online.target" ]` to
      `systemd.services.ensure-printers` via override in
      `modules/nixos/brother-mfc-l2740dw.nix`.

      Immediate remediation (with explicit user confirmation, since
      restarting any unit on torrent is a hard-confirm action):
      `systemctl restart ensure-printers.service` succeeded once the
      printer was confirmed reachable; `systemctl --failed` is empty.

## State

Diagnosed and fixed. `systemd.services.ensure-printers.after`/`wants` now
include `network-online.target` in `modules/nixos/brother-mfc-l2740dw.nix`,
build-verified on torrent (`nixos-rebuild build`), confirmed the generated
unit carries the new ordering. Immediate alert cleared live via
`systemctl restart ensure-printers.service`, confirmed with the user first.

## Progress

- [x] Root cause confirmed live via journalctl/systemctl on torrent
- [x] Immediate remediation: restarted ensure-printers.service (user-confirmed)
- [x] Declarative fix: order after network-online.target
- [x] Build-verified on torrent, confirmed in generated unit file


## Decisions (D)


## Gotchas (G)
### G1 -- upstream `hardware.printers.ensurePrinters` doesn't wait for network
The nixpkgs module only orders `ensure-printers.service` after
`cups.service`. Any `ensurePrinters` entry using `-m everywhere` (IPP
Everywhere) needs live network access at setup time, so on a host where
network bring-up (`NetworkManager`/`systemd-networkd`) isn't already
guaranteed to precede `cups.service`, add `after`/`wants =
[ "network-online.target" ]` on the service yourself -- the module won't
do it for you, and a failure here doesn't self-heal (`Type=oneshot`, no
`Restart=`).

## Findings (F)
*(populated by security/docs-updater when invoked)*
