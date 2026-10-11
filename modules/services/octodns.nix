_: {
  flake.modules.nixos.octodns =
    {
      config,
      lib,
      vars,
      pkgs-unstable,
      ...
    }:
    let
      enable = true;

      # zone data and octoDNS config are both rendered from these, no checked-in YAML
      inherit (vars) domain;
      vpsPublicIp = "137.184.45.18";

      # only minecraft and factorio are meant to be public (hosts/vps/README.md);
      # mail records point at Google Workspace, not the vps
      zoneRecords = {
        "" = [
          {
            type = "A";
            ttl = 300;
            value = vpsPublicIp;
          }
          # Google Workspace mail, single-MX form
          {
            type = "MX";
            ttl = 300;
            value = {
              preference = 1;
              exchange = "smtp.google.com.";
            };
          }
          # SPF and the site-verification token as one TXT with two values
          {
            type = "TXT";
            ttl = 300;
            values = [
              "v=spf1 include:_spf.google.com ~all"
              "google-site-verification=rC01szyAkLHzaXQ9BS69zEDh0sW9Z2k7inhCN9LgWxs"
            ];
          }
        ];
        # DKIM public key from the Workspace admin console (Gmail > Authenticate
        # email); `\;` escaping is required by octoDNS
        "google._domainkey" = [
          {
            type = "TXT";
            ttl = 300;
            value = "v=DKIM1\\;k=rsa\\;p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsonrfzXTCC2+UEvz952v6fJgq6V/dUzIzORTEogwWdoBQHotImyklUGvhGhimwx49P4jDd+IezTeA7spO+EZpepXPidYPrDyzOnqtYyjgCM6z4SrD4RFGIcmtAIcVxYw8uy0LQ/L1L4JHxNf83LGQSRQpGo5HFwbwvAPsVCsE+t4CjFCIbWOlZuvHIuOLApKjrmYT2OBiu6jScKZvAiFTB98c9zJe7Arsws7SrSC41O0S5P/4v6bLCMq524TGiuVWPAJnvrJYJqXzj8nWfkqkZ5tVe/KeJi32pCGevfh1eGXU+IThT27Wcgl6QferAtYs10U/KiVMNRUV/Zeu+4IXwIDAQAB";
          }
        ];
        # DMARC, monitor-only (`p=none`)
        "_dmarc" = [
          {
            type = "TXT";
            ttl = 300;
            value = "v=DMARC1\\; p=none\\; rua=mailto:postmaster@${domainNoDot}";
          }
        ];
        # IPv4-only on purpose: game ports are only DNAT'd over IPv4 on the vps,
        # so an AAAA would break IPv6-preferring clients
        minecraft = [
          {
            type = "A";
            ttl = 300;
            value = vpsPublicIp;
          }
        ];
        factorio = [
          {
            type = "A";
            ttl = 300;
            value = vpsPublicIp;
          }
        ];
        # SRV so players connect by hostname without ":port" (factorio >= 1.1.67)
        "_factorio._udp.factorio" = [
          {
            type = "SRV";
            ttl = 300;
            value = {
              priority = 0;
              weight = 0;
              port = 34197;
              target = "factorio.${domainNoDot}.";
            };
          }
        ];
      };

      yamlFormat = pkgs-unstable.formats.yaml { };
      domainNoDot = lib.removeSuffix "." domain;
      zoneFileName = "${domainNoDot}.yaml";
      zoneFile = yamlFormat.generate zoneFileName zoneRecords;
      # octoDNS's YamlProvider wants a directory with `<zone-without-trailing-dot>.yaml`
      zoneDir = pkgs-unstable.linkFarm "octodns-zones" [
        {
          name = zoneFileName;
          path = zoneFile;
        }
      ];

      octodnsConfig = yamlFormat.generate "octodns-config.yaml" {
        providers = {
          config = {
            class = "octodns.provider.yaml.YamlProvider";
            directory = "${zoneDir}";
            default_ttl = 300;
            enforce_order = false;
          };
          cloudflare = {
            class = "octodns_cloudflare.CloudflareProvider";
            token = "env/CLOUDFLARE_TOKEN";
            # the scoped DNS-edit token lacks Page Rules permission; the default
            # pagerules call 403s and is misreported as a DNS auth failure
            pagerules = false;
          };
        };
        zones."${domain}" = {
          sources = [ "config" ];
          targets = [ "cloudflare" ];
        };
      };

      octodnsEnv = pkgs-unstable.python3.withPackages (_: [ pkgs-unstable.octodns-providers.cloudflare ]);
    in
    {
      config = lib.mkIf enable {
        users.users.octodns = {
          isSystemUser = true;
          group = "octodns";
        };
        users.groups.octodns = { };

        sops.secrets.cloudflare_octodns_token = {
          owner = "octodns";
          group = "octodns";
        };
        sops.templates."octodns-env" = {
          owner = "octodns";
          group = "octodns";
          content = ''
            CLOUDFLARE_TOKEN=${config.sops.placeholder.cloudflare_octodns_token}
          '';
        };

        systemd.services.octodns-sync = {
          description = "octoDNS: sync declared DNS records to Cloudflare";
          serviceConfig = {
            Type = "oneshot";
            User = "octodns";
            Group = "octodns";
            EnvironmentFile = config.sops.templates."octodns-env".path;
            ExecStart = "${octodnsEnv}/bin/octodns-sync --config-file=${octodnsConfig} --doit";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectKernelLogs = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            RestrictNamespaces = true;
            PrivateTmp = true;
            # this unit holds the token controlling the whole zone
            PrivateDevices = true;
            CapabilityBoundingSet = "";
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            SystemCallArchitectures = "native";
          };
        };

        systemd.timers.octodns-sync = {
          description = "Run octodns-sync periodically";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5m";
            OnUnitActiveSec = "1h";
            Persistent = true;
          };
        };
      };
    };
}
