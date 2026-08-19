{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myNixCacheWarm;
in
{
  options.myNixCacheWarm = {
    enable = lib.mkEnableOption "build-only jobs to pre-populate this host's nix cache for other hosts' closures";

    flakeDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      description = "Path to the local flake checkout to build from.";
    };

    jobs = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Attrset of nixosConfigurations attribute name -> systemd OnCalendar
        spec, e.g. `{ thinkpad = "Sat 03:00"; torrent = "Sun 03:00"; }`.
        Each gets its own independently-scheduled build-only (never
        switch/push) job, so their closures land in this host's
        /nix/store for the cache to serve. Deliberately independent
        timers, not chained via onSuccess, so they can be staggered
        across the week instead of bursting all at once.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.jobs != { }) {
    systemd.services = lib.mapAttrs' (
      hostAttr: _dates:
      lib.nameValuePair "cache-warm-${hostAttr}" {
        description = "Build ${hostAttr}'s closure locally to warm the nix cache (never switches)";
        path = with pkgs; [
          nixos-rebuild
          nix
          coreutils
        ];
        script = ''
          set -euo pipefail
          cd ${cfg.flakeDir}
          nixos-rebuild build --flake .#${hostAttr}
        '';
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          # build-only: never runs switch/boot, never touches this
          # host's own kernel/units, and the checkout itself is only
          # read, not mutated (that already happened in whatever job
          # updated master) — so this can be sandboxed harder than the
          # git-mutating auto-update job.
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          RestrictNamespaces = true;
          ReadOnlyPaths = [ cfg.flakeDir ];
        };
      }
    ) cfg.jobs;

    systemd.timers = lib.mapAttrs' (
      hostAttr: dates:
      lib.nameValuePair "cache-warm-${hostAttr}" {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = dates;
          Persistent = true;
        };
      }
    ) cfg.jobs;
  };
}
