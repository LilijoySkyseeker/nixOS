{
  description = "Nixos config flake";

  inputs = {
    nixpkgs = {
      url = "nixpkgs/nixos-24.05";
    };
    nixpkgs-unstable = {
      url = "nixpkgs/nixos-unstable";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, ... }@inputs:
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
            inputs.stylix.nixosModules.stylix
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
            inputs.stylix.nixosModules.stylix
          ];
      	};
      };
    };
}
