{ config, lib, ... }:
let
  ips = config.flake.vars.tailnetIPv4;
  clients = lib.concatMapStringsSep " " (ip: "${ip}(rw,sync,no_subtree_check,root_squash)") [
    ips.torrent
    ips.thinkpad
  ];
in
{
  flake.modules.nixos.nfs = _: {
    services.nfs.server = {
      enable = true;
      exports = ''
        /storage ${clients}
        /storage-bulk ${clients}
      '';
    };

    # tailnet only, never the LAN NIC; the
    # exports' per-PC addresses are a second layer
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 2049 ];

    # /storage* are persistent ZFS datasets, so no environment.persistence entry
  };
}
