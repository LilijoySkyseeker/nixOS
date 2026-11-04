{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos."nfs-homelab-mounts" = { utils, ... }: {
    # must match homelab's "multimedia" gid (services/jellyfin.nix): NFS
    # sec=sys authorizes by numeric uid/gid
    users.groups.multimedia = {
      gid = vars.gids.multimedia;
      members = [ "lilijoy" ];
    };

    fileSystems =
      let
        mountOpts = [
          "noauto"
          "x-systemd.automount"
          "x-systemd.idle-timeout=600"
          "x-systemd.mount-timeout=10"
          "_netdev"
          "soft"
          "timeo=30"
          "retry=0"

          # security: sec=sys trusts homelab's uids/modes, so without these
          # root on homelab could plant setuid binaries/device nodes here
          "nosuid"
          "nodev"
          "noexec"
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

    # a mount attempt fails whenever homelab is unreachable (offline, tailnet
    # not up yet at boot) and the automount retries on the next access
    myHealthAlerts.ignoreFailedUnits = map (path: "${utils.escapeSystemdPath path}.mount") [
      "/home/lilijoy/storage"
      "/home/lilijoy/storage-bulk"
    ];
  };
}
