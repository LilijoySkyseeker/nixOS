{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos."nfs-homelab-mounts" = _: {
    # must match homelab's "multimedia" gid (services/jellyfin.nix): NFS
    # sec=sys authorizes by numeric uid/gid
    users.groups.multimedia = {
      gid = vars.gids.multimedia;
      members = [ "lilijoy" ];
    };

    # nfs client mounts for homelab's tailnet-only share (services/nfs.nix),
    # automounted so boot never blocks when homelab is unreachable
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

          # security: sec=sys trusts homelab's uids/modes, so without these
          # root on homelab could plant setuid binaries/device nodes here
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
