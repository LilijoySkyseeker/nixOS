{
  config,
  lib,
  vars,
  pkgs-unstable,
  ...
}:
let
  enable = true;

  # Everything octoDNS needs is generated from these two values instead
  # of checked-in YAML — the zone data and octoDNS's own config file are
  # both build-time-rendered Nix. `domain` is the single source of truth
  # (also consumed by hosts/vps/configuration.nix) — see flake.nix's
  # `vars`.
  domain = vars.domain;
  vpsPublicIp = "137.184.45.18";
  # Same droplet's public IPv6 — already in use as the WireGuard peer
  # endpoint in hosts/homelab/configuration.nix.
  vpsPublicIp6 = "2604:a880:4:1d0:0:3:5045:8000";

  # Only jellyfin, minecraft, and factorio are meant to be publicly
  # reachable (see hosts/vps/README.md).
  zoneRecords = {
    "" = [
      {
        type = "A";
        ttl = 300;
        value = vpsPublicIp;
      }
      {
        type = "AAAA";
        ttl = 300;
        value = vpsPublicIp6;
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
    # raw IP. IPv4-only, deliberately: these ports are only DNAT'd
    # through to homelab over IPv4 (net.ipv6.conf.all.forwarding is
    # explicitly off on the vps, see hosts/vps/configuration.nix, and
    # there are no ip6tables DNAT rules for them either) — an AAAA
    # record here would advertise reachability that doesn't exist and
    # silently break any client that prefers IPv6 when a hostname
    # resolves to both (confirmed live: a Bedrock client could connect
    # to the raw IPv4 address fine but not to the hostname). The apex
    # keeps its AAAA record since that's Caddy running directly on the
    # vps — native IPv6, no forwarding involved.
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
        # We don't use Cloudflare page rules, and the scoped DNS-edit
        # token doesn't have Page Rules permission — without this,
        # octodns-cloudflare's default pagerules=true makes an extra
        # GET /zones/{id}/pagerules call that 403s and gets
        # misreported as a DNS auth failure.
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
