{ config, ... }:
{
  perSystem =
    { ... }:
    {
      devShells.default = config.flake.pkgsUnstable.mkShell {
        packages =
          with config.flake.pkgsUnstable;
          [
            # core (needed even off-NixOS, e.g. macOS/other-distro w/ Nix installed)
            git
            nixos-rebuild # `nixos-rebuild build/switch --flake .#<host>` from anywhere
            nixos-anywhere # remote installs, e.g. `nixos-anywhere --flake .#vps root@<ip>`

            # editing/linting the flake itself
            nixd # nix LSP
            nixfmt
            statix # lints
            deadnix # dead code detection
            nvd # readable diff between nixos generations/closures before switching

            # secrets
            sops
            age
            ssh-to-age

            # git hooks (.githooks/*, all bash)
            shellcheck
            shfmt

            # misc CLI needed by vps/homelab tooling (see hosts/vps/README.md)
            wireguard-tools # wg genkey/pubkey/genpsk
            dig # DNS verification (octoDNS/Cloudflare records)
            yq-go # secrets.yaml / other yaml

            gh
          ]
          # Shared with every host, from modules/flake/debug-tools.nix, so the
          # two lists cannot drift — a tool added because it was missing on a
          # host shows up here too, and vice versa. `jq` used to be listed
          # above and now comes from there.
          #
          # Only *inspect a running system* tooling belongs in the shared
          # list; everything above stays here because it is dev-machine-only
          # (formatting, linting, gh, sops, nixos-anywhere).
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
