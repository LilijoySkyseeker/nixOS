_: {
  flake.modules.nixos.nfs = _: {
    # nfs server: tailnet-only share of /storage and /storage-bulk for linux
    # clients; android gets the same datasets over samba (samba.nix)
    services.nfs.server = {
      enable = true;
      exports = ''
        /storage 100.64.0.0/10(rw,sync,no_subtree_check,root_squash)
        /storage-bulk 100.64.0.0/10(rw,sync,no_subtree_check,root_squash)
      '';
    };

    # NFSv4-only: single port (2049), no rpcbind/mountd/statd/lockd
    services.nfs.settings.nfsd = {
      vers3 = false;
      vers4 = true;
    };

    # tailnet only, never the LAN NIC (homelab is a LAN subnet router); the
    # exports' 100.64.0.0/10 is a second layer
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 2049 ];

    # /storage* are persistent ZFS datasets, so no environment.persistence entry
  };
}
