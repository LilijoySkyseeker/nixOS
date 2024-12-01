{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
  ];
  environment.systemPackages = with pkgs; [
    flac
  ];

  # nh, nix helper
  programs.nh = {
    flake = "/etc/nixos";
  };

  # home-manager
  home-manager.users.root = {
    imports = [ ../modules/home-manager/tooling.nix ];
    home.stateVersion = "23.11";
    home.username = "root";
    programs.home-manager.enable = true;
    home.homeDirectory = "/root";
  };

  # sops shh keypath
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # disable laptop lid power
  services.logind.lidSwitch = "ignore";
}
