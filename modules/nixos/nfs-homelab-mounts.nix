{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos."nfs-homelab-mounts" =
    { ... }:
    {
      # matches homelab's "multimedia" group (services/jellyfin.nix), which
      # owns /storage and /storage-bulk — NFS with sec=sys authorizes purely
      # by numeric uid/gid, so lilijoy needs this exact gid locally to get
      # group read/write on the mounts below.
      users.groups.multimedia = {
        gid = vars.gids.multimedia;
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

            # These two are about trust, not availability (F-P6-05). NFS
            # here is sec=sys, so the client takes homelab's word for
            # every uid, gid and mode on the share. The server's
            # root_squash stops a compromised *client* writing root-owned
            # files; it does nothing about files the *server* already
            # owns. Without these, root on homelab can drop a setuid-root
            # binary or a mknod'd device node under /storage and it
            # becomes a privilege path on both laptops -- and the
            # multimedia gid mapping above gives lilijoy group rw over
            # the whole share, so nothing else is in the way.
            "nosuid" # no setuid/setgid on execution from the share
            "nodev" # no device nodes honoured from the share
            "noexec" # plan: 2026-09-03-add-noexec-to-the-homelab-nfs-share-mounts.md#D1
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
    };
}
