{
  description = "Nixos config flake";

  # use `nix flake metadata` to see duplicated sources
  inputs = {
    nixkpgs.url = "nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/release-24.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    stylix.url = "github:danth/stylix/release-24.05";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    stylix.inputs.home-manager.follows = "home-manager";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.inputs.nixpkgs-stable.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    stylix,
    sops-nix,
    disko,
    impermanence,
    ...
  }: let
    system = "x86_64-linux";
    vars = {
      # root access ssh keys
      publicSshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPDTrihTKFWJxIMkK1lPqf5RnydYCO8PuKZZq6tiuDED lilijoy@nixos" # legion-laptop
        "sk-ecdsa-sha2-nistp256@openssh.com AAAAInNrLWVjZHNhLXNoYTItbmlzdHAyNTZAb3BlbnNzaC5jb20AAAAIbmlzdHAyNTYAAABBBOMWwCahxhLGbypUW77xlIkIGpvknKvWZKPinnIULANbtcttspjkYvGc/n1IJICvOUg7qIWXKMEBrQZQT3dTeywAAAAEc3NoOg== lilijoy@nixos-legion" # legion flipper
        "sk-ecdsa-sha2-nistp256@openssh.com AAAAInNrLWVjZHNhLXNoYTItbmlzdHAyNTZAb3BlbnNzaC5jb20AAAAIbmlzdHAyNTYAAABBBEjfX78Dy65xkJV1Kd8Q5d+zvE+/GtnQOWniIoQS7FfBlIPMd9qUNY9o3Z7n5/ILwcnZIia01277BdPlAKXYGTAAAAAEc3NoOg== lilijoy@nixos-thinkpad" # thinkpad tpm
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIPlHQiJlsDCcOWk/EadTOgm8mnkGpsg1y8gzvhUgsg7rAAAABHNzaDo= lilijoy@yubikey" # yubikey
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJyPj+k9bbz+wMhINARS45jZMrKn9JnUBXCEmmJ+/qwh coffee@coffeetoffee-rogzephyrusg15" # Coffee rogzephyrusg15
      ];
    };
    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    pkgs-unstable = import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    nixosConfigurations = {
      #==================================================
      nixos-legion = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs pkgs pkgs-unstable vars;
        };
        modules = [
          ./hosts/nixos-legion/configuration.nix
          home-manager.nixosModules.home-manager
          stylix.nixosModules.stylix
          sops-nix.nixosModules.sops
        ];
      };
      #==================================================
      nixos-thinkpad = nixpkgs.lib.nixosSystem {
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
      homelab = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs pkgs pkgs-unstable vars;
        };
        modules = [
          ./hosts/homelab/configuration.nix
          sops-nix.nixosModules.sops
          disko.nixosModules.disko
          impermanence.nixosModules.impermanence
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
