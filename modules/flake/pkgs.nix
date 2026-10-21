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
      # a test broken by Cython 3.3.0 fails the build (NixOS/nixpkgs#576442),
      # taking piper-tts and calibre with it; drop once NixOS/nixpkgs#576063
      # reaches nixos-unstable
      (_: prev: {
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (_: pyPrev: {
            pyopenjtalk-plus = pyPrev.pyopenjtalk-plus.overridePythonAttrs (old: {
              disabledTests = (old.disabledTests or [ ]) ++ [
                "test_run_njd_from_mecab_invalid_input_should_not_break_next_call"
              ];
            });
          })
        ];
        # speechd-minimal stopped installing its python module, which
        # calibre's tests import; drop once NixOS/nixpkgs#576062 reaches
        # nixos-unstable. Scoped to calibre to avoid rebuilding speechd's
        # other dependents.
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
