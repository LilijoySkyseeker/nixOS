{ ... }:
{
  # networking
  networking.firewall.allowedTCPPorts = [
    25565
    8100
  ];
  networking.firewall.allowedUDPPorts = [
    25565
    8100
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
      "8100:8100"
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
        bluemap
        c2me-fabric
        carpet
        distanthorizons
        easy-shulker-boxes
        ferrite-core
        infinitymendingbows
        krypton
        lithium
        no-chat-reports
        scalablelux
        servux
        vmp-fabric
      '';
      # enchant-tweaker
      # memoryleakfix
      # viabackwards
      # viafabric
      # viarewind
      ENABLE_WHITELIST = "TRUE";
      WHITELIST = ''
        LilijoySkyseeker
      '';
      OPS = ''
        LilijoySkyseeker
      '';
    };
    volumes = [ "/srv/minecraft/vanilla-plus:/data" ];
  };
}
