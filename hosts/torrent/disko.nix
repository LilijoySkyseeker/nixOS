{ vars, ... }:
{
  # disko
  disko.devices =
    let
      rootSsd = vars.mkZfsRootSsd;
    in
    {
      disk = {
        # Root pool disks
        nvme-a = rootSsd 1 "nvme-Samsung_SSD_990_PRO_4TB_S7KGNU0XA02842B" "16G";
      };
      zpool = {
        zroot = {
          type = "zpool";
          mode = "";
          rootFsOptions = vars.zfsRootFsOptions;
          options.ashift = "13"; # MAKE SURE THIS IS CORRECT WITH DIFFRENT DRIVE
          datasets = {
            "local" = {
              type = "zfs_fs";
              options.mountpoint = "none"; # top dir is options.mountpoint
              options."com.sun:auto-snapshot" = "false";
            };
            "local/nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options."com.sun:auto-snapshot" = "false";
            };
            "local/root" = {
              type = "zfs_fs";
              mountpoint = "/";
              options."com.sun:auto-snapshot" = "false";
            };
            "local/home" = {
              type = "zfs_fs";
              mountpoint = "/home";
              options."com.sun:auto-snapshot" = "false";
            };
          };
        };
      };
    };
}
