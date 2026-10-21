# Upstream fixes from the thinkpad reinstall

## Goal

"after we finish testing, we should evaluate if any of this needs to go
back upsteam"

## Your decisions

- 2026-10-21: thinkpad is a secondary laptop and the test platform for
  this setup; keep it as built and see how sturdy it is before deciding.

## State

Candidates found while building #137, most valuable first:
1. nixpkgs `zfs.nix`: the systemd initrd's `zfs-import-<pool>` isn't
   ordered after `systemd-hibernate-resume.service`, so with
   `boot.zfs.unsafeAllowHibernation` the pool can be imported before the
   resume (the corruption case). Fix and VM test: `myHibernate`,
   `tests/thinkpad-disk.nix`. A PR.
2. nixpkgs systemd-boot builder: installing a generation renames older
   entries' files, which breaks `bootctl set-oneshot @current` (and
   `systemctl reboot --boot-loader-entry=@current`). An issue.
3. Docs: `tpm2-measure-pcr=` turns off systemd-cryptsetup's token
   discovery (crypttab(5) doesn't say), and NixOS luksroot.nix's "systemd
   will usually detect it at runtime" is wrong then. Short issues.
4. Kernel: with a TPM, the EFI stub's TPM event log copy moves the e820
   map between boots and resumes are refused. VM evidence only; report
   only if thinkpad shows it (`journalctl -k -b | grep "memory map"`).
5. lanzaboote docs (#427): Windows on another disk via `bcdboot` onto
   the NixOS ESP. Low priority.

Not upstream: the pre-hibernate `zpool sync` (fleet's own
`sync=disabled`), the stick's dm read-only fix (usb-toolbox).

## Next

After thinkpad has run a while: decide which to send; start with 1.
