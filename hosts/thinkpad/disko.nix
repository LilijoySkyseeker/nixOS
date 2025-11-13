{
  # disko
  disko.devices =
    let
      rootSsd = idx: id: {
        type = "disk";
        device = "/dev/disk/by-id/${id}";
        content = {
          type = "gpt";
          partitions = {
            esp = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = if idx == 1 then "/boot" else "/boot-${builtins.toString idx}";
              };
            };
            swap = {
              size = "16G";
              content = {
                type = "swap";
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
    in
    {
      disk = {
        # Root pool disks
        nvme-a = rootSsd 1 "nvme-Samsung_SSD_970_EVO_Plus_500GB_S58SNS0R706072M";
      };
      zpool = {
        zroot = {
          type = "zpool";
          mode = "";
          rootFsOptions = {
            acltype = "posixacl";
            xattr = "sa";
            atime = "off";
            mountpoint = "none";
            canmount = "off";
            compression = "lz4";
            devices = "off";
            sync = "disabled";
            "com.sun:auto-snapshot" = "false";
          };
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
