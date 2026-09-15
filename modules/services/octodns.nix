{ ... }:
{
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

      # Everything octoDNS needs is generated from these two values instead
      # of checked-in YAML — the zone data and octoDNS's own config file are
      # both build-time-rendered Nix. `domain` is the single source of truth
      # (also consumed by hosts/vps/configuration.nix) — see flake vars.
      domain = vars.domain;
      vpsPublicIp = "137.184.45.18";
      # Same droplet's public IPv6 — already in use as the WireGuard peer
      # endpoint in hosts/homelab/configuration.nix.
      vpsPublicIp6 = "2604:a880:4:1d0:0:3:5045:8000";

      # Only jellyfin, minecraft, and factorio are meant to be publicly
      # reachable (see hosts/vps/README.md). The mail records below are
      # separate: they point at Google Workspace, not at the vps.
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
          # Google Workspace mail. One MX record, not the five
          # aspmx.l.google.com ones — those are the pre-2023 shape, kept
          # only on domains that already had them.
          {
            type = "MX";
            ttl = 300;
            value = {
              preference = 1;
              exchange = "smtp.google.com.";
            };
          }
          # SPF and the site-verification token are one record with two
          # values, not two records: a duplicate name+type is an error
          # here, since populate_should_replace defaults to false.
          # plan: 2026-09-15-re-add-google-workspace-mail-dns-records-to-octodns.md#G2
          {
            type = "TXT";
            ttl = 300;
            values = [
              "v=spf1 include:_spf.google.com ~all"
              "google-site-verification=rC01szyAkLHzaXQ9BS69zEDh0sW9Z2k7inhCN9LgWxs"
            ];
          }
        ];
        # DKIM public key, issued by the Workspace admin console (Gmail >
        # Authenticate email). Public by definition — it is published in
        # DNS; the private half stays with Google. 408 chars, so octoDNS
        # splits it across DNS's 255-byte strings on push. The `\;` escapes
        # are required: octoDNS rejects bare semicolons in a TXT value and
        # the Cloudflare provider unescapes them again on the way out.
        # plan: 2026-09-15-re-add-google-workspace-mail-dns-records-to-octodns.md#G1
        "google._domainkey" = [
          {
            type = "TXT";
            ttl = 300;
            value = "v=DKIM1\\;k=rsa\\;p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsonrfzXTCC2+UEvz952v6fJgq6V/dUzIzORTEogwWdoBQHotImyklUGvhGhimwx49P4jDd+IezTeA7spO+EZpepXPidYPrDyzOnqtYyjgCM6z4SrD4RFGIcmtAIcVxYw8uy0LQ/L1L4JHxNf83LGQSRQpGo5HFwbwvAPsVCsE+t4CjFCIbWOlZuvHIuOLApKjrmYT2OBiu6jScKZvAiFTB98c9zJe7Arsws7SrSC41O0S5P/4v6bLCMq524TGiuVWPAJnvrJYJqXzj8nWfkqkZ5tVe/KeJi32pCGevfh1eGXU+IThT27Wcgl6QferAtYs10U/KiVMNRUV/Zeu+4IXwIDAQAB";
          }
        ];
        # Monitor-only to start: p=none delivers everything and only
        # collects reports, so a misconfiguration can't bounce real mail.
        # Tighten to quarantine and then reject once reports come back
        # clean. rua stays on this domain so no external-reporting
        # authorization record is needed; postmaster@ is a Workspace
        # reserved word, so it only exists as a Group, never a user.
        # plan: 2026-09-15-re-add-google-workspace-mail-dns-records-to-octodns.md#D1
        "_dmarc" = [
          {
            type = "TXT";
            ttl = 300;
            value = "v=DMARC1\\; p=none\\; rua=mailto:postmaster@${domainNoDot}";
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
        # factorio: one server, one name. The old/new split (`old.factorio`
        # and `new.factorio`, plus their SRV records) was removed
        # 2026-08-27 when the second server was retired — these records
        # are declarative, so octodns-sync retires the stale names from
        # Cloudflare on its next run rather than leaving them dangling at
        # the vps.
        factorio = [
          {
            type = "A";
            ttl = 300;
            value = vpsPublicIp;
          }
        ];
        # SRV record so players can connect with just the hostname (no
        # ":port" suffix) — Factorio has supported DNS SRV lookup for this
        # since 1.1.67.
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
    };
}
