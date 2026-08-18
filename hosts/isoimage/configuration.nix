{
  pkgs-unstable,
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

  environment.systemPackages = with pkgs-unstable; [
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
    # PasswordAuthentication must be set as a structured option, not via
    # extraConfig — NixOS's openssh module renders its own default
    # (PasswordAuthentication yes) *before* extraConfig, and sshd_config
    # uses first-directive-wins, so "passwordAuthentication = no" here
    # was silently overridden and password auth was actually enabled
    # this whole time (confirmed live on vps, which had the identical
    # pattern; fixed there too — see hosts/vps/configuration.nix).
    settings.PasswordAuthentication = false;
    extraConfig = ''
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
