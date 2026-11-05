_: {
  flake.modules.nixos."yubikey" = { pkgs-unstable, ... }: {
    environment.systemPackages = [ pkgs-unstable.yubikey-manager ];
    services.pcscd.enable = true;
  };
}
