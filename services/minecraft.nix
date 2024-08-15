{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  
# import for some reason
  imports = [ inputs.nix-minecraft.nixosModules.minecraft-servers ];
  nixpkgs.overlays = [inputs.nix-minecraft.overlay];

  # networking
  services.caddy.virtualHosts."minecraft.skyseekerhomelab.duckdns.org".extraConfig = ''
    reverse_proxy localhost:25566
  '';
  networking.firewall.allowedTCPPorts = [
    25565
  ];
  networking.firewall.allowedUDPPorts = [
    25565
  ];

  # persistence
  environment.persistence."/nix/state".directories = with config.services.minecraft-servers; [
    {
      directory = dataDir;
      inherit user group;
    }
  ];

  # mc servers
  services.minecraft-servers = {
    enable = true;
    eula = true;
    servers = {
      survival = {
        enable = true;
        openFirewall = true;
        package = pkgs.fabricServers.fabric-1_21_1;
        serverProperties = {
          gamemode = "survival";
          difficulty = "hard";
          level-seed = "3522075773609978693";
          enable-command-block = true;
          level-name = "world";
          motd = "GC+Friends Server";
          allow-flight = true;
          force-gamemode = true;
          spawn-protection= 0;
          white-list = false;
        };
        whitelist = {
        };
        jvmOpts = "-Xms2048M -Xmx2048M";
        symlinks = {
          mods = pkgs.linkFarmFromDrvs "mods" (builtins.attrValues {
            C2ME = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/VSNURh3q/versions/eth8wAqz/c2me-fabric-mc1.21.1-0.3.0%2Balpha.0.142.jar";
              sha512 = "a80619d36f9176e62aca1d9a65402d70d708c47ce07c75573dd86d8b668c0272b59fc007e721ffe665c462b8287cc38369c74d76ce4db04f1de90f20edc6d197";
            };
            EasyShulkerBoxes = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/gA5euN8S/versions/bNypwmCo/EasyShulkerBoxes-v21.0.3-1.21-Fabric.jar";
              sha512 = "4d4a8497375f20413284f746a205619c1f1059b0c1817b18ddab010176505880f2f5aaf4b71f3fabc045bddbf24036fc13f96d1a28bac5f99bcd6295b0c9d34c";
            };
            EnchantmentTweaker = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/e4Vpm1dD/versions/NnHrife9/enchanttweaker-1.4.9%2Bmc1.20.3-1.20.4.jar";
              sha512 = "ee921a5ba7235f15b74944b6fe7859a6e991468d3a0d83a07cf6b609e76b38a87537627a350358105d9e1cc16834a28b79d459bcd584d1e91fccb57984225b65";
            };
            FabricAPI = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/bK6OgzFj/fabric-api-0.102.1%2B1.21.1.jar";
              sha512 = "ff058bdb4d30866a34a74ae457da7e981affd130c23887c0c8194c6ecb5023cca353dd7b831326ab33df5c6d3bbfb1d07aa71bbd79dbb30cca5534fd74c5f551";
            };
            Carpet = pkgs.fetchurl {
              url = "https://github.com/gnembon/fabric-carpet/releases/download/1.4.147/fabric-carpet-1.21-1.4.147+v240613.jar";
              sha512 = "e6f33d13406796a34e7598d997113f25f7bea3e55f9d334b73842adda52b2c5d0a86b7b12ac812d7e758861e3f468bf201c6c710c40162bb79d6818938204151";
            };
            FerriteCore = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/uXXizFIs/versions/wmIZ4wP4/ferritecore-7.0.0-fabric.jar";
              sha512 = "0f2f9b5aebd71ef3064fc94df964296ac6ee8ea12221098b9df037bdcaaca7bccd473c981795f4d57ff3d49da3ef81f13a42566880b9f11dc64645e9c8ad5d4f";
            };
            ForgeConfigAPIPort = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/ohNO6lps/versions/gtorYSGm/ForgeConfigAPIPort-v21.1.0-1.21.1-Fabric.jar";
              sha512 = "d3b261d4017c05d25be105a5108b0d9cda6a1cc876858e20adfa78f9d0a704325c839db638a81dcd8b7c096373fd7e58d067c835f3e350df01e81c4383bff72c";
            };
            ItemSwapper = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/RPOSBQgq/versions/gCWWXbDj/itemswapper-fabric-0.7.0-mc1.21.jar";
              sha512 = "6eb7b62d2ba0ec86bbd60fecd9e2f238424f2a4641b01c6de2f9351f41bf41f46daa5e812628489e34a81351a1d44058ce444f821c67d7acf29180a09e666ac6";
            };
            Krypton = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/fQEb0iXm/versions/Acz3ttTp/krypton-0.2.8.jar";
              sha512 = "5f8cf96c79bfd4d893f1d70da582e62026bed36af49a7fa7b1e00fb6efb28d9ad6a1eec147020496b4fe38693d33fe6bfcd1eebbd93475612ee44290c2483784";
            };
            Lithium = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/gvQqBUqZ/versions/5szYtenV/lithium-fabric-mc1.21.1-0.13.0.jar";
              sha512 = "d4bd9a9cc37daad8828aa4fa9ca20e4f89d10e30cf6daf4546ef4cf4a684ba21ea0865a9c23cef9d1f4348e9ba4aca9aaca3db9f99534fc610fa78a5ca0bf151";
            };
            MemoryLeakFix = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/NRjRiSSD/versions/5xvCCRjJ/memoryleakfix-fabric-1.17%2B-1.1.5.jar";
              sha512 = "a7bf7429340d076f4b30602bc714280c3f5cb8e814e76e89296c8155e3355b33304a148e9218378a3383127e95b7ba47402506c687f1d58609704fe8cc60ab93";
            };
            NoChatReports = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/qQyHxfxd/versions/riMhCAII/NoChatReports-FABRIC-1.21-v2.8.0.jar";
              sha512 = "092837afc0fcb5208561062f8e4cd69971efa94c0180ae377e318d35d8f278abbf1552e4a577be882dc7e870f884779bc36caf808c8bc90bb05490f1e034ddb8";
            };
            PuzzlesLib = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/QAGBst4M/versions/Rzc9NmZd/PuzzlesLib-v21.0.22-1.21-Fabric.jar";
              sha512 = "41aa20f19bbecd1f10f120e0fc2aebe587ff99ee8f9a389f616c7e40bdcfc63c18ad73e57dad779fa103168939cf11f62b79c5c182451a342c46ff40389a9931";
            };
            Servux = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/zQhsx8KF/versions/MBfJui8X/servux-fabric-1.21.0-0.2.0.jar";
              sha512 = "650612424dfceb55a194d2dd25eb79585f657d110f89f0659c1006b218ad199e135e9e26c94fb0be151906789d7b8b99b82de17a0306709e24cc0ac4b68045fd";
            };
            ViaFabric = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/YlKdE5VK/versions/dS5UWGlC/ViaFabric-0.4.15%2B78-main.jar";
              sha512 = "cc676d2605c9fc22ad3aa8ae8b784783a6511a603ff019f9a02d382e0f851ba35586930c5d69fbdbac5cfde411aa0b634edc891a62673a3d29a1a0efe93cbfb1";
            };
            VeryManyPlayers = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/wnEe9KBa/versions/PT5DZrQC/vmp-fabric-mc1.21-0.2.0%2Bbeta.7.163-all.jar";
              sha512 = "0449ade761cc4b7dcb51e68907f02211393ea999d4799f79f10750dad84ea263661c002a171c77c90d8a6fe9b8c14effa3d15a6df76436e5f4c7432d8a291383";
            };
          });
          EnchantmentTweaker-config-file = pkgs.writeTextFile {
            name = "config/enchant-tweaker.properties";
            text = ''
              mod_enabled=true
              cheap_names=true
              prior_work_free=true
              axes_not_tools=true
              axe_weapons=true
              better_mending=true
              bow_infinity_fix=true
              god_armor=true
              god_weapons=true
              infinite_mending=true
              loyal_void_tridents=true
              multishot_piercing=true
              shiny_name=true
              trident_weapons=true
            '';
          };
        };
      };
    };
  };
}
