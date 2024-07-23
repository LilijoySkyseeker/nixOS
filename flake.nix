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
      inputs.home-manager.follows = "home-manager";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, stylix, sops-nix, ... }@inputs:
    let
    system = "x86_64-linux";
  vars = { 
    publicSshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPDTrihTKFWJxIMkK1lPqf5RnydYCO8PuKZZq6tiuDED lilijoy@nixos" # legion-laptop
    ];
  };

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
#==================================================
      nixos-legion = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs pkgs pkgs-unstable;
        };
        modules = [ 
          ./hosts/nixos-legion/configuration.nix
          home-manager.nixosModules.home-manager
          stylix.nixosModules.stylix
          sops-nix.nixosModules.sops
        ];
      };
#==================================================
      nixos-thinkpad  = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs pkgs pkgs-unstable vars;
        };
        modules = [ 
          ./hosts/nixos-thinkpad/configuration.nix
          home-manager.nixosModules.home-manager
          stylix.nixosModules.stylix
          sops-nix.nixosModules.sops
        ];
      };
#==================================================
      isoimage = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs pkgs vars;
        };
        modules = [ 
          ./hosts/isoimage/configuration.nix
        ];
      };
#==================================================
    };
  };
}
