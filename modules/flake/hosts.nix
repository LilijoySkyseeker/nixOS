{ config, inputs, ... }:
let
  nixosModules = config.flake.modules.nixos;
  homeManagerModules = config.flake.modules.homeManager;
  vars = config.flake.vars;
  pkgsUnstable = config.flake.pkgsUnstable;
  pkgsStable = config.flake.pkgsStable;
  pkgsHomelab = config.flake.pkgsHomelab;
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
        nixosModules."pull-deploy"
        nixosModules."nfs-homelab-mounts"
        nixosModules."zrepl"
        nixosModules."zfs-space-guard"
        nixosModules."zfs-dataset-properties"
        nixosModules."health-alerts"
        nixosModules."backup-canary"
        nixosModules."encrypted-root"
        nixosModules."secure-boot"
        nixosModules.hibernate
        nixosModules."hibernate-only"
        nixosModules."reboot-notice"
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
        nixosModules."pull-deploy"
        nixosModules."nfs-homelab-mounts"
        # torrent only, not profile-pc
        nixosModules."agent-user"
        # agent-user's shared ~/work, at ~/Agent for lilijoy
        {
          home-manager.users.lilijoy =
            { config, ... }:
            {
              home.file."Agent".source = config.lib.file.mkOutOfStoreSymlink "/home/agent/work";
            };
        }
        nixosModules."zrepl"
        nixosModules."zfs-space-guard"
        nixosModules."zfs-dataset-properties"
        nixosModules."health-alerts"
        nixosModules."backup-canary"
        # torrent only, not profile-pc: hotkeys hardcode this desk's outputs
        {
          home-manager.users.lilijoy.imports = [
            homeManagerModules."audio-switch"
          ];
        }
        # torrent only, not profile-pc: static-IP printer/scanner entries are
        # spoofable on roaming thinkpad; unfree scan blob confined here
        nixosModules."brother-mfc-l2740dw"
        # torrent only: its RX 7900 XTX serves the local models
        nixosModules."local-ai"
        nixosModules."local-ai-speech"
      ];
    };
    #==================================================
    # its own release pin (nixpkgs-homelab), not nixpkgs-stable
    homelab = inputs.nixpkgs-homelab.lib.nixosSystem {
      specialArgs = {
        pkgs-unstable = pkgsUnstable;
        pkgs-stable = pkgsHomelab;
        inherit vars;
        # use the home-manager release matching nixpkgs-homelab to avoid a version mismatch
        inputs = inputs // {
          home-manager = inputs.home-manager-homelab;
        };
      };
      modules = [
        ../../hosts/homelab/configuration.nix
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
        nixosModules.octodns
        nixosModules.nfs
        nixosModules.samba
        nixosModules.website
      ];
    };
    #==================================================
    vps = inputs.nixpkgs-stable.lib.nixosSystem {
      specialArgs = {
        # home-manager release matching nixpkgs-stable
        inputs = inputs // {
          home-manager = inputs.home-manager-stable;
        };
        pkgs-unstable = pkgsUnstable;
        pkgs-stable = pkgsStable;
        inherit vars;
      };
      modules = [
        ../../hosts/vps/configuration.nix
        nixosModules."profile-server"
        nixosModules."health-alerts"
      ];
    };
  };
}
