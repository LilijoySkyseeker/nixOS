{
  config,
  lib,
  ...
}:
let
  cfg = config.myZfsImpermanence;
in
{
  options.myZfsImpermanence = {
    enable = lib.mkEnableOption "roll the zfs root dataset back to a blank snapshot on every boot";

    rootDataset = lib.mkOption {
      type = lib.types.str;
      default = "zroot/local/root";
      description = ''
        zfs dataset to roll back. Must have a `@blank` snapshot taken
        immediately after creation, before anything is written to it —
        disko's `postCreateHook` on the dataset does this at install
        time (`zfs snapshot <rootDataset>@blank`), confirmed against
        disko's own create-phase ordering to run entirely before
        nixos-install populates the mounted filesystem.
      '';
    };

    persistPath = lib.mkOption {
      type = lib.types.str;
      default = "/nix/state";
      description = "Mountpoint of the zfs dataset environment.persistence binds into.";
    };

    directories = lib.mkOption {
      type = lib.types.listOf lib.types.anything;
      default = [ ];
      description = "environment.persistence directories list (plain strings or {directory,user,group,mode} attrs).";
    };

    files = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/etc/machine-id"
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
      ];
      description = ''
        environment.persistence files list. Defaults cover the
        machine-id and SSH host key every host needs regardless —
        losing the host key breaks sops' age identity, not just SSH
        (see TODO.md's Phase 3 recovery plan on the sops/age
        chicken-and-egg problem).
      '';
    };
  };

  config = lib.mkMerge [
    # Independent of cfg.enable: services/{minecraft,jellyfin,factorio}.nix
    # already write into environment.persistence.${cfg.persistPath}
    # unconditionally (predates this gate), so persistPath must stay
    # neededForBoot regardless of whether the root-rollback retrofit
    # below has landed on this host.
    { fileSystems.${cfg.persistPath}.neededForBoot = true; }
    (lib.mkIf cfg.enable {
      boot.initrd = {
        systemd = {
          enable = true;
          services.rollback = {
            description = "Rollback root filesystem to a pristine state on boot";
            wantedBy = [ "initrd.target" ];
            # Derived from rootDataset, not hardcoded — a caller with a
            # non-zroot pool would otherwise order against a
            # zfs-import-*.service unit that doesn't exist on their
            # host, silently dropping the ordering guarantee (bug_003).
            after = [ "zfs-import-${builtins.head (lib.splitString "/" cfg.rootDataset)}.service" ];
            before = [ "sysroot.mount" ];
            # config.boot.zfs.package, not pkgs-stable.zfs: on
            # nixpkgs-unstable hosts (thinkpad/torrent), the kernel
            # module comes from the unstable channel, so pinning the
            # userspace zfs binary to stable risks a userspace/kmod
            # IOCTL version mismatch once the two channels' zfs series
            # diverge (bug_002).
            path = [ config.boot.zfs.package ];
            unitConfig.DefaultDependencies = "no";
            serviceConfig.Type = "oneshot";
            script = ''
              zfs rollback -r ${cfg.rootDataset}@blank && echo "  >> >> ROLLBACK COMPLETE << <<"
            '';
          };
        };
      };

      environment.persistence.${cfg.persistPath} = {
        # https://github.com/nix-community/impermanence?tab=readme-ov-file#module-usage
        enable = true;
        hideMounts = true;
        inherit (cfg) directories files;
      };
    })
  ];
}
