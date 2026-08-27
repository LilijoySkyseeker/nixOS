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
          # No `VERSION` here on purpose — VERSION_FROM_MODRINTH_PROJECTS
          # below computes it. Setting both would pin the game version and
          # defeat the point; the image exports its resolved value over
          # whatever VERSION held.
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
          # autopause (SIGSTOP-when-idle, via knockd) deliberately not used:
          # pausing only ever saves CPU, not RAM (a stopped JVM keeps its
          # full heap resident), and this port is public — DNAT'd through
          # vps for friends without Tailscale — so it gets knocked by
          # internet background scanners (confirmed: Oracle Cloud source
          # IPs) every couple minutes regardless of real players. Measured
          # live 2026-08-26: under knockd's default 120s re-pause window,
          # that noise alone kept the JVM resumed ~65-75% of "idle" time,
          # eating most of the CPU savings autopause exists for. Not worth
          # the added complexity/attack surface (knockd needs NET_RAW,
          # which in turn needs no-new-privileges dropped — see git history
          # on this file if reconsidering autopause later).
          # Track the newest Minecraft version that *every* project in
          # MODRINTH_PROJECTS already supports, rather than the newest
          # Minecraft version full stop. This is the upstream feature for
          # "don't move the game ahead of the mods"; before this, VERSION
          # = "LATEST" moved first and the mod set had to catch up, which
          # is the wrong way round. Resolved at each container start by
          # `mc-image-helper version-from-modrinth-projects`
          # (scripts/start-configuration:196-207), and it **fails closed**
          # — an unresolvable set aborts startup rather than falling back
          # to a version the mods do not support.
          VERSION_FROM_MODRINTH_PROJECTS = "true";
          # `alpha` is load-bearing, not laziness: mod releases lag game
          # releases, so restricting to `release` would hold the server on
          # an old Minecraft version for as long as any one mod had only a
          # pre-release build out.
          #
          # Must be spelled MODRINTH_PROJECTS_DEFAULT_VERSION_TYPE, not
          # the legacy MODRINTH_ALLOWED_VERSION_TYPE. Both still work for
          # *downloading* mods (start-setupModpack:286 keeps the old name
          # as an alias), but the version resolver above reads only the
          # new name (start-configuration:198-200). Under the legacy name
          # the two halves silently disagree: mods resolve at `alpha`
          # while the game version resolves at the default `release`.
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
          "--security-opt=no-new-privileges:true"
        ];
      };
    };
}
