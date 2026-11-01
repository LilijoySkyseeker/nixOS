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
      # into the desktop session
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

    # no inbound firewall rule: brscan4 dials the printer's 54921 outbound,
    # conntrack ESTABLISHED covers it
  };
}
