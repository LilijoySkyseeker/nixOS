# Printer and scanner on torrent: usable but glitchy

## Goal

The Brother MFC-L2740DW on torrent prints and scans reliably.

## Your decisions

- 2026-10-06: "usable but unreliable and glitchy"; worth fixing.

## State

Three fixes exist in the repo and have never been running on torrent
(nothing was deployed between 2026-08-27 and the deploy-schedules PR):

- `ensure-printers` gets `After=/Wants=network-online.target` and
  restarts on failure, so it no longer fails on every boot.
- Scanning uses Brother's closed-source `brscan4` driver (ADF duplex up
  to 9600 dpi), recognised by the real device before it was configured.
- One scanner outage on 2026-09-16 was device-side; a power-cycle fixed it.

Open idea: pin the scanner in `airscan.conf` (`[devices]`) instead of
discovering it. Its WSD URL is
`http://192.168.1.166:80/WebServices/ScannerService` (port 80, not
5357). That would drop WS-Discovery probing and sane-airscan's ~20s
stall waiting on avahi, which is gone. It needs the printer's IP to stay
fixed (a DHCP reservation).

Detail is in git history: the three 2026-09-16 printer/scanner plans
under `docs/plans/in-progress/`, deleted 2026-10-06.

## Next

After torrent switches to the deploy-schedules change and reboots:
check `systemctl status ensure-printers`, print a page, and scan a
two-sided sheet through the ADF. Then decide whether the remaining
glitches justify pinning the scanner.
