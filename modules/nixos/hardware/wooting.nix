{ config, pkgs, inputs, lib, ... }:
{

  # Wooting keyboard
  hardware.wooting.enable = true;
  users.users.lilijoy = {
      extraGroups = [ "input" ];
    };

}
