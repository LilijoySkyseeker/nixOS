{
  # Sources:
  # https://github.com/lovesegfault/nix-config/blob/eebebff8e682ba2deb96320afa35789537a1e58e/hosts/plato/disko.nix#L1
  # https://docs.oracle.com/cd/E19120-01/open.solaris/817-2271/6mhupg6ma/index.html#gcfgr
  # https://jrs-s.net/2018/08/17/zfs-tuning-cheat-sheet/

  # install command
  # disko-install --write-efi-boot-entries --flake 'github:lilijoyskyseeker/nixos#homelab' --disk nvme-a /dev/disk/by-id/ata-SAMSUNG_MZNLN256HMHQ-00000_S2SVNX0J403512 --disk hdd-a /dev/disk/by-id/ata-HUH721212ALE601_8CH9J1UE --disk hdd-b /dev/disk/by-id/ata-HUH721212ALE601_8CJJUE6E --disk hdd-c /dev/disk/by-id/ata-HUH721212ALE601_8CK6DXTF  --disk hdd-d /dev/disk/by-id/ata-HUH721212ALE601_2AHDD1AY && zpool export -af
  #
  # NOTE (post-FDE): each disk's `luks` content block below has no
  # passwordFile/keyFile set, so `askPassword` defaults true — this
  # command will now interactively prompt for a passphrase per LUKS
  # container (5 disks = 5 prompts; same passphrase each time is fine,
  # they're independent LUKS headers) and print/pause for a QR-coded
  # recovery passphrase per container via `enrollRecovery`. See
  # hosts/homelab/RECOVERY.md for what to do with those recovery
  # passphrases (escrow, not discard) and the post-install TPM2
  # enrollment step this command does NOT do.
  # get hardware config command
  # nixos-generate-config --dir <dir> --no-filesystems

  disko.devices =
    let
      luksZfs = import ../../modules/nixos/disko-luks-zfs.nix;
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
              size = "8G";
              content = {
                type = "swap";
              };
            };
            zfs = {
              size = "100%";
              content = luksZfs {
                name = "zroot-crypt";
                pool = "zroot";
                extraSettings.allowDiscards = true; # SSD
              };
            };
          };
        };
      };
      # zdata/zbackup (bulk storage + local backup mirror, both on spinning
      # HDDs) get the same LUKS treatment as zroot — per-user decision, the
      # theft threat model covers bulk storage the same as the OS disk, not
      # just zroot. `name` must be unique per disk (each HDD is its own LUKS
      # container, mirrored at the zpool layer above LUKS, same as the
      # unencrypted layout was mirrored above the raw partitions).
      dataHdd = name: id: {
        type = "disk";
        device = "/dev/disk/by-id/${id}";
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "100%";
            content = luksZfs {
              inherit name;
              pool = "zdata";
            };
          };
        };
      };
      backupHdd = name: id: {
        type = "disk";
        device = "/dev/disk/by-id/${id}";
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "100%";
            content = luksZfs {
              inherit name;
              pool = "zbackup";
            };
          };
        };
      };
    in
    {
      disk = {
        # Root pool disks
        nvme-a = rootSsd 1 "ata-SAMSUNG_MZNLN256HMHQ-00000_S2SVNX0J403512";

        # Data pool disks
        hdd-a = dataHdd "zdata-a-crypt" "ata-HUH721212ALE601_8CH9J1UE";
        hdd-b = dataHdd "zdata-b-crypt" "ata-HUH721212ALE601_8CJJUE6E";

        # Backup pool disks
        hdd-c = backupHdd "zbackup-c-crypt" "ata-HUH721212ALE601_8CK6DXTF";
        hdd-d = backupHdd "zbackup-d-crypt" "ata-HUH721212ALE601_2AHDD1AY";
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
            sync = "disabled";
            "com.sun:auto-snapshot" = "false";
          };
          options.ashift = "12"; # IMPORTANT
          datasets = {
            "storage" = {
              type = "zfs_fs";
              options.mountpoint = "none"; # "none" needs option.mountpoint
              options."com.sun:auto-snapshot" = "false";
            };
            "storage/storage" = {
              type = "zfs_fs";
              mountpoint = "/storage"; # "<path>" just mountpoint
              options."com.sun:auto-snapshot" = "false";
            };
            "storage/storage-bulk" = {
              type = "zfs_fs";
              mountpoint = "/storage-bulk";
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
            sync = "disabled";
            "com.sun:auto-snapshot" = "false";
          };
          options.ashift = "12"; # IMPORTANT
          datasets = {
            "backup" = {
              type = "zfs_fs";
              options.mountpoint = "none"; # "none" needs option.mountpoint
              options."com.sun:auto-snapshot" = "false";
            };
            "backup-bulk" = {
              type = "zfs_fs";
              options.mountpoint = "none";
              options."com.sun:auto-snapshot" = "false";
            };
            # homelab
            "backup/homelab" = {
              type = "zfs_fs";
              options.mountpoint = "none";
              options."com.sun:auto-snapshot" = "false";
            };
            "backup-bulk/homelab" = {
              type = "zfs_fs";
              options.mountpoint = "none";
              options."com.sun:auto-snapshot" = "false";
            };
            # thinkpad
            "backup/thinkpad" = {
              type = "zfs_fs";
              mountpoint = "/backup/thinkpad"; # "<path>" just mountpoint
              options."com.sun:auto-snapshot" = "false";
            };
            "backup-bulk/thinkpad" = {
              type = "zfs_fs";
              mountpoint = "/backup/thinkpad/bulk";
              options."com.sun:auto-snapshot" = "false";
            };
            # legion
            "backup/legion" = {
              type = "zfs_fs";
              mountpoint = "/backup/legion";
              options."com.sun:auto-snapshot" = "false";
            };
            "backup-bulk/legion" = {
              type = "zfs_fs";
              mountpoint = "/backup/legion/bulk";
              options."com.sun:auto-snapshot" = "false";
            };
            # other
            "backup/other" = {
              type = "zfs_fs";
              mountpoint = "/backup/other";
              options."com.sun:auto-snapshot" = "false";
            };
            "backup-bulk/other" = {
              type = "zfs_fs";
              mountpoint = "/backup/other/bulk";
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
            sync = "disabled";
            "com.sun:auto-snapshot" = "false";
          };
          options.ashift = "12"; # MAKE SURE THIS IS CORRECT WITH DIFFRENT DRIVE
          datasets = {
            "local" = {
              type = "zfs_fs";
              options.mountpoint = "none"; # top dir is options.mountpoint
            };
            "local/state" = {
              type = "zfs_fs";
              mountpoint = "/nix/state"; # sub dir are just mountpoint
            };
            "local/nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
            };
            "local/root" = {
              type = "zfs_fs";
              mountpoint = "/";
              postCreateHook = "zfs snapshot zroot/local/root@blank";
            };
          };
        };
      };
    };
}
