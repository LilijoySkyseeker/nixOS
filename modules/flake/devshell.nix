{ config, ... }:
{
  perSystem = _: {
    devShells.default = config.flake.pkgsUnstable.mkShell {
      packages =
        with config.flake.pkgsUnstable;
        [
          git
          nixos-rebuild
          nixos-anywhere

          nixfmt
          statix
          deadnix

          sops
          age
          age-plugin-yubikey
          ssh-to-age

          wireguard-tools

          gh
        ]
        ++ config.flake.debugTools config.flake.pkgsUnstable;

      shellHook = ''
        if [ -d .git ] || git rev-parse --git-dir >/dev/null 2>&1; then
          if [ "$(git config --local --get core.hooksPath)" != ".githooks" ]; then
            git config --local core.hooksPath .githooks
          fi
          if [ "$(git config --local --get pull.rebase)" != "true" ]; then
            git config --local pull.rebase true
          fi
        fi
      '';
    };
  };
}
