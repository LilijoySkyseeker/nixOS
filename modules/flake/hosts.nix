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
        vars = vars;
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
        nixosModules."zrepl"
        nixosModules."zfs-space-guard"
        nixosModules."zfs-dataset-properties"
        nixosModules."health-alerts"
        # audio-switch's dedicated hotkeys hardcode this desk's three output
        # devices, so it's wired in here (torrent only), not profile-pc,
        # which thinkpad also uses.
        { home-manager.users.lilijoy.imports = [ homeManagerModules."audio-switch" ]; }
        # The Brother printer/scanner is wired in here (torrent only), not
        # profile-pc: its static-IP queue and sane-airscan's WSD discovery
        # are network-supplied-identity risks on thinkpad, a roaming
        # laptop -- see modules/nixos/brother-mfc-l2740dw.nix.
        nixosModules."brother-mfc-l2740dw"
      ];
    };
    #==================================================
    homelab = inputs.nixpkgs-stable.lib.nixosSystem {
      specialArgs = {
        pkgs-unstable = pkgsUnstable;
        pkgs-stable = pkgsStable;
        vars = vars;
        # use the home-manager release matching nixpkgs-stable to avoid a version mismatch
        inputs = inputs // {
          home-manager = inputs.home-manager-stable;
        };
      };
      modules = [
        ../../hosts/homelab/configuration.nix
        nixosModules."profile-default"
        nixosModules."profile-server"
        nixosModules."auto-update"
        nixosModules."health-alerts"
        nixosModules."push-deploy"
        nixosModules."zrepl"
        nixosModules."docker-publish-guard"
        nixosModules."zfs-dataset-properties"
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
