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
        # by itself, then the passphrase; naming a token type in crypttab, or
        # tpm2-measure-pcr, would limit it to the named ones
        boot.initrd.systemd.enable = true;
      };
    };
}
