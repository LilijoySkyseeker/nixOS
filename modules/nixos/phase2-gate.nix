# Per-host safety gate for the FDE/Secure-Boot/TPM2/impermanence
# rollout (TODO.md). Defaults to false so merging Phase 2 config to
# master cannot brick an existing, un-reinstalled host: pull-deploy
# (modules/nixos/pull-deploy.nix) runs unattended with
# `operation = "boot"`, so a plain merge would otherwise set a
# LUKS-expecting generation as the default boot entry before the disk
# actually has a LUKS header, hanging the next reboot in initrd.
#
# Flip this to `true` for a host only in the same commit that actually
# reinstalls it via disko-install.
{ lib, ... }:
{
  options.myPhase2.reinstalled = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Whether this host has been reprovisioned with the LUKS-wrapped
      disko layout. Gates mySecureBoot, myZfsImpermanence, and the
      LUKS wrapping in disko.nix — all of which require booting from a
      disk that was actually partitioned with disko-install under this
      config, not a live host that predates it.
    '';
  };
}
