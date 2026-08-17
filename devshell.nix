{ pkgs-unstable }:
pkgs-unstable.mkShell {
  packages = with pkgs-unstable; [
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

    # misc CLI needed by things documented in this repo (docs/TODO-vps-manual-steps.md)
    wireguard-tools # wg genkey/pubkey/genpsk
    dig # DNS verification (octoDNS/Cloudflare records)
    jq # docs/tailscale-acl.json
    yq-go # secrets.yaml / other yaml

    gh
  ];

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
}
