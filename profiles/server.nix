{
  pkgs,
  lib,
  ...
}:
{
  environment.systemPackages = with pkgs; [
  ];

  services.networkd-dispatcher = {
    enable = true;
    rules."50-tailscale" = {
      onState = [ "routable" ];
      script = ''
        ${lib.getExe pkgs.ethtool} -K enp3s0 rx-udp-gro-forwarding on rx-gro-list off
      '';
    };
  };

  # allow caddy to modify tailscale
  services.tailscale.permitCertUid = "caddy";

  #security
  # lock down nix
  nix.settings.allowed-users = [ "root" ];
  # disable sudo
  security.sudo.enable = false;

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
