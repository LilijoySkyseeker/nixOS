_: {
  flake.vars = {
    # root access ssh keys
    publicSshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFA+HAQkhmPxKyJFSopziqIVNvFqEaqyRWPVvgu+urfh lilijoy@nixos-thinkpad" # thinkpad
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIPlHQiJlsDCcOWk/EadTOgm8mnkGpsg1y8gzvhUgsg7rAAAABHNzaDo= lilijoy@yubikey" # keychain YubiKey 5C NFC, serial 27674308
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIALu+W5qQ76HBkHDZLAJ9Fd1ECG/v4MAFI9AnSYGu5vsAAAABHNzaDo= lilijoy@yubikey-torrent" # torrent's YubiKey 5C Nano, serial 29680883
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6pG0Y9QdCBRJZKpCD62U3uXl5Lz/bE0ifWLbhZ4q9o lilijoy@torrent" # torrent
    ];
    # public half of homelab's zrepl pull key (private: homelab_zrepl_key
    # sops secret); both source hosts pin it to a forced `zrepl stdinserver`
    zreplPullerKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOoS9ClNSmPtMu4wlvJNDXq8ZD8klgRguXR08RrSe3i/ homelab-zrepl-puller";
    username = "lilijoy";
    # public domain fronted by hosts/vps (minecraft, factorio subdomains,
    # see services/octodns.nix)
    domain = "skyseekerlabs.net.";
    # shared numeric IDs that must stay consistent across files
    # (services/jellyfin.nix, modules/nixos/nfs-homelab-mounts.nix, profiles/PC.nix)
    gids = {
      multimedia = 999;
      flatpak = 998;
    };
    # the PCs' tailnet IPv4 addresses, assigned by tailscale and changed by
    # a re-registration (services/nfs.nix exports only to these)
    tailnetIPv4 = {
      torrent = "100.110.203.119";
      thinkpad = "100.95.127.26";
    };
    # impermanence persistence root shared by profiles/default.nix and the
    # homelab services that append their own state dirs to it
    persistRoot = "/nix/state";
    # root's shell state on the servers, under each host's persistence root:
    # history (profile-server's programs.bash.historyFile), atuin, zoxide,
    # direnv's allow list
    rootShellState = [
      ".local/state/bash"
      ".local/share/atuin"
      ".local/share/zoxide"
      ".local/share/direnv"
    ];

    # disko.nix's zpool rootFsOptions, shared by every zpool on every host
    zfsRootFsOptions = {
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

    # reads a dataset's properties from the host's own
    # myZfsDatasetProperties for disko.nix: `(vars.zfsProps config) "<pool>"
    # "<dataset>"`; fails at eval on a host without zfs-dataset-properties
    zfsProps =
      config: pool: dataset:
      config.myZfsDatasetProperties."${pool}/${dataset}" or { };

    # disko.nix's root-SSD layout (ESP + swap + zroot), shared by
    # homelab/torrent/thinkpad. `idx` picks the boot mountpoint (`/boot`
    # for 1, else `/boot-<idx>`) and keeps disko partition labels unique
    mkZfsRootSsd = idx: id: swapSize: {
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
            size = swapSize;
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

    # disko.devices for an encrypted root SSD: ESP, then one LUKS2 container
    # holding LVM with a swap LV (the hibernation image) and zroot. One
    # unlock opens both; myEncryptedRoot and myHibernate match these names
    # (LUKS `crypt`, swap `/dev/mapper/vg-swap`)
    mkEncryptedRootSsd = id: swapSize: {
      disk.root = {
        type = "disk";
        device = "/dev/disk/by-id/${id}";
        content = {
          type = "gpt";
          partitions = {
            esp = {
              # lanzaboote keeps several kernels and initrds here, and Windows'
              # boot files share it on a dual-boot machine
              size = "2G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypt";
                settings.allowDiscards = true;
                content = {
                  type = "lvm_pv";
                  vg = "vg";
                };
              };
            };
          };
        };
      };
      lvm_vg.vg = {
        type = "lvm_vg";
        lvs = {
          swap = {
            size = swapSize;
            content.type = "swap";
          };
          zfs = {
            size = "100%FREE";
            content = {
              type = "zfs";
              pool = "zroot";
            };
          };
        };
      };
    };
  };
}
