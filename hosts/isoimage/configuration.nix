{
  pkgs,
  modulesPath,
  vars,
  config,
  ...
}:
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

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # drivers
  boot.extraModulePackages = with config.boot.kernelPackages; [ r8125 ];
  boot.kernelModules = [ "r8125" ];

  # TEMP BYPASS FOR 'r8125' driver
  nixpkgs.config.allowBroken = true;

  # ssh server
  users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;
  services.openssh = {
    ports = [ 22 ];
    allowSFTP = true;
    enable = true;
    settings.KbdInteractiveAuthentication = false;
    extraConfig = ''
      passwordAuthentication = no
      PermitRootLogin = prohibit-password
      AllowTcpForwarding yes
      X11Forwarding no
      AllowAgentForwarding no
      AllowStreamLocalForwarding no
      AuthenticationMethods publickey
      PermitTunnel no
    '';
  };
}
