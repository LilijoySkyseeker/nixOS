{ config, ... }:
{
  flake.modules.nixos."profile-server" = {
    imports = [
      config.flake.modules.nixos.base
      config.flake.modules.nixos."server-console"
    ];
  };
}
