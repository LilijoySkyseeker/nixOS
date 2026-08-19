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
                # LUKS wraps the zfs partition rather than using ZFS
                # native encryption: systemd-cryptenroll's TPM2 sealing
                # is an upstream-supported NixOS module for LUKS, with
                # no equivalent for native ZFS encryption (see
                # TODO.md's FDE/Secure Boot/TPM2 entry). enrollRecovery
                # has disko auto-generate a second, high-entropy
                # passphrase slot at provision time (printed/QR'd for
                # escrow) alongside whatever passphrase is typed
                # interactively — never a TPM2-only slot, so a TPM
                # failure/board swap always has a manual fallback. The
                # TPM2 slot itself is enrolled post-install via
                # `systemd-cryptenroll`, once Secure Boot (lanzaboote)
                # is confirmed working — not here, disko has no TPM2
                # primitive and sealing before Secure Boot is verified
                # would seal against an untrusted boot chain.
                type = "luks";
                name = "zroot-crypt";
                enrollRecovery = true;
                settings.allowDiscards = true; # SSD
                content = {
                  type = "zfs";
                  pool = "zroot";
                };
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
            "local" = {
              type = "zfs_fs";
              options.mountpoint = "none"; # top dir is options.mountpoint
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
            };
            "local/home" = {
              type = "zfs_fs";
              mountpoint = "/home";
              options."com.sun:auto-snapshot" = "false";
            };
          };
        };
      };
    };
}
