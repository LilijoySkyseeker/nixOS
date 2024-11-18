{ ... }: {
  # networking
  services.caddy.virtualHosts."minecraft.skyseekerhomelab.duckdns.org".extraConfig =
    ''
      reverse_proxy localhost:25565
    '';
  networking.firewall.allowedTCPPorts = [ 25565 ];
  networking.firewall.allowedUDPPorts = [ 25565 ];

  # persistence
  environment.persistence."/nix/state".directories = [{
    directory = "/srv/minecraft/vanilla-plus";
    #     inherit user group;
  }];

  # mc server
  virtualisation.oci-containers.containers.minecraft-vanilla-plus = {
    autoStart = true;
    image = "itzg/minecraft-server";
    ports = [ "25565:25565" ];
    environment = {
      VERSION = "1.20.4";
      EULA = "TRUE";
      MEMORY = "2G";
      USE_AIKAR_FLAGS = "TRUE";
      TYPE = "FABRIC";
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
        lithium
        no-chat-reports
        krypton
        c2me-fabric
        vmp-fabric
        servux
        memoryleakfix
        ferrite-core
        easy-shulker-boxes
        carpet
        enchant-tweaker
        bluemap
      '';
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
