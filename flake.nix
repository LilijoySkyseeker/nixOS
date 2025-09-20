{
  description = "Nixos config flake";

  # use `nix flake metadata` to see duplicated sources
  inputs = {
    nixpkgs-stable.url = "nixpkgs/nixos-25.05";

    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/release-25.05";
    #   home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-stable";

    stylix.url = "github:danth/stylix/release-25.05";
    stylix.inputs.nixpkgs.follows = "nixpkgs-stable";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs-unstable";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-unstable";

    impermanence.url = "github:nix-community/impermanence";

    nvf.url = "github:notashelf/nvf";
    nvf.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # for comma index
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs-unstable";

    plasma-manager.url = "github:nix-community/plasma-manager";
    plasma-manager.inputs.nixpkgs.follows = "nixpkgs-unstable";
    plasma-manager.inputs.home-manager.follows = "home-manager";

    nix-flatpak.url = "github:gmodena/nix-flatpak";
  };

  outputs =
    inputs@{
      nixpkgs-unstable,
      nixpkgs-stable,
      ...
    }:
    let
      vars = {
        # root access ssh keys
        publicSshKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPDTrihTKFWJxIMkK1lPqf5RnydYCO8PuKZZq6tiuDED lilijoy@nixos" # legion-laptop
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFA+HAQkhmPxKyJFSopziqIVNvFqEaqyRWPVvgu+urfh lilijoy@nixos-thinkpad" # thinkpad
          "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIPlHQiJlsDCcOWk/EadTOgm8mnkGpsg1y8gzvhUgsg7rAAAABHNzaDo= lilijoy@yubikey" # yubikey
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6pG0Y9QdCBRJZKpCD62U3uXl5Lz/bE0ifWLbhZ4q9o lilijoy@torrent" # torrent

        ];
        username = "lilijoy";
      };
      pkgs-unstable = import inputs.nixpkgs-unstable {
        system = "x86_64-linux";
        config = {
          allowUnfree = true;
          permittedInsecurePackages = [
            "libsoup-2.74.3"
            "qtwebengine-5.15.19"
          ];
        };
      };
      pkgs-stable = import inputs.nixpkgs-stable {
        system = "x86_64-linux";
        config = {
          allowUnfree = true;
        };
      };
    in
    {
      nixosConfigurations = {
        #==================================================
        legion = nixpkgs-stable.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              pkgs-unstable
              pkgs-stable
              vars
              ;
          };
          modules = [ ./hosts/legion/configuration.nix ];
        };
        #==================================================
        thinkpad = nixpkgs-stable.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              pkgs-unstable
              pkgs-stable
              vars
              ;
          };
          modules = [ ./hosts/thinkpad/configuration.nix ];
        };
        #==================================================
        torrent = nixpkgs-stable.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              pkgs-unstable
              pkgs-stable
              vars
              ;
          };
          modules = [ ./hosts/torrent/configuration.nix ];
        };
        #==================================================
        homelab = nixpkgs-stable.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              pkgs-unstable
              pkgs-stable
              vars
              ;
          };
          modules = [ ./hosts/homelab/configuration.nix ];
          #         specialArgs = {
          #           inherit
          #             pkgs-unstable
          #             vars
          #             ;
          #           inputs = inputs;
          #         };
          #         pkgs-stable = import nixpkgs-stable {
          #           system = "x86_64-linux";
          #           config.allowUnfree = true;
          #           overlays = [ copyparty.overlays.default ];
          #         };
        };
        #==================================================
        isoimage = nixpkgs-unstable.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              pkgs-unstable
              vars
              ;
          };
          modules = [ ./hosts/isoimage/configuration.nix ];
        };
      };
    };
}
