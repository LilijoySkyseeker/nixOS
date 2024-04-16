{config, pkgs, inputs, lib, ...}:
{

  # Docker
  virtualisation.docker = {
    enable = true;
  };

  users.users.lilijoy.extraGroups = [ "docker" ];

}

