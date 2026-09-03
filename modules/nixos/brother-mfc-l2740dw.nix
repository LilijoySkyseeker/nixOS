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

      # WS-Discovery's probe/reply doesn't fit conntrack's usual
      # request/reply matching: the probe goes out to the 239.255.255.250
      # multicast group from an ephemeral source port, but the printer's
      # reply comes back as unicast from its own IP to that same ephemeral
      # port -- a different source than the packet's original destination,
      # so it's never RELATED/ESTABLISHED and the default-deny firewall
      # silently drops it (confirmed with tcpdump: the printer replies
      # every time, sane-airscan just never sees it). The reply's
      # destination port is whatever ephemeral port sane-airscan happened
      # to bind that run, so a dport-based allow can't target it -- allow
      # by the printer's own source IP instead, scoped to enp8s0 (torrent's
      # LAN NIC), not host-wide.
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -i enp8s0 -p udp -s 192.168.1.166 -j nixos-fw-accept
      '';
    };
}
