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

      # networking: dropped host-wide allowedTCPPorts/allowedUDPPorts
      # (2026-08-26) — homelab's LAN NIC carries a real public IPv6
      # address (ISP RA-delegated), which turns any host-wide firewall
      # rule into direct internet exposure. These ports only ever
      # legitimately arrive two ways: over the tailnet directly, or over
      # the wg0 tunnel from vps (which is how vps's DNAT'd public game
      # ports actually reach this host — see hosts/vps/configuration.nix's
      # networking.nat.forwardPorts) — scope to just those two interfaces.
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
          VERSION = "LATEST";
          EULA = "TRUE";
          # the entrypoint writes /etc/nsswitch.conf on every start unless told
          # not to; --read-only below makes that write fail, so skip it — the
          # image's default nsswitch config is fine for our use.
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
          # pause the JVM (SIGSTOP) when no clients are connected, resuming on
          # the next connection attempt (knockd watches for it on the
          # container's eth0). Requires max-tick-time disabled below — the
          # server watchdog would otherwise self-kill on resume, since a
          # single tick spans however long the process was paused.
          ENABLE_AUTOPAUSE = "TRUE";
          MAX_TICK_TIME = "-1";
          MODRINTH_ALLOWED_VERSION_TYPE = "alpha";
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
          # RCON isn't published in `ports` below, so it's already
          # unreachable from outside the docker network — this is belt-and-
          # suspenders in case a port ever gets added later without
          # noticing (the itzg image has historically shipped RCON enabled
          # by default with a weak default password).
          ENABLE_RCON = "FALSE";
        };
        environmentFiles = [ config.sops.templates."minecraft-whitelist".path ];
        volumes = [
          "/srv/minecraft/vanilla-plus:/data"
          # overlays Geyser-Fabric/config.yml into /data/config on every start
          # (itzg's /config sync); see modules/services/minecraft-geyser-config for why.
          "${./minecraft-geyser-config}:/config:ro"
        ];
        # container hardening: no capabilities beyond what a JVM needs (none)
        # plus the two the entrypoint needs to drop from root to the
        # "minecraft" user (SETUID/SETGID, via gosu), and a read-only
        # rootfs — everything the itzg entrypoint/JVM actually needs to
        # write lives under /data (already a writable volume) or /tmp
        # (tmpfs below).
        #
        # TROUBLESHOOTING: if the container fails to start or crash-loops
        # after this change, check `docker logs minecraft-vanilla-plus` for
        # "Read-only file system" errors — that means the entrypoint or a
        # mod/plugin writes somewhere outside /data and /tmp that wasn't
        # anticipated here. Fix by adding another `--tmpfs=/path` for that
        # specific directory, not by dropping --read-only outright.
        extraOptions = [
          "--read-only"
          # exec is required: netty and DistantHorizons both extract and run
          # native .so libraries from /tmp at startup — Docker's --tmpfs
          # defaults to noexec unless overridden, which silently broke both
          # (netty falls back to pure-Java, DH's error handler NPEs because
          # the real "library validation" failure it's reporting is itself
          # this noexec block, and that handler assumes a client context).
          "--tmpfs=/tmp:rw,exec,nosuid,nodev,size=1024m"
          "--cap-drop=ALL"
          "--cap-add=SETUID"
          "--cap-add=SETGID"
          # knockd (autopause) sniffs the connection attempt that wakes the
          # paused JVM back up; needs raw-socket access to do that.
          "--cap-add=NET_RAW"
          # deliberately no --security-opt=no-new-privileges here (unlike
          # factorio.nix): itzg's image grants knockd NET_RAW via a build-time
          # `setcap cap_net_raw=ep` file capability (PR itzg/docker-minecraft-
          # server#2625), since gosu's setuid drop to the unprivileged
          # "minecraft" user clears the process's own effective NET_RAW
          # before knockd ever runs. no-new-privileges disables exactly that
          # file-capability-on-exec mechanism (that's its purpose), so with
          # it set knockd fails with "could not open eth0: ... Operation not
          # permitted" and autopause never actually pauses — confirmed live
          # 2026-08-26, root-caused via itzg/docker-minecraft-server#2421/
          # #2625/#2813. Accepted trade-off: --cap-drop=ALL above already
          # limits the bounding set to just SETUID/SETGID/NET_RAW, so
          # dropping no-new-privileges only lets those three (already-
          # granted) capabilities be exercised via setuid/file-cap binaries
          # inside the container — it doesn't let the container acquire
          # anything beyond what --cap-add already grants it.
        ];
      };
    };
}
