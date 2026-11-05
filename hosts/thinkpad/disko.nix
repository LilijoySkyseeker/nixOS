{ vars, config, ... }:
{
  disko.devices =
    let
      zfsProps = vars.zfsProps config;
    in
    vars.mkEncryptedRootSsd "nvme-Samsung_SSD_970_EVO_Plus_500GB_S58SNS0R706072M" "64G"
    // {
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
              }
              // zfsProps "zroot" "local";
            };
            "local/nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options = zfsProps "zroot" "local/nix";
            };
            # Secure Boot keys: outside zrepl's snapshots and replication
            "local/secureboot" = {
              type = "zfs_fs";
              mountpoint = "/var/lib/sbctl";
              options = zfsProps "zroot" "local/secureboot";
            };
            "local/root" = {
              type = "zfs_fs";
              mountpoint = "/";
              options = zfsProps "zroot" "local/root";
            };
            "local/home" = {
              type = "zfs_fs";
              mountpoint = "/home";
              options = zfsProps "zroot" "local/home";
            };
          };
        };
      };
    };
}
