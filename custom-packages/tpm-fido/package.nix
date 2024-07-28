{
  pkgs,
  stdenv,
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  installShellFiles,
  pinentry,
}: {
  tpm-fido = buildGoModule rec {
    pname = "tpm-fido";
    version = "0-unstable-2023-06-21";

    src = fetchFromGitHub {
      owner = "psanford";
      repo = "tpm-fido";
      rev = "5f8828b82b58f9badeed65718fca72bc31358c5c";
      hash = "sha256-Yfr5B4AfcBscD31QOsukamKtEDWC9Cx2ee4L6HM2554";
    };

    vendorHash = "sha256-qm/iDc9tnphQ4qooufpzzX7s4dbnUbR9J5L770qXw8Y=";

    nativeBuildInputs = [installShellFiles makeWrapper];

    postInstall = ''
      wrapProgram $out/bin/tpm-fido --prefix PATH : '${pinentry}/bin'
    '';

    meta = {
      description = "A FIDO token implementation for Linux that protects the token keys by using your system's TPM";
      homepage = "https://github.com/psanford/tpm-fido";
      license = lib.licenses.mit;
      mainProgram = "tpm-fido";
      maintainers = with lib.maintainers; [lilijoyskyseeker];
    };
  };
}
