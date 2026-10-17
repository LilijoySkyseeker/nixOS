# the rescue ISO for the USB toolbox stick: `nix build .#rescue-iso`
# not a host, so it's a package here rather than an entry in hosts.nix
{ config, inputs, ... }:
let
  nixosModules = config.flake.modules.nixos;
  rescue = inputs.nixpkgs-unstable.lib.nixosSystem {
    specialArgs = {
      inherit inputs;
      pkgs-unstable = config.flake.pkgsUnstable;
      pkgs-stable = config.flake.pkgsStable;
      inherit (config.flake) vars;
    };
    modules = [
      "${inputs.nixpkgs-unstable}/nixos/modules/installer/cd-dvd/installation-cd-graphical-calamares-plasma6.nix"
      (
        { lib, ... }:
        {
          nixpkgs.hostPlatform = "x86_64-linux";
          nixpkgs.config.allowUnfree = true; # all firmware (hardware.enableAllFirmware)
          isoImage.edition = lib.mkForce "rescue";
          isoImage.appendToMenuLabel = " Rescue";
          # the ISO's own label; Ventoy finds it via root=LABEL=
          isoImage.volumeID = "NIXOS_RESCUE";
        }
      )
      # the image-independent part, also used by tests/rescue-iso.nix
      nixosModules."rescue-iso"
      # the user's own shell and editor, as on the PCs
      nixosModules.tooling
      inputs.nvf.nixosModules.default
    ];
  };
in
{
  flake.rescueIsoSystem = rescue;
  perSystem = _: {
    packages.rescue-iso = rescue.config.system.build.isoImage;
  };
}
