_: {
  flake.modules.nixos."hibernate" =
    {
      config,
      lib,
      pkgs,
      utils,
      ...
    }:
    let
      cfg = config.myHibernate;

      # the pools zfs.nix imports in the systemd initrd (its `rootPools`)
      initrdPools = lib.unique (
        map (fs: lib.head (lib.splitString "/" fs.device)) (
          lib.filter (fs: fs.fsType == "zfs" && utils.fsNeededForBoot fs) config.system.build.fileSystems
        )
      );

      # the entry booting the running system, found by its init path: the ID
      # it booted under (@current) can be renamed when a newer generation is
      # installed, and a one-shot naming a missing entry boots the default
      oneshotRunningEntry = pkgs.writeShellApplication {
        name = "hibernate-oneshot-running-entry";
        runtimeInputs = [
          config.systemd.package
          pkgs.coreutils
          pkgs.jq
        ];
        text = ''
          init="init=$(readlink -f /run/booted-system)/init"
          id=$(bootctl list --json=short --no-pager \
            | jq -r --arg init "$init" '.[] | select((.options // "") | split(" ") | index($init)) | .id' \
            | head -n1)
          if [[ -z $id ]]; then
            echo "no boot entry boots the running system; a resume after an update may boot fresh" >&2
            exit 0
          fi
          bootctl set-oneshot "$id"
        '';
      };
    in
    {
      options.myHibernate = {
        enable = lib.mkEnableOption "hibernation on a ZFS root, with the initrd importing the pool only after any resume";

        resumeDevice = lib.mkOption {
          type = lib.types.str;
          example = "/dev/mapper/vg-swap";
          description = ''
            Swap device that holds the hibernation image (`boot.resumeDevice`).
            Must be a stable path the initrd can see, e.g. an LVM volume
            inside the unlocked LUKS container.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        boot.resumeDevice = cfg.resumeDevice;

        # drops the `nohibernate` zfs.nix adds; safe only with the ordering below
        boot.zfs.unsafeAllowHibernation = true;

        # importing a pool before resuming the image corrupts it (openzfs#12842);
        # zfs.nix orders zfs-import-<pool> against nothing resume-related
        boot.initrd.systemd.services = lib.genAttrs (map (pool: "zfs-import-${pool}") initrdPools) (_: {
          after = [ "systemd-hibernate-resume.service" ];
        });

        systemd.services.hibernate-prepare = {
          description = "Commit ZFS writes and boot the running entry once, before hibernating";
          wantedBy = [ "hibernate.target" ];
          before = [ "systemd-hibernate.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = [
              # with sync=disabled the kernel's pre-hibernate sync leaves ZFS's
              # last seconds of writes in RAM, lost if the resume then fails
              "${config.boot.zfs.package}/bin/zpool sync"
              # resume through the boot entry that hibernated: a newer kernel or
              # initrd installed since can move the memory map and refuse the image
              (lib.getExe oneshotRunningEntry)
            ];
          };
        };

        # after a resume (systemd-boot already used it) or a failed hibernate,
        # so a later restart takes the default entry
        systemd.services.hibernate-resumed = {
          description = "Drop the one-time boot entry after hibernating";
          wantedBy = [ "hibernate.target" ];
          after = [ "hibernate.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${config.systemd.package}/bin/bootctl set-oneshot ''";
          };
        };
      };
    };
}
