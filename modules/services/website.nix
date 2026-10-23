{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos.website =
    {
      lib,
      pkgs-stable,
      ...
    }:
    let
      # public repo, no credentials; only main is ever built
      repoUrl = "https://github.com/LilijoySkyseeker/skyseekerlabs.net.git";
      stateDir = "/var/lib/website";
      # homelab's end of the vps tunnel
      wgAddress = "10.100.0.2";
      domain = lib.removeSuffix "." vars.domain;

      # the site loads nothing from third parties
      securityHeaders = ''
        header {
          Content-Security-Policy "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
          X-Content-Type-Options nosniff
          Referrer-Policy strict-origin-when-cross-origin
          Permissions-Policy "camera=(), microphone=(), geolocation=(), interest-cohort=()"
          # no includeSubDomains: the game hostnames aren't HTTPS
          Strict-Transport-Security "max-age=86400"
          -Server
        }
      '';
    in
    {
      # caddy: the public site, ACME through the vps's 80/443 DNAT
      services.caddy = {
        enable = true;
        package = pkgs-stable.caddy;
        # no HTTP/3: the vps doesn't forward UDP 443
        globalConfig = ''
          servers {
            protocols h1 h2
          }
        '';
        virtualHosts.${domain}.extraConfig = ''
          bind ${wgAddress}
          encode zstd gzip
          ${securityHeaders}
          # written by website-status, read by the page's status stickers
          handle /status.json {
            root * ${stateDir}
            header Cache-Control "no-store"
            file_server
          }
          handle {
            root * ${stateDir}/current
            file_server
          }
          handle_errors 404 {
            root * ${stateDir}/current
            rewrite * /404.html
            file_server
          }
        '';
        virtualHosts."www.${domain}".extraConfig = ''
          bind ${wgAddress}
          redir https://${domain}{uri} permanent
        '';
      };
      # the bind address only exists once wg0 is up
      systemd.services.caddy = {
        after = [ "wireguard-wg0.service" ];
        wants = [ "wireguard-wg0.service" ];
      };
      # tunnel only: the LAN NIC carries a public IPv6
      networking.firewall.interfaces.wg0.allowedTCPPorts = [
        80
        443
      ];

      # website-deploy: build main's newest commit and swap it in
      # root because profile-server's allowed-users is root only; build-only, so fully sandboxed
      systemd.services.website-deploy = {
        description = "Build skyseekerlabs.net from main and publish it";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = with pkgs-stable; [
          git
          nix
          coreutils
        ];
        environment = {
          REPO_URL = repoUrl;
          NIX_REMOTE = "daemon";
          HOME = stateDir;
        };
        script = ''
          set -euo pipefail
          mirror="$STATE_DIRECTORY/mirror.git"
          [ -d "$mirror/objects" ] || git init -q --bare "$mirror"
          git -C "$mirror" fetch -q --prune "$REPO_URL" "+refs/heads/main:refs/heads/main"
          rev=$(git -C "$mirror" rev-parse refs/heads/main)
          case "$rev" in
            "" | *[!0-9a-f]*) echo "Not a revision: '$rev'" >&2; exit 1 ;;
          esac

          if [ "$(cat "$STATE_DIRECTORY/rev" 2>/dev/null || true)" = "$rev" ] && [ -e "$STATE_DIRECTORY/current" ]; then
            exit 0
          fi

          # the out-link is the GC root; mv -T swaps it in atomically
          nix build --no-write-lock-file --out-link "$STATE_DIRECTORY/next" "git+file://$mirror?ref=main&rev=$rev"
          mv -T "$STATE_DIRECTORY/next" "$STATE_DIRECTORY/current"
          echo "$rev" > "$STATE_DIRECTORY/rev"
          touch "$STATE_DIRECTORY/deployed"
          echo "Published $rev."
        '';
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "website";
          # caddy reads current/ and status.json from here
          StateDirectoryMode = "0755";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ stateDir ];
          ProtectHome = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          RestrictNamespaces = true;
        };
      };
      systemd.timers.website-deploy = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "5min";
        };
      };

      # website-status: the numbers behind the status stickers
      systemd.services.website-status = {
        description = "Write the site's status.json";
        path = with pkgs-stable; [ coreutils ];
        script = ''
          set -euo pipefail
          now=$(date +%s)
          days_since() { [ -e "$1" ] && echo $(( (now - $(stat -c %Y "$1")) / 86400 )) || echo null; }
          uptime_days=$(( $(cut -d. -f1 /proc/uptime) / 86400 ))
          deployed=null
          [ -e "$STATE_DIRECTORY/deployed" ] && deployed="\"$(date -u -d "@$(stat -c %Y "$STATE_DIRECTORY/deployed")" +%Y-%m-%dT%H:%M:%SZ)\""
          # mtime is the deployed nixpkgs' date (myPullDeploy)
          nixpkgs_days=$(days_since /var/lib/pull-deploy/nixpkgs-date)
          printf '{"uptime_days": %s, "deployed": %s, "nixpkgs_days": %s}\n' \
            "$uptime_days" "$deployed" "$nixpkgs_days" > "$STATE_DIRECTORY/status.json.tmp"
          mv "$STATE_DIRECTORY/status.json.tmp" "$STATE_DIRECTORY/status.json"
        '';
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "website";
          StateDirectoryMode = "0755";
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateNetwork = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ stateDir ];
          ProtectHome = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          RestrictNamespaces = true;
        };
      };
      systemd.timers.website-status = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "5min";
        };
      };
    };
}
