_: {
  flake.modules.nixos."brother-mfc-l2740dw" = _: {
    # driverless IPP Everywhere queue (`-m everywhere`, CUPS built-in) at a
    # router DHCP reservation; bare IP, not mDNS: avahi is gone fleet-wide
    # torrent only: bare-IP printer/scanner identities are unsafe on a roaming laptop
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

      # scanning: CLOSED SOURCE brscan4, an unfree x86-only vendor blob dlopen'd
      # into the desktop session (docs/adr/0003-unfree-brscan4-blob-for-scanning-on-torrent.md)
      # no extraBackends: the brscan4 module wires pkgs.brscan4 itself
      sane = {
        enable = true;
        brscan4 = {
          enable = true;
          # attr name is brsaneconfig4's friendly `name=`, not the `scanimage -L`
          # device string; ip= not nodename=: nodename needs mDNS (avahi is gone)
          netDevices."mfc-l2740dw" = {
            model = "MFC-L2740DW";
            ip = "192.168.1.166";
          };
        };
      };
    };

    # `-m everywhere` queries the printer live at setup, so it needs the
    # network up, not just cups.service
    systemd.services.ensure-printers = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # lpadmin's probe fails against a sleeping printer and one miss leaves the
      # queue half-built; retry so a waking printer self-heals, then give up
      startLimitIntervalSec = 600;
      startLimitBurst = 5;
      serviceConfig = {
        # systemd refuses always/on-success on Type=oneshot
        Restart = "on-failure";
        RestartSec = 30;

        # worst case 5x45 + 4x30 = 345s must fit startLimitIntervalSec, or the
        # burst resets, retries never end and the unit never reaches `failed`
        TimeoutStartSec = 45;
      };
    };

    # no inbound firewall rule: brscan4 dials the printer's 54921 outbound,
    # conntrack ESTABLISHED covers it
  };
}
