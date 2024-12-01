{
  description = "Nixos config flake";

  # use `nix flake metadata` to see duplicated sources
  inputs = {
    nixkpgs.url = "nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager-unstable.url = "github:nix-community/home-manager";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";


#   stylix.url = "github:danth/stylix/cf8b6e2d4e8aca8ef14b839a906ab5eb98b08561"; # pinned to commit beacause of: https://github.com/danth/stylix/issues/577
    stylix.url = "github:danth/stylix/release-24.05"; # pinned to commit beacause of: https://github.com/danth/stylix/issues/577
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    stylix.inputs.home-manager.follows = "home-manager";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";

    nixvim.url = "github:nix-community/nixvim/nixos-24.11";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";
    nixvim.inputs.home-manager.follows = "home-manager";

    copyparty.url = "github:9001/copyparty";
    copyparty.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # for comma index
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      home-manager-unstable,
      stylix,
      sops-nix,
      disko,
      impermanence,
      nixvim,
      copyparty,
      nix-index-database,
      ...
    }:
    let
      system = "x86_64-linux";
      vars = {
        # root access ssh keys
        publicSshKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPDTrihTKFWJxIMkK1lPqf5RnydYCO8PuKZZq6tiuDED lilijoy@nixos" # legion-laptop
          "sk-ecdsa-sha2-nistp256@openssh.com AAAAInNrLWVjZHNhLXNoYTItbmlzdHAyNTZAb3BlbnNzaC5jb20AAAAIbmlzdHAyNTYAAABBBOMWwCahxhLGbypUW77xlIkIGpvknKvWZKPinnIULANbtcttspjkYvGc/n1IJICvOUg7qIWXKMEBrQZQT3dTeywAAAAEc3NoOg== lilijoy@nixos-legion" # legion flipper
          "sk-ecdsa-sha2-nistp256@openssh.com AAAAInNrLWVjZHNhLXNoYTItbmlzdHAyNTZAb3BlbnNzaC5jb20AAAAIbmlzdHAyNTYAAABBBEjfX78Dy65xkJV1Kd8Q5d+zvE+/GtnQOWniIoQS7FfBlIPMd9qUNY9o3Z7n5/ILwcnZIia01277BdPlAKXYGTAAAAAEc3NoOg== lilijoy@nixos-thinkpad" # thinkpad tpm
          "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIPlHQiJlsDCcOWk/EadTOgm8mnkGpsg1y8gzvhUgsg7rAAAABHNzaDo= lilijoy@yubikey" # yubikey
        ];
        username = "";
      };
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        nixpkgs.overlays = [ copyparty.overlays.default ];
      };
      pkgs-unstable = import inputs.nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      nixosConfigurations = {
        #==================================================
        legion = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              pkgs
              pkgs-unstable
              vars
              ;
          };
          modules = [ ./hosts/legion/configuration.nix ];
        };
        #==================================================
        thinkpad = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              pkgs
              pkgs-unstable
              vars
              ;
          };
          modules = [ ./hosts/thinkpad/configuration.nix ];
        };
        #==================================================
        homelab = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit pkgs-unstable vars;
            inputs = inputs;
          };
          modules = [ ./hosts/homelab/configuration.nix ];
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
            overlays = [ copyparty.overlays.default ];
          };
        };
        #==================================================
        isoimage = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              pkgs
              vars
              pkgs-unstable
              ;
          };
          modules = [ ./hosts/isoimage/configuration.nix ];
        };
      };
    };
}
