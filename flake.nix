{
  description = "Nixos config flake";

  # use `nix flake metadata` to see duplicated sources
  inputs = {
    nixpkgs-stable.url = "nixpkgs/nixos-24.11";

    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";

#   home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-unstable";

    stylix.url = "github:danth/stylix/release-24.11";
    stylix.inputs.nixpkgs.follows = "nixpkgs-stable";
    stylix.inputs.home-manager.follows = "home-manager";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs-unstable";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-unstable";

    impermanence.url = "github:nix-community/impermanence";

    nixvim.url = "github:nix-community/nixvim";
    nixvim.inputs.nixpkgs.follows = "nixpkgs-unstable";
    nixvim.inputs.home-manager.follows = "home-manager";

    copyparty.url = "github:9001/copyparty";
    copyparty.inputs.nixpkgs.follows = "nixpkgs-unstable";

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
      self,
      nixpkgs-unstable,
      nixpkgs-stable,
      home-manager,
      stylix,
      sops-nix,
      disko,
      impermanence,
      nixvim,
      copyparty,
      nix-index-database,
      plasma-manager,
      nix-flatpak,
      ...
    }:
    let
      vars = {
        # root access ssh keys
        publicSshKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPDTrihTKFWJxIMkK1lPqf5RnydYCO8PuKZZq6tiuDED lilijoy@nixos" # legion-laptop
          "sk-ecdsa-sha2-nistp256@openssh.com AAAAInNrLWVjZHNhLXNoYTItbmlzdHAyNTZAb3BlbnNzaC5jb20AAAAIbmlzdHAyNTYAAABBBOMWwCahxhLGbypUW77xlIkIGpvknKvWZKPinnIULANbtcttspjkYvGc/n1IJICvOUg7qIWXKMEBrQZQT3dTeywAAAAEc3NoOg== lilijoy@nixos-legion" # legion flipper
          "sk-ecdsa-sha2-nistp256@openssh.com AAAAInNrLWVjZHNhLXNoYTItbmlzdHAyNTZAb3BlbnNzaC5jb20AAAAIbmlzdHAyNTYAAABBBEjfX78Dy65xkJV1Kd8Q5d+zvE+/GtnQOWniIoQS7FfBlIPMd9qUNY9o3Z7n5/ILwcnZIia01277BdPlAKXYGTAAAAAEc3NoOg== lilijoy@nixos-thinkpad" # thinkpad tpm
          "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIPlHQiJlsDCcOWk/EadTOgm8mnkGpsg1y8gzvhUgsg7rAAAABHNzaDo= lilijoy@yubikey" # yubikey
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6pG0Y9QdCBRJZKpCD62U3uXl5Lz/bE0ifWLbhZ4q9o lilijoy@torrent" # torrent

        ];
        username = "lilijoy";
      };
      pkgs-unstable = import inputs.nixpkgs-unstable {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
      pkgs-stable = import inputs.nixpkgs-stable {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
    in
    {
      nixosConfigurations = {
        #==================================================
        legion = nixpkgs-unstable.lib.nixosSystem {
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
        thinkpad = nixpkgs-unstable.lib.nixosSystem {
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
        homelab = nixpkgs-unstable.lib.nixosSystem {
          specialArgs = {
            inherit vars;
            inputs = inputs;
          };
          modules = [ ./hosts/homelab/configuration.nix ];
          pkgs = import nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfree = true;
            overlays = [ copyparty.overlays.default ];
          };
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
