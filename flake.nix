{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-23.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";

      pkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = (_: true);
        };
      };

      pkgs-unstable = import inputs.nixpkgs-unstable {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = (_: true);
        };
      };

      #pkgs = nixpkgs.legacyPackages.${system};
      #pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
    in
    {
      nixosConfigurations = {
        default = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs pkgs pkgs-unstable;
          };
          modules = [ 
            ./hosts/default/configuration.nix
            inputs.home-manager.nixosModules.default
          ];
        };
      };
    };
}
