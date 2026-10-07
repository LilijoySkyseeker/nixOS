_: {
  flake.vars = {
    # root access ssh keys
    publicSshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFA+HAQkhmPxKyJFSopziqIVNvFqEaqyRWPVvgu+urfh lilijoy@nixos-thinkpad" # thinkpad
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIPlHQiJlsDCcOWk/EadTOgm8mnkGpsg1y8gzvhUgsg7rAAAABHNzaDo= lilijoy@yubikey" # yubikey
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
    # impermanence persistence root shared by profiles/default.nix and the
    # homelab services that append their own state dirs to it
    persistRoot = "/nix/state";

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
  };
}
