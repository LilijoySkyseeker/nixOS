{
  pkgs,
  lib,
  config,
  ...
}: let
  tpm-fido = pkgs.buildGoModule rec {
    pname = "tpm-fido";
    version = "0-unstable-2023-06-21";

    src = pkgs.fetchFromGitHub {
      owner = "psanford";
      repo = "tpm-fido";
      rev = "5f8828b82b58f9badeed65718fca72bc31358c5c";
      hash = "sha256-Yfr5B4AfcBscD31QOsukamKtEDWC9Cx2ee4L6HM2554";
    };

    vendorHash = "sha256-qm/iDc9tnphQ4qooufpzzX7s4dbnUbR9J5L770qXw8Y=";

    nativeBuildInputs = [pkgs.installShellFiles pkgs.makeWrapper];

    postInstall = ''
      wrapProgram $out/bin/tpm-fido --prefix PATH : '${pkgs.pinentry}/bin'
    '';

    meta = {
      description = "A FIDO token implementation for Linux that protects the token keys by using your system's TPM";
      homepage = "https://github.com/psanford/tpm-fido";
      license = lib.licenses.mit;
      mainProgram = "tpm-fido";
      maintainers = with lib.maintainers; [lilijoyskyseeker];
    };
  };
in {
  options = {
    tpm-fido.enable =
      lib.mkEnableOption "enables tpm-fido service";
  };

  config = lib.mkIf config.tpm-fido.enable {

  # tpm
  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
    tctiEnvironment.enable = true;
    tssUser = "lilijoy";
  };
  users.users.lilijoy.extraGroups = ["tss"];

  # udev rules for tpm-fido
  services.udev.extraRules = ''
    KERNEL=="uhid", SUBSYSTEM=="misc", GROUP="tss", MODE="0660"
  '';
  boot.kernelModules = ["uhid"];

# tpm-fido service
    systemd.user.services.tpm-fido = {
      enable = true;
      wantedBy = ["default.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = ''${tpm-fido}/bin/tpm-fido'';
      };
    };
  };
}
