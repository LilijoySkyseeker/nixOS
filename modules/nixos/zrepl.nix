{ ... }:
{
  # Single shared zrepl module covering every role this repo needs:
  # snapshotting, local replication, and both ends of remote replication.
  # zrepl is one daemon per host driven by one YAML file, so unlike the
  # sanoid+syncoid pair it replaces there is no separate "snapshot tool"
  # and "replication tool" to keep in sync -- retention lives in the same
  # job that does the sending.
  #
  # Topology: pull is the default and push is opt-in per host. In a pull
  # setup the backup server dials out and the source hosts are passive,
  # which means a compromised source host has no RPC handle on the backup
  # server at all. That matters because zrepl's receiving endpoint
  # exposes DestroySnapshots (internal/endpoint/endpoint.go:1058), bounded
  # only to the client's own subtree -- so in a *push* setup a compromised
  # source can delete its own backup history. Pull removes that entirely:
  # the puller owns retention (keep_sender prunes the source), and the
  # source can only answer questions it is asked.
  #
  # Use push only where pull genuinely loses coverage -- e.g. a laptop
  # that is online in short unpredictable windows the puller may miss.
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

      # zrepl names the two ends of one transport asymmetrically: the
      # dialing side is connect.type = "ssh+stdinserver" while the
      # listening side is serve.type = "stdinserver" (verified against
      # v0.7.0 internal/config/config.go's ConnectEnum/ServeEnum
      # unmarshallers). Callers name a transport once, using the
      # connect-side spelling, and these renderers absorb the split.
      mkConnect =
        t:
        {
          "ssh+stdinserver" = {
            type = "ssh+stdinserver";
            inherit (t) host user port;
            identity_file = toString t.identityFile;
          }
          // lib.optionalAttrs (t.sshOptions != [ ]) { options = t.sshOptions; };
          "tcp" = {
            type = "tcp";
            inherit (t) address;
          };
          "tls" = {
            type = "tls";
            inherit (t) address;
            ca = toString t.ca;
            cert = toString t.cert;
            key = toString t.key;
            server_cn = t.serverCn;
          };
          "local" = {
            type = "local";
            listener_name = t.listenerName;
            client_identity = t.clientIdentity;
          };
        }
        .${t.type};

      mkServe =
        s:
        {
          "ssh+stdinserver" = {
            type = "stdinserver";
            client_identities = lib.attrNames s.clients;
          };
          "tcp" = {
            type = "tcp";
            inherit (s) listen;
            clients = lib.mapAttrs (_: c: c.address) s.clients;
          };
          "tls" = {
            type = "tls";
            inherit (s) listen;
            ca = toString s.ca;
            cert = toString s.cert;
            key = toString s.key;
            client_cns = lib.attrNames s.clients;
          };
          "local" = {
            type = "local";
            listener_name = s.listenerName;
          };
        }
        .${s.type};

      # zrepl's filesystem filter is a pattern -> bool map. A trailing "<"
      # on a pattern means "this dataset and its children", so callers can
      # express recursion in the dataset string itself.
      mkFilesystems = datasets: lib.genAttrs datasets (_: true);

      mkSnapshotting = {
        type = "periodic";
        inherit (cfg.snapshot) interval prefix;
      };

      # Grid rules are regex-scoped to zrepl's own snapshot prefix.
      #
      # Careful with what that scoping means: it does NOT spare
      # non-matching snapshots. KeepGrid puts every snapshot that fails
      # the regex straight onto its destroy list
      # (internal/pruning/keep_grid.go), and PruneSnapshots destroys a
      # snapshot once *every* rule lists it
      # (internal/pruning/pruning.go:39). So a lone grid rule condemns
      # foreign snapshots rather than ignoring them. The regex only stops
      # foreign snapshots from being counted as grid occupants and
      # displacing zrepl's own. See legacyRule for the actual guard.
      gridRule = grid: {
        type = "grid";
        inherit grid;
        regex = "^${cfg.snapshot.prefix}";
      };

      # Never prune a snapshot the receiver hasn't got yet. Without this a
      # slow or long-offline replication target can have its incremental
      # base pruned out from under it -- the exact failure that stranded
      # the syncoid push this module replaces.
      notReplicatedRule = {
        type = "not_replicated";
      };

      # Transition guard for the sanoid -> zrepl cutover.
      #
      # Without this, the first prune after initial replication destroys
      # every pre-existing sanoid snapshot: the replication cursor lands
      # on a fresh zrepl_ snapshot, everything older is then treated as
      # replicated ("all snapshots older than cursor are interpreted as
      # replicated", internal/daemon/pruner/pruner.go:441), so
      # not_replicated condemns them and the grid rule condemns them for
      # failing the prefix regex -- unanimous, therefore destroyed.
      #
      # A keep rule matching the legacy prefix breaks that unanimity and
      # holds them indefinitely. Turn it off (or drop the old snapshots by
      # hand) once zrepl has enough history of its own to stand on.
      legacyRule = {
        type = "regex";
        regex = "^${cfg.legacySnapshotPrefix}";
      };

      keepLegacy = lib.optional (
        cfg.preserveLegacySnapshots && cfg.legacySnapshotPrefix != ""
      ) legacyRule;

      mkPruning = keepSender: keepReceiver: {
        keep_sender = keepSender;
        keep_receiver = keepReceiver;
      };

      # ---- job builders, one per role ------------------------------

      serveJob = lib.optional cfg.serve.enable {
        type = "source";
        name = "serve";
        serve = mkServe cfg.serve;
        filesystems = mkFilesystems cfg.serve.datasets;
        snapshotting = mkSnapshotting;
      };

      pullJobs = lib.mapAttrsToList (name: r: {
        type = "pull";
        inherit name;
        connect = mkConnect r;
        # Pull jobs do NOT append the client identity to root_fs
        # (PullJob.GetAppendClientIdentity() returns false, unlike
        # SinkJob's true), so each remote needs its own explicit root_fs.
        root_fs = r.rootFs;
        interval = r.interval;
        pruning = mkPruning r.keepSender r.keepReceiver;
      }) cfg.pull.remotes;

      pushJobs = lib.mapAttrsToList (name: t: {
        type = "push";
        name = "push-${name}";
        connect = mkConnect t;
        filesystems = mkFilesystems t.datasets;
        snapshotting = mkSnapshotting;
        pruning = mkPruning t.keepSender t.keepReceiver;
      }) cfg.push.targets;

      sinkJob = lib.optional cfg.sink.enable {
        type = "sink";
        name = "sink";
        serve = mkServe cfg.sink;
        root_fs = cfg.sink.rootFs;
      };

      # Same-host replication needs a matching push/sink pair joined by a
      # listener name -- zrepl's "local" transport, no ssh or tcp involved.
      localJobs = lib.optionals cfg.local.enable [
        {
          type = "sink";
          name = "local-sink";
          serve = {
            type = "local";
            listener_name = cfg.local.listenerName;
          };
          root_fs = cfg.local.rootFs;
        }
        {
          type = "push";
          name = "local-push";
          connect = {
            type = "local";
            listener_name = cfg.local.listenerName;
            # sink appends this to root_fs, so it becomes the per-host
            # directory component under cfg.local.rootFs.
            client_identity = cfg.local.clientIdentity;
            dial_timeout = "10s";
          };
          filesystems = mkFilesystems cfg.local.datasets;
          snapshotting = mkSnapshotting;
          pruning = mkPruning cfg.local.keepSender cfg.local.keepReceiver;
        }
      ];

      settings = {
        global.logging = [
          {
            type = "syslog";
            level = cfg.logLevel;
            format = "human";
          }
        ];
        jobs = serveJob ++ pullJobs ++ pushJobs ++ sinkJob ++ localJobs;
      };

      configFile = yamlFormat.generate "zrepl.yml" settings;

      # zrepl parses its config with UnmarshalStrict, so a stray or
      # misspelled key is a hard startup failure rather than a warning.
      # Running configcheck at build time turns that into a build error,
      # which keeps it inside the repo's build-before-commit convention
      # instead of surfacing on the target host at activation.
      configCheck =
        pkgs.runCommand "zrepl-config-check-${config.networking.hostName}"
          { nativeBuildInputs = [ config.services.zrepl.package ]; }
          ''
            zrepl --config ${configFile} configcheck
            touch $out
          '';

      # ---- shared option fragments ---------------------------------

      keepSenderOption =
        default:
        lib.mkOption {
          type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
          inherit default;
          description = "zrepl keep rules applied to the sending side's snapshots.";
        };

      keepReceiverOption =
        default:
        lib.mkOption {
          type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
          inherit default;
          description = "zrepl keep rules applied to the receiving side's snapshots.";
        };

      # Every dialing role shares one transport shape so the transport
      # stays pluggable: swapping ssh+stdinserver for tls is a type change
      # plus the fields that type needs, with no other config churn.
      connectOptions = {
        type = lib.mkOption {
          type = lib.types.enum [
            "ssh+stdinserver"
            "tcp"
            "tls"
            "local"
          ];
          default = cfg.defaultTransport;
          defaultText = lib.literalExpression "config.myZrepl.defaultTransport";
          description = "Transport used to dial the peer.";
        };
        host = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Peer hostname (ssh+stdinserver).";
        };
        user = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = ''
            SSH user on the peer (ssh+stdinserver).

            This is root by design, and is not the privilege downgrade it
            looks like. zrepl's stdinserver socket lives in the daemon's
            RuntimeDirectory at mode 0700 (upstream's unit) and go-netssh
            creates it with a bare net.Listen("unix", ...) and no chmod, so
            under systemd's default umask only the owner can connect to it.
            A non-root SSH user therefore needs Group/RuntimeDirectoryMode/
            UMask overrides that also expose zrepl's *control* socket to
            that group. The forced command in authorized_keys is the real
            boundary here: the key can run exactly "zrepl stdinserver
            <identity>" and nothing else, and the identity is fixed
            server-side rather than asserted by the client.
          '';
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 22;
          description = "SSH port on the peer (ssh+stdinserver).";
        };
        identityFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "SSH private key used to dial the peer (ssh+stdinserver), e.g. a sops secret path.";
        };
        sshOptions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "Compression=yes" ];
          description = "Extra -o options passed to ssh (ssh+stdinserver).";
        };
        address = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "homelab:8888";
          description = "host:port of the peer (tcp/tls).";
        };
        ca = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "CA certificate validating the peer (tls).";
        };
        cert = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Our client certificate (tls).";
        };
        key = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Private key for our client certificate (tls).";
        };
        serverCn = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Common name the peer's certificate must carry (tls).";
        };
        listenerName = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Listener name of the in-process peer job (local).";
        };
        clientIdentity = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Identity presented to the in-process peer job (local).";
        };
      };
    in
    {
      options.myZrepl = {
        enable = lib.mkEnableOption "zrepl-managed ZFS snapshotting and replication";

        defaultTransport = lib.mkOption {
          type = lib.types.enum [
            "ssh+stdinserver"
            "tcp"
            "tls"
            "local"
          ];
          default = "ssh+stdinserver";
          description = ''
            Transport every role defaults to, so a repo-wide change is a
            one-line edit here rather than a per-host sweep. Individual
            roles can still override it.
          '';
        };

        logLevel = lib.mkOption {
          type = lib.types.enum [
            "error"
            "warn"
            "info"
            "debug"
          ];
          default = "warn";
          description = "zrepl log level, emitted to syslog (and so to the journal).";
        };

        validateConfig = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run `zrepl configcheck` against the generated config at build time.";
        };

        preserveLegacySnapshots = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Keep pre-zrepl snapshots (see legacySnapshotPrefix) instead of
            letting the first prune destroy them. On by default so the
            sanoid cutover doesn't take local snapshot history with it.

            Turn off once zrepl has built up enough history of its own,
            then destroy the leftovers by hand -- nothing ages them out
            while this is on.
          '';
        };

        legacySnapshotPrefix = lib.mkOption {
          type = lib.types.str;
          default = "autosnap_";
          description = "Snapshot prefix of the tool zrepl replaced (sanoid's), protected while preserveLegacySnapshots is on.";
        };

        snapshot = {
          interval = lib.mkOption {
            type = lib.types.str;
            default = "5m";
            description = ''
              How often every snapshotting job takes a snapshot. Deliberately
              uniform across all hosts -- one cadence to reason about rather
              than a per-host matrix.

              Note this also sets how often push jobs replicate, since an
              active job replicates after each snapshot. Pull jobs are
              exempt: they run on their own interval and simply collect
              whatever snapshots accumulated, so a source host's cadence
              does not drive network traffic.

              This is 3x the snapshot rate of the sanoid setup it replaces
              (which ran minutely) and so a net reduction in metadata churn
              on homelab's USB-contended zbackup pool, where sanoid was
              enumerating every snapshot every 60s.
            '';
          };

          prefix = lib.mkOption {
            type = lib.types.str;
            default = "zrepl_";
            description = ''
              Prefix for snapshots zrepl creates. Also scopes every grid
              keep rule -- though note that scoping condemns foreign
              snapshots rather than sparing them; see legacyRule.
            '';
          };
        };

        retention = {
          source = lib.mkOption {
            type = lib.types.str;
            default = "1x1h(keep=all) | 48x1h | 7x1d";
            description = ''
              Retention on whichever host owns the data, uniform across
              every host: an hour at full 5m granularity, then hourly for
              two days, then daily for a week.

              ~67 snapshots, ~9 day window. The full-granularity hour is
              the "undo an accidental rm" window; the 9 day tail means a
              multi-day outage of the backup server doesn't immediately
              leave the source as the only copy of recent history.
            '';
          };

          archive = lib.mkOption {
            type = lib.types.str;
            default = "168x1h | 30x1d | 12x30d";
            description = ''
              Retention for copies living on the backup target: hourly for
              a week, daily for a month, monthly for a year.

              ~210 snapshots, ~13 month reach. Tiering rather than a flat
              wall of dailies buys longer reach for well under half the
              snapshot count, which matters here because every prune walks
              the whole list on a pool already short on I/O headroom.

              No full-granularity bucket, so the source's 5m snapshots
              collapse to one per hour shortly after arriving. They are
              still sent (replication walks the snapshot chain), which
              costs a little transient space for blocks that changed
              between them and are then freed -- add a leading
              1x1h(keep=all) if fine-grained recent history is wanted on
              the target too.
            '';
          };
        };

        # ---- passive sender (default topology, source hosts) --------
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

          type = lib.mkOption {
            type = lib.types.enum [
              "ssh+stdinserver"
              "tcp"
              "tls"
              "local"
            ];
            default = cfg.defaultTransport;
            defaultText = lib.literalExpression "config.myZrepl.defaultTransport";
            description = "Transport this host listens on.";
          };

          clients = lib.mkOption {
            default = { };
            description = ''
              Pullers allowed to connect, keyed by zrepl client identity.

              For ssh+stdinserver this renders both halves of the wiring
              from one declaration: the job's client_identities list, and
              a forced-command entry in root's authorized_keys pinning that
              key to `zrepl stdinserver <identity>`.
            '';
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  publicKey = lib.mkOption {
                    type = lib.types.str;
                    default = "";
                    description = "Puller's SSH public key (ssh+stdinserver).";
                  };
                  address = lib.mkOption {
                    type = lib.types.str;
                    default = "";
                    description = "Puller's source IP, mapped to this identity (tcp).";
                  };
                };
              }
            );
          };

          listen = lib.mkOption {
            type = lib.types.str;
            default = "";
            example = "100.64.0.1:8888";
            description = "Address to listen on (tcp/tls). Bind to the tailnet address, not 0.0.0.0.";
          };

          ca = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "CA certificate validating pullers (tls).";
          };
          cert = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "This host's server certificate (tls).";
          };
          key = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Private key for this host's server certificate (tls).";
          };
          listenerName = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Listener name for in-process peers (local).";
          };
        };

        # ---- active receiver (default topology, backup server) ------
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
                options = connectOptions // {
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

                  interval = lib.mkOption {
                    type = lib.types.str;
                    default = "15m";
                    description = "How often to attempt a pull from this remote.";
                  };

                  keepSender = keepSenderOption (
                    [
                      notReplicatedRule
                      (gridRule cfg.retention.source)
                    ]
                    ++ keepLegacy
                  );

                  keepReceiver = keepReceiverOption [ (gridRule cfg.retention.archive) ];
                };
              }
            );
          };
        };

        # ---- active sender (opt-in, roaming hosts) ------------------
        push = {
          targets = lib.mkOption {
            default = { };
            description = ''
              Sinks to push to, keyed by job name. Opt-in alternative to
              the pull default, for hosts a puller would struggle to catch
              online.

              Understand the tradeoff before enabling: an authenticated
              push client can call DestroySnapshots against its own subtree
              on the sink, so a compromised host can delete its own backup
              history. Pull does not have that property.
            '';
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = connectOptions // {
                  datasets = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Datasets to snapshot and push. Append \"<\" to include children.";
                  };

                  keepSender = keepSenderOption (
                    [
                      notReplicatedRule
                      (gridRule cfg.retention.source)
                    ]
                    ++ keepLegacy
                  );

                  keepReceiver = keepReceiverOption [ (gridRule cfg.retention.archive) ];
                };
              }
            );
          };
        };

        # ---- passive receiver (only needed for push-mode peers) -----
        sink = {
          enable = lib.mkEnableOption "passive sink role: accept pushes from remote hosts";

          rootFs = lib.mkOption {
            type = lib.types.str;
            default = "";
            example = "zbackup/backup";
            description = ''
              Dataset pushes land under. Sink jobs append the client
              identity as a single path component, so one sink serves every
              pusher while confining each to its own subtree.
            '';
          };

          type = lib.mkOption {
            type = lib.types.enum [
              "ssh+stdinserver"
              "tcp"
              "tls"
              "local"
            ];
            default = cfg.defaultTransport;
            defaultText = lib.literalExpression "config.myZrepl.defaultTransport";
            description = "Transport this sink listens on.";
          };

          clients = lib.mkOption {
            default = { };
            description = "Pushers allowed to connect, keyed by client identity. Same shape as serve.clients.";
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  publicKey = lib.mkOption {
                    type = lib.types.str;
                    default = "";
                    description = "Pusher's SSH public key (ssh+stdinserver).";
                  };
                  address = lib.mkOption {
                    type = lib.types.str;
                    default = "";
                    description = "Pusher's source IP, mapped to this identity (tcp).";
                  };
                };
              }
            );
          };

          listen = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Address to listen on (tcp/tls).";
          };
          ca = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "CA certificate validating pushers (tls).";
          };
          cert = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "This host's server certificate (tls).";
          };
          key = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Private key for this host's server certificate (tls).";
          };
          listenerName = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Listener name for in-process peers (local).";
          };
        };

        # ---- same-host replication ---------------------------------
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

          listenerName = lib.mkOption {
            type = lib.types.str;
            default = "localsink";
            description = "Name joining this host's local push and sink jobs.";
          };

          keepSender = keepSenderOption (
            [
              notReplicatedRule
              (gridRule cfg.retention.source)
            ]
            ++ keepLegacy
          );

          keepReceiver = keepReceiverOption [ (gridRule cfg.retention.archive) ];
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.serve.enable -> cfg.serve.datasets != [ ];
            message = "myZrepl.serve.enable is set but myZrepl.serve.datasets is empty.";
          }
          {
            assertion = cfg.sink.enable -> cfg.sink.rootFs != "";
            message = "myZrepl.sink.enable is set but myZrepl.sink.rootFs is empty.";
          }
          {
            assertion = cfg.local.enable -> (cfg.local.rootFs != "" && cfg.local.datasets != [ ]);
            message = "myZrepl.local.enable is set but myZrepl.local.rootFs or .datasets is empty.";
          }
          {
            assertion = settings.jobs != [ ];
            message = "myZrepl is enabled but no role is configured, so zrepl would run with no jobs.";
          }
        ];

        services.zrepl = {
          enable = true;
          inherit settings;
        };

        # Forced-command keys for every ssh+stdinserver peer. The command
        # is fixed here rather than chosen by the client, so a key can only
        # ever proxy to the one identity it was issued for -- it cannot ask
        # for a shell, and it cannot claim to be a different host.
        users.users.root.openssh.authorizedKeys.keys =
          let
            forcedCommand =
              identity:
              "command=\"${config.services.zrepl.package}/bin/zrepl --config /etc/zrepl/zrepl.yml stdinserver ${identity}\",restrict";
            keysFor =
              role:
              lib.mapAttrsToList (identity: c: "${forcedCommand identity} ${c.publicKey}") (
                lib.filterAttrs (_: c: c.publicKey != "") role.clients
              );
          in
          lib.optionals (cfg.serve.enable && cfg.serve.type == "ssh+stdinserver") (keysFor cfg.serve)
          ++ lib.optionals (cfg.sink.enable && cfg.sink.type == "ssh+stdinserver") (keysFor cfg.sink);

        system.extraDependencies = lib.optional cfg.validateConfig configCheck;
      };
    };
}
