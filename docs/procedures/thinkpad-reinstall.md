# Reinstall thinkpad: encrypted root, Secure Boot, Windows dual boot

A runbook for the agent on the TOOLBOX stick (`docs/procedures/toolbox-stick.md`),
carried out with the owner at the machine. It wipes and reinstalls NixOS on
one disk, restores the owner's data onto it from homelab's backups, turns on
Secure Boot, and puts Windows, encrypted with BitLocker, in the boot menu.
The steps suit another machine too: change the values below and the host's
`disko.nix`.

Each step says who does it: **agent** (alone), **owner** (their hands: a
firmware screen, a QR code, a key to plug in, a test), or ⚠ (the agent
prepares it, the owner says yes and types any secret). The stick's
`Runbooks/README.md` and its agents' instructions hold the general rules
for working with the owner at the machine.

## The machine and its values

| What | Value |
|---|---|
| Machine | hostname `thinkpad`; Lenovo ThinkPad P1 Gen 3 |
| NixOS disk (wiped) | Samsung SSD 970 EVO Plus 500GB, serial `S58SNS0R706072M`, `/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_500GB_S58SNS0R706072M` |
| Windows disk (never touched by this runbook's disk commands) | INTEL SSDPEKKW256G8L, 256 GB, serial `BTHH851316MB256B` |
| Flake | `https://github.com/LilijoySkyseeker/nixOS`, branch `master`, `#thinkpad` |
| Backups | on `homelab` (Tailscale name), `zbackup/backup/thinkpad/zroot/local/root` and `…/home` |
| Layout | ESP 2G (`/boot`), then LUKS2 `crypt` → LVM `vg`: `swap` 64G, `zfs` = pool `zroot` (`hosts/thinkpad/disko.nix`) |
| SSH to homelab from the stick | the keychain YubiKey 5C NFC, serial `27674308` (`modules/flake/vars.nix`) |
| Secrets | all in Bitwarden: LUKS recovery passphrase, firmware supervisor password, BitLocker recovery key |

## Rules for this job

- **Tell the owner the plan and wait for their yes** before each step marked
  ⚠ (disk, firmware or boot changes). Before the wipe, show them the disk's
  model and serial and get a yes for that exact disk.
- **The owner types every secret**: the LUKS recovery passphrase, PINs, the
  YubiKey PIN and touch, the firmware supervisor password, Bitwarden. Don't
  ask for them, read them, or put them in files or notes. Commands that
  print a secret (named below) run in the owner's window.
- Never read, edit or decrypt anything under `secrets/` or
  `/var/lib/sops-nix`, and never print private keys.
- After each step, run its check before going on. Log progress, findings and
  the next step in this machine's `NOTES.md` on the stick after every step
  and before every reboot or switch of OS, so the next agent (in another
  OS, maybe another CLI) picks up where it stopped.
- If a check fails, stop and tell the owner. Nothing below is worth guessing
  past: the backups on homelab are the way back.

## Before the day

- **Owner:** prove the keychain YubiKey's FIDO2 PIN works (log in to
  Bitwarden with it, or `ssh-keygen -K` on torrent). The FIDO2 PIN can be
  longer than the key's other PINs; a wrong one costs one of its 8 tries,
  and at 0 the FIDO2 app must be reset, which deletes the SSH key.
- **Agent, on torrent:** build `#thinkpad` from `master`, and run the
  `thinkpad-disk` VM test (`nix build .#checks.x86_64-linux.thinkpad-disk`):
  it rehearses the disk layout, TPM + PIN unlock and hibernation. It
  doesn't build the Home Manager session, so a desktop bug shows only at C9.

## A. Windows and firmware updates (Windows, owner)

1. In Windows, the stick's **Upgrade Windows** brings it to the newest
   Windows 11, then Windows Update until nothing is pending. Leave BitLocker
   off for now.
2. Update the BIOS with Lenovo's tool (Lenovo Vantage or Commercial Vantage).
   Check: the BIOS version in the firmware setup (F1 at power-on) is the
   newest Lenovo lists for the P1 Gen 3 (the agent can compare it with LVFS:
   `fwupdmgr get-updates`).

Both change what the TPM measures, so they come before anything is sealed
to it.

