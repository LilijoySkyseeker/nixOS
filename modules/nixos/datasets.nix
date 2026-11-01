# myDatasets: the per-service ZFS dataset registry.
#
# one entry, keyed by full dataset name, generates the disko entry
_: {
  flake.modules.nixos."datasets" =
    {
      config,
      lib,
      vars,
      ...
    }:
    let
      cfg = config.myDatasets;

      poolOf = name: builtins.head (lib.splitString "/" name);
      relOf = name: lib.concatStringsSep "/" (lib.tail (lib.splitString "/" name));

      # a mountpoint under persistRoot is mounted directly; anything else is
      # mounted at persistRoot+mountpoint for impermanence to bind-mount
      diskoMountpoint =
        ds:
        if lib.hasPrefix "${vars.persistRoot}/" ds.mountpoint then
          ds.mountpoint
        else
          "${vars.persistRoot}${ds.mountpoint}";
    in
    {
      options.myDatasets = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.mountpoint = lib.mkOption {
              type = lib.types.str;
              description = ''
                Absolute path the service actually reads/writes.

                A path under persistRoot (e.g. "/nix/state/myservice") is
                mounted there directly -- no impermanence indirection
                needed. Any other path (e.g. "/var/lib/docker") gets the
                dataset mounted at persistRoot+mountpoint instead, exactly
                where impermanence's own bind-mount convention expects to
                find it.
              '';
            };
          }
        );
        default = { };
        description = ''
          Per-service ZFS dataset registry -- one entry per dataset,
          keyed by its full name.
        '';
      };

      # NB: this attrset's top-level shape (disko) must stay static
      # regardless of `cfg` -- only the *values* depend on it, lazily, or
      # evaluation hits infinite recursion
      config = lib.mkIf (cfg != { }) {
        disko.devices.zpool = lib.foldl' (
          acc: name:
          lib.recursiveUpdate acc {
            ${poolOf name}.datasets.${relOf name} = {
              type = "zfs_fs";
              mountpoint = diskoMountpoint cfg.${name};
            };
          }
        ) { } (lib.attrNames cfg);
      };
    };
}
