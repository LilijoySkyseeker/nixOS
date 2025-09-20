{ config, ... }:
{
  # cloudflared tunnel
  services.cloudflared = {
    enable = true;
    tunnels = {
      "e16db923-1cc0-46d3-b841-8a274417516a" = {
        credentialsFile = "${config.sops.secrets.cloudflare_tunnel_token_01.path}";
        ingress = {
          "skyseekerlabs.xyz" = {
            service = "ssh://localhost:22";
          };
          "test.skyseekerlabs.xyz" = {
            service = "hello_world";
          };
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
    };
  };
}
