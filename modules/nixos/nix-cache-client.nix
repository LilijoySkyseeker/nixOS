{
  config,
  lib,
  ...
}:
let
  cfg = config.myNixCacheClient;
in
{
  options.myNixCacheClient = {
    enable = lib.mkEnableOption "trust and substitute from homelab's tailnet-only harmonia binary cache";

    cacheHost = lib.mkOption {
      type = lib.types.str;
      default = "homelab";
      description = "Tailscale MagicDNS name of the cache server.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "TCP port the cache server listens on.";
    };

    publicKey = lib.mkOption {
      type = lib.types.str;
      description = ''
        The cache server's public signing key, e.g.
        "cache.homelab-1:base64pubkey=". Get it with
        `nix key convert-secret-to-public < signKey.secret` on the server,
        or `cat /var/cache-key.pub`-equivalent if kept alongside the secret.
        Not sensitive — safe to commit.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # http, not https: this only ever traverses the tailnet (already
    # encrypted/authenticated by WireGuard), so TLS here would just be
    # redundant overhead with no cert to manage.
    nix.settings.substituters = [ "http://${cfg.cacheHost}:${toString cfg.port}" ];
    nix.settings.trusted-public-keys = [ cfg.publicKey ];
  };
}
