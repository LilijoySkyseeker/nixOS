{ config, ... }:
{
  sops.secrets.minecraft_username = { };
  sops.templates."minecraft-whitelist".content = ''
    WHITELIST=${config.sops.placeholder.minecraft_username}
    OPS=${config.sops.placeholder.minecraft_username}
  '';

  # networking
  networking.firewall.allowedTCPPorts = [
    25565
  ];
  networking.firewall.allowedUDPPorts = [
    25565
  ];

  # persistence
  environment.persistence."/nix/state".directories = [
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
    ];
    environment = {
      TYPE = "FABRIC";
      VERSION = "26.2";
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
      MODRINTH_ALLOWED_VERSION_TYPE = "alpha";
      MODRINTH_DOWNLOAD_DEPENDENCIES = "required";
      MODRINTH_PROJECTS = ''
        c2me-fabric
        carpet
        distanthorizons
        ferrite-core
        krypton
        lithium
        no-chat-reports
        scalablelux
        servux
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
    volumes = [ "/srv/minecraft/vanilla-plus:/data" ];
    # container hardening: no capabilities beyond what a JVM needs (none)
    # plus the two the entrypoint needs to drop from root to the
    # "minecraft" user (SETUID/SETGID, via gosu), no privilege escalation,
    # and a read-only rootfs — everything the itzg entrypoint/JVM actually
    # needs to write lives under /data (already a writable volume) or /tmp
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
}
