{
  # ssd has /boot 8G of swap, and then the rest is a zfs partition
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
    # there are 3 datasets, /root, /nix, /state. /root gets a blank partiton
    zpool = {
      zroot = {
        type = "zpool";
        mode = "mirror";
        rootFsOptions = {
          # https://docs.oracle.com/cd/E19120-01/open.solaris/817-2271/6mhupg6ma/index.html#gcfgr
          # https://jrs-s.net/2018/08/17/zfs-tuning-cheat-sheet/
          acltype = "posixacl";
          xattr = "sa";
          atime = "off";
          mountpoint = "none";
          canmount = "off";
          compression = "lz4";
          devices = "off";
          "com.sun:auto-snapshot" = "false";
        };
        options.ashift = "9"; # MAKE SURE THIS IS CORRECT WITH DIFFRENT DRIVE

        datasets = {
          "local" = {
            type = "zfs_fs";
            options.mountpoint = "none";
            options."com.sun:auto-snapshot" = "false";
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
          "reserved" = {
            options = {
              mountpoint = "none";
              reservation = "50G";
            };
            type = "zfs_fs";
          };
        };
      };
    };
  };
}