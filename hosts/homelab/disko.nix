{ vars, config, ... }:
{
  # Sources:
  # https://github.com/lovesegfault/nix-config/blob/eebebff8e682ba2deb96320afa35789537a1e58e/hosts/plato/disko.nix#L1
  # https://docs.oracle.com/cd/E19120-01/open.solaris/817-2271/6mhupg6ma/index.html#gcfgr
  # https://jrs-s.net/2018/08/17/zfs-tuning-cheat-sheet/

  # install command
  # disko-install --write-efi-boot-entries --flake 'github:lilijoyskyseeker/nixos#homelab' --disk nvme-a /dev/disk/by-id/ata-SAMSUNG_MZNLN256HMHQ-00000_S2SVNX0J403512 --disk hdd-a /dev/disk/by-id/ata-HUH721212ALE601_8CH9J1UE --disk hdd-b /dev/disk/by-id/ata-HUH721212ALE601_8CJJUE6E --disk hdd-c /dev/disk/by-id/ata-HUH721212ALE601_8CK6DXTF  --disk hdd-d /dev/disk/by-id/ata-HUH721212ALE601_2AHDD1AY && zpool export -af
  # get hardware config command
  # nixos-generate-config --dir <dir> --no-filesystems

  disko.devices =
    let
      rootSsd = vars.mkZfsRootSsd;
      zfsProps = vars.zfsProps config; # see vars.nix
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
        # Root pool disks
        nvme-a = rootSsd 1 "ata-SAMSUNG_MZNLN256HMHQ-00000_S2SVNX0J403512" "8G";

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
          rootFsOptions = config.myZfsDatasetProperties."zdata";
          options.ashift = "12"; # IMPORTANT
          datasets = {
            "storage" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none"; # "none" needs option.mountpoint
                "com.sun:auto-snapshot" = "false";
              }
              // zfsProps "zdata" "storage";
            };
            "storage/storage" = {
              type = "zfs_fs";
              mountpoint = "/storage"; # "<path>" just mountpoint
              # legacy: prevents zfs-mount.service's `zfs mount -a` from also
              # trying to mount this dataset at boot, racing against the
              # fstab-generated storage.mount unit (disko's documented
              # zfs-over-legacy pattern, see example/zfs.nix upstream).
              options = {
                mountpoint = "legacy";
                "com.sun:auto-snapshot" = "false";
              }
              // zfsProps "zdata" "storage/storage";
            };
            "storage/storage-bulk" = {
              type = "zfs_fs";
              mountpoint = "/storage-bulk";
              options = {
                mountpoint = "legacy"; # see storage/storage above
                "com.sun:auto-snapshot" = "false";
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
            # "backup/<host>/..." tree — one convention for everything (no
            # more backup vs backup-bulk split: restic's offsite job never
            # reads from zbackup at all regardless, so that split wasn't
            # doing anything functionally). All pure containers; real data
            # lives in the children underneath, created by zrepl on first
            # receive and so not declared here.
            #
            # Note zrepl receives into <root_fs>/<full source dataset
            # path>, so the real children are deeper than the old syncoid
            # names: e.g. backup/torrent/zroot/local/home, not
            # backup/torrent/home.
            "backup" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none"; # "none" needs option.mountpoint
                "com.sun:auto-snapshot" = "false";
              }
              // zfsProps "zbackup" "backup";
            };
            "backup/homelab" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                "com.sun:auto-snapshot" = "false";
              }
              // zfsProps "zbackup" "backup/homelab";
            };
            "backup/thinkpad" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                "com.sun:auto-snapshot" = "false";
              }
              // zfsProps "zbackup" "backup/thinkpad";
            };
            "backup/torrent" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                "com.sun:auto-snapshot" = "false";
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
