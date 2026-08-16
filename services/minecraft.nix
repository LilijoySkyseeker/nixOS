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
      VERSION = "1.21.4";
      EULA = "TRUE";
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
        # easy-shulker-boxes
        ferrite-core
        # infinitymendingbows
        krypton
        lithium
        no-chat-reports
        scalablelux
        servux
        vmp-fabric
      '';
      ENABLE_WHITELIST = "TRUE";
    };
    environmentFiles = [ config.sops.templates."minecraft-whitelist".path ];
    volumes = [ "/srv/minecraft/vanilla-plus:/data" ];
  };
}
