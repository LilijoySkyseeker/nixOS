{ config, pkgs, pkgs-unstable, inputs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos/shared.nix
  ];


  ];
}
