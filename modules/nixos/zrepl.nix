_: {
  # pull, not push: a push client can DestroySnapshots on its own backup
  # subtree, so a compromised source could wipe its history
  flake.modules.nixos."zrepl" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.myZrepl;

      yamlFormat = pkgs.formats.yaml { };

      # zrepl's 10s default dial_timeout fails a whole job interval on a few
      # seconds of path renegotiation (e.g. tailscale endpoint flapping)
      remoteDialTimeout = "60s";

      mkFilesystems = datasets: lib.genAttrs datasets (_: true);

      mkSnapshotting = {
        type = "periodic";
        inherit (cfg.snapshot) interval;
        prefix = "zrepl_";
      };

      # the prefix regex does NOT spare foreign snapshots: keep_grid condemns
      # every non-match, it only stops them occupying grid slots
      gridRule = grid: {
        type = "grid";
        inherit grid;
        regex = "^zrepl_";
      };

      # never prune a snapshot the receiver hasn't got, or a slow/offline
      # target loses its incremental base
      notReplicatedRule = {
        type = "not_replicated";
      };

      mkPruning = keepSender: keepReceiver: {
        keep_sender = keepSender;
        keep_receiver = keepReceiver;
      };

      sourcePruning =
        mkPruning
          [
            notReplicatedRule
            (gridRule "1x1h(keep=all) | 48x1h | 7x1d")
          ]
          [ (gridRule "1x15m(keep=all) | 168x1h | 30x1d | 12x30d") ];

      # placeholder.encryption is required: zrepl's "unspecified" default
      # fails every receive that creates a placeholder, and configcheck
      # doesn't catch it
      # security: the source controls the send stream, so pin props
      # a hostile stream could set (e.g. mountpoint=/etc, canmount=on, shares);
      # -o and -x are exclusive per property, so each is in one list only
      mkRecv = {
        placeholder.encryption = "off";
        properties = {
          override = {
            mountpoint = "none";
            canmount = "off";
          };
          # quoted: `inherit` is a nix keyword
          "inherit" = [
            "sharenfs"
            "sharesmb"
            "exec"
            "setuid"
            "devices"
          ];
        };
      };

      ownedDatasets = lib.unique (cfg.serve.datasets ++ cfg.local.datasets);

      # local snapshotting and a prune ceiling, beholden to no peer (under
      # pull a source with its puller down never prunes); keep the ceiling
      # slacker than the source retention: snap jobs ignore not_replicated
      snapJob = lib.optional (ownedDatasets != [ ]) {
        type = "snap";
        name = "snapshots";
        filesystems = mkFilesystems ownedDatasets;
        snapshotting = mkSnapshotting;
        pruning.keep = [ (gridRule "1x1h(keep=all) | 48x1h | 30x1d") ];
      };

      serveJob = lib.optional cfg.serve.enable {
        type = "source";
        name = "serve";
        serve = {
          type = "stdinserver";
          client_identities = lib.attrNames cfg.serve.clients;
        };
        filesystems = mkFilesystems cfg.serve.datasets;
        snapshotting.type = "manual";
      };

      pullJobs = lib.mapAttrsToList (name: r: {
        type = "pull";
        inherit name;
        connect = {
          type = "ssh+stdinserver";
          inherit (r) host;
          user = "root";
          port = 22;
          identity_file = toString r.identityFile;
          dial_timeout = remoteDialTimeout;
        };
        root_fs = r.rootFs;
        interval = "15m";
        recv = mkRecv;
        pruning = sourcePruning;
      }) cfg.pull.remotes;

      # source+pull, not push+sink, so replication has its own interval
      localJobs = lib.optionals cfg.local.enable [
        {
          type = "source";
          name = "local-source";
          serve = {
            type = "local";
            listener_name = "localsink";
          };
          filesystems = mkFilesystems cfg.local.datasets;
          snapshotting.type = "manual";
        }
        {
          type = "pull";
          name = "local-pull";
          connect = {
            type = "local";
            listener_name = "localsink";
            client_identity = cfg.local.clientIdentity;
            dial_timeout = "10s";
          };
          # pull jobs don't append the client identity, so add it here
          root_fs = "${cfg.local.rootFs}/${cfg.local.clientIdentity}";
          interval = "15m";
          recv = mkRecv;
          pruning = sourcePruning;
        }
      ];

      settings = {
        global.logging = [
          {
            type = "syslog";
            level = "warn";
            format = "human";
          }
        ];
        jobs = snapJob ++ serveJob ++ pullJobs ++ localJobs;
      };

      configFile = yamlFormat.generate "zrepl.yml" settings;

      # zrepl parses strictly: a bad key fails startup; catch it at build time
      configCheck =
        pkgs.runCommand "zrepl-config-check-${config.networking.hostName}"
          { nativeBuildInputs = [ config.services.zrepl.package ]; }
          ''
            zrepl --config ${configFile} configcheck
            touch $out
          '';
    in
    {
      options.myZrepl = {
        enable = lib.mkEnableOption "zrepl-managed ZFS snapshotting and replication";

        snapshot.interval = lib.mkOption {
          type = lib.types.str;
          default = "5m";
          description = "How often the snap job takes a snapshot.";
        };

        serve = {
          enable = lib.mkEnableOption "passive source role: snapshot locally and serve those snapshots to a puller";

          datasets = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [
              "zroot/local/home"
              "zroot/local/root"
            ];
            description = "Datasets to snapshot and offer to pullers. Append \"<\" to include children.";
          };

          clients = lib.mkOption {
            default = { };
            description = ''
              Pullers allowed to connect, keyed by zrepl client identity.

              This renders both halves of the wiring from one declaration:
              the job's client_identities list, and a forced-command entry
              in root's authorized_keys pinning that key to
              `zrepl stdinserver <identity>`.
            '';
            type = lib.types.attrsOf (
              lib.types.submodule {
                options.publicKey = lib.mkOption {
                  type = lib.types.str;
                  description = "Puller's SSH public key.";
                };
              }
            );
          };
        };

        pull = {
          remotes = lib.mkOption {
            default = { };
            description = ''
              Remotes to pull from, keyed by job name. Each remote gets its
              own job and its own root_fs, because pull jobs -- unlike sink
              jobs -- do not append a client identity to root_fs.
            '';
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  host = lib.mkOption {
                    type = lib.types.str;
                    description = "Peer hostname.";
                  };
                  identityFile = lib.mkOption {
                    type = lib.types.path;
                    description = "SSH private key used to dial the peer, e.g. a sops secret path.";
                  };
                  rootFs = lib.mkOption {
                    type = lib.types.str;
                    example = "zbackup/backup/torrent";
                    description = ''
                      Dataset received filesystems land under. zrepl extends
                      this with the *full* source dataset path, so
                      zroot/local/home from a remote rooted here becomes
                      zbackup/backup/torrent/zroot/local/home.
                    '';
                  };
                };
              }
            );
          };
        };

        local = {
          enable = lib.mkEnableOption "same-host replication via zrepl's local transport (no ssh/tcp)";

          datasets = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Datasets to snapshot and replicate within this host.";
          };

          rootFs = lib.mkOption {
            type = lib.types.str;
            default = "";
            example = "zbackup/backup";
            description = "Dataset the local copies land under, before the clientIdentity component.";
          };

          clientIdentity = lib.mkOption {
            type = lib.types.str;
            default = config.networking.hostName;
            defaultText = lib.literalExpression "config.networking.hostName";
            description = "Path component appended to rootFs for this host's own copies.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        services.zrepl = {
          enable = true;
          inherit settings;
        };

        # upstream Requires=local-fs.target: one transient mount failure at
        # boot leaves zrepl dead with no retry (silent backup outage); keep
        # the ordering, a not-yet-mounted dataset just fails one job cycle
        systemd.services.zrepl = {
          requires = lib.mkForce [ ];
          wants = [ "local-fs.target" ];
          after = [ "local-fs.target" ];
        };

        # forced-command keys: each key only proxies to its own identity, no
        # shell, no claiming another host
        users.users.root.openssh.authorizedKeys.keys = lib.optionals cfg.serve.enable (
          lib.mapAttrsToList (
            identity: c:
            "command=\"${config.services.zrepl.package}/bin/zrepl --config /etc/zrepl/zrepl.yml stdinserver ${identity}\",restrict ${c.publicKey}"
          ) cfg.serve.clients
        );

        system.extraDependencies = [ configCheck ];
      };
    };
}
