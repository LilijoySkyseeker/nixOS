{ config, inputs, ... }:
let
  nixosModules = config.flake.modules.nixos;
  vars = config.flake.vars;
  pkgsUnstable = config.flake.pkgsUnstable;
  pkgsStable = config.flake.pkgsStable;
in
{
  flake.nixosConfigurations = {
    #==================================================
    thinkpad = inputs.nixpkgs-unstable.lib.nixosSystem {
      specialArgs = {
        inherit inputs;
        pkgs-unstable = pkgsUnstable;
        pkgs-stable = pkgsStable;
        vars = vars;
      };
      modules = [
        ../../hosts/thinkpad/configuration.nix
        nixosModules."profile-pc"
        nixosModules.kde
        nixosModules."pull-deploy"
        nixosModules."nfs-homelab-mounts"
        nixosModules."backup-push"
        nixosModules."zfs-space-guard"
      ];
    };
    #==================================================
    torrent = inputs.nixpkgs-unstable.lib.nixosSystem {
      specialArgs = {
        inherit inputs;
        pkgs-unstable = pkgsUnstable;
        pkgs-stable = pkgsStable;
        vars = vars;
      };
      modules = [
        ../../hosts/torrent/configuration.nix
        nixosModules."profile-pc"
        nixosModules.kde
        nixosModules."pull-deploy"
        nixosModules."nfs-homelab-mounts"
        nixosModules."iso-autobuild"
        nixosModules."backup-push"
        nixosModules."zfs-space-guard"
      ];
    };
    #==================================================
    homelab = inputs.nixpkgs-stable.lib.nixosSystem {
      specialArgs = {
        pkgs-unstable = pkgsUnstable;
        pkgs-stable = pkgsStable;
        vars = vars;
        # use the home-manager release matching nixpkgs-stable to avoid a version mismatch
        inputs = inputs // { home-manager = inputs.home-manager-stable; };
      };
      modules = [
        ../../hosts/homelab/configuration.nix
        nixosModules."profile-default"
        nixosModules."profile-server"
        nixosModules."auto-update"
        nixosModules."health-alerts"
        nixosModules."push-deploy"
        nixosModules.jellyfin
        nixosModules.minecraft
        nixosModules.factorio
        nixosModules.octodns
        nixosModules.nfs
        nixosModules.samba
      ];
    };
    #==================================================
    vps = inputs.nixpkgs-unstable.lib.nixosSystem {
      specialArgs = {
        inherit inputs;
        pkgs-unstable = pkgsUnstable;
        pkgs-stable = pkgsStable;
        vars = vars;
      };
      modules = [
        ../../hosts/vps/configuration.nix
        nixosModules."profile-default"
        nixosModules."profile-server"
        nixosModules."health-alerts"
      ];
    };
    #==================================================
    isoimage = inputs.nixpkgs-unstable.lib.nixosSystem {
      specialArgs = {
        inherit inputs;
        pkgs-unstable = pkgsUnstable;
        vars = vars;
      };
      modules = [
        ../../hosts/isoimage/configuration.nix
        nixosModules."copyparty-iso"
      ];
    };
  };
}
