{
  # Sources:
  # https://github.com/lovesegfault/nix-config/blob/eebebff8e682ba2deb96320afa35789537a1e58e/hosts/plato/disko.nix#L1
  # https://docs.oracle.com/cd/E19120-01/open.solaris/817-2271/6mhupg6ma/index.html#gcfgr
  # https://jrs-s.net/2018/08/17/zfs-tuning-cheat-sheet/

  # install command
  # disko-install --write-efi-boot-entries --flake 'github:lilijoyskyseeker/nixos#homelab' --disk nvme-a /dev/disk/by-id/ata-SAMSUNG_MZNLN256HMHQ-00000_S2SVNX0J403512 --disk hdd-a /dev/disk/by-id/ata-HUH721212ALE601_8CH9J1UE --disk hdd-b /dev/disk/by-id/ata-HUH721212ALE601_8CJJUE6E --disk hdd-c /dev/disk/by-id/ata-HUH721212ALE601_8CK6DXTF  --disk hdd-d /dev/disk/by-id/ata-HUH721212ALE601_2AHDD1AY && zpool export -af

  disko.devices = let
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
              mountpoint =
                if idx == 1
                then "/boot"
                else "/boot-${builtins.toString idx}";
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
    dataHdd = id: {
      type = "disk";
      device = "/dev/disk/by-id/${id}";
      content = {
        type = "gpt";
        partitions.zfs = {
          size = "100%";
          content = {
            type = "zfs";
            pool = "zdata";
          };
        };
      };
    };
    backupHdd = id: {
      type = "disk";
      device = "/dev/disk/by-id/${id}";
      content = {
        type = "gpt";
        partitions.zfs = {
          size = "100%";
          content = {
            type = "zfs";
            pool = "zbackup";
          };
        };
      };
    };
  in {
    disk = {
      # Root pool disks
      nvme-a = rootSsd 1 "ata-SAMSUNG_MZNLN256HMHQ-00000_S2SVNX0J403512";

      # Data pool disks
      hdd-a = dataHdd "ata-HUH721212ALE601_8CH9J1UE";
      hdd-b = dataHdd "ata-HUH721212ALE601_8CJJUE6E";

      # Backup pool disks
      hdd-c = backupHdd "ata-HUH721212ALE601_8CK6DXTF";
      hdd-d = backupHdd "ata-HUH721212ALE601_2AHDD1AY";
    };

    zpool = {
      zdata = {
        type = "zpool";
        mode = "mirror";
        rootFsOptions = {
          acltype = "posixacl";
          xattr = "sa";
          atime = "off";
          compression = "lz4";
          mountpoint = "none";
          canmount = "off";
          devices = "off";
          "com.sun:auto-snapshot" = "false";
        };
        options.ashift = "12"; # IMPORTANT
        datasets = {
          storage = {
            type = "zfs_fs";
            mountpoint = "/storage";
            options."com.sun:auto-snapshot" = "false";
          };
        };
      };
      zbackup = {
        type = "zpool";
        mode = "mirror";
        rootFsOptions = {
          acltype = "posixacl";
          xattr = "sa";
          atime = "off";
          compression = "lz4";
          mountpoint = "none";
          canmount = "off";
          devices = "off";
          "com.sun:auto-snapshot" = "false";
        };
        options.ashift = "12"; # IMPORTANT
        datasets = {
          backup = {
            type = "zfs_fs";
            mountpoint = "/backup";
            options."com.sun:auto-snapshot" = "false";
          };
        };
      };
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
            type = "zfs_fs";
            options = {
              mountpoint = "none";
              reservation = "50G";
            };
          };
        };
      };
    };
  };
}
