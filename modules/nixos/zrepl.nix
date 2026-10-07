_: {
  # zrepl: snapshotting, local replication and both ends of remote replication
  # pull is the default: a push client can DestroySnapshots on its own backup
  # subtree, so a compromised source could wipe its history; push only where
  # a puller would miss the host (e.g. a laptop online in short windows)
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

      # zrepl spells the two ends asymmetrically: connect "ssh+stdinserver",
      # serve "stdinserver"; callers use the connect spelling, these map it
      mkConnect =
        t:
        {
          "ssh+stdinserver" = {
            type = "ssh+stdinserver";
            inherit (t) host user port;
            identity_file = toString t.identityFile;
            dial_timeout = remoteDialTimeout;
          }
          // lib.optionalAttrs (t.sshOptions != [ ]) { options = t.sshOptions; };
          "tcp" = {
            type = "tcp";
            inherit (t) address;
            dial_timeout = remoteDialTimeout;
          };
          "tls" = {
            type = "tls";
            inherit (t) address;
            ca = toString t.ca;
            cert = toString t.cert;
            key = toString t.key;
            server_cn = t.serverCn;
            dial_timeout = remoteDialTimeout;
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

      # pattern -> bool map; a trailing "<" means the dataset and its children
      mkFilesystems = datasets: lib.genAttrs datasets (_: true);

      mkSnapshotting = {
        type = "periodic";
        inherit (cfg.snapshot) interval prefix;
      };

      # the prefix regex does NOT spare foreign snapshots: keep_grid condemns
      # every non-match, it only stops them occupying grid slots; protectRule
      # is the actual guard
      gridRule = grid: {
        type = "grid";
        inherit grid;
        regex = "^${cfg.snapshot.prefix}";
      };

      # never prune a snapshot the receiver hasn't got, or a slow/offline
      # target loses its incremental base
      notReplicatedRule = {
        type = "not_replicated";
      };

      # required: without it zrepl destroys every snapshot it didn't create
      # (not_replicated and the grid both condemn it); a regex keep rule holds
      # whatever it matches, against the bare snapshot name
      protectRule = regex: {
        type = "regex";
        inherit regex;
      };

      keepProtected = map protectRule (
        cfg.protectRegexes
        ++ lib.optional (
          cfg.preserveLegacySnapshots && cfg.legacySnapshotPrefix != ""
        ) "^${cfg.legacySnapshotPrefix}"
      );

      mkPruning = keepSender: keepReceiver: {
        keep_sender = keepSender;
        keep_receiver = keepReceiver;
      };

      # placeholder.encryption is required: zrepl's "unspecified" default
      # fails every receive that creates a placeholder, and configcheck
      # doesn't catch it
      # security (F-P6-03): the source controls the send stream, so pin props
      # a hostile stream could set (e.g. mountpoint=/etc, canmount=on, shares);
      # -o and -x are exclusive per property, so each is in one list only
      mkRecv = {
        placeholder.encryption = cfg.placeholderEncryption;
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

      # ---- job builders, one per role ------------------------------

      # every dataset this host owns, however replicated; snap job default
      ownedDatasets = lib.unique (
        cfg.serve.datasets
        ++ cfg.local.datasets
        ++ lib.concatMap (t: t.datasets) (lib.attrValues cfg.push.targets)
      );

      snapEnabled = cfg.snap.enable && cfg.snap.datasets != [ ];

      # other jobs stand down when a snap job owns snapshotting, or the
      # datasets get two snapshot streams
      ownedSnapshotting = if snapEnabled then { type = "manual"; } else mkSnapshotting;

      # local snapshotting and a prune ceiling, beholden to no peer (under
      # pull a source with its puller down never prunes); keep the ceiling
      # slacker than retention.source: snap jobs ignore not_replicated
      snapJob = lib.optional snapEnabled {
        type = "snap";
        name = "snapshots";
        filesystems = mkFilesystems cfg.snap.datasets;
        snapshotting = mkSnapshotting;
        pruning.keep = cfg.snap.keep;
      };

      serveJob = lib.optional cfg.serve.enable {
        type = "source";
        name = "serve";
        serve = mkServe cfg.serve;
        filesystems = mkFilesystems cfg.serve.datasets;
        snapshotting = ownedSnapshotting;
      };

      pullJobs = lib.mapAttrsToList (name: r: {
        type = "pull";
        inherit name;
        connect = mkConnect r;
        # pull jobs don't append the client identity, unlike sink jobs
        root_fs = r.rootFs;
        inherit (r) interval;
        recv = mkRecv;
        pruning = mkPruning r.keepSender r.keepReceiver;
      }) cfg.pull.remotes;

      # push jobs keep their own snapshotting even with a snap job: push
      # replicates only after its own snapshots (no interval field)
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
        recv = mkRecv;
      };

      # same-host replication: a source/pull pair joined by a listener name;
      # source+pull, not push+sink, so replication has its own interval
      localJobs = lib.optionals cfg.local.enable [
        {
          type = "source";
          name = "local-source";
          serve = {
            type = "local";
            listener_name = cfg.local.listenerName;
          };
          filesystems = mkFilesystems cfg.local.datasets;
          snapshotting = ownedSnapshotting;
        }
        {
          type = "pull";
          name = "local-pull";
          connect = {
            type = "local";
            listener_name = cfg.local.listenerName;
            client_identity = cfg.local.clientIdentity;
            dial_timeout = "10s";
          };
          # pull jobs don't append the client identity, so add it here
          root_fs = "${cfg.local.rootFs}/${cfg.local.clientIdentity}";
          interval = cfg.local.interval;
          recv = mkRecv;
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
        jobs = snapJob ++ serveJob ++ pullJobs ++ pushJobs ++ sinkJob ++ localJobs;
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

      # one transport shape for every dialing role
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

        placeholderEncryption = lib.mkOption {
          type = lib.types.enum [
            "off"
            "inherit"
          ];
          default = "off";
          description = ''
            What to do with the encryption property when a receiving job
            creates an intermediate placeholder dataset.

            "off" suits an unencrypted receiving pool (zbackup);
            "inherit" is for receiving into an encrypted root. There is no
            third option worth exposing: zrepl's own default of
            "unspecified" fails every receive that needs a placeholder,
            and root_fs plus a full source path always needs one.
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

        protectRegexes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "^blank$" ];
          description = ''
            Snapshots zrepl must never destroy, matched by regex against
            the bare snapshot name.

            Defaults to the impermanence `@blank` snapshots. Those are
            created once by disko's postCreateHook at install time and are
            what the initrd rollback service resets root to on every boot
            -- they cannot be regenerated without reinstalling, and losing
            one breaks the boot-time rollback. Since they are the oldest
            snapshot on their dataset (hence "replicated") and carry no
            zrepl prefix, every other keep rule would agree to destroy
            them. hosts/thinkpad has these on both zroot/local/root and
            zroot/local/home, which are exactly the datasets it serves.

            Anchor patterns (^...$) so a prefix match cannot catch more
            than intended.
          '';
        };

        preserveLegacySnapshots = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Keep pre-zrepl snapshots (see legacySnapshotPrefix) instead of
            letting the first prune destroy them.

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
            '';
          };

          prefix = lib.mkOption {
            type = lib.types.str;
            default = "zrepl_";
            description = ''
              Prefix for snapshots zrepl creates. Also scopes every grid
              keep rule -- though note that scoping condemns foreign
              snapshots rather than sparing them; see protectRegexes.
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

          ceiling = lib.mkOption {
            type = lib.types.str;
            default = "1x1h(keep=all) | 48x1h | 30x1d";
            description = ''
              Upper bound enforced locally by the snap job, independent of
              any peer: an hour at full granularity, hourly for two days,
              daily for a month. ~90 snapshots, ~32 day window.

              Intentionally slacker than retention.source so that in
              normal operation the puller's stricter rules are what
              actually prune, and this only takes effect once a peer has
              been unreachable long enough that the alternative is
              unbounded growth. Whatever the outage length, snapshot count
              stops at ~90 rather than climbing at ~8.6k/month.
            '';
          };

          archive = lib.mkOption {
            type = lib.types.str;
            default = "1x15m(keep=all) | 168x1h | 30x1d | 12x30d";
            description = ''
              Retention for copies living on the backup target: hourly for
              a week, daily for a month, monthly for a year.

              ~212 snapshots, ~13 month reach. Tiering rather than a flat
              wall of dailies buys longer reach for well under half the
              snapshot count, which matters here because every prune walks
              the whole list on a pool already short on I/O headroom.

              The source's 5m snapshots collapse to one per hour shortly
              after arriving, past the leading bucket. That leading
              1x15m(keep=all) bucket is load-bearing, not cosmetic: without
              it, the grid's "keep the oldest snapshot per bucket, remove
              younger ones in the same bucket" rule (retentiongrid.go's
              RemoveYoungerSnapsExceedingKeepCount) marks the just-received
              newest snapshot for destruction on almost every pull cycle --
              directly colliding with the hold zrepl's endpoint places on
              that same snapshot (zrepl_last_received_J_<job>) to guarantee
              a valid incremental base. The destroy fails loudly every
              cycle even though nothing is actually wrong. Widen this past
              the pull interval (default 15m) if pull interval ever grows,
              or drop to keep=all for a full hour for more fine-grained
              recent history on the target as a side effect.
            '';
          };
        };

        # ---- local snapshotting + local prune ceiling ---------------
        snap = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Give this host a `snap` job owning snapshotting and a local
              prune ceiling for every dataset it owns, so neither depends
              on a peer being reachable.

              On by default, and on for every host rather than only the
              roaming ones, because the failure it prevents is not
              laptop-specific: any host whose peer is unreachable long
              enough will otherwise accumulate snapshots without bound.

              When on, the serve and local-source jobs switch to
              `snapshotting: manual` so the datasets aren't snapshotted
              twice. Push jobs are exempt -- their replication is driven
              by their snapshotter, so they must keep it.
            '';
          };

          datasets = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = ownedDatasets;
            defaultText = lib.literalExpression "every dataset named by serve.datasets, local.datasets or push.targets.*.datasets";
            description = ''
              Datasets to snapshot and locally prune. Defaults to every
              dataset this host owns, so declaring a dataset for
              replication is enough to get it snapshotted.
            '';
          };

          keep = lib.mkOption {
            type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
            default = [ (gridRule cfg.retention.ceiling) ] ++ keepProtected;
            defaultText = lib.literalExpression "the retention.ceiling grid, plus the protected-snapshot rules";
            description = ''
              Keep rules for the local prune ceiling.

              Note a `not_replicated` rule would be inert here: snap jobs
              have no replication cursor, so zrepl treats every snapshot
              as replicated (alwaysUpToDateReplicationCursorHistory in
              internal/daemon/job/snapjob.go). Protection against pruning
              a still-needed incremental base comes from zrepl's holds and
              the cursor bookmark, not from this rule set.
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
                    ++ keepProtected
                  );

                  keepReceiver = keepReceiverOption ([ (gridRule cfg.retention.archive) ] ++ keepProtected);
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
                    ++ keepProtected
                  );

                  keepReceiver = keepReceiverOption ([ (gridRule cfg.retention.archive) ] ++ keepProtected);
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
            description = "Name joining this host's local source and pull jobs.";
          };

          interval = lib.mkOption {
            type = lib.types.str;
            default = "15m";
            description = ''
              How often to replicate this host's own datasets into its
              backup pool. Separate from snapshot.interval on purpose --
              snapshots are cheap and local, whereas each replication run
              costs I/O on the target pool.
            '';
          };

          keepSender = keepSenderOption (
            [
              notReplicatedRule
              (gridRule cfg.retention.source)
            ]
            ++ keepProtected
          );

          keepReceiver = keepReceiverOption ([ (gridRule cfg.retention.archive) ] ++ keepProtected);
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

        # upstream Requires=local-fs.target: one transient mount failure at
        # boot leaves zrepl dead with no retry (silent backup outage); keep
        # the ordering, a not-yet-mounted dataset just fails one job cycle
        systemd.services.zrepl = {
          requires = lib.mkForce [ ];
          wants = [ "local-fs.target" ];
          after = [ "local-fs.target" ];
        };

        # security (F-P6-04): the puller destroys whatever snapshots it names,
        # ignoring local keep rules; a non-zrepl hold tag can't be released
        # over RPC; only ever @blank, holding zrepl_ snapshots pins the pool
        systemd.services.zrepl-protect-blank = lib.mkIf (cfg.serve.enable && cfg.serve.datasets != [ ]) {
          description = "Hold @blank on served datasets so a puller cannot destroy it";
          wantedBy = [ "multi-user.target" ];
          after = [ "zfs-mount.service" ];
          path = [ pkgs.zfs ];
          script = ''
            set -uo pipefail
            ${lib.concatMapStringsSep "\n" (dataset: ''
              snap=${lib.escapeShellArg dataset}@blank
              if ! zfs list -t snapshot -H -o name "$snap" >/dev/null 2>&1; then
                # no @blank (not on impermanence, or a test pool): not an error
                echo "zrepl-protect-blank: $snap does not exist, skipping"
              elif zfs holds -H "$snap" | cut -f2 | grep -qx protect; then
                echo "zrepl-protect-blank: $snap already held"
              else
                echo "zrepl-protect-blank: holding $snap"
                zfs hold protect "$snap"
              fi
            '') cfg.serve.datasets}
          '';
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # no PrivateDevices: needs /dev/zfs
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            RestrictNamespaces = true;
            PrivateTmp = true;
          };
        };

        # forced-command keys: each key only proxies to its own identity, no
        # shell, no claiming another host
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
