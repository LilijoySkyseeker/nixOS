{

  # nfs server — tailnet-only file share for /storage and /storage-bulk
  # (the same datasets previously served by copyparty). NFSv4 covers Linux
  # clients; Android has no usable native NFS client, so it's served the
  # same datasets separately over Samba (see services/samba.nix).
  services.nfs.server = {
    enable = true;
    exports = ''
      /storage 100.64.0.0/10(rw,sync,no_subtree_check,root_squash)
      /storage-bulk 100.64.0.0/10(rw,sync,no_subtree_check,root_squash)
    '';
  };

  # NFSv4-only: single port (2049), no rpcbind/mountd/statd/lockd
  # negotiation needed on the wire, which keeps the firewall surface to
  # one port below.
  services.nfs.settings.nfsd = {
    vers3 = false;
    vers4 = true;
  };

  # restrict to the tailnet interface only — never exposed on the LAN NIC,
  # even though homelab is also a LAN subnet router/exit node (see
  # tailscale extraUpFlags in hosts/homelab/configuration.nix). The
  # 100.64.0.0/10 restriction in the exports above is defense-in-depth on
  # top of this interface scoping.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 2049 ];

  # /storage and /storage-bulk are already-persistent ZFS datasets (see
  # zdata/storage/* in hosts/homelab/configuration.nix), not impermanence
  # paths, so no environment.persistence entry is needed here.
}
