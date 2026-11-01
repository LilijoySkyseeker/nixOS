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
      # vps's end: its SNAT makes every visitor arrive from here
      vpsWgAddress = "10.100.0.1";
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
        # Go 1.27: stable's go 1.26.8 lacks 1.26.9's net/http and net/textproto fixes
        # TODO: drop when NixOS/nixpkgs#571809 (go 1.26.9) is in nixos-26.05
        package = pkgs-stable.caddy.override { buildGoModule = pkgs-stable.buildGo127Module; };
        # no HTTP/3: the vps doesn't forward UDP 443
        # no HTTP/2: caddy 2.11.7's vendored x/net 0.59 has the HTTP/2 server DoS bugs
        # TODO: drop when a caddy release with caddyserver/caddy#8179 (x/net 0.60) is in nixos-26.05, and restore h2
        # admin API on a socket only caddy can reach, so the sandbox can deny loopback
        globalConfig = ''
          admin unix//run/caddy/admin.sock
          servers {
            protocols h1
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
      };
      # the bind address only exists once wg0 is up
      systemd.services.caddy = {
        after = [ "wireguard-wg0.service" ];
        wants = [ "wireguard-wg0.service" ];
      };
      # caddy: sandbox on top of the upstream unit's NoNewPrivileges, PrivateTmp, ProtectSystem=full
      systemd.services.caddy.serviceConfig = {
        RuntimeDirectory = "caddy";
        RuntimeDirectoryMode = "0700";
        ProtectSystem = "strict";
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        SystemCallErrorNumber = "EPERM";
        # upstream also grants CAP_NET_ADMIN, for HTTP/3's UDP buffers; HTTP/3 is off
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        AmbientCapabilities = [
          ""
          "CAP_NET_BIND_SERVICE"
        ];
        # public internet only: no LAN, tailnet, docker, loopback services or IPv6
        IPAddressDeny = [
          "0.0.0.0/8"
          "10.0.0.0/8"
          "100.64.0.0/10"
          "127.0.0.0/8"
          "169.254.0.0/16"
          "172.16.0.0/12"
          "192.168.0.0/16"
          "224.0.0.0/3"
          "::/0"
        ];
        IPAddressAllow = [
          vpsWgAddress
          # systemd-resolved's stub, for ACME's lookups
          "127.0.0.53"
        ];
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
