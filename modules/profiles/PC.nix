{ config, ... }:
let
  nixosModules = config.flake.modules.nixos;
in
{
  flake.modules.nixos."profile-pc" = {
    imports = [
      nixosModules.base
      nixosModules.tooling
      nixosModules."agent-tools"
      nixosModules."virtual-machines"
      nixosModules.keyboards
      nixosModules.kde
      nixosModules."desktop-apps"
      nixosModules."desktop-user"
      nixosModules."desktop-theme"
      nixosModules.yubikey
      nixosModules."kde-connect"
      nixosModules.bluetooth
      nixosModules.printing
      nixosModules."desktop-audio"
      nixosModules.steam
      nixosModules.mullvad
    ];
  };
}
