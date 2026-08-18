{
  config,
  lib,
  vars,
  pkgs-unstable,
  ...
}:
let
  # Disabled until the vps is provisioned and a real Cloudflare token
  # exists (see docs/TODO-vps-manual-steps.md) — flip to `true` once that's
  # done, rather than leaving a service pointed at a placeholder IP
  # live.
  enable = false;

  # Everything octoDNS needs is generated from these two values instead
  # of checked-in YAML — the zone data and octoDNS's own config file are
  # both build-time-rendered Nix. `domain` is the single source of truth
  # (also consumed by hosts/vps/configuration.nix) — see flake.nix's
  # `vars`.
  domain = vars.domain;
  vpsPublicIp = "REPLACE_WITH_VPS_PUBLIC_IP"; # TODO: fill in once the vps is provisioned

  # Only jellyfin, minecraft, and factorio are meant to be publicly
  # reachable (see hosts/vps/README.md).
  zoneRecords = {
    "" = [
      {
        type = "A";
        ttl = 300;
        value = vpsPublicIp;
      }
    ];
    jellyfin = [
      {
        type = "CNAME";
        ttl = 300;
        value = domain;
      }
    ];
    # minecraft/factorio clients connect via ip:port, not domain, but a
    # record still makes it easier to hand out a hostname instead of a
    # raw IP.
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
  };

  yamlFormat = pkgs-unstable.formats.yaml { };
  domainNoDot = lib.removeSuffix "." domain;
  zoneFileName = "${domainNoDot}.yaml";
  zoneFile = yamlFormat.generate zoneFileName zoneRecords;
  # octoDNS's YamlProvider wants a directory containing a file named
  # exactly `<zone-without-trailing-dot>.yaml`.
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
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        PrivateTmp = true;
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
}
