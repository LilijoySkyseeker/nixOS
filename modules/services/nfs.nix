{ config, lib, ... }:
let
  ips = config.flake.vars.tailnetIPv4;
  # torrent and thinkpad only; other tailnet devices can't mount
  clients = lib.concatMapStringsSep " " (ip: "${ip}(rw,sync,no_subtree_check,root_squash)") [
    ips.torrent
    ips.thinkpad
  ];
in
{
  flake.modules.nixos.nfs = _: {
    # nfs server: tailnet-only share of /storage and /storage-bulk for the
    # linux PCs; android gets the same datasets over samba (samba.nix)
    services.nfs.server = {
      enable = true;
      exports = ''
        /storage ${clients}
        /storage-bulk ${clients}
      '';
    };

    # NFSv4-only: single port (2049), no rpcbind/mountd/statd/lockd
    services.nfs.settings.nfsd = {
      vers3 = false;
      vers4 = true;
    };

    # tailnet only, never the LAN NIC (homelab is a LAN subnet router); the
    # exports' per-PC addresses are a second layer
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 2049 ];

    # /storage* are persistent ZFS datasets, so no environment.persistence entry
  };
}
