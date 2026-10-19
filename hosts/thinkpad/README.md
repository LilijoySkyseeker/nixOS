# thinkpad

Primary laptop.

## Hardware

- Chasis: ThinkPad P1 Gen 3, Lenovo
- CPU: Core i7-10750H 6x, Intel
- GPU: Quadro T1000 4GB Max-Q, NVIDIA
- RAM: 64 GB (2x32GB) DDR4 3200
- SSD1: 500 GB M.2, Samsung 970 EVO Plus (NixOS)
- SSD2: 256 GB M.2, INTEL SSDPEKKW256G8L (Windows 11)
- Display: 15" 1080p 60Hz

## Backups

Snapshots and replication are handled by zrepl — see
[`docs/backups.md`](../../docs/backups.md).

**This host now runs `sshd`, which it did not before.** It exists solely to
carry zrepl's `ssh+stdinserver` transport, because homelab *pulls* from
this host rather than being pushed to. It is locked down accordingly:
tailnet-only (`openFirewall = false` plus a `tailscale0` firewall rule),
`PermitRootLogin = "forced-commands-only"`, and the only key in root's
`authorized_keys` is a forced command pinned to
`zrepl stdinserver homelab`. Don't add unrestricted root keys here without
reconsidering that posture.

## Disk encryption and boot

The Samsung SSD (`disko.nix`, `vars.mkEncryptedRootSsd`) is an ESP and one
LUKS2 container, `crypt`, holding LVM: `vg/swap` (64G, the hibernation
image) and `vg/zfs` (zroot). At boot the systemd initrd unlocks it with
whichever works first:

- **TPM2 + PIN**, the everyday way. The TPM releases the key only for
  this machine's Secure Boot state (PCR 7) and before any volume has been
  opened (PCR 15 = 0).
- **Either YubiKey** (FIDO2, with its PIN), plugged in at the prompt.
- **The recovery passphrase**, typed when the disk was formatted. It lives
  in Bitwarden.

Enrolling, after Secure Boot is on (each command asks for an existing
passphrase first):

```
dev=/dev/disk/by-partlabel/disk-root-luks
pcrs=7+15:sha256=0000000000000000000000000000000000000000000000000000000000000000
systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrs=$pcrs $dev
systemd-cryptenroll --fido2-device=auto $dev   # once per YubiKey, one plugged in at a time
systemd-cryptenroll $dev                         # lists the slots
```

**When the PIN prompt falls back to the passphrase**, the Secure Boot state
changed: a firmware update, Secure Boot keys changed, or Windows applying
a Secure Boot database update. Unlock with a YubiKey or the passphrase,
then re-seal against the new state:

```
systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrs=$pcrs $dev
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

`files/windows/dual-boot.ps1` sets Windows to match NixOS: hardware clock
in UTC, hibernate in place of sleep, nothing on idle until a 60-minute
hibernate, and PowerToys Awake to pause that timer.

## Power

No sleep: lid closed, critical battery and 60 minutes idle all hibernate
(`myHibernateOnly`, safe on ZFS through `myHibernate`). Nothing happens
before that: no dimming, no screen off, no auto-lock, so lock by hand
(Meta+L) when leaving it. The battery applet's "Manually block sleep and
screen locking" switch pauses the idle timer for long jobs. Resuming isn't
a restart, so a pull-deploy's update waits for one; a notification says
when (`myRebootNotice`).
