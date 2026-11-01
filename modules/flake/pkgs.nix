{ inputs, ... }:
{
  flake.pkgsUnstable = import inputs.nixpkgs-unstable {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
    overlays = [
      (_: prev: {
        # speechd-minimal stopped installing its python module, which
        # calibre's tests import. Scoped to calibre to avoid rebuilding
        # speechd's other dependents.
        # TODO: drop when NixOS/nixpkgs#576062 is in nixos-unstable
        calibre = prev.calibre.override {
          speechd-minimal = prev.speechd-minimal.overrideAttrs (old: {
            nativeBuildInputs = old.nativeBuildInputs ++ [ prev.python3Packages.python ];
          });
        };
      })
    ];
  };

  flake.pkgsStable = import inputs.nixpkgs-stable {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
  };

  # homelab's pkgs-stable, from its own release pin (flake.nix)
  flake.pkgsHomelab = import inputs.nixpkgs-homelab {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
  };
}
