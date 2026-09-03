_: {
  flake.modules.nixos."docker-userns-remap" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.myDockerUserns;
    in
    {
      options.myDockerUserns = {
        enable = lib.mkEnableOption "docker userns-remap with declarative bind-mount ownership migration";

        subIdStart = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10000000;
          description = ''
            Start of the subordinate uid/gid range assigned to the
            `dockremap` user (applied identically to both id spaces).
            Container uid/gid 0 maps to this host id, container id N
            maps to `subIdStart + N`.

            Fixed rather than left to Docker's own `"default"`
            auto-provisioning, which writes `/etc/subuid`/`/etc/subgid`
            at daemon startup -- unreliable on a `mutableUsers = false`
            host, where NixOS regenerates those files declaratively from
            `users.users.<n>.subUidRanges`/`subGidRanges` on every
            switch, clobbering whatever Docker itself wrote.

            Deliberately *not* `100000`, Docker's own doc example: that
            is byte-identical to the start of NixOS's own
            `autoSubUidGidRange` pool (`nixos/modules/config/
            update-users-groups.pl`'s `allocSubUid`, `min = 100000,
            delta = 65536`), which any `isNormalUser` account without
            its own explicit `subUidRanges` gets assigned into --
            silently, since the auto-allocator's collision check never
            sees manually-declared ranges like this one. `10000000`
            sits clear of that pool for any realistic number of human
            accounts (the pool would need >150 auto-allocated accounts
            on one host to reach this far).
          '';
        };

        subIdCount = lib.mkOption {
          type = lib.types.ints.positive;
          default = 65536;
          description = "Size of the subordinate id range. 65536 covers every id a container image plausibly uses.";
        };

        migrations = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                path = lib.mkOption {
                  type = lib.types.str;
                  description = "Bind-mount directory to migrate.";
                };
                uid = lib.mkOption {
                  type = lib.types.ints.unsigned;
                  description = "The uid this path's files are currently owned by (pre-remap).";
                };
                gid = lib.mkOption {
                  type = lib.types.ints.unsigned;
                  description = "The gid this path's files are currently owned by (pre-remap).";
                };
              };
            }
          );
          default = [ ];
          description = ''
            Bind-mount directories that already have data on them from
            before userns-remap was enabled. Docker never adjusts
            existing bind-mount ownership on its own (confirmed against
            Docker's own docs, which recommend avoiding the combination
            entirely) -- without this, a container's uid 0 no longer
            being host uid 0 also means it can no longer read/write
            files it wrote before the remap.

            Each entry is migrated with `chown --from=<uid>:<gid> -R
            <uid+subIdStart>:<gid+subIdStart>`, so only files still at
            the old ownership are touched. Safe to leave declared
            permanently: a fully-migrated tree matches nothing on a
            second run, making this idempotent rather than merely fast
            on repeat.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        users.groups.dockremap = { };
        users.users.dockremap = {
          isSystemUser = true;
          group = "dockremap";
          subUidRanges = [
            {
              startUid = cfg.subIdStart;
              count = cfg.subIdCount;
            }
          ];
          subGidRanges = [
            {
              startGid = cfg.subIdStart;
              count = cfg.subIdCount;
            }
          ];
        };

        virtualisation.docker.daemon.settings.userns-remap = "dockremap";

        # Ordered before docker.service (and pulled in by it via
        # requiredBy) rather than tied to any specific container unit --
        # every docker-<name>.service already carries `After = [
        # "docker.service" ]` (nixpkgs' oci-containers.nix), so this
        # transitively runs before any container touches its bind mount,
        # without this module needing to know container names.
        #
        # requiredBy, not wantedBy: `Wants=` doesn't propagate failure,
        # so a failed migration would silently let docker.service (and
        # both game containers) start anyway, against unmigrated
        # (wrong-owner) data -- a quiet permission failure instead of a
        # loud one. `Requires=` fails the whole start transaction if
        # this unit fails, which is the fail-closed behavior a
        # security-relevant remap wants: a visible outage is easier to
        # notice and fix than a game server silently unable to read its
        # own save data.
        systemd.services.docker-userns-remap-migrate = {
          description = "Migrate bind-mount ownership for docker userns-remap (myDockerUserns)";
          requiredBy = [ "docker.service" ];
          before = [ "docker.service" ];
          after = [ "local-fs.target" ];
          path = [ pkgs.coreutils ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            RestrictNamespaces = true;
            PrivateTmp = true;
            ReadWritePaths = map (m: m.path) cfg.migrations;
            # Completion markers, kept out of the migrated trees
            # themselves deliberately: a marker inside e.g.
            # /srv/factorio/main would be owned by real host root (this
            # unit runs as root, outside any remap), which sits outside
            # the container's own mapped uid range entirely --
            # factorio.nix's entrypoint does its own `chown -R
            # factorio:factorio` over the whole volume at every start,
            # which would choke trying to touch a file it has no
            # namespace permission over. StateDirectory keeps them
            # somewhere the container's bind mount never sees.
            StateDirectory = "docker-userns-remap-migrate";
            # Narrower than full root, matching this repo's own pattern
            # for other root-necessary units (health-alerts.nix's
            # CAP_SYS_RAWIO-only smartctl unit, vps's CAP_NET_ADMIN-only
            # unit): CAP_CHOWN to actually change ownership regardless of
            # current owner, CAP_FOWNER for owner-gated metadata ops on
            # files this unit doesn't own, CAP_DAC_OVERRIDE/
            # CAP_DAC_READ_SEARCH to traverse into the migrated trees at
            # all -- factorio.nix/minecraft.nix's directories are mode
            # 0700 owned by 845/1000, not this unit's own uid.
            CapabilityBoundingSet = [
              "CAP_CHOWN"
              "CAP_FOWNER"
              "CAP_DAC_OVERRIDE"
              "CAP_DAC_READ_SEARCH"
            ];
          };
          # A per-path marker skips the recursive chown -R (and the
          # stat-every-file walk it implies) on every boot after the one
          # that actually needed it -- `RemainAfterExit` already stops
          # this unit re-running within a single boot, but does nothing
          # for the next one. `--from` scoping alone is still correct
          # without the marker, just needlessly expensive forever on a
          # tree that only ever needed touching once.
          script = lib.concatStringsSep "\n" (
            map (
              m:
              let
                marker = "/var/lib/docker-userns-remap-migrate/${
                  lib.replaceStrings [ "/" ] [ "-" ] m.path
                }.migrated";
              in
              ''
                if [ -e ${lib.escapeShellArg m.path} ] && [ ! -e ${lib.escapeShellArg marker} ]; then
                  chown --from=${toString m.uid}:${toString m.gid} -R ${toString (m.uid + cfg.subIdStart)}:${
                    toString (m.gid + cfg.subIdStart)
                  } ${lib.escapeShellArg m.path}
                  touch ${lib.escapeShellArg marker}
                fi''
            ) cfg.migrations
          );
        };
      };
    };
}
