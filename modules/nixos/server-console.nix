{ config, ... }:
let
  homeManagerModules = config.flake.modules.homeManager;
in
{
  flake.modules.nixos."server-console" = _: {
    programs.nh = {
      flake = "/etc/nixos";
    };

    home-manager.users.root = {
      imports = [
        homeManagerModules.tooling
        homeManagerModules.tmux
      ];
      home.stateVersion = "23.11";
    };

    services.logind.settings.Login.HandleLidSwitch = "ignore";
  };
}
