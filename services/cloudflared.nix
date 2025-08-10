{ config, ... }:
{
  # cloudflared tunnel
  services.cloudflared = {
    enable = true;
    tunnels = {
      "homelab-skyseekerlabs" = {
        credentialsFile = "${config.sops.secrets.cloudflare_tunnel_token_01.path}";
        ingress = {
          "*.skyseekerlabs.xyz" = {
            service = "http://localhost:80";
          };
        };
        default = "http_status:404";
      };
    };
  };
  sops.secrets = {
    cloudflare_tunnel_token_01 = {
      owner = "cloudflared";
      group = "cloudflared";
    };
  };
}
