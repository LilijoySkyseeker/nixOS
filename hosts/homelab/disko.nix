{ vars, config, ... }:
{

  disko.devices =
    let
      rootSsd = vars.mkZfsRootSsd;
      zfsProps = vars.zfsProps config;
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
    in
    {
      disk = {
        nvme-a = rootSsd 1 "ata-SAMSUNG_MZNLN256HMHQ-00000_S2SVNX0J403512" "8G";

        hdd-a = dataHdd "ata-HUH721212ALE601_8CH9J1UE";
        hdd-b = dataHdd "ata-HUH721212ALE601_8CJJUE6E";

        hdd-c = backupHdd "ata-HUH721212ALE601_8CK6DXTF";
        hdd-d = backupHdd "ata-HUH721212ALE601_2AHDD1AY";
      };

      zpool = {
        zdata = {
          type = "zpool";
          mode = "mirror";
          rootFsOptions = config.myZfsDatasetProperties."zdata";
          options.ashift = "12"; # IMPORTANT
          datasets = {
            "storage" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none"; # "none" needs option.mountpoint
              }
              // zfsProps "zdata" "storage";
            };
            "storage/storage" = {
              type = "zfs_fs";
              mountpoint = "/storage"; # "<path>" just mountpoint
              # legacy: keeps zfs-mount.service's `zfs mount -a` from racing
              # the fstab-generated storage.mount unit
              options = {
                mountpoint = "legacy";
              }
              // zfsProps "zdata" "storage/storage";
            };
            "storage/storage-bulk" = {
              type = "zfs_fs";
              mountpoint = "/storage-bulk";
              options = {
                mountpoint = "legacy"; # see storage/storage above
              }
              // zfsProps "zdata" "storage/storage-bulk";
            };
          };
        };
        zbackup = {
          type = "zpool";
          mode = "mirror";
          rootFsOptions = config.myZfsDatasetProperties."zbackup";
          options.ashift = "12"; # IMPORTANT
          datasets = {
            # "backup/<host>/..." containers only; zrepl creates the real
            # children on first receive as <root_fs>/<full source path>,
            # e.g. backup/torrent/zroot/local/home
            "backup" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none"; # "none" needs option.mountpoint
              }
              // zfsProps "zbackup" "backup";
            };
            "backup/homelab" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
              }
              // zfsProps "zbackup" "backup/homelab";
            };
            "backup/thinkpad" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
              }
              // zfsProps "zbackup" "backup/thinkpad";
            };
            "backup/torrent" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
              }
              // zfsProps "zbackup" "backup/torrent";
            };
          };
        };
        zroot = {
          type = "zpool";
          mode = "";
          rootFsOptions = config.myZfsDatasetProperties."zroot";
          options.ashift = "12"; # MAKE SURE THIS IS CORRECT WITH DIFFRENT DRIVE
          datasets = {
            "local" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none"; # top dir is options.mountpoint
              }
              // zfsProps "zroot" "local";
            };
            "local/state" = {
              type = "zfs_fs";
              mountpoint = "/nix/state"; # sub dir are just mountpoint
              options = zfsProps "zroot" "local/state";
            };
            "local/nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options = zfsProps "zroot" "local/nix";
            };
            "local/root" = {
              type = "zfs_fs";
              mountpoint = "/";
              postCreateHook = "zfs snapshot zroot/local/root@blank";
              options = zfsProps "zroot" "local/root";
            };
          };
        };
      };
    };
}
