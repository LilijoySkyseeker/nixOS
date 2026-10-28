{
  description = "Nixos config flake";

  # use `nix flake metadata` to see duplicated sources
  inputs = {
    nixpkgs-stable.url = "nixpkgs/nixos-26.05";

    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # matches nixpkgs-stable's release; used only by hosts pinned to nixpkgs-stable
    home-manager-stable.url = "github:nix-community/home-manager/release-26.05";
    home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";

    # homelab's own release pin, held on 26.05 when nixpkgs-stable moves on, so
    # Immich's 2→3 database migration runs only in a planned switch
    # TODO: drop when the Immich 2→3 move merges (consolidation step 3, area 3 E12); deadline 2026-12-31, when 26.05 support ends.
    # -small: Immich's Node 24.22.1 (Node2Shell, CVE-2026-111497, exploited) is there first
    # TODO: drop when nixos-26.05 has nodejs_24 24.22.1 (NixOS/nixpkgs#576787): back to "nixpkgs/nixos-26.05"
    nixpkgs-homelab.url = "nixpkgs/nixos-26.05-small";
    home-manager-homelab.url = "github:nix-community/home-manager/release-26.05";
    home-manager-homelab.inputs.nixpkgs.follows = "nixpkgs-homelab";

    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs-unstable";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs-unstable";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-unstable";

    impermanence.url = "github:nix-community/impermanence";

    # Secure Boot (modules/nixos/secure-boot.nix); pinned to a release, as upstream asks
    lanzaboote.url = "github:nix-community/lanzaboote/v1.2.0";
    lanzaboote.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nvf.url = "github:notashelf/nvf";
    nvf.inputs.nixpkgs.follows = "nixpkgs-unstable";

    plasma-manager.url = "github:nix-community/plasma-manager";
    plasma-manager.inputs.nixpkgs.follows = "nixpkgs-unstable";
    plasma-manager.inputs.home-manager.follows = "home-manager";

    # for comma index
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    # audio.cpp: speech models on vulkan (local-ai-speech); not in nixpkgs
    audio-cpp.url = "github:0xShug0/audio.cpp";
    audio-cpp.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # claude-desktop, until nixpkgs has it (NixOS/nixpkgs#537215)
    llm-agents.url = "github:numtide/llm-agents.nix";
    llm-agents.inputs.nixpkgs.follows = "nixpkgs-unstable";
    llm-agents.inputs.flake-parts.follows = "flake-parts";

    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.modules
        (inputs.import-tree ./modules)
      ];
    };
}
