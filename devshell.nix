{ pkgs-unstable }:
pkgs-unstable.mkShell {
  packages = with pkgs-unstable; [
    nixd # nix LSP
    nixfmt
    statix # lints
    deadnix # dead code detection
    sops
    age
    ssh-to-age
    gh
  ];
}
