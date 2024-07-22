{
  description = "Nixos config flake";

  # use `nix flake metadata` to see duplicated sources
  inputs = {
    nixkpgs.url = "nixpkgs/nixos-24.05";

    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/release-24.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    stylix.inputs.home-manager.follows = "home-manager";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, home-manager, stylix, sops-nix, disko, ... }:
    let
      system = "x86_64-linux";

      pkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
      pkgs-unstable = import inputs.nixpkgs-unstable {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
    in {

      nixosConfigurations = {
        nixos-legion = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs pkgs pkgs-unstable;
          };
          modules = [ 
            ./hosts/nixos-legion/configuration.nix
	          home-manager.nixosModules.home-manager {
		          home-manager.users.lilijoy = import ./hosts/nixos-legion/home.nix;
		          home-manager.useGlobalPkgs = true;
		          home-manager.useUserPackages = true;
	          }
            stylix.nixosModules.stylix
            sops-nix.nixosModules.sops
          ];
        };

        nixos-thinkpad  = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs pkgs pkgs-unstable;
          };
          modules = [ 
            ./hosts/nixos-thinkpad/configuration.nix
	          home-manager.nixosModules.home-manager {
		          home-manager.users.lilijoy = import ./hosts/nixos-thinkpad/home.nix;
		          home-manager.useGlobalPkgs = true;
		          home-manager.useUserPackages = true;
	          }
            stylix.nixosModules.stylix
            sops-nix.nixosModules.sops
          ];
      	};

        homelab = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs pkgs pkgs-unstable;
          };
          modules = [ 
            ./hosts/homelab/configuration.nix
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
          ];
      	};

        isoimage = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs pkgs pkgs-unstable;
          };
          modules = [ 
            ./hosts/isoimage/configuration.nix
          ];
      	};
      };
    };
}
