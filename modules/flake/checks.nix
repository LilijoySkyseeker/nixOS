# Integration tests, run with `nix build .#checks.x86_64-linux.<name>` or
# all at once with `nix flake check`. These are the layer above
# `nixos-rebuild build`: they boot real VMs, so they can catch what only
# breaks at runtime. See docs/procedures/testing-changes.md.
{ config, ... }:
{
  perSystem =
    { ... }:
    {
      checks.zrepl-replication = import ../../tests/zrepl-replication.nix {
        pkgs = config.flake.pkgsUnstable;
        zreplModule = config.flake.modules.nixos."zrepl";
      };
    };
}