## B. Final backup, checked on homelab before the shutdown

homelab *pulls* from the thinkpad, so once the thinkpad is off nothing newer
can reach it. B2 and B3 come **before** B4.

1. Owner stops using the laptop. On the thinkpad (old NixOS):
   `run0 zrepl signal wakeup snapshots`, then `zfs list -t snapshot -o name,guid -s creation zroot/local/home zroot/local/root | tail -4`.
   Note the newest `zrepl_…` snapshot of each.
2. From a machine on the tailnet that homelab trusts (torrent, in the
   owner's shell): `ssh root@homelab zrepl signal wakeup thinkpad`, wait a
   few minutes, then check that the snapshot from B1 is on homelab for both
   datasets, with the same GUIDs:
   `ssh root@homelab zfs list -t snapshot -o name,guid zbackup/backup/thinkpad/zroot/local/root zbackup/backup/thinkpad/zroot/local/home | grep <snapshot>`
3. Hold both, so homelab's pruning can't remove them during the job, and
   **write the snapshot name and both GUIDs into `NOTES.md`** (C6 checks
   against them):
   `ssh root@homelab zfs hold reinstall zbackup/backup/thinkpad/zroot/local/root@<snapshot> zbackup/backup/thinkpad/zroot/local/home@<snapshot>`
4. Shut the thinkpad down. Anything written after B1 is lost.

## C. Wipe, restore, install (Rescue System)

Boot the stick's Rescue System on the thinkpad. A reboot of the Rescue
System loses the `/tmp` clone, its Tailscale login and the YubiKey's key
file: redo C1 and C2 after one. Keep the stick in a port away from the
YubiKey: unplugged together, the stick's writes are lost.

1. **Owner + agent:** internet (Wi-Fi or the phone's USB tethering), then
   the tailnet: `sudo tailscale up --qr` in a window on the screen (the
   owner scans the QR code and approves).
   Clone: `git clone https://github.com/LilijoySkyseeker/nixOS /tmp/nixOS`.
2. **Owner + agent:** SSH to homelab with the keychain YubiKey. First
   `ykman fido info`: the serial must be `27674308`, and it shows the PIN
   tries left. Then, in a window on the screen (the owner enters the FIDO2
   PIN): `mkdir /tmp/sk && cd /tmp/sk && ssh-keygen -K` writes the key and
   its `.pub` (usually `id_ed25519_sk_rk`). "Provider returned failure -3 /
   incorrect passphrase supplied" means a wrong FIDO2 PIN: stop after one,
   don't retry. Use the private file in every SSH command below:
   ```
   key=/tmp/sk/id_ed25519_sk_rk
   ssh -i "$key" -o IdentitiesOnly=yes root@homelab true   # owner touches the key
   ```
   Check: it returns without error.
3. **Agent:** find the disks: `lsblk -o NAME,SIZE,MODEL,SERIAL`. Show the
   owner the Samsung's model and serial, compare with the table above.
4. ⚠ Make only that disk writable: `disk-rw /dev/<the Samsung, e.g. nvme0n1>`,
   never the Intel. The LUKS and LVM volumes made on it next stay writable
   with it.
5. ⚠ Wipe, then format, from `/tmp` (the format asks for the LUKS
   passphrase: the owner generates a long random one in Bitwarden, saves it
   there as the thinkpad's recovery passphrase, and types it):
   ```
   cd /tmp
   sudo nix run github:nix-community/disko/v1.13.0 -- --mode destroy --flake /tmp/nixOS#thinkpad
   sudo nix run github:nix-community/disko/v1.13.0 -- --mode format --flake /tmp/nixOS#thinkpad
   ```
   (`destroy,format` isn't a valid mode.) Check: `lsblk` shows `crypt` →
   `vg-swap` (64G) and `vg-zfs`; `zpool status zroot` is ONLINE;
   `zfs list -r zroot` shows `local/{nix,root,home,secureboot}`.
6. ⚠ Replace the empty root and home with the backups (snapshot from B1),
   about 128 GiB, about 40 minutes over Wi-Fi, two YubiKey touches. Show
   progress and an ETA: `zfs send -nvP` gives each size, then `pv -s`.
   ```
   sudo zfs destroy zroot/local/root
   sudo zfs destroy zroot/local/home
   ssh -i "$key" -o IdentitiesOnly=yes root@homelab zfs send -c zbackup/backup/thinkpad/zroot/local/root@<snapshot> \
     | sudo zfs recv -u -o mountpoint=/ zroot/local/root
   ssh -i "$key" -o IdentitiesOnly=yes root@homelab zfs send -c zbackup/backup/thinkpad/zroot/local/home@<snapshot> \
     | sudo zfs recv -u -o mountpoint=/home zroot/local/home
   ```
   Check: each received snapshot's `guid`
   (`zfs get -H -o value guid <dataset>@<snapshot>`) equals the one noted
   at B3.
7. **Agent:** mount: `sudo nix run github:nix-community/disko/v1.13.0 -- --mode mount --flake /tmp/nixOS#thinkpad </dev/null`.
   Check: `/mnt/home/lilijoy` and `/mnt/etc/ssh/ssh_host_ed25519_key` exist;
   `/mnt/var/lib/sops-nix/key.txt` exists (`test -f`, don't read it).
8. ⚠ Install, building straight into the new disk's store (about 35
   minutes: some 1,900 paths to fetch and 1,400 small builds). Run it under
   one `sudo` with `nom` for progress; piping `nom` through `tee` garbles it.
   ```
   sys=$(sudo nix build --no-link --print-out-paths --store /mnt \
     /tmp/nixOS#nixosConfigurations.thinkpad.config.system.build.toplevel)
   sudo nixos-install --system "$sys" --no-root-passwd --no-channel-copy
   ```
   The boot entry is unsigned until the Secure Boot keys exist (D1).
9. ⚠ **The firmware boot entry.** The install can leave "Linux Boot
   Manager" pointing at the wiped ESP, and the first boot then lands in
   Windows. Check: `efibootmgr` shows "Linux Boot Manager" on the new
   ESP's PARTUUID (`blkid -s PARTUUID -o value /dev/disk/by-partlabel/disk-root-esp`),
   first in BootOrder. If not, create it and delete the stale entries
   (by the numbers `efibootmgr` shows; never guess them):
   ```
   sudo efibootmgr -c -d /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_500GB_S58SNS0R706072M -p 1 \
     -L "Linux Boot Manager" -l '\EFI\systemd\systemd-bootx64.efi'
   sudo efibootmgr -b <stale number> -B
   ```
10. **Agent:** close everything before the reboot, or the new system may
    find the pool in use: `sudo umount -R /mnt && sudo swapoff -a && sudo zpool export zroot && sudo vgchange -an vg && sudo cryptsetup close crypt`.
11. ⚠ **Owner:** firmware (F1 at power-on), Security → Secure Boot:
    **Reset to Setup Mode** (Secure Boot stops enforcing, so the unsigned
    entry boots). Save, remove the stick, boot NixOS, type the LUKS
    passphrase.
    Check: the graphical login works and the desktop has its wallpaper and
    panel; `ls /run/secrets` lists secrets; `zpool status -x` healthy;
    `swapon --show` shows the swap LV; `tailscale status` up. A broken
    desktop: log in on a TTY (Ctrl+Alt+F3), and collect
    `journalctl -b -p warning` and `journalctl --user -b -u plasma-plasmashell`
    for the agent.

## D. Secure Boot (new NixOS)

The agent here runs sandboxed: no system journal, EFI variables or `/boot`.
The owner runs each root command block and pastes the output.

1. ⚠ Keys and enrollment:
   `sudo sbctl status` (Setup Mode: Enabled; keys present in `/var/lib/sbctl`, made at first boot),
   `sudo sbctl enroll-keys --microsoft` (Microsoft's keys keep Windows and the GPU's option ROM booting),
   then re-sign the current generation: `sudo /run/current-system/bin/switch-to-configuration boot`.
   If enrollment refuses because EFI variables are immutable, remove the
   immutable flag from exactly the variables it names
   (`nix shell nixpkgs#e2fsprogs -c sudo chattr -i <path>`), then retry.
   Check: `sudo sbctl verify` lists `BOOTX64.EFI`, `systemd-bootx64.efi` and
   each generation's entry as signed. A separate unsigned
   `EFI/nixos/kernel-*.efi` is expected with lanzaboote.
2. ⚠ **Owner, one firmware visit:** Secure Boot **On** (keep the enrolled
   keys: don't restore factory keys); set the **supervisor password** (save
   it in Bitwarden first) and **Lock UEFI BIOS Settings** On; network boot
   off (UEFI Wi-Fi network boot, IPv4 and IPv6 network stack); **password at
   the F12 boot device list** On. F10 to save. Boot NixOS.
   Check: `sbctl status` shows Secure Boot enabled; `bootctl status` says
   "Secure Boot: enabled (user)".

## E. Windows in the boot menu, BitLocker, Windows' settings (Windows)

Admin steps in Windows show a UAC prompt: the agent's own shell isn't
elevated.

1. **Owner:** boot Windows from F12 (its own boot files on the Intel disk
   still work).
2. ⚠ Copy its boot files onto NixOS's ESP, in an admin terminal. Type
   `diskpart`, then at the `DISKPART>` prompt one line at a time (pasted
   together, they run out of order):
   ```
   list disk
   select disk <the 465 GB one>
   detail disk
   list partition
   ```
   Check: `detail disk` names the Samsung 970 EVO Plus, and partition 1 is
   the 2 GB System partition. Stop if not. Then:
   ```
   select partition 1
   assign letter=S
   exit
   ```
   Back in PowerShell: `bcdboot C:\Windows /s S: /f UEFI` ("Boot files
   successfully created"), then `mountvol S: /D`.
3. **Owner:** reboot through F12 → Linux Boot Manager → systemd-boot →
   Windows Boot Manager. Check: Windows reaches the desktop; `bcdedit /enum
   firmware` (admin) lists Linux Boot Manager before Windows Boot Manager.
   If Windows comes first, put Linux Boot Manager back first in the
   firmware's boot order, or in NixOS with `efibootmgr -o`.
4. ⚠ BitLocker with TPM + PIN:
   - Preflight (admin, agent): `manage-bde -status C:` is Fully Decrypted
     with no protectors; `reagentc /info` says Windows RE is **Enabled**.
     Without Windows RE, `manage-bde -on` fails with 0x80070002. A fresh
     install can leave it disabled: give the Intel disk's Recovery
     partition a letter (check its type is `de94bba4-06d1-4d40-a16a-bfd50179d6ac`),
     `reagentc /setreimage /path R:\Recovery\WindowsRE`, `reagentc /enable`,
     then remove the letter.
   - **Owner:** `gpedit.msc` → Computer Configuration → Administrative
     Templates → Windows Components → BitLocker Drive Encryption →
     Operating System Drives → **Require additional authentication at
     startup**: Enabled, and all four dropdowns: Configure TPM startup:
     *Do not allow TPM*; startup PIN: *Require startup PIN with TPM*;
     startup key: *Do not allow startup key with TPM*; startup key and PIN:
     *Do not allow startup key and PIN with TPM*.
     Check (agent): `reg query HKLM\SOFTWARE\Policies\Microsoft\FVE` shows
     `UseTPM 0`, `UseTPMPIN 1`, `UseTPMKey 0`, `UseTPMKeyPIN 0`. Don't edit
     those values directly: Group Policy rewrites them.
   - ⚠ **Owner's own admin window** (it shows the recovery key):
     `manage-bde -protectors -add C: -RecoveryPassword` (the owner saves the
     key in Bitwarden), then `manage-bde -on C: -TPMAndPIN` (the owner
     types the PIN).
   - **Owner:** restart through systemd-boot for BitLocker's hardware test:
     it asks for the PIN; encryption starts after it.
   - Check (agent): until that restart, `manage-bde -status C:` ends with
     "ACTIONS REQUIRED" and **prints the recovery key**, so read only
     filtered lines (untested filter: check it shows no 48-digit number):
     `manage-bde -status C: | Select-String 'Conversion Status','Percentage Encrypted','Protection Status','TPM And PIN','Numerical Password'`.
     `Get-BitLockerVolume` returns the key in its objects too. Done:
     Fully Encrypted, Protection On (it stays Off until 100%), protectors
     TPM And PIN and Numerical Password. If a recovery key reaches an
     agent, add a new one in the owner's window and delete the exposed
     protector by its ID.
5. **Agent** (admin, via UAC): download and run `files/windows/dual-boot.ps1`
   (`https://raw.githubusercontent.com/LilijoySkyseeker/nixOS/master/files/windows/dual-boot.ps1`):
   `powershell -ExecutionPolicy Bypass -File dual-boot.ps1 -NoSignInOnResume`
   (only once step 4's BitLocker PIN works: that PIN is then the unlock).
   Check with `powercfg /qh SCHEME_CURRENT SUB_BUTTONS` and
   `powercfg /qh SCHEME_CURRENT SUB_NONE CONSOLELOCK` (`/q` hides these);
   `powercfg /a` lists Hibernate.
   **Owner** tests: the power menu shows Hibernate and no Sleep; the power
   button shuts down; Start → Hibernate and closing the lid each hibernate,
   and powering on asks only for the BitLocker PIN and restores the
   session; the clock is right after a reboot.
6. **Owner:** shut Windows down fully (not hibernate) before booting NixOS.

## F. Unlock NixOS with TPM + PIN and the YubiKeys (NixOS, last)

Last, because the Secure Boot state is now final.

1. ⚠ `hosts/thinkpad/README.md` § Disk encryption and boot has the commands:
   TPM2 + PIN (the owner picks the PIN), then FIDO2 for each YubiKey, one
   plugged in at a time. Each asks for the passphrase.
2. Check: `sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-root-luks`
   lists password, tpm2 and two fido2 slots, and each YubiKey's slot opens
   with the README's test command. Token IDs (`cryptsetup luksDump`) aren't
   keyslot numbers: the test takes the token ID.
   **Owner:** reboot with no YubiKey plugged in: "Please enter LUKS2 token
   PIN:", the TPM PIN alone unlocks. A few wrong PINs lock the TPM out for a
   while (the passphrase still works); don't test that.

## G. Checks, then finish

1. Hibernate (owner pastes the root commands' output): the step before
   each hibernate names the entry that boots the running system as the next
   boot's one-time choice; check it finds one under lanzaboote:
   `sudo systemctl start hibernate-prepare`, then
   `tail -c +5 /sys/firmware/efi/efivars/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f | tr -d '\0'`
   prints an ID that `bootctl list` shows for the running generation; clear it
   with `sudo bootctl set-oneshot ''`. The journal says "no boot entry boots
   the running system" if it found none.
   **Owner:** close the lid; open it; PIN; the session comes back,
   unlocked, as left. KDE's power menu has Hibernate and no Sleep. Do it
   three times; if a resume ever boots fresh instead,
   `journalctl -k -b | grep -E "memory map|Image mismatch"` says whether the
   firmware's memory map moved (note it for the owner).
2. Backups: homelab pulls every 15 minutes, and pulls while the laptop
   hibernates fail (expected). Check that homelab's **newest** snapshot of
   root and of home has the same name and GUID as the thinkpad's
   (`zfs list -t snapshot -o name,guid -s creation <dataset> | tail -1` on
   each side), and is newer than the restored one. A fixed snapshot name
   won't do: homelab prunes it within hours. Then release the holds:
   `zfs release reinstall <both snapshots from B3>`, and check
   `zfs holds` lists none.
3. Close the job: write it up in `NOTES.md` and the retrospective, and,
   with the owner's yes, delete this machine's runbook from the stick's
   `Runbooks/`.

## If something goes wrong

- **Before C5** nothing is changed.
- **After C5**, the old system is gone; the backups held in B3 are intact.
  Redo from C5.
- **The PIN prompt falls back to the passphrase**: the Secure Boot state
  changed (firmware update, keys, Windows Secure Boot updates). Unlock with
  a YubiKey or the passphrase and re-seal (README).
- **Secure Boot refuses to boot NixOS**: firmware → Secure Boot off, boot,
  `sbctl verify`, re-sign with `switch-to-configuration boot`, turn it on.
- **Windows asks for the BitLocker recovery key**: expected once after
  systemd-boot changes or when Windows is started another way (README,
  Dual boot). The key is in Bitwarden.
