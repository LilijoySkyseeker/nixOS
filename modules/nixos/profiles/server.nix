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

  # sops shh keypath
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

  # disable laptop lid power
  services.logind.lidSwitch = "ignore";
}
