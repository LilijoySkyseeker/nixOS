{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.mySecureBoot;
in
{
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

  options.mySecureBoot = {
    enable = lib.mkEnableOption ''
      UEFI Secure Boot via lanzaboote (TODO.md Phase 1). Beta-quality
      upstream (NixOS wiki flags sharp edges) — proven on thinkpad
      first before landing on other hosts. See each host's README.md
      for the one-time manual sbctl/firmware steps this config alone
      can't do (sbctl create-keys, Setup Mode enrollment)
    '';
  };

  config = lib.mkIf cfg.enable {
    boot.lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };
    boot.loader.systemd-boot.enable = lib.mkForce false;
    environment.systemPackages = [
      pkgs.sbctl # Secure Boot key mgmt/debugging
    ];
  };
}
