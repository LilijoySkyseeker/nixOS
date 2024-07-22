{
  fileSystems."/nix/state".neededForBoot = true;
  fileSystems."/nix".neededForBoot = true;

  disko.devices = {
    disk = {
      boot-ssd = {
        type = "disk";
        device = "/dev/disk/by-id/ata-SAMSUNG_MZNLN256HMHQ-00000_S2SVNX0J403512";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            swap = {
              size = "8G";
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
    };
    zpool = {
      zroot = {
        tpe = "zpool";
        mode = "mirror";
        rootFsOptions = {
          acltype = "posixacl";
          xattr = "sa";
          atime = "off";
          mountpoint = "none";
          compression = "lz4";
          "com.sun:auto-snapshot" = "false";
        };
        options.ashift = "9";

        datasets = {
          "local" = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };
          "local/state" = {
            type = "zfs_fs";
            mountpoint = "/nix/state";
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
            postCreateHook = "zfs snapshot zroot/local/root@blank";
          };
        };
      };
    };
  };
}
