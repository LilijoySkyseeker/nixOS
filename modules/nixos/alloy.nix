# myAlloy: fleet log shipper (Grafana Alloy) plus the journald capture
# policy it depends on. Reads the whole journal and pushes it to Loki on
# homelab over the tailnet.
# plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md
{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos."alloy" =
    {
      config,
      lib,
      pkgs-stable,
      ...
    }:
    let
      cfg = config.myAlloy;

      # a real user instead of the module's DynamicUser: impermanence
      # cannot bind-mount onto the /var/lib/private symlink DynamicUser
      # turns StateDirectory into (docs/hardening.md), and the read
      # cursor must survive reboots on the impermanent hosts
      # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#G2
      alloyServiceOverrides = {
        DynamicUser = lib.mkForce false;
        User = "alloy";
        Group = "alloy";
        # DynamicUser=true implied these six (systemd.exec(5)); keep them
        # now that it's off
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RemoveIPC = true;
        RestrictSUIDSGID = true;
        # the repo's usual sandbox flags on top -- not DynamicUser leftovers
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
      };
    in
    {
      options.myAlloy = {
        enable = lib.mkEnableOption "the Alloy journal shipper";

        lokiUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://homelab:3100/loki/api/v1/push";
          description = "Loki push endpoint, tailnet MagicDNS name.";
        };

        # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D9
        maxAge = lib.mkOption {
          type = lib.types.str;
          default = "24h";
          description = "Oldest journal entries Alloy reads on catch-up.";
        };

        # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#G6
        journalMaxUse = lib.mkOption {
          type = lib.types.str;
          default = "2G";
          description = "journald SystemMaxUse for this host.";
        };

        # sshd fleet-wide; hosts append their own security-relevant units
        # (vps adds caddy). kernel messages aren't unit-scoped -- vps's
        # iptables LOG rule is already rate-capped below journald's global
        # limit, which stays at its default as the safety valve
        # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D7
        raisedRateLimitUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "sshd" ];
          description = "Units whose journald per-unit rate limit is raised 10x.";
        };

        # where this host's impermanence tree lives; only vps differs
        # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#G3
        persistenceRoot = lib.mkOption {
          type = lib.types.str;
          default = vars.persistRoot;
          description = "environment.persistence root the Alloy cursor entry goes under.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.alloy = {
          enable = true;
          # stable fleet-wide to match homelab's Loki, removing the
          # cross-tree version skew
          # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D18
          package = pkgs-stable.grafana-alloy;
          # Alloy's own HTTP endpoint is debug-only: keep it off the network
          extraFlags = [ "--server.http.listen-addr=127.0.0.1:12345" ];
        };

        environment.etc."alloy/config.alloy".text = ''
          // ship everything; filtering waits for observed volume
          // plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D8
          loki.relabel "journal" {
            forward_to = []

            // UNIT (PID1's field naming the unit its message is about) is
            // client-suppliable via the journal native protocol; the
            // kernel-attested _SYSTEMD_UNIT is applied second so a forged
            // UNIT from an unprivileged sender can't relabel its stream.
            // PID1's own unit-state messages end up unit=init.scope; the
            // rules that need those match on identifier+text instead
            // plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#F7
            rule {
              source_labels = ["__journal_unit"]
              target_label  = "unit"
            }

            rule {
              source_labels = ["__journal__systemd_unit"]
              target_label  = "unit"
            }

            rule {
              source_labels = ["__journal_syslog_identifier"]
              target_label  = "identifier"
            }

            rule {
              source_labels = ["__journal_priority_keyword"]
              target_label  = "level"
            }
          }

          loki.source.journal "read" {
            forward_to    = [loki.write.homelab.receiver]
            relabel_rules = loki.relabel.journal.rules
            max_age       = "${cfg.maxAge}"
            labels        = {host = "${config.networking.hostName}"}
          }

          loki.write "homelab" {
            endpoint {
              url = "${cfg.lokiUrl}"
            }
          }
        '';

        # Storage=persistent is already the nixos default (F11); only the
        # burst-sized cap needs setting
        # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D9
        services.journald.extraConfig = ''
          SystemMaxUse=${cfg.journalMaxUse}
        '';

        # 10x journald's 10000/30s default, which has already eaten a real
        # port-scan burst on vps; raised, not disabled
        # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#G1
        systemd.services =
          lib.genAttrs cfg.raisedRateLimitUnits (_: {
            serviceConfig = {
              LogRateLimitIntervalSec = "30s";
              LogRateLimitBurst = 100000;
            };
          })
          // {
            alloy.serviceConfig = alloyServiceOverrides;
          };

        # the pinned real user the DynamicUser override above runs as
        users.users.alloy = {
          isSystemUser = true;
          group = "alloy";
        };
        users.groups.alloy = { };

        # on all hosts, even the not-yet-impermanent two
        # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#G3
        environment.persistence.${cfg.persistenceRoot}.directories = [
          {
            directory = "/var/lib/alloy";
            user = "alloy";
            group = "alloy";
          }
        ];
      };
    };
}
