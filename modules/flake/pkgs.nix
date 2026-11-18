{ config, inputs, ... }:
{
  # Paseo held at 0.15.4: the repo's patches (modules/nixos/paseo) don't
  # apply to 0.16.0, and 0.16.0 approves `ask` rules without a card (fixed
  # in 0.16.1). paseo-desktop follows, it's paseo.passthru.desktop
  # TODO: drop when the Paseo patches are ported to 0.16.1 or later: this
  # overlay and its two uses, here and in hosts.nix
  flake.overlays.paseo-hold = _: prev: {
    paseo = prev.paseo.overrideAttrs (
      _:
      let
        version = "0.15.4";
        src = prev.fetchFromGitHub {
          owner = "getpaseo";
          repo = "paseo";
          tag = "v${version}";
          hash = "sha256-zqD9MrqYZ6S3O72b5y+7P0iJgIMf4MRq1zgcqBcyhko=";
        };
      in
      {
        inherit version src;
        npmDepsHash = "sha256-a8IgSFKtCzql2c2hCbhxxXnSzEUHRC6dGnBuQhgN2Jg=";
        npmDeps = prev.fetchNpmDeps {
          inherit src;
          name = "paseo-${version}-npm-deps";
          hash = "sha256-a8IgSFKtCzql2c2hCbhxxXnSzEUHRC6dGnBuQhgN2Jg=";
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
      config.flake.overlays.paseo-hold
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
