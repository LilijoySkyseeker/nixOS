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

            Fixed rather than Docker's `"default"` auto-provisioning,
            whose `/etc/subuid`/`/etc/subgid` writes NixOS overwrites on
            every switch.

            Not `100000`: that is where NixOS's `autoSubUidGidRange` pool
            for `isNormalUser` accounts starts, and its collision check
            never sees manually-declared ranges. `10000000` sits clear of
            it for any realistic number of accounts.
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
            existing bind-mount ownership, so without this a container
            can no longer read/write files it wrote before the remap.

            Each entry is migrated with `chown --from=<uid>:<gid> -R
            <uid+subIdStart>:<gid+subIdStart>`, so only files still at
            the old ownership are touched. Idempotent, safe to leave
            declared permanently.
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

        # before docker.service, so transitively before every docker-<name>.service
        # requiredBy, not wantedBy: fail closed, a failed migration must stop
        # docker rather than let containers start on wrong-owner data
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
            # completion markers, kept out of the migrated trees: a host-root
            # owned marker there breaks factorio's own `chown -R` at start
            StateDirectory = "docker-userns-remap-migrate";
            # narrower than full root: chown, owner-gated metadata ops, and
            # DAC caps to traverse the 0700 game-server trees
            CapabilityBoundingSet = [
              "CAP_CHOWN"
              "CAP_FOWNER"
              "CAP_DAC_OVERRIDE"
              "CAP_DAC_READ_SEARCH"
            ];
          };
          # per-path marker skips the full-tree chown walk on later boots;
          # `--from` alone is correct, just slow every boot
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
