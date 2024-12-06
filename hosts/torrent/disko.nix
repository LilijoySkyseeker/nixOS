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
        nvme-a = rootSsd 1 "nvme-Samsung_SSD_990_PRO_4TB_S7KGNU0XA02842B";
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
            "root" = {
              type = "zfs_fs";
              mountpoint = "/";
              options."com.sun:auto-snapshot" = "false";
            };
            "home" = {
              type = "zfs_fs";
              mountpoint = "/home";
              options."com.sun:auto-snapshot" = "false";
            };
          };
        };
      };
    };
}
