{ config, inputs, ... }:
let
  nixosModules = config.flake.modules.nixos;
  homeManagerModules = config.flake.modules.homeManager;
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
        inherit vars;
      };
      modules = [
        ../../hosts/thinkpad/configuration.nix
        nixosModules."profile-pc"
        nixosModules.kde
        nixosModules."pull-deploy"
        nixosModules."nfs-homelab-mounts"
        nixosModules."zrepl"
        nixosModules."zfs-space-guard"
        nixosModules."zfs-dataset-properties"
        nixosModules."health-alerts"
        nixosModules."backup-canary"
      ];
    };
    #==================================================
    torrent = inputs.nixpkgs-unstable.lib.nixosSystem {
      specialArgs = {
        inherit inputs;
        pkgs-unstable = pkgsUnstable;
        pkgs-stable = pkgsStable;
        inherit vars;
      };
      modules = [
        ../../hosts/torrent/configuration.nix
        nixosModules."profile-pc"
        nixosModules.kde
        nixosModules."pull-deploy"
        nixosModules."nfs-homelab-mounts"
        # torrent only, not profile-pc
        # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#F11
        nixosModules."agent-user"
        nixosModules."zrepl"
        nixosModules."zfs-space-guard"
        nixosModules."zfs-dataset-properties"
        nixosModules."health-alerts"
        nixosModules."backup-canary"
        # torrent only, not profile-pc: hotkeys hardcode this desk's outputs
        { home-manager.users.lilijoy.imports = [ homeManagerModules."audio-switch" ]; }
        # torrent only, not profile-pc: static-IP printer/scanner entries are
        # spoofable on roaming thinkpad; unfree scan blob confined here (ADR-0003)
        nixosModules."brother-mfc-l2740dw"
      ];
    };
    #==================================================
    homelab = inputs.nixpkgs-stable.lib.nixosSystem {
      specialArgs = {
        pkgs-unstable = pkgsUnstable;
        pkgs-stable = pkgsStable;
        inherit vars;
        # use the home-manager release matching nixpkgs-stable to avoid a version mismatch
        inputs = inputs // {
          home-manager = inputs.home-manager-stable;
        };
      };
      modules = [
        ../../hosts/homelab/configuration.nix
        nixosModules."profile-default"
        nixosModules."profile-server"
        nixosModules."pull-deploy"
        nixosModules."health-alerts"
        nixosModules."push-deploy"
        nixosModules."zrepl"
        nixosModules."docker-publish-guard"
        nixosModules."docker-userns-remap"
        nixosModules."zfs-dataset-properties"
        nixosModules."datasets"
        nixosModules."backup-canary"
        nixosModules."backup-restore-test"
        nixosModules.jellyfin
        nixosModules.immich
        nixosModules.beets
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
        inherit vars;
      };
      modules = [
        ../../hosts/vps/configuration.nix
        nixosModules."profile-default"
        nixosModules."profile-server"
        nixosModules."health-alerts"
      ];
    };
  };
}
