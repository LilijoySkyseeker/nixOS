_: {
  flake.modules.nixos."brother-mfc-l2740dw" =
    { pkgs-unstable, ... }:
    {
      # Driverless IPP Everywhere queue at a router-side DHCP reservation
      # (192.168.1.166). `-m everywhere` is CUPS's own built-in keyword
      # for this (see `lpadmin(8)`), not a vendor PPD. The device URI uses
      # the IP directly rather than the usual `._ipp._tcp.local` mDNS
      # form: that form resolves via avahi, and avahi is intentionally
      # gone fleet-wide (D9).
      #
      # Scoped to torrent only, not the shared profile-pc: both this
      # queue's bare-IP deviceUri and sane-airscan's WSD discovery below
      # are network-supplied-identity risks on a roaming laptop, which is
      # exactly what D9 was written to avoid.
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

        # Scanning. This model speaks WSD, not eSCL, but sane-airscan
        # auto-negotiates both, so it still needs no Brother brscan4 blob.
        # WSD must also be turned on in the printer's own web console
        # first (off by default).
        # plan: 2026-08-27-set-up-the-new-network-printer-scanner-brother-mfc.md#G2
        sane = {
          enable = true;
          extraBackends = [ pkgs-unstable.sane-airscan ];
        };
      };

      # ensurePrinters' own module only orders after cups.service, but
      # `-m everywhere` does a live IPP query against the printer at
      # setup time -- it needs the network up too, or it fails outright
      # with no retry (Type=oneshot, no Restart=). Hit this for real: a
      # 2026-09-02 boot ran lpadmin the same second NetworkManager
      # started, before torrent had a route to the LAN.
      # plan: 2026-09-03-ensure-printers-service-boot-race-on-torrent-order-after-network.md#G1
      systemd.services.ensure-printers = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };

      # WSD's reply comes back unicast from the printer to whatever
      # ephemeral port sane-airscan bound that run -- a different source
      # than the original multicast probe's destination, so conntrack
      # never marks it RELATED/ESTABLISHED and the default-deny firewall
      # silently drops it (confirmed via tcpdump). dport can't target a
      # single port, so scope to the kernel's ephemeral range instead of
      # all UDP -- see F3 for why that matters. enp8s0 (LAN NIC) only.
      # plan: 2026-08-27-set-up-the-new-network-printer-scanner-brother-mfc.md#F3
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -i enp8s0 -p udp -s 192.168.1.166 --dport 32768:60999 -j nixos-fw-accept
      '';
    };
}
