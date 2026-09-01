{ vars, config, ... }:
{
  # disko
  disko.devices =
    let
      rootSsd = vars.mkZfsRootSsd;
      zfsProps = vars.zfsProps config; # see vars.nix
    in
    {
      disk = {
        # Root pool disks
        nvme-a = rootSsd 1 "nvme-Samsung_SSD_970_EVO_Plus_500GB_S58SNS0R706072M" "16G";
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
                mountpoint = "none"; # top dir is options.mountpoint
              }
              // zfsProps "zroot" "local";
            };
            "local/nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options = zfsProps "zroot" "local/nix";
            };
            "local/state" = {
              type = "zfs_fs";
              mountpoint = "/nix/state"; # sub dir are just mountpoint
              options = zfsProps "zroot" "local/state";
            };
            "local/root" = {
              type = "zfs_fs";
              mountpoint = "/";
              postCreateHook = "zfs snapshot zroot/local/root@blank";
              options = zfsProps "zroot" "local/root";
            };
            "local/home" = {
              type = "zfs_fs";
              mountpoint = "/home";
              postCreateHook = "zfs snapshot zroot/local/home@blank";
              options = zfsProps "zroot" "local/home";
            };
          };
        };
      };
    };
}
