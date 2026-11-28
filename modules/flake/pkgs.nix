{ config, inputs, ... }:
{
  # Paseo held at 0.16.2: the repo's patches (modules/nixos/paseo) don't
  # apply to nixos-unstable's 0.17.4. paseo-desktop follows, it's
  # paseo.passthru.desktop
  # TODO: drop when the Paseo patches are ported to nixos-unstable's Paseo: this
  # overlay and its two uses, here and in hosts.nix
  flake.overlays.paseo-hold = _: prev: {
    paseo = prev.paseo.overrideAttrs (
      _:
      let
        version = "0.16.2";
        src = prev.fetchFromGitHub {
          owner = "getpaseo";
          repo = "paseo";
          tag = "v${version}";
          hash = "sha256-QUiFW45kS0CSMOTIUg5odZhbcub/aHDhxs5geRb2+0c=";
        };
        npmDepsHash = "sha256-qEvMRNmbsL3lAQvonKBc3VQ2QrnropB51nAJoxPD994=";
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
