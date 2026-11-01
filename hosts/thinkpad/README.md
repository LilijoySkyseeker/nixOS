# thinkpad

## Disk encryption and boot

The Samsung SSD (`disko.nix`, `vars.mkEncryptedRootSsd`) is an ESP and one
LUKS2 container, `crypt`, holding LVM: `vg/swap` (64G, the hibernation
image) and `vg/zfs` (zroot). At boot the systemd initrd asks "Please enter
LUKS2 token PIN:" and tries every enrolled way in:

- **TPM2 + PIN**, the everyday way. The TPM releases the key only for this
  machine's Secure Boot state (PCR 7), and only for the right PIN; it locks
  itself out after a few wrong ones.
- **Either YubiKey** (FIDO2): plug it in and type its FIDO2 PIN at the same
  prompt. A PIN is tried against every token, so a wrong one also counts
  against a plugged-in YubiKey's PIN retries; keep the YubiKey out unless
  you're using it.
- **The recovery passphrase**, asked for once the tokens fail (a changed
  Secure Boot state, or the TPM locked out). It lives in Bitwarden.

The PIN is also the unlock after hibernating: the session resumes unlocked
(`myHibernateOnly.lockOnResume = false`). Lock by hand (Meta+L) to come back
to a locked session.

Enrolling, after Secure Boot is on (each command asks for the passphrase
first):

```
dev=/dev/disk/by-partlabel/disk-root-luks
systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrs=7 $dev
systemd-cryptenroll --fido2-device=auto $dev   # once per YubiKey, one plugged in at a time
systemd-cryptenroll $dev                         # lists the slots
```

To check a YubiKey's slot without rebooting, with only that key plugged in:

```sh
run0 --pty env LD_LIBRARY_PATH=/run/current-system/sw/lib/cryptsetup \
  cryptsetup open --test-passphrase --token-only \
  --token-id <its token id from cryptsetup luksDump> $dev
```

Token IDs are separate from keyslot numbers. The library search path lets
cryptsetup load systemd's FIDO2 handler on NixOS. A successful test asks for
the YubiKey PIN and touch and exits with status 0; add `--verbose` to
cryptsetup to display the result. If it fails silently, use `--debug`.

**When the PIN stops working and the passphrase is asked for**, the Secure
Boot state changed: a firmware update, Secure Boot keys changed, or Windows
applying a Secure Boot database update. Unlock with a YubiKey or the
passphrase, then re-seal against the new state:

```
systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrs=7 $dev
```

**Secure Boot** is lanzaboote (`mySecureBoot`). Its keys are on
`zroot/local/secureboot` at `/var/lib/sbctl`, which zrepl neither
snapshots nor replicates; they were enrolled with Microsoft's
(`sbctl enroll-keys --microsoft`), so Windows and the GPU's option ROM
still boot. Losing them isn't a lockout: `sbctl create-keys`, enroll again
from firmware Setup Mode, and re-seal the TPM as above. The firmware has a
supervisor password (in Bitwarden), network boot off, and a password on
the F12 boot menu.

## Dual boot with Windows

Windows 11 is on the Intel SSD, encrypted with BitLocker (TPM + PIN; the
recovery key is in Bitwarden). Its boot files were copied onto this ESP
(`bcdboot C:\Windows /s <this ESP> /f UEFI`), so the boot menu
(systemd-boot, shown for 2 seconds) lists it next to NixOS. If Windows
ever puts itself first in the firmware boot order, put "Linux Boot
Manager" back first (`efibootmgr -o`, or the firmware's boot menu).
Windows' firmware entry points at this ESP too, so Windows boots from the
Samsung disk; the Intel disk's own ESP still holds its original boot files.

**BitLocker isn't bound to Secure Boot here.** Started through
systemd-boot, Windows can't use PCR 7 (its log shows events 813, 881 and
893), so BitLocker seals to PCRs 0, 2, 4 and 11. PCR 4 measures every boot
binary on the way, systemd-boot's included, so expect the 48-digit
recovery key once after an update changes systemd-boot, or when Windows is
started another way (F12 straight to Windows Boot Manager). Windows RE
lives on the Intel disk's Recovery partition and must stay enabled
(`reagentc /info`): `manage-bde -on` fails without it.
