{ inputs, ... }:
{
  flake.modules.nixos."secure-boot" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.mySecureBoot;
    in
    {
      imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

      options.mySecureBoot = {
        enable = lib.mkEnableOption "UEFI Secure Boot with lanzaboote, signing with the machine's own keys (enrolled alongside Microsoft's)";
      };

      config = lib.mkIf cfg.enable {
        boot.loader.systemd-boot.enable = lib.mkForce false;
        boot.lanzaboote = {
          enable = true;
          pkiBundle = "/var/lib/sbctl";
          autoGenerateKeys.enable = true;
          configurationLimit = lib.mkDefault 10;
        };

        environment.systemPackages = [
          pkgs.sbctl
          pkgs.efibootmgr
        ];
      };
    };
}
