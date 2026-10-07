{ config, ... }:
let
  homeManagerModules = config.flake.modules.homeManager;
in
{
  flake.modules.nixos."profile-server" =
    {
      pkgs,
      ...
    }:
    {
      environment.systemPackages = with pkgs; [
      ];

      #security
      # lock down nix
      nix.settings.allowed-users = [ "root" ];
      # disable sudo
      security.sudo.enable = false;

      # audit log of every executed command; /var/log is in each host's
      # persistence list, else impermanence wipes it
      security.auditd.enable = true;
      security.audit.enable = true;
      security.audit.rules = [ "-a exit,always -F arch=b64 -S execve" ];

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
        home.username = "root";
        programs.home-manager.enable = true;
        home.homeDirectory = "/root";
      };

      # sops shh keypath
      sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

      # disable laptop lid power
      services.logind.settings.Login.HandleLidSwitch = "ignore";
    };
}
