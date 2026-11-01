{ config, ... }:
let
  homeManagerModules = config.flake.modules.homeManager;
in
{
  flake.modules.nixos."profile-server" = _: {
    # nh, nix helper
    programs.nh = {
      flake = "/etc/nixos";
    };

    # home-manager
    home-manager.users.root = {
      imports = [
        homeManagerModules.tooling
        homeManagerModules.tmux
      ];
      home.stateVersion = "23.11";
    };

    # disable laptop lid power
    services.logind.settings.Login.HandleLidSwitch = "ignore";
  };
}
