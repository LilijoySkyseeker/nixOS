{
  # matches homelab's "multimedia" group (services/jellyfin.nix), which
  # owns /storage and /storage-bulk — NFS with sec=sys authorizes purely
  # by numeric uid/gid, so lilijoy needs this exact gid locally to get
  # group read/write on the mounts below.
  users.groups.multimedia = {
    gid = 999;
    members = [ "lilijoy" ];
  };

  # nfs client mounts for homelab's tailnet-only file share (see
  # services/nfs.nix). Automounted on first access rather than at boot —
  # laptops/desktops aren't always on the tailnet or near homelab, so
  # boot must never block on this.
  fileSystems =
    let
      mountOpts = [
        "noauto" # don't mount at boot
        "x-systemd.automount" # mount on first access instead
        "x-systemd.idle-timeout=600" # unmount after 10m unused
        "x-systemd.mount-timeout=10" # give up quickly if homelab/tailnet is unreachable
        "_netdev" # needs the network, not local disk
        "soft" # time out rather than hang a process forever if the server disappears
        "timeo=30"
        "retry=0"
      ];
    in
    {
      "/home/lilijoy/storage" = {
        device = "homelab:/storage";
        fsType = "nfs4";
        options = mountOpts;
      };
      "/home/lilijoy/storage-bulk" = {
        device = "homelab:/storage-bulk";
        fsType = "nfs4";
        options = mountOpts;
      };
    };
}
