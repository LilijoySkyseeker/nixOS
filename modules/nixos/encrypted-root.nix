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
        boot.initrd.systemd.enable = true;

        boot.initrd.luks.devices.${cfg.luksName}.crypttabExtraOpts = [
          # measures the volume key into PCR 15 once unlocked; TPM2 enrollment
          # binds PCR 15 to all-zeros, so the TPM refuses a second unseal after
          # any volume, real or substituted, has been opened
          "tpm2-measure-pcr=yes"
          # tpm2-measure-pcr turns off systemd-cryptsetup's token auto-discovery,
          # so the TPM2 token must be asked for; with none enrolled, or a wrong
          # PIN, it falls back to the passphrase
          "tpm2-device=auto"
        ];
      };
    };
}
