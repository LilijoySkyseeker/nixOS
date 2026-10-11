{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos.minecraft =
    { config, ... }:
    {
      sops.secrets.minecraft_username = { };
      sops.templates."minecraft-whitelist".content = ''
        WHITELIST=${config.sops.placeholder.minecraft_username}
        OPS=${config.sops.placeholder.minecraft_username}
      '';

      # networking: tailnet and wg0 (vps's DNAT'd game ports) only; the LAN NIC
      # has a public IPv6. INPUT rules don't constrain docker publishes:
      # myDockerPublishGuard on homelab enforces this list -- change both together
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
        25565
      ];
      networking.firewall.interfaces.tailscale0.allowedUDPPorts = [
        25565
        19132 # Geyser Bedrock listener
      ];
      networking.firewall.interfaces.wg0.allowedTCPPorts = [
        25565
      ];
      networking.firewall.interfaces.wg0.allowedUDPPorts = [
        25565
        19132 # Geyser Bedrock listener
      ];

      # persistence
      environment.persistence.${vars.persistRoot}.directories = [
        {
          directory = "/srv/minecraft/vanilla-plus";
          #     inherit user group;
        }
      ];

      # deny non-owner access to server state; mode only since the owning uid
      # comes from the image (same as factorio.nix)
      systemd.tmpfiles.settings."10-minecraft-state"."/srv/minecraft/vanilla-plus".z.mode = "0700";

      # docker userns-remap ownership migration; 1000 is itzg's baked-in uid
      myDockerUserns.migrations = [
        {
          path = "/srv/minecraft/vanilla-plus";
          uid = 1000;
          gid = 1000;
        }
      ];

      # mc server
      virtualisation.oci-containers.containers.minecraft-vanilla-plus = {
        autoStart = true;
        image = "itzg/minecraft-server";
        ports = [
          "25565:25565"
          "19132:19132/udp" # Geyser Bedrock listener
        ];
        environment = {
          TYPE = "FABRIC";
          # no VERSION: VERSION_FROM_MODRINTH_PROJECTS below computes it
          EULA = "TRUE";
          # the entrypoint's nsswitch.conf write fails under --read-only
          SKIP_NSSWITCH_CONF = "TRUE";
          MEMORY = "4G";
          USE_MEOWICE_FLAGS = "TRUE";
          MOTD = "GC and Friends";
          DIFFICULTY = "hard";
          MODE = "survival";
          FORCE_GAMEMODE = "TRUE";
          ENABLE_COMMAND_BLOCK = "TRUE";
          ALLOW_FLIGHT = "TRUE";
          SPAWN_PROTECTION = "FALSE";
          SEED = "3522075773609978693";
          # no autopause: saves CPU not RAM, internet scanners on the public port
          # keep waking it, and knockd needs NET_RAW (no no-new-privileges)
          # newest game version every MODRINTH_PROJECTS mod supports; resolved at
          # each start, fails closed (aborts startup) if unresolvable
          VERSION_FROM_MODRINTH_PROJECTS = "true";
          # alpha: mod releases lag game releases. must be this name, not legacy
          # MODRINTH_ALLOWED_VERSION_TYPE, which the version resolver ignores
          MODRINTH_PROJECTS_DEFAULT_VERSION_TYPE = "alpha";
          MODRINTH_DOWNLOAD_DEPENDENCIES = "required";
          MODRINTH_PROJECTS = ''
            c2me-fabric
            carpet
            distanthorizons
            easy-shulker-boxes
            ferrite-core
            floodgate
            geyser
            krypton
            lithium
            no-chat-reports
            scalablelux
            servux
            viabackwards
            viafabric
            viarewind
            vmp-fabric
          '';
          ENABLE_WHITELIST = "TRUE";
          # not published anyway; guards a future port addition (weak default password)
          ENABLE_RCON = "FALSE";
        };
        environmentFiles = [ config.sops.templates."minecraft-whitelist".path ];
        volumes = [
          "/srv/minecraft/vanilla-plus:/data"
          # overlays Geyser-Fabric/config.yml into /data/config on every start
          # (itzg's /config sync); see modules/services/minecraft-geyser-config for why
          "${./minecraft-geyser-config}:/config:ro"
        ];
        # container hardening: only SETUID/SETGID (gosu drop to "minecraft") and
        # a read-only rootfs; writes go to /data and the /tmp tmpfs. on
        # "Read-only file system" errors add a --tmpfs for that path, don't
        # drop --read-only
        extraOptions = [
          # --memory: no container may exceed 50% of host memory (homelab: 15.5 GiB).
          # don't size from MEMORY = "4G": that's the heap, RSS runs ~1 GB above it
          "--memory=7g"
          # --pids-limit: ~8x idle peak; modded JVMs spawn more threads under load
          "--pids-limit=1024"
          "--read-only"
          # exec: netty and DistantHorizons load native .so files from /tmp
          "--tmpfs=/tmp:rw,exec,nosuid,nodev,size=1024m"
          "--cap-drop=ALL"
          "--cap-add=SETUID"
          "--cap-add=SETGID"
          "--security-opt=no-new-privileges:true"
        ];
      };
    };
}
