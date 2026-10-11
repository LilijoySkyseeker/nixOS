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
  };

  flake.pkgsStable = import inputs.nixpkgs-stable {
    system = "x86_64-linux";
    config = {
      permittedInsecurePackages = [ "" ];
      allowUnfree = true;
    };
  };
}
