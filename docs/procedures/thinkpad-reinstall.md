# Reinstall thinkpad: encrypted root, Secure Boot, Windows dual boot

A runbook for the agent on the TOOLBOX stick (`docs/procedures/toolbox-stick.md`),
carried out with the owner at the machine. It wipes and reinstalls NixOS on
one disk, restores the owner's data onto it from homelab's backups, turns on
Secure Boot, and puts Windows in the boot menu. The steps suit another
machine too: change the values below and the host's `disko.nix`.

## The machine and its values

| What | Value |
|---|---|
| Machine | hostname `thinkpad`; Lenovo ThinkPad P1 Gen 3 |
| NixOS disk (wiped) | Samsung SSD 970 EVO Plus 500GB, serial `S58SNS0R706072M`, `/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_500GB_S58SNS0R706072M` |
| Windows disk (never touched by this runbook's disk commands) | INTEL SSDPEKKW256G8L, 256 GB |
| Flake | `https://github.com/LilijoySkyseeker/nixOS`, branch `thinkpad-fde`, `#thinkpad` |
| Backups | on `homelab` (Tailscale name), `zbackup/backup/thinkpad/zroot/local/root` and `…/home` |
| Layout | ESP 2G (`/boot`), then LUKS2 `crypt` → LVM `vg`: `swap` 64G, `zfs` = pool `zroot` (`hosts/thinkpad/disko.nix`) |

## Rules for this job

- **Tell the owner the plan and wait for their yes** before each step marked
  ⚠ (disk, firmware or boot changes). Before the wipe, show them the disk's
  model and serial and get a yes for that exact disk.
- **The owner types every secret**: the LUKS recovery passphrase, PINs, the
  YubiKey PIN and touch, the firmware supervisor password, Bitwarden. Don't
  ask for them, read them, or put them in files or notes.
- Never read, edit or decrypt anything under `secrets/` or
  `/var/lib/sops-nix`, and never print private keys.
- Install from branch `thinkpad-fde`, not `master`.
- After each step, run its check before going on. Log progress, findings and
  the next step in this machine's `NOTES.md` on the stick, so a reboot picks
  up where it stopped.
- If a check fails, stop and tell the owner. Nothing below is worth guessing
  past: the backups on homelab are the way back.

## A. Before: Windows and firmware (Windows, owner)

1. In Windows, the stick's **Upgrade Windows** brings it to the newest
   Windows 11, then Windows Update until nothing is pending. Leave BitLocker
   off for now.
2. Update the BIOS with Lenovo's tool (Lenovo Vantage or Commercial Vantage).
   Check: the BIOS version in the firmware setup (F1 at power-on) is the
   newest Lenovo lists for the P1 Gen 3.

Both change what the TPM measures, so they come before anything is sealed
to it.

## B. Final backup (old NixOS, then homelab)

1. Owner stops using the laptop. On the thinkpad (old NixOS):
   `run0 zrepl signal wakeup snapshots`, then `zfs list -t snapshot -o name,creation -s creation zroot/local/home | tail -2`.
   Note the newest `zrepl_…` snapshot name.
2. From a machine on the tailnet that homelab trusts (torrent, or later the
   stick with the keychain YubiKey, see C2): `ssh root@homelab zrepl signal wakeup thinkpad`, wait a few minutes, then check that the snapshot from B1 is on homelab for both datasets:
   `ssh root@homelab zfs list -t snapshot -o name zbackup/backup/thinkpad/zroot/local/root zbackup/backup/thinkpad/zroot/local/home | grep <snapshot>`
3. Hold both, so homelab's pruning can't remove them during the job:
   `ssh root@homelab zfs hold reinstall zbackup/backup/thinkpad/zroot/local/root@<snapshot> zbackup/backup/thinkpad/zroot/local/home@<snapshot>`
4. Shut the thinkpad down. Anything written after B1 is lost.

## C. Wipe, restore, install (Rescue System)

Boot the stick's Rescue System on the thinkpad.

1. Internet (Wi-Fi or the phone's USB tethering), then the tailnet:
   `sudo tailscale up --qr` (the owner scans the QR code and approves).
   Clone: `git clone -b thinkpad-fde https://github.com/LilijoySkyseeker/nixOS /tmp/nixOS`.
2. SSH to homelab with the keychain YubiKey (owner plugs it in, enters its
   FIDO2 PIN): `mkdir /tmp/sk && cd /tmp/sk && ssh-keygen -K` writes the
   key and its `.pub` (`ls` shows the name, usually `id_ed25519_sk_rk`).
   Pick the private file, the one without `.pub`, and use it in every SSH
   command below:
   ```
   key=/tmp/sk/id_ed25519_sk_rk
   ssh -i "$key" -o IdentitiesOnly=yes root@homelab true   # owner touches the key
   ```
   Check: it returns without error.
3. Find the disks: `lsblk -o NAME,SIZE,MODEL,SERIAL`. Show the owner the
   Samsung's model and serial, compare with the table above.
4. ⚠ Make only that disk writable: `disk-rw /dev/<the Samsung, e.g. nvme0n1>`,
   never the Intel. The LUKS and LVM volumes made on it next stay writable
   with it.
5. ⚠ Wipe and format (asks for the LUKS passphrase: the owner generates a
   long random one in Bitwarden, saves it there as the thinkpad's recovery
   passphrase, and types it):
   `sudo nix run github:nix-community/disko/latest -- --mode destroy,format --flake /tmp/nixOS#thinkpad`
   Check: `lsblk` shows `crypt` → `vg-swap` (64G) and `vg-zfs`; `zpool status zroot` is ONLINE;
   `zfs list -r zroot` shows `local/{nix,root,home,secureboot}`.
6. ⚠ Replace the empty root and home with the backups (snapshot from B1):
   ```
   sudo zfs destroy zroot/local/root
   sudo zfs destroy zroot/local/home
   ssh -i "$key" -o IdentitiesOnly=yes root@homelab zfs send -c zbackup/backup/thinkpad/zroot/local/root@<snapshot> \
     | sudo zfs recv -u -o mountpoint=/ zroot/local/root
   ssh -i "$key" -o IdentitiesOnly=yes root@homelab zfs send -c zbackup/backup/thinkpad/zroot/local/home@<snapshot> \
     | sudo zfs recv -u -o mountpoint=/home zroot/local/home
   ```
   About 131 GB in all; run them in `tmux`. Check: the received snapshot's
   `guid` (`zfs get -H -o value guid <dataset>@<snapshot>`) equals homelab's for each.
7. Mount: `sudo nix run github:nix-community/disko/latest -- --mode mount --flake /tmp/nixOS#thinkpad`.
   Check: `/mnt/home/lilijoy` and `/mnt/etc/ssh/ssh_host_ed25519_key` exist;
   `/mnt/var/lib/sops-nix/key.txt` exists (`test -f`, don't read it).
8. ⚠ Install, building straight into the new disk's store:
   ```
   sys=$(sudo nix build --no-link --print-out-paths --store /mnt \
     /tmp/nixOS#nixosConfigurations.thinkpad.config.system.build.toplevel)
   sudo nixos-install --system "$sys" --no-root-passwd --no-channel-copy
   ```
   The boot entry is unsigned until the Secure Boot keys exist (D1).
9. ⚠ Firmware (F1 at power-on), Security → Secure Boot: **Reset to Setup
   Mode** (Secure Boot stops enforcing, so the unsigned entry boots). Save,
   remove the stick, boot NixOS: the owner types the LUKS passphrase.
   Check: login works; `ls /run/secrets` lists secrets; `zpool status -x`
   healthy; `swapon --show` shows the swap LV; `tailscale status` up.

## D. Secure Boot (new NixOS)

1. ⚠ Keys and enrollment:
   `sudo sbctl status` (Setup Mode: Enabled; keys present in `/var/lib/sbctl`, made at first boot),
   `sudo sbctl enroll-keys --microsoft` (Microsoft's keys keep Windows and the GPU's option ROM booting),
   then re-sign the current generation: `sudo /run/current-system/bin/switch-to-configuration boot`.
   Check: `sudo sbctl verify` lists the ESP's NixOS files as signed.
2. ⚠ Firmware: Secure Boot **On**. Boot NixOS. Check: `sbctl status` shows
   Secure Boot enabled; `bootctl status` says "Secure Boot: enabled (user)".
3. ⚠ Firmware hardening (owner): set the **supervisor password** (save it in
   Bitwarden first), turn **network boot** (PXE/IPv4/IPv6 network stack) off,
   and turn on the **password at the F12 boot device list**.

## E. Windows in the boot menu, and Windows' settings (Windows)

1. Boot Windows from F12 (its own boot files on the Intel disk still work).
2. ⚠ Copy its boot files onto NixOS's ESP (admin terminal):
   `diskpart` → `list disk` → `select disk <the 465 GB Samsung>` → `list partition` →
   `select partition 1` (2 GB, System) → `assign letter=S` → `exit`; then
   `bcdboot C:\Windows /s S: /f UEFI`; then `mountvol S: /D`.
3. Reboot. bcdboot puts Windows first in the firmware boot order, so in
   NixOS (`nix shell nixpkgs#efibootmgr`): `efibootmgr` to see the entries,
   then `sudo efibootmgr -o <Linux Boot Manager>,<Windows Boot Manager>,…`.
   Check: the boot menu lists NixOS and Windows Boot Manager, and Windows boots from it.
4. ⚠ BitLocker with TPM + PIN (owner types the PIN; the recovery key goes
   straight into Bitwarden, never into notes):
   - `gpedit.msc` → Computer Configuration → Administrative Templates →
     Windows Components → BitLocker Drive Encryption → Operating System
     Drives → **Require additional authentication at startup**: Enabled,
     "Require startup PIN with TPM".
   - `manage-bde -protectors -add C: -RecoveryPassword` (owner saves the
     shown key in Bitwarden), then `manage-bde -on C: -TPMAndPIN`.
   - Reboot into Windows: it asks for the PIN. Check: `manage-bde -status C:`
     shows protectors "TPM And PIN" and "Numerical Password".
5. ⚠ In Windows, admin PowerShell: download and run
   `files/windows/dual-boot.ps1` from the branch
   (`https://raw.githubusercontent.com/LilijoySkyseeker/nixOS/thinkpad-fde/files/windows/dual-boot.ps1`):
   `powershell -ExecutionPolicy Bypass -File dual-boot.ps1 -NoSignInOnResume`
   (only once step 4's BitLocker PIN works: that PIN is then the unlock).
   Check: the power menu shows Hibernate and no Sleep; the power button
   shuts down (press it once); `powercfg /a` lists
   Hibernate available; the clock is right in both OSes after a reboot each
   way; closing the lid hibernates, and opening it asks only for the
   BitLocker PIN.

## F. Unlock NixOS with TPM + PIN and the YubiKeys (NixOS, last)

Last, because the Secure Boot state is now final.

1. ⚠ `hosts/thinkpad/README.md` § Disk encryption and boot has the commands:
   TPM2 + PIN (the owner picks the PIN), then FIDO2 for each YubiKey, one
   plugged in at a time. Each asks for the passphrase.
2. Check: `sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-root-luks`
   lists password, tpm2 and two fido2 slots, and each YubiKey's slot opens
   with the README's `cryptsetup open --test-passphrase --token-only` check.
   Reboot with no YubiKey plugged in: "Please enter LUKS2 token PIN:", the
   TPM PIN alone unlocks. A few wrong PINs lock the TPM out for a while (the
   passphrase still works); don't test that.

## G. Checks, then finish

1. Hibernate: close the lid; open it; PIN; the session comes back, unlocked,
   as left. KDE's power menu has Hibernate and no Sleep. Do it three times;
   if a resume ever boots fresh instead, `journalctl -k -b | grep -E "memory map|Image mismatch"`
   says whether the firmware's memory map moved (note it for the owner).
   In Windows, the lid hibernates too, and opening it asks only for the
   BitLocker PIN.
   The step before each hibernate names the entry that boots the running
   system as the next boot's one-time choice; check it finds one under
   lanzaboote: `sudo systemctl start hibernate-prepare`, then
   `tail -c +5 /sys/firmware/efi/efivars/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f | tr -d '\0'`
   prints an ID that `bootctl list` shows for the running generation; clear it
   with `sudo bootctl set-oneshot ''`. The journal says "no boot entry boots
   the running system" if it found none.
2. Backups: on homelab, `zrepl status` shows the `thinkpad` job replicating
   again (it should continue from the restored snapshot). Then release the
   holds: `zfs release reinstall <both snapshots from B3>`.
3. The owner merges the `thinkpad-fde` PR the same day. Until it merges,
   thinkpad's weekly pull-deploy (Thursday 03:00) would install `master`,
   which doesn't know this disk layout.
4. Delete this machine's runbook file from the stick's `_toolbox/runbooks/`.

## If something goes wrong

- **Before C5** nothing is changed.
- **After C5**, the old system is gone; the backups held in B3 are intact.
  Redo from C5.
- **The PIN prompt falls back to the passphrase**: the Secure Boot state
  changed (firmware update, keys, Windows Secure Boot updates). Unlock with
  a YubiKey or the passphrase and re-seal (README).
- **Secure Boot refuses to boot NixOS**: firmware → Secure Boot off, boot,
  `sbctl verify`, re-sign with `switch-to-configuration boot`, turn it on.
