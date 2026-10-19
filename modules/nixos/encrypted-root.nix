_: {
  flake.modules.nixos."encrypted-root" =
    { config, lib, ... }:
    let
      cfg = config.myEncryptedRoot;
    in
    {
      options.myEncryptedRoot = {
        enable = lib.mkEnableOption "a LUKS2 root (vars.mkEncryptedRootSsd) unlocked in the systemd initrd by TPM2 + PIN, a FIDO2 key, or the recovery passphrase";

        luksName = lib.mkOption {
          type = lib.types.str;
          default = "crypt";
          description = "The LUKS container's name, as in `boot.initrd.luks.devices` (vars.mkEncryptedRootSsd uses `crypt`).";
        };
      };

      config = lib.mkIf cfg.enable {
        # systemd-cryptsetup tries every enrolled LUKS2 token (TPM2 + PIN, FIDO2)
        # by itself, then falls back to the passphrase
        boot.initrd.systemd.enable = true;

        # measures the volume key into PCR 15 once unlocked; TPM2 enrollment
        # binds PCR 15 to all-zeros, so the TPM refuses a second unseal after
        # any volume, real or substituted, has been opened
        boot.initrd.luks.devices.${cfg.luksName}.crypttabExtraOpts = [ "tpm2-measure-pcr=yes" ];
      };
    };
}
