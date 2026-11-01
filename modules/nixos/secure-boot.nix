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

        pkiBundle = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/sbctl";
          description = ''
            Where sbctl keeps the Secure Boot keys. Generated here on first
            boot. Put it on a filesystem that is neither snapshotted nor
            replicated.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        boot.loader.systemd-boot.enable = lib.mkForce false;
        boot.lanzaboote = {
          enable = true;
          inherit (cfg) pkiBundle;
          # keys are made on first boot; until then generations install unsigned
          autoGenerateKeys.enable = true;
          configurationLimit = lib.mkDefault 10;
        };

        environment.systemPackages = [
          pkgs.sbctl
          pkgs.efibootmgr # firmware BootOrder, which Windows resets to put itself first
        ];
      };
    };
}
