# Plain Nix helper (not a NixOS module — disko.nix files are bare
# attrsets, not module-system functions), imported directly from each
# host's disko.nix to build a LUKS-wrapped zfs disko partition content
# block without repeating the same ~15-line comment and options struct
# three times.
#
# LUKS wraps the zfs partition rather than using ZFS native encryption:
# systemd-cryptenroll's TPM2 sealing is an upstream-supported NixOS
# module for LUKS, with no equivalent for native ZFS encryption (see
# TODO.md's FDE/Secure Boot/TPM2 entry). enrollRecovery has disko
# auto-generate a second, high-entropy passphrase slot at provision
# time (printed/QR'd for escrow) alongside whatever passphrase is
# typed interactively — never a TPM2-only slot, so a TPM
# failure/board swap always has a manual fallback. The TPM2 slot
# itself is enrolled post-install via `systemd-cryptenroll`, once
# Secure Boot (lanzaboote) is confirmed working — not here, disko has
# no TPM2 primitive and sealing before Secure Boot is verified would
# seal against an untrusted boot chain.
#
# `reinstalled` gates the LUKS wrapping itself (modules/nixos/phase2-gate.nix):
# disko's `type = "luks"` unconditionally emits a
# `boot.initrd.luks.devices.<name>` entry (initrdUnlock defaults true),
# so evaluating this as "luks" on a host whose disk was never actually
# reprovisioned with a LUKS header would hang initrd on next boot.
# Defaults false — callers must pass `config.myPhase2.reinstalled`
# explicitly.
{
  name, # unique LUKS container name (one per physical disk)
  pool, # target zpool name
  extraSettings ? { }, # e.g. { allowDiscards = true; } for SSDs
  reinstalled ? false, # only true once this disk was actually disko-installed with LUKS
}:
if reinstalled then
  {
    type = "luks";
    inherit name;
    enrollRecovery = true;
    settings = extraSettings;
    content = {
      type = "zfs";
      inherit pool;
    };
  }
else
  {
    type = "zfs";
    inherit pool;
  }
