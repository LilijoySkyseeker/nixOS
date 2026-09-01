{ inputs, ... }:
{
  # Exposed alongside pkgsUnstable (not just the instantiated pkgs) so
  # perSystem code -- where plain `inputs` is deliberately unusable, see
  # flake-parts' modules/perSystem.nix -- can still call `.lib.nixosSystem`
  # on the exact same flake input, e.g. tests/push-deploy-sandbox.nix.
  flake.nixpkgsUnstableFlake = inputs.nixpkgs-unstable;

  flake.pkgsUnstable = import inputs.nixpkgs-unstable {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
      permittedInsecurePackages = [
        "electron-39.8.10"
      ];
    };
  };

  flake.pkgsStable = import inputs.nixpkgs-stable {
    system = "x86_64-linux";
    config = {
      permittedInsecurePackages = [ "" ];
      allowUnfree = true;
    };
  };
}
