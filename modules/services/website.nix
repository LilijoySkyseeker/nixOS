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
      statusDir = "/var/lib/website-status";
      # homelab's end of the vps tunnel
      wgAddress = "10.100.0.2";
      domain = lib.removeSuffix "." vars.domain;

      # a friend who opens a game server's address in a browser: show them how to connect
      gameOops = game: ''
        bind ${wgAddress}
        redir https://${domain}/oops/${game}/ 302
      '';

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
            root * ${statusDir}
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
        virtualHosts."minecraft.${domain}".extraConfig = gameOops "minecraft";
        virtualHosts."factorio.${domain}".extraConfig = gameOops "factorio";
        virtualHosts."hytale.${domain}".extraConfig = gameOops "hytale";
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
      # its own user, so evaluating the site's flake can't read anything root-only
      users.users.website = {
        isSystemUser = true;
        group = "website";
      };
      users.groups.website = { };
      # profile-server allows root only; this adds the deploy user (the lists merge)
      nix.settings.allowed-users = [ "website" ];
      systemd.services.website-deploy = {
        description = "Build skyseekerlabs.net from main and publish it";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = with pkgs-stable; [
          git
          nix
          coreutils
          findutils
        ];
        environment = {
          REPO_URL = repoUrl;
          NIX_REMOTE = "daemon";
          HOME = stateDir;
        };
        script = ''
          set -euo pipefail
          mirror="$STATE_DIRECTORY/mirror.git"
          builds="$STATE_DIRECTORY/builds"
          mkdir -p "$builds"
          [ -d "$mirror/objects" ] || git init -q --bare "$mirror"
          git -C "$mirror" fetch -q --prune "$REPO_URL" "+refs/heads/main:refs/heads/main"
          rev=$(git -C "$mirror" rev-parse refs/heads/main)
          case "$rev" in
            "" | *[!0-9a-f]*) echo "Not a revision: '$rev'" >&2; exit 1 ;;
          esac

          if [ "$(readlink "$STATE_DIRECTORY/current" 2>/dev/null || true)" = "builds/$rev" ] && [ -e "$builds/$rev" ]; then
            exit 0
          fi

          # each build's out-link is its GC root and is never renamed
          nix build --no-write-lock-file --out-link "$builds/$rev" "git+file://$mirror?ref=main&rev=$rev"

          # a symlink in the output could point caddy at any file it can read
          if [ -n "$(find "$builds/$rev/" -type l -print -quit)" ]; then
            echo "Build $rev contains symlinks; not publishing it." >&2
            rm -f "$builds/$rev"
            exit 1
          fi

          ln -sfn "builds/$rev" "$STATE_DIRECTORY/current.new"
          mv -T "$STATE_DIRECTORY/current.new" "$STATE_DIRECTORY/current"
          touch "$STATE_DIRECTORY/deployed"
          # keep the live build and the one before it; older roots go, and gc takes them
          ls -1t "$builds" | tail -n +3 | while read -r old; do rm -f "$builds/$old"; done
          echo "Published $rev."
        '';
        serviceConfig = {
          Type = "oneshot";
          User = "website";
          Group = "website";
          StateDirectory = "website";
          # caddy reads current/ from here
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
          [ -e ${stateDir}/deployed ] && deployed="\"$(date -u -d "@$(stat -c %Y ${stateDir}/deployed)" +%Y-%m-%dT%H:%M:%SZ)\""
          # mtime is the deployed nixpkgs' date (myPullDeploy)
          nixpkgs_days=$(days_since /var/lib/pull-deploy/nixpkgs-date)
          printf '{"uptime_days": %s, "deployed": %s, "nixpkgs_days": %s}\n' \
            "$uptime_days" "$deployed" "$nixpkgs_days" > "$STATE_DIRECTORY/status.json.tmp"
          mv "$STATE_DIRECTORY/status.json.tmp" "$STATE_DIRECTORY/status.json"
        '';
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "website-status";
          # caddy serves status.json from here
          StateDirectoryMode = "0755";
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateNetwork = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ statusDir ];
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
