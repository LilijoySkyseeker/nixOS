# Printer and scanner on torrent: usable but glitchy

## Goal

The Brother MFC-L2740DW on torrent prints and scans reliably.

## Your decisions

- 2026-10-06: "usable but unreliable and glitchy"; worth fixing.

## State

torrent runs all of it since the 10-11 deploy schedules. Checked
2026-10-26 (agent-maintenance): the queue exists and is the default
(`lpstat -p -d`). nixpkgs now adds `ensurePrinters` in `cups.service`'s
`postStart` and has no `ensure-printers` unit, so the repo's retry and
network-online ordering for that unit applied to nothing (systemd
showed it as `bad-setting`) and were removed. If the queue goes missing
after a boot, that race is back: the fix would go on `cups.service`.

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

The owner prints a page and scans a two-sided sheet through the ADF, then
decides whether the remaining glitches justify pinning the scanner.
