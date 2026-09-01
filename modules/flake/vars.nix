{ ... }:
{
  flake.vars = {
    # root access ssh keys
    publicSshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFA+HAQkhmPxKyJFSopziqIVNvFqEaqyRWPVvgu+urfh lilijoy@nixos-thinkpad" # thinkpad
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIPlHQiJlsDCcOWk/EadTOgm8mnkGpsg1y8gzvhUgsg7rAAAABHNzaDo= lilijoy@yubikey" # yubikey
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6pG0Y9QdCBRJZKpCD62U3uXl5Lz/bE0ifWLbhZ4q9o lilijoy@torrent" # torrent
    ];
    # Public half of homelab's zrepl pull key (private half is the
    # homelab_zrepl_key sops secret). Both source hosts pin this same key
    # to a forced `zrepl stdinserver` command in root's authorized_keys, so
    # it lives here rather than being repeated per host.
    zreplPullerKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOoS9ClNSmPtMu4wlvJNDXq8ZD8klgRguXR08RrSe3i/ homelab-zrepl-puller";
    username = "lilijoy";
    # public domain fronted by hosts/vps (jellyfin, minecraft, factorio
    # subdomains — see services/octodns.nix and hosts/vps/configuration.nix)
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

    # disko.nix's zpool rootFsOptions -- byte-identical across every zpool
    # on every host (torrent's zroot, thinkpad's zroot, homelab's
    # zroot/zdata/zbackup) before this was consolidated. One copy here
    # instead of five, so a change doesn't have to be made five times and
    # can't quietly drift between them.
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

    # Shared lookup for a ZFS host's disko.nix: reads a dataset's properties
    # from that host's own myZfsDatasetProperties instead of a second
    # hand-written literal. Call as `(vars.zfsProps config) "<pool>"
    # "<dataset>"`; fails loudly at eval time on a host that doesn't import
    # zfs-dataset-properties (deliberate coupling). plan:
    # 2026-09-01-unify-myzfsdatasetproperties-and-disko-so-one-declaration-covers-both.md#G3
    zfsProps =
      config: pool: dataset:
      config.myZfsDatasetProperties."${pool}/${dataset}" or { };

    # disko.nix's root-SSD disk layout (ESP + swap + a zroot-pool
    # partition) -- identical shape on homelab/torrent/thinkpad, differing
    # only in swap size. `idx` picks the boot mountpoint (`/boot` for 1,
    # `/boot-<idx>` otherwise, for hosts with more than one ESP) and feeds
    # disko's partition-label uniqueness requirement.
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
