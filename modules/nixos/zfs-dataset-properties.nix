_: {
  flake.modules.nixos."zfs-dataset-properties" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.myZfsDatasetProperties;
    in
    {
      options.myZfsDatasetProperties = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
        default = { };
        example = {
          "zroot/local/state" = {
            snapdir = "disabled";
          };
        };
        description = ''
          Per-dataset ZFS properties, reapplied declaratively on every
          boot/switch rather than set once by hand or left to `disko.nix`
          (which only runs at install time, so a property added later
          never reaches an already-installed host without this).

          `zfs set` is idempotent, so reapplying every activation is
          always safe. Note some properties only take full effect, for
          state that predates the change, on that dataset's *next*
          unmount/mount or the host's next reboot -- verified true of
          `snapdir` specifically; do not assume it is true of every
          property without checking.
        '';
      };

      config = lib.mkIf (cfg != { }) {
        systemd.services.zfs-dataset-properties = {
          description = "Apply declarative ZFS dataset properties (myZfsDatasetProperties)";
          after = [ "zfs-mount.service" ];
          wantedBy = [ "zfs-mount.service" ];
          path = [ pkgs.zfs ];
          serviceConfig.Type = "oneshot";
          script = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              dataset: props:
              lib.concatStringsSep "\n" (
                lib.mapAttrsToList (
                  prop: value: "zfs set ${lib.escapeShellArg "${prop}=${value}"} ${lib.escapeShellArg dataset}"
                ) props
              )
            ) cfg
          );
        };
      };
    };
}
