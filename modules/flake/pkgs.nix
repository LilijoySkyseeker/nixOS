{ config, inputs, ... }:
{
  # Paseo 0.16.1: nixos-unstable has 0.16.0, which approves `ask` rules and
  # hooks without a permission card. paseo-desktop follows, it's
  # paseo.passthru.desktop. The repo's patches (modules/nixos/paseo) are on 0.16.1
  # TODO: drop when nixos-unstable's paseo is 0.16.1 or later: this overlay
  # and its two uses, here and in hosts.nix
  flake.overlays.paseo-0-16-1 = _: prev: {
    paseo = prev.paseo.overrideAttrs (
      _:
      let
        version = "0.16.1";
        src = prev.fetchFromGitHub {
          owner = "getpaseo";
          repo = "paseo";
          tag = "v${version}";
          hash = "sha256-NmVhT+H3pSVUvB2hLYZYFPGbdnXSpEPcQG9w13q7XFQ=";
        };
        npmDepsHash = "sha256-KO2VVoE6cuoND3INlYrQPaj9hNFpw4iNw5aGe9Ml2pE=";
      in
      {
        inherit version src npmDepsHash;
        npmDeps = prev.fetchNpmDeps {
          inherit src;
          name = "paseo-${version}-npm-deps";
          hash = npmDepsHash;
          fetcherVersion = 2;
        };
      }
    );
  };

  flake.pkgsUnstable = import inputs.nixpkgs-unstable {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
    overlays = [
      config.flake.overlays.paseo-0-16-1
    ];
  };

  flake.pkgsStable = import inputs.nixpkgs-stable {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
  };

  flake.pkgsHomelab = import inputs.nixpkgs-homelab {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
  };
}
