{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos.hytale =
    { pkgs, ... }:
    let
      dir = "/srv/hytale";

      # first-install seed only: `--bootstrap` downloads the current release
      # itself and the server self-updates from then on, so this never needs a bump
      seedJar = pkgs.fetchurl {
        url = "https://maven.hytale.com/release/com/hypixel/hytale/Server/0.7.2/Server-0.7.2.jar";
        hash = "sha256-I/cfA3Y0Is58BN8ZHbSc0OfYfUOxK6rXXEP9wgJBCv8=";
      };

      # read by the upstream start.sh; the official minimum. raise with
      # player count or view radius, keeping it well under MemoryMax
      jvmOptions = pkgs.writeText "hytale-jvm.options" ''
        -Xmx4G
      '';
    in
    {
      users.users.hytale = {
        isSystemUser = true;
        group = "hytale";
        home = dir;
      };
      users.groups.hytale = { };

      # networking: tailnet and wg0 (vps's DNAT'd game port) only; the LAN NIC
      # has a public IPv6. a native service, so these INPUT rules do apply
      # (no myDockerPublishGuard entry needed)
      networking.firewall.interfaces.tailscale0.allowedUDPPorts = [
        5520 # hytale (QUIC)
      ];
      networking.firewall.interfaces.wg0.allowedUDPPorts = [
        5520 # hytale (QUIC)
      ];

      # persistence; holds auth.enc (the server's account tokens), so owner-only
      environment.persistence.${vars.persistRoot}.directories = [
        {
          directory = dir;
          user = "hytale";
          group = "hytale";
          mode = "0700";
        }
      ];

      # server console: `echo '/auth status' > /run/hytale.stdin` as root,
      # output in `journalctl -u hytale`
      systemd.sockets.hytale = {
        bindsTo = [ "hytale.service" ];
        socketConfig = {
          ListenFIFO = "/run/hytale.stdin";
          SocketMode = "0600";
          SocketUser = "hytale";
          SocketGroup = "hytale";
          RemoveOnStop = true;
          FlushPending = true;
        };
      };

      systemd.services.hytale = {
        description = "Hytale dedicated server";
        wantedBy = [ "multi-user.target" ];
        requires = [ "hytale.socket" ];
        after = [
          "hytale.socket"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        # start.sh needs bash, java and coreutils on PATH
        path = with pkgs; [
          bash
          coreutils
          jdk25_headless
        ];

        # the server writes config.json itself, so patch the fields we own
        # before each start; unlisted fields are left as-is. no file yet means
        # the bootstrap install hasn't run
        preStart = ''
          ln -sfn ${jvmOptions} jvm.options
          settings=Server/config.json
          if [ -f "$settings" ]; then
            ${pkgs.jq}/bin/jq \
              '.Update.AutoApplyMode = "WhenEmpty"
               | .MaxViewRadius = 12
               | .RequireJoinPermission = true' \
              "$settings" >"$settings.tmp"
            mv "$settings.tmp" "$settings"
          fi
        '';

        # first start (no start.sh yet): run the seed jar in bootstrap mode,
        # which waits on the console for `/auth login device` and
        # `/update setup`, installs the real server and exits; Restart= then
        # brings it back through start.sh, which applies staged self-updates
        script = ''
          if [ -f start.sh ]; then
            exec bash start.sh
          fi
          install -m 0644 ${seedJar} HytaleServer.jar
          # bootstrap mode crashes creating a missing permissions.json (0.7.1
          # and 0.7.2, "Stream closed"); an existing one is read instead
          [ -e permissions.json ] || echo '{}' >permissions.json
          exec java -jar HytaleServer.jar --bootstrap
        '';

        serviceConfig = {
          User = "hytale";
          Group = "hytale";
          WorkingDirectory = dir;
          StandardInput = "socket";
          StandardOutput = "journal";
          StandardError = "journal";
          Restart = "always";
          RestartSec = "10s";
          # SIGTERM runs the server's shutdown hook, which saves the worlds and
          # the JVM then exits 143; without this every stop is a failed unit
          # (and an alert)
          TimeoutStopSec = "120s";
          SuccessExitStatus = [ 143 ];

          # MemoryMax: no game server may exceed 50% of host memory (homelab:
          # 15.5 GiB), same bound as the containers; a blast-radius bound, not
          # a tuned figure. TasksMax matches minecraft's --pids-limit
          MemoryMax = "7G";
          TasksMax = 1024;

          UMask = "0077";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ dir ];
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          ProtectHostname = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          # no MemoryDenyWriteExecute: the JVM's JIT needs W+X pages
          CapabilityBoundingSet = "";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
            "AF_NETLINK"
          ];
          SystemCallArchitectures = "native";
          SystemCallFilter = [ "@system-service" ];
        };
      };
    };
}
