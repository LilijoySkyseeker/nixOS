{
  config,
  lib,
  ...
}:
let
  cfg = config.myNixCacheServer;
in
{
  options.myNixCacheServer = {
    enable = lib.mkEnableOption "harmonia nix binary cache, reachable over tailscale only";

    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "TCP port harmonia listens on.";
    };

    signKeyPath = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to the cache's secret signing key (e.g. a sops secret path).
        Generate with `nix key generate-secret --key-name cache.<hostname>-1`.
        Never edit/create this file by hand outside sops — see repo docs on
        manual secret management.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # harmonia's own module already runs the service as DynamicUser with a
    # locked-down systemd sandbox and uses LoadCredential for signKeyPaths
    # (so the key file itself can stay root-only, no group/world-readable
    # loosening needed here) — nothing to re-harden on top of that.
    services.harmonia.cache = {
      enable = true;
      signKeyPaths = [ cfg.signKeyPath ];
      settings = {
        bind = "[::]:${toString cfg.port}";
      };
    };

    # tailscale-only: no LAN/public exposure, matching how other
    # homelab-hosted internal services are scoped in this repo (see
    # services/nfs.nix).
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.port ];

    # No dedicated GC-retention logic needed: nh.clean (profiles/default.nix,
    # "--keep-since 7d --keep 7", daily) already keeps this host's last ~7
    # days of generations as GC roots, which transitively keeps every store
    # path a client could substitute during that window alive. Once a
    # generation ages out past 7 days its paths become collectible like
    # anything else — this is what bounds the cache to "about 1 week" rather
    # than growing unbounded.
  };
}
