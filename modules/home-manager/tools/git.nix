{ config, pkgs, ... }:
{

  # Git
  programs.git = {
    enable = true;
    userName = "LilijoySkyseeker";
    userEmail = "lilijoyskyseeker@gmail.com";
  };

}
