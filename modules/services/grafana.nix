# Grafana, the fleet's log dashboard over Loki. Written for homelab but
# wired to no host yet: enabling it needs two operator-added sops keys first
# plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#G9
_: {
  flake.modules.nixos.grafana =
    { config, ... }:
    {
      services.grafana = {
        enable = true;

        settings = {
          server = {
            # tailnet-only exposure comes from the interface-scoped
            # firewall rule below, same pattern as immich/nfs
            # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D10
            http_addr = "0.0.0.0";
            http_port = 3000;
          };

          # frictionless browsing on the tailnet, admin login to change
          # anything -- an accidental phone-browser deletion is the threat,
          # not the tailnet's users
          # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D12
          "auth.anonymous" = {
            enabled = true;
            org_role = "Viewer";
          };
          users.allow_sign_up = false;

          # $__file{} keeps both values out of the store
          # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#G9
          security = {
            admin_password = "$__file{${config.sops.secrets.grafana_admin_password.path}}";
            secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";
          };

          analytics = {
            reporting_enabled = false;
            check_for_updates = false;
          };
        };

        provision = {
          enable = true;
          datasources.settings.datasources = [
            {
              name = "Loki";
              type = "loki";
              access = "proxy";
              url = "http://127.0.0.1:3100";
              isDefault = true;
            }
          ];
        };
      };

      sops.secrets.grafana_admin_password = {
        owner = "grafana";
        group = "grafana";
      };
      sops.secrets.grafana_secret_key = {
        owner = "grafana";
        group = "grafana";
      };

      # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D10
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 3000 ];
    };
}
