# thinkpad: disk encryption, Secure Boot and Windows dual boot

## Goal

"do any and all tabled work that was planned for it. things along this
line is setting it up for full disk encryption, secure boot, automatic
decryption with the tpm, settign any setting necessary to live with
windows as a dual boot option with first class support, aka its in the
main boot menu, and any other little bits like the clock that need
fixed."

Underneath it: a stolen thinkpad shouldn't hand over its data or its
sops age key (accepted-risks D5).

## Your decisions

- 2026-10-06: keep this for thinkpad. Dropped: PC impermanence and the
  distributed-builders work that shared a plan with it.
- 2026-10-19: Windows 11 is installed on the Intel SSD; NixOS keeps the
  Samsung. Windows is encrypted too (BitLocker).
- 2026-10-19: unlock with TPM plus PIN, on both NixOS and Windows.
- 2026-10-19: keep the current NixOS data; restore it from homelab
  rather than set anything up again.
- 2026-10-19: hibernate replaces sleep on both systems. Lid closed:
  hibernate. Sleep fully hidden and disabled; the Hibernate button must
  be there and work.
- 2026-10-19: idle does nothing until 60 minutes, on AC or battery, then
  hibernates; the same on both systems.
- 2026-10-19: no automatic screen lock before the 60-minute hibernate
  either; screen stays on (hands-busy work). Lock by hand when leaving.
- 2026-10-19: a GUI toggle on KDE and on Windows pauses the idle
  hibernate for long-running tasks (screen locked by hand, trusted
  places only).
- 2026-10-19: a KDE notification when an installed update is waiting
  for a reboot.
- 2026-10-19: write the modules so another machine (e.g. a future
  laptop) can reuse them.
- 2026-10-19: clean up the leftover impermanence config (`/nix/state`)
  now.
- 2026-10-19: do the at-machine steps with Claude Code from the TOOLBOX
  stick, following a runbook written for it.
- 2026-10-19: fix the lid setting properly (`hybrid-sleep` can't work:
  ZFS adds `nohibernate`; KDE was handling the lid).

## State

Branch `thinkpad-fde`, built for thinkpad, not merged (it changes the disk
layout, so it merges on reinstall day). Done: `vars.mkEncryptedRootSsd`,
`myEncryptedRoot`, `mySecureBoot` (lanzaboote v1.2.0), `myHibernate` (VM
tested), `myHibernateOnly`, `myRebootNotice`, `files/windows/dual-boot.ps1`,
thinkpad wiring, README, runbook `docs/procedures/thinkpad-reinstall.md`.
Stick stub for `_toolbox/runbooks/`: `~/Agent/projects/thinkpad-reinstall/thinkpad.md`.
usb-toolbox (local commits, ship with the next ISO build and sync): pcscd
and YubiKey tools (`4919842`); dm volumes follow their disk's writability
(`e135e26`), without which disko fails in the Rescue System.

Facts checked 2026-10-19:

- Data to restore: `zroot/local/home` 126G, `zroot/local/root` 5G.
  `local/nix` (92G) is rebuilt by the install; `local/state` is empty.
- lanzaboote can't add a Windows that lives on another ESP
  (lanzaboote#427), so Windows' boot files go onto NixOS's ESP with
  `bcdboot`, where systemd-boot finds them itself.
- sbctl 0.18 (nixpkgs) enrolls Microsoft's 2023 certificates with
  `--microsoft`; Windows boot files are moving to them.
- NixOS's systemd-initrd `zfs-import-<pool>` has no ordering against
  `systemd-hibernate-resume.service`; importing before resume corrupts
  the pool (openzfs#12842). Needs an explicit `after`.
- Thunderbolt DMA protection is on (`iommu_dma_protection` = 1).
- The stick's AI Help and Rescue System share a per-machine folder
  (`_toolbox/collected/sessions/<maker-model-serial>/notes/NOTES.md`,
  read first, kept across reboots). Per docs/procedures/toolbox-stick.md
  the runbook lives in this repo, with a short `_toolbox/runbooks/
  thinkpad.md` on the stick that the owner copies there.
- Resuming through a newer kernel works on x86; systemd accepts the
  mismatch on purpose (`hibernate-resume-config.c`).

## Next

1. VM test of the real layout with TPM2 + PIN (running).
2. `/security-review` and Codex review, then the PR.
3. Owner: Windows upgrade and BIOS update; build the toolbox ISO and sync
   the stick, copy the stub; then the runbook at the machine.
