# Stage-2 (post-initrd) unlock for non-root LUKS containers, via a
# plain /etc/crypttab keyfile entry — the counterpart to
# disko-luks-zfs.nix's `initrdUnlock = false`. Never generates or
# stores key material itself (per this repo's manual-secrets
# convention): each keyfile at /etc/cryptsetup-keys.d/<name>.key must
# be created and enrolled manually (`dd` + `cryptsetup luksAddKey`)
# during the host's reinstall, then persisted like any other
# environment.persistence file — this module only wires the crypttab
# entry and the zfs-import ordering that depends on it.
{ config, lib, ... }:
let
  cfg = config.myLuksStage2Unlock;
in
{
  options.myLuksStage2Unlock = {
    enable = lib.mkEnableOption "stage-2 unlock of non-root LUKS containers via crypttab keyfiles";

    containers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "LUKS container name — must match the `name` passed to disko-luks-zfs.nix's luksZfs.";
            };
            device = lib.mkOption {
              type = lib.types.str;
              description = "Block device to unlock, e.g. /dev/disk/by-partlabel/disk-hdd-a-zfs (disko's default GPT partlabel: disk-<diskName>-<partitionName>).";
            };
          };
        }
      );
      default = [ ];
      description = "Non-root LUKS containers to unlock at stage 2 instead of initrd.";
    };

    zpools = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "zpool names (not unit names — NixOS's systemd.services appends `.service` to the attr key) whose zfs-import-<pool>.service must wait for these containers to unlock.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.containers != [ ]) {
    environment.etc.crypttab.text = lib.concatMapStrings (
      c: "${c.name} ${c.device} /etc/cryptsetup-keys.d/${c.name}.key luks\n"
    ) cfg.containers;

    systemd.services = lib.genAttrs (map (pool: "zfs-import-${pool}") cfg.zpools) (_: {
      after = map (c: "systemd-cryptsetup@${c.name}.service") cfg.containers;
      requires = map (c: "systemd-cryptsetup@${c.name}.service") cfg.containers;
    });
  };
}
