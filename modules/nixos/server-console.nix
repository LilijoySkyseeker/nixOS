{ config, ... }:
let
  nixosModules = config.flake.modules.nixos;
  homeManagerModules = config.flake.modules.homeManager;
in
{
  flake.modules.nixos."server-console" = _: {
    imports = [ nixosModules."login-summary" ];

    programs.nh = {
      flake = "/etc/nixos";
    };

    home-manager.users.root = {
      imports = [
        homeManagerModules.tooling
        homeManagerModules.tmux
      ];
      home.stateVersion = "23.11";
      # a persisted directory (vars.rootShellState): bash renames over the file on
      # write, which a bind-mounted file refuses
      programs.bash.historyFile = "/root/.local/state/bash/history";
    };

    services.logind.settings.Login.HandleLidSwitch = "ignore";

    sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
}
