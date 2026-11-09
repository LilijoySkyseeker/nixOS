{ inputs, ... }:
{
  flake.pkgsUnstable = import inputs.nixpkgs-unstable {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
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
