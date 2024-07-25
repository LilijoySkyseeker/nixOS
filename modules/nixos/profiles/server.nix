{
  config,
  pkgs,
  pkgs-unstable,
  inputs,
  lib,
  ...
}: {
  environment.systemPackages =
    (with pkgs; [
      # STABLE installed packages
    ])
    ++ (with pkgs-unstable; []); # UNSTABLE installed packages

# disable laptop lid power
services.logind.lidSwitch = "ignore";

}
