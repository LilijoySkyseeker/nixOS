{ vars, config, ... }:
{
  disko.devices =
    let
      rootSsd = vars.mkZfsRootSsd;
      zfsProps = vars.zfsProps config;
    in
    {
      disk = {
        nvme-a = rootSsd 1 "nvme-Samsung_SSD_990_PRO_4TB_S7KGNU0XA02842B" "16G";
      };
      zpool = {
        zroot = {
          type = "zpool";
          mode = "";
          rootFsOptions = config.myZfsDatasetProperties."zroot";
          options.ashift = "13"; # MAKE SURE THIS IS CORRECT WITH DIFFRENT DRIVE
          datasets = {
            "local" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                "com.sun:auto-snapshot" = "false";
              }
              // zfsProps "zroot" "local";
            };
            "local/nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options = {
                "com.sun:auto-snapshot" = "false";
              }
              // zfsProps "zroot" "local/nix";
            };
            "local/root" = {
              type = "zfs_fs";
              mountpoint = "/";
              options = {
                "com.sun:auto-snapshot" = "false";
              }
              // zfsProps "zroot" "local/root";
            };
            "local/home" = {
              type = "zfs_fs";
              mountpoint = "/home";
              options = {
                "com.sun:auto-snapshot" = "false";
              }
              // zfsProps "zroot" "local/home";
            };
            # local-ai's model store; on a live host it needs a manual zfs create.
            # nofail: not needed to boot, so a missing dataset only means no models
            "local/models" = {
              type = "zfs_fs";
              mountpoint = "/srv/models";
              mountOptions = [
                "defaults"
                "nofail"
              ];
              options = {
                "com.sun:auto-snapshot" = "false";
              }
              // zfsProps "zroot" "local/models";
            };
          };
        };
      };
    };
}
