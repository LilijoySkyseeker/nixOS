{ config, ... }:
{
  perSystem = _: {
    devShells.default = config.flake.pkgsUnstable.mkShell {
      packages =
        with config.flake.pkgsUnstable;
        [
          # core (needed even off-NixOS, e.g. macOS/other-distro w/ Nix installed)
          git
          nixos-rebuild # `nixos-rebuild build/switch --flake .#<host>` from anywhere
          nixos-anywhere # remote installs, e.g. `nixos-anywhere --flake .#vps root@<ip>`

          # editing/linting the flake itself
          nixfmt
          statix # lints
          deadnix # dead code detection

          # secrets
          sops
          age
          age-plugin-yubikey # the YubiKey recipients in .sops.yaml
          ssh-to-age

          # misc CLI needed by vps/homelab tooling (see hosts/vps/README.md)
          wireguard-tools # wg genkey/pubkey/genpsk

          gh
        ]
        # shared with every host (modules/flake/debug-tools.nix); dev-only
        # tools stay in the list above
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
