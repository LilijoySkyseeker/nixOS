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
- 2026-10-19: a GUI toggle on KDE and on Windows pauses the idle
  hibernate for long-running tasks (screen locked by hand, trusted
  places only).
- 2026-10-19: a KDE notification when an installed update is waiting
  for a reboot.
- 2026-10-19: write the modules so another machine (e.g. a future
  laptop) can reuse them.
- 2026-10-19: clean up the leftover impermanence config (`/nix/state`)
  now.
- 2026-10-19: fix the lid setting properly (`hybrid-sleep` can't work:
  ZFS adds `nohibernate`; KDE was handling the lid).

## State

Branch `thinkpad-fde`. Nothing built yet. The stale branch
`origin/worktree-fde-secureboot-plan` is direction only; its scripts,
runbooks, rollout flag and shared modules are not being carried over.

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
- Resuming through a newer kernel works on x86; systemd accepts the
  mismatch on purpose (`hibernate-resume-config.c`).

## Next

1. Modules: encrypted root disk layout (`vars`), TPM+PIN unlock,
   lanzaboote, hibernate-only power handling, reboot notice. Windows
   settings as a script under `files/windows/`.
2. VM test: ZFS on LUKS, hibernate, resume through a newer kernel.
3. At the machine: final zrepl snapshot + `zfs hold` on homelab, rescue
   stick, format, `zfs recv` root and home, `nixos-install`, Secure
   Boot keys (with Microsoft's), `bcdboot`, BitLocker TPM+PIN,
   supervisor password, TPM+PIN enroll last. Merge the PR the same day,
   before Thursday's pull-deploy.
