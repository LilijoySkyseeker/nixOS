# Loki log aggregation on homelab, with its ruler alerting through a
# localhost Alertmanager into the fleet's existing Discord webhook.
# plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md
_: {
  flake.modules.nixos.loki =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      lokiDir = "/nix/state/loki";

      # ruler rules are code, not secrets: a store path is fine, and the
      # "fake" tenant dir is what Loki's local rule storage expects with
      # auth_enabled=false
      # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D13
      rulerRules = pkgs.writeTextDir "fake/security.yml" ''
        groups:
          - name: security
            rules:
              - alert: VpsDeployRejected
                # repo-owned text: hosts/vps dispatcher reject() logger line
                expr: 'sum(count_over_time({host="vps", identifier="vps-deploy"} |= "rejected command" [5m])) > 0'
                annotations:
                  summary: vps-deploy dispatcher rejected a command (the only remote-root path into vps)

              - alert: PolkitVpsDeployGrant
                # repo-owned text: polkit.log() call in the vps polkit rule
                expr: 'sum(count_over_time({host="vps", identifier="polkitd"} |= "vps-deploy manage-units grant" [5m])) > 0'
                annotations:
                  summary: polkit granted vps-deploy a manage-units action

              - alert: Run0Escalation
                # verified live against a real escalation in homelab's journal (G7)
                expr: 'sum by (host) (count_over_time({host!=""} |~ `pam_unix\(systemd-run0:session\): session opened` [5m])) > 0'
                annotations:
                  summary: run0 escalation on {{ $labels.host }}

              - alert: JellyfinFailedLogins
                # journald transport verified (G8); threshold, not single events:
                # one typo'd password is life, a run of them is a guess attempt
                expr: 'sum(count_over_time({host="homelab", unit="jellyfin.service"} |~ `(?i)(auth(entication)? request .* (denied|failed)|invalid (username|password|credentials))` [15m])) > 3'
                annotations:
                  summary: repeated Jellyfin login failures

              - alert: SambaAuthFailure
                # needs samba "log level = 1 auth:3" (same change) to print at all
                expr: 'sum(count_over_time({host="homelab", unit="samba-smbd.service"} |~ `(?i)(auth.*fail|NT_STATUS_(WRONG_PASSWORD|LOGON_FAILURE|NO_SUCH_USER))` [15m])) > 0'
                annotations:
                  summary: Samba authentication failures

          - name: operational
            rules:
              # the two deliberate overlaps with myHealthAlerts: severe, and
              # its 15-minute poll is slow for a window in which SSH may be
              # publicly exposed
              # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D14
              - alert: FirewallFailed
                expr: 'sum by (host) (count_over_time({identifier="systemd"} |= "firewall.service" |~ `(?i)(failed|failure)` [5m])) > 0'
                annotations:
                  summary: firewall unit trouble on {{ $labels.host }} — SSH may be exposed (G5)

              - alert: CrowdSecDown
                expr: 'sum(count_over_time({host="vps", identifier="systemd"} |~ `crowdsec.*(Failed|failure|Scheduled restart)` [10m])) > 2'
                annotations:
                  summary: CrowdSec (or its bouncer) failing or restart-looping on vps

              - alert: SopsDecryptFailure
                expr: 'sum by (host) (count_over_time({host!=""} |~ `sops-(nix|install-secrets)` |~ `(?i)(error|fail)` [10m])) > 0'
                annotations:
                  summary: sops secret provisioning failure on {{ $labels.host }}

              - alert: TailscaleAuthTrouble
                expr: 'sum by (host) (count_over_time({unit="tailscaled.service"} |~ `(?i)(reauth required|auth.*(fail|expir)|invalid.*key|logged out)` [10m])) > 0'
                annotations:
                  summary: tailscale auth trouble on {{ $labels.host }} — tailnet loss loses all SSH

              - alert: CaddyUpstreamErrors
                expr: 'sum(count_over_time({host="vps", unit="caddy.service"} |= `"status":502` | json | status == 502 [10m])) > 5'
                annotations:
                  summary: Caddy 502s on vps — anubis/wireguard path to jellyfin failing

              - alert: AnubisDown
                expr: 'sum(count_over_time({host="vps", identifier="systemd"} |= "anubis-jellyfin.service" |~ `(?i)failed` [10m])) > 0'
                annotations:
                  summary: anubis (the only gate in front of personal media) failing on vps
      '';
    in
    {
      # the one seam the VM test needs: everything else in here is inert
      # without homelab's sops-provisioned webhook file, and the test
      # substitutes a fake one (same curl -K format) instead of dragging
      # sops-nix into the test nodes
      options.myLoki.alertWebhookFile = lib.mkOption {
        type = lib.types.str;
        default = config.sops.secrets.discord_webhook.path;
        defaultText = lib.literalExpression "config.sops.secrets.discord_webhook.path";
        description = "curl -K config file carrying the Discord webhook url line.";
      };

      config = {
        services.loki = {
          enable = true;
          dataDir = lokiDir;
          configuration = {
            auth_enabled = false;

            server = {
              http_listen_address = "0.0.0.0";
              http_listen_port = 3100;
              # single node: no reason for gRPC off-host
              grpc_listen_address = "127.0.0.1";
            };

            common = {
              path_prefix = lokiDir;
              replication_factor = 1;
              instance_addr = "127.0.0.1";
              ring.kvstore.store = "inmemory";
              storage.filesystem = {
                chunks_directory = "${lokiDir}/chunks";
                rules_directory = "${lokiDir}/rules";
              };
            };

            schema_config.configs = [
              {
                from = "2026-01-01";
                store = "tsdb";
                object_store = "filesystem";
                schema = "v13";
                index = {
                  prefix = "index_";
                  period = "24h";
                };
              }
            ];

            # 30d retention; the data is expendable by design, which is what
            # justifies the dataset's never-snapshotted persist tier
            # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D3
            compactor = {
              working_directory = "${lokiDir}/compactor";
              retention_enabled = true;
              delete_request_store = "filesystem";
            };
            limits_config = {
              retention_period = "720h";
              # keep the retention machinery but kill the user-facing
              # deletion API: with it live, a compromised tailnet node can
              # erase the central record of its own intrusion
              # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#F4
              deletion_mode = "disabled";
            };

            ruler = {
              storage = {
                type = "local";
                local.directory = "${rulerRules}";
              };
              rule_path = "${lokiDir}/ruler-tmp";
              alertmanager_url = "http://127.0.0.1:9093";
              wal.dir = "${lokiDir}/ruler-wal";
              ring.kvstore.store = "inmemory";
            };

            analytics.reporting_enabled = false;
          };
        };

        # push endpoint for the fleet's shippers: tailnet only, no auth --
        # the tailnet is the fleet's existing trust boundary (NFS, Samba, SSH)
        # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D11
        networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 3100 ];

        # ruler -> localhost Alertmanager -> the same Discord webhook
        # myHealthAlerts uses; detection paths stay independent
        # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D6
        services.prometheus.alertmanager = {
          enable = true;
          listenAddress = "127.0.0.1";
          port = 9093;
          # config only becomes valid after envsubst injects the webhook URL,
          # so the sandboxed build-time check has to be off
          checkConfig = false;
          environmentFile = "/run/alertmanager-discord.env";
          configuration = {
            route = {
              receiver = "discord";
              group_by = [
                "alertname"
                "host"
              ];
              group_wait = "30s";
              group_interval = "5m";
              repeat_interval = "12h";
            };
            receivers = [
              {
                name = "discord";
                discord_configs = [ { webhook_url = "$DISCORD_WEBHOOK_URL"; } ];
              }
            ];
          };
        };

        # the shared discord_webhook secret (declared by homelab's own
        # config) is a curl -K config snippet (url = "..."), which
        # Alertmanager can't consume directly -- this root oneshot extracts
        # the bare URL into the env file envsubst reads. root-only file; the
        # EnvironmentFile is read by the service manager, not the
        # DynamicUser process, so 0400 root:root is right
        systemd.services.alertmanager-discord-env = {
          description = "render Alertmanager's Discord webhook env file from the sops secret";
          before = [ "alertmanager.service" ];
          requiredBy = [ "alertmanager.service" ];
          serviceConfig = {
            Type = "oneshot";
            UMask = "0077";
            # root only because the sops secret is root:0400; sandboxed to
            # the repo baseline otherwise
            # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#F6
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ "/run" ];
            ProtectHome = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            RestrictNamespaces = true;
            PrivateTmp = true;
          };
          script = ''
            url=$(${pkgs.gnused}/bin/sed -n 's/^url *= *"\(.*\)"$/\1/p' ${config.myLoki.alertWebhookFile})
            if [ -z "$url" ]; then
              echo "webhook file did not parse as a curl config 'url = ...' line" >&2
              exit 1
            fi
            printf 'DISCORD_WEBHOOK_URL=%s\n' "$url" > /run/alertmanager-discord.env
          '';
        };
      };
    };
}
