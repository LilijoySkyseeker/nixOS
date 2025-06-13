{config, ... }:
{
# cloudflared tunnel
services.cloudflared = {
    enable = true;
    tunnels = {
      "d74010ef-332c-44dc-8216-8131b2825f43" = {
        credentialsFile = "${config.sops.secrets.cloudflare_tunnel_token_01.path}";
        ingress = {
          "*.skyseekerlabs.duckdns.org" = {
            service = "http://localhost:80";
          };
        };
        default = "http_status:404";
      };
    };
  };
  sops.secrets = {
    cloudflare_tunnel_token_01 = { };
  };
}
