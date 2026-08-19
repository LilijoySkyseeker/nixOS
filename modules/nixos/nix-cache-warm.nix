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

    hostAttrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "nixosConfigurations attribute names to build (never switch/push) so their closures land in this host's /nix/store for the cache to serve.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.hostAttrs != [ ]) {
    systemd.services = lib.listToAttrs (
      map (hostAttr: {
        name = "cache-warm-${hostAttr}";
        value = {
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
        };
      }) cfg.hostAttrs
    );
  };
}
