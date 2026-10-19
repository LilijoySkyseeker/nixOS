_: {
  flake.modules.nixos."hibernate" =
    {
      config,
      lib,
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
        assertions = [
          {
            assertion = config.boot.initrd.systemd.enable;
            message = "myHibernate needs boot.initrd.systemd.enable: the import ordering below only exists in the systemd initrd";
          }
        ];

        boot.resumeDevice = cfg.resumeDevice;

        # drops the `nohibernate` zfs.nix adds; safe only with the ordering below
        boot.zfs.unsafeAllowHibernation = true;

        # importing a pool before resuming the image corrupts it (openzfs#12842);
        # zfs.nix orders zfs-import-<pool> against nothing resume-related
        boot.initrd.systemd.services = lib.genAttrs (map (pool: "zfs-import-${pool}") initrdPools) (_: {
          after = [ "systemd-hibernate-resume.service" ];
        });
      };
    };
}
