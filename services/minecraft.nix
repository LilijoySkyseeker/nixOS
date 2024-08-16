{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  # networking
  services.caddy.virtualHosts."minecraft.skyseekerhomelab.duckdns.org".extraConfig = ''
    reverse_proxy localhost:25565
  '';
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

  # rootless docker
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };

  # mc server
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.minecraft-vanilla-plus = {
    autoStart = true;
    image = "itzg/minecraft-server";
    ports = ["25565:25565"];
    environment = {
      EULA = "TRUE";
      VERSION = "1.20";
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
        c2me-fabric
        easy-shulker-boxes
        carpet
        ferrite-core
        itemswapper
        krypton
        lithium
        memoryleakfix
        no-chat-reports
        servux
        viafabric
        vmp-fabric
      '';
      ENABLE_WHITELIST = "TRUE";
      WHITELIST = ''
        LilijoySkyseeker
      '';
    };
    volumes = ["/srv/minecraft/vanilla-plus:/data"];
  };

  #         EnchantmentTweaker-config-file = pkgs.writeTextFile {
  #           name = "config/enchant-tweaker.properties";
  #           text = ''
  #             mod_enabled=true
  #             cheap_names=true
  #             prior_work_free=true
  #             axes_not_tools=true
  #             axe_weapons=true
  #             better_mending=true
  #             bow_infinity_fix=true
  #             god_armor=true
  #             god_weapons=true
  #             infinite_mending=true
  #             loyal_void_tridents=true
  #             multishot_piercing=true
  #             shiny_name=true
  #             trident_weapons=true
}
