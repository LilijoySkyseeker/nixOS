_: {
  flake.modules.nixos."brother-mfc-l2740dw" = _: {
    # Driverless IPP Everywhere queue at a router-side DHCP reservation
    # (192.168.1.166). `-m everywhere` is CUPS's own built-in keyword
    # for this (see `lpadmin(8)`), not a vendor PPD. The device URI uses
    # the IP directly rather than the usual `._ipp._tcp.local` mDNS
    # form: that form resolves via avahi, and avahi is intentionally
    # gone fleet-wide (D9).
    #
    # Scoped to torrent only, not the shared profile-pc: this queue's
    # bare-IP deviceUri and the scanner's bare-IP netDevices entry below
    # are both network-supplied-identity risks on a roaming laptop,
    # which is exactly what D9 was written to avoid.
    # plan: 2026-08-27-set-up-the-new-network-printer-scanner-brother-mfc.md#F1
    # plan: 2026-08-27-set-up-the-new-network-printer-scanner-brother-mfc.md#F2
    hardware = {
      printers.ensurePrinters = [
        {
          name = "Brother_MFC_L2740DW";
          description = "Brother MFC-L2740DW";
          deviceUri = "ipp://192.168.1.166/ipp/print";
          model = "everywhere";
        }
      ];
      printers.ensureDefaultPrinter = "Brother_MFC_L2740DW";

      # Scanning. >>> CLOSED SOURCE <<< brscan4 is an unfree, binary-only,
      # x86-only vendor blob, dlopen'd into the desktop session and fed by
      # a bare LAN IP. Rejected alternatives and costs: ADR-0003. No
      # extraBackends line -- the brscan4 module wires pkgs.brscan4 itself.
      # adr: docs/adr/0003-unfree-brscan4-blob-for-scanning-on-torrent.md
      # plan: 2026-09-16-switch-torrent-scanning-to-brother-s-closed-source-brscan-driver-for.md#D1
      sane = {
        enable = true;
        brscan4 = {
          enable = true;
          # attr name becomes brsaneconfig4's `name=` -- the friendly
          # name in brsanenetdevice4.cfg, not the `scanimage -L` device
          # string; ip= rather than nodename= because nodename resolves
          # via mDNS and avahi is gone fleet-wide (D9).
          netDevices."mfc-l2740dw" = {
            model = "MFC-L2740DW";
            ip = "192.168.1.166";
          };
        };
      };
    };

    # ensurePrinters' own module only orders after cups.service, but
    # `-m everywhere` does a live IPP query against the printer at
    # setup time -- it needs the network up too. Hit this for real: a
    # 2026-09-02 boot ran lpadmin the same second NetworkManager
    # started, before torrent had a route to the LAN.
    # plan: 2026-09-03-ensure-printers-service-boot-race-on-torrent-order-after-network.md#G1
    systemd.services.ensure-printers = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # A waited-for network still isn't a reachable printer: this one
      # sleeps, and lpadmin's probe fails outright against a sleeping or
      # powered-off device. Type=oneshot has no retry of its own, and the
      # generated script is `set -e` with the probing lpadmin first, so a
      # single miss leaves the queue half-built and ensureDefaultPrinter
      # never applied. Retry a few times so a waking printer self-heals,
      # then give up rather than spin against an unplugged one.
      # plan: 2026-09-16-ensure-printers-fails-every-boot-on-torrent-undeployed-fix-plus-no.md#D1
      # plan: 2026-09-16-ensure-printers-fails-every-boot-on-torrent-undeployed-fix-plus-no.md#G2
      startLimitIntervalSec = 600;
      startLimitBurst = 5;
      serviceConfig = {
        # on-failure, not always -- systemd refuses always/on-success on
        # Type=oneshot.
        # plan: 2026-09-16-ensure-printers-fails-every-boot-on-torrent-undeployed-fix-plus-no.md#G3
        Restart = "on-failure";
        RestartSec = 30;

        # Without this the unit inherits systemd's 90s default, and a
        # printer that accepts the TCP connect but never answers stretches
        # each cycle past RestartSec -- five starts then outlast
        # startLimitIntervalSec, the burst resets instead of being spent,
        # and the retry never terminates. A unit stuck retrying also never
        # reaches `failed`, so health-alerts' `systemctl --failed` sweep
        # never reports it. 45s keeps the worst case (5x45 + 4x30 = 345s)
        # inside the window while still leaving a slow-but-awake printer
        # room to answer Get-Printer-Attributes.
        # plan: 2026-09-16-ensure-printers-fails-every-boot-on-torrent-undeployed-fix-plus-no.md#F3
        TimeoutStartSec = 45;
      };
    };

    # No inbound firewall rule, deliberately: brscan4 dials the printer's
    # 54921 outbound, so conntrack ESTABLISHED covers it.
    # plan: 2026-09-16-switch-torrent-scanning-to-brother-s-closed-source-brscan-driver-for.md#D2
  };
}
