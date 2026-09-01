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
        nvme-a = rootSsd 1 "nvme-Samsung_SSD_970_EVO_Plus_500GB_S58SNS0R706072M" "16G";
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
            };
            "local/nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
            };
            "local/state" = {
              type = "zfs_fs";
              mountpoint = "/nix/state"; # sub dir are just mountpoint
            };
            "local/root" = {
              type = "zfs_fs";
              mountpoint = "/";
              postCreateHook = "zfs snapshot zroot/local/root@blank";
            };
            "local/home" = {
              type = "zfs_fs";
              mountpoint = "/home";
              postCreateHook = "zfs snapshot zroot/local/home@blank";
            };
          };
        };
      };
    };
}
