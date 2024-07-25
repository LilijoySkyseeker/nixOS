{
  pkgs,
  modulesPath,
  vars,
  ...
}: {
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

  nix.settings.experimental-features = ["nix-command" "flakes"];

  # ssh server
  users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;
  services.openssh = {
    ports = [ 2222 ];
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
