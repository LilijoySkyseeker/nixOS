{ inputs, ... }:
{
  # the flake input itself, for perSystem code (no `inputs` there) that needs
  # `.lib.nixosSystem`, e.g. tests/push-deploy-sandbox.nix
  flake.nixpkgsUnstableFlake = inputs.nixpkgs-unstable;

  flake.pkgsUnstable = import inputs.nixpkgs-unstable {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
      permittedInsecurePackages = [
        "electron-39.8.10"
      ];
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
      permittedInsecurePackages = [ "" ];
      allowUnfree = true;
    };
  };
}
