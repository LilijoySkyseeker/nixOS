{pkgs, modulesPath, vars, ...}:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    "${modulesPath}/installer/cd-dvd/channel.nix"
  ];
  nixpkgs.hostPlatform = "x86_64-linux";

  environment.systemPackages = with pkgs; [
    neovim
    disko
    parted
    git
  ];

  nix.settings.experimental-features = ["nix-command" "flakes" ];

  users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;

}
