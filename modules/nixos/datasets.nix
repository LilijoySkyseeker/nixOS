# myDatasets: the per-service ZFS dataset registry.
#
# plan: 2026-09-05-adopt-zfs-policy-tiers-and-a-mydatasets-registry.md
# design: docs/adr/0001-zfs-policy-tiers-and-the-mydatasets-registry.md
#
# One entry, keyed by full dataset name, generates every consumer: the
# disko entry, the ZFS properties (via myZfsDatasetProperties, which
# vars.zfsProps already reads for disko's own options), and -- for a
# dataset nothing else already persists -- the environment.persistence
# entry. `tier` has no default: a dataset declared without one is an
# evaluation error, which is the point (ADR-0001, "safe by default,
# twice over").
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

      # com.sun:auto-snapshot follows from the tier alone (ADR-0001's
      # table); every other zfs-dataset-properties key a specific dataset
      # needs stays a plain myZfsDatasetProperties entry outside this
      # registry, same as today.
      tierAutoSnapshot = {
        offsite = "true";
        onsite = "true";
        persist = "false";
        volatile = "false";
      };

      poolOf = name: builtins.head (lib.splitString "/" name);
      relOf = name: lib.concatStringsSep "/" (lib.tail (lib.splitString "/" name));

      # A dataset already mounted under persistRoot (the new, flat
      # `/nix/state/<service>` convention) needs no impermanence
      # indirection -- it is real, non-volatile storage already. Anything
      # else (an existing service's own directory elsewhere, e.g.
      # jellyfin's `/srv/jellyfin/cache`) is bind-mounted from
      # persistRoot+mountpoint by impermanence, same as every other
      # persisted directory.
      diskoMountpoint =
        ds:
        if lib.hasPrefix "${vars.persistRoot}/" ds.mountpoint then
          ds.mountpoint
        else
          "${vars.persistRoot}${ds.mountpoint}";

      needsPersistenceEntry = ds: ds.managePersistence && diskoMountpoint ds != ds.mountpoint;

      datasetSubmodule =
        { config, ... }:
        {
          options = {
            tier = lib.mkOption {
              type = lib.types.enum [
                "offsite"
                "onsite"
                "persist"
                "volatile"
              ];
              description = ''
                Protection tier -- see docs/adr/0001-zfs-policy-tiers-and-the-mydatasets-registry.md.
                No default on purpose: an eval-time error is safer than a
                dataset silently getting a policy nobody chose.
              '';
            };

            mountpoint = lib.mkOption {
              type = lib.types.str;
              description = ''
                Absolute path the service actually reads/writes.

                A path under persistRoot (e.g. "/nix/state/loki") is
                mounted there directly -- no impermanence indirection
                needed. Any other path (e.g. "/var/lib/docker") gets the
                dataset mounted at persistRoot+mountpoint instead, exactly
                where impermanence's own bind-mount convention expects to
                find it.
              '';
            };

            owner = lib.mkOption {
              type = lib.types.str;
              default = "root";
              description = "User owning this dataset's generated persistence entry, if any.";
            };

            group = lib.mkOption {
              type = lib.types.str;
              default = config.owner;
              defaultText = lib.literalExpression "config.owner";
              description = "Group owning this dataset's generated persistence entry, if any.";
            };

            managePersistence = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Generate an environment.persistence directory entry for
                this dataset. Turn off when a service module already
                declares its own entry for this exact path -- e.g.
                modules/services/jellyfin.nix's cacheDir -- so the
                registry doesn't add a second, conflicting one. Service
                modules stay tier-unaware either way -- plan:
                2026-09-05-adopt-zfs-policy-tiers-and-a-mydatasets-registry.md#D9;
                this only controls who owns the persistence declaration.
              '';
            };
          };
        };
    in
    {
      options.myDatasets = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule datasetSubmodule);
        default = { };
        example = {
          "zroot/persist/loki" = {
            tier = "persist";
            mountpoint = "/nix/state/loki";
            owner = "loki";
          };
        };
        description = ''
          Per-service ZFS dataset registry -- one entry per dataset,
          keyed by its full name. See docs/adr/0001-zfs-policy-tiers-and-the-mydatasets-registry.md.
        '';
      };

      # plan: 2026-09-05-adopt-zfs-policy-tiers-and-a-mydatasets-registry.md#G4
      # every onsite/offsite myDatasets entry, "<"-suffixed for zrepl
      # recursion -- not wired into myZrepl directly, see
      # 2026-09-05-adopt-zfs-policy-tiers-and-a-mydatasets-registry.md#F2
      options.myDatasetsReplicated = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = map (name: "${name}<") (
          lib.attrNames (lib.filterAttrs (_: ds: ds.tier == "onsite" || ds.tier == "offsite") cfg)
        );
        defaultText = lib.literalExpression ''every "onsite"/"offsite" myDatasets entry, "<"-suffixed for zrepl recursion'';
        description = ''
          Dataset names of every `onsite`/`offsite` myDatasets entry, each
          suffixed with zrepl's recursive "<" marker -- feed this into
          whichever zrepl role (`myZrepl.local.datasets`,
          `myZrepl.serve.datasets`, ...) covers this host's own datasets.
        '';
      };

      # NB: this attrset's top-level shape (disko/myZfsDatasetProperties/
      # environment) must stay static regardless of `cfg` -- only the
      # *values* depend on it, lazily. plan:
      # 2026-09-05-adopt-zfs-policy-tiers-and-a-mydatasets-registry.md#F1
      config = lib.mkIf (cfg != { }) {
        myZfsDatasetProperties = lib.mapAttrs (_: ds: {
          "com.sun:auto-snapshot" = tierAutoSnapshot.${ds.tier};
        }) cfg;

        disko.devices.zpool = lib.foldl' (
          acc: name:
          let
            ds = cfg.${name};
            pool = poolOf name;
            rel = relOf name;
          in
          lib.recursiveUpdate acc {
            ${pool}.datasets.${rel} = {
              type = "zfs_fs";
              mountpoint = diskoMountpoint ds;
              options = vars.zfsProps config pool rel;
            };
          }
        ) { } (lib.attrNames cfg);

        environment.persistence.${vars.persistRoot}.directories = lib.mapAttrsToList (_: ds: {
          directory = ds.mountpoint;
          user = ds.owner;
          inherit (ds) group;
        }) (lib.filterAttrs (_: needsPersistenceEntry) cfg);
      };
    };
}
