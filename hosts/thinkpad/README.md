# thinkpad - (Main Laptop)

## Hardware

- Chasis: ThinkPad P1 Gen 3, Lenovo
- CPU: Core i7-10750H 6x, Intel
- GPU: Quadro T1000 4GB Max-Q, NVIDIA
- RAM: 64 GB (2x32GB) DDR4 3200
- SSD1: 500 GB M.2, Samsung 970 EVO Plus
- SSD2: 256 GB M.2, INTEL SSDPEKKW256G8L
- Display: 15" 1080p 60Hz

## Secure Boot setup (lanzaboote, one-time manual steps)

`configuration.nix` declares `boot.lanzaboote.enable = true`, but
lanzaboote can't take effect purely declaratively — it needs manual
steps on this physical machine, in this order (see
nix-community/lanzaboote's own `docs/getting-started/`):

1. `sudo sbctl create-keys` — generates this machine's Secure Boot
   keys into `/var/lib/sbctl` (the `pkiBundle` path this config
   points at). Do this *before* the first `nixos-rebuild switch` that
   carries the lanzaboote config, so the activation script has keys to
   sign the boot entries with.
2. `nixos-rebuild switch` (or reboot into the new generation) — this
   replaces systemd-boot with lanzaboote's signed UKI entries. Secure
   Boot enforcement in firmware isn't on yet, so this boots fine
   either way; it's just laying down signed images.
3. Reboot into firmware ("Reboot into Firmware" from the boot menu) →
   Security → Secure Boot → enable it → "Reset to Setup Mode". **Do
   not** select "Clear All Secure Boot Keys" — that drops the
   Forbidden Signature Database (dbx) too. Save and exit.
4. Boot back into NixOS, then `sudo sbctl enroll-keys --microsoft`
   (includes Microsoft's OEM/boot-manager keys — needed to avoid boot
   issues from OptionROMs signed by Microsoft).
5. Reboot once more. Verify with `sudo sbctl verify` (all `/boot/EFI/...`
   entries except the raw `kernel-*` file should show signed) and
   `bootctl status` (should report `Secure Boot: enabled (user)`).

Only after this is confirmed working should the TPM2 auto-unlock work
(Phase 2, not yet implemented) be enrolled on this host — the TPM
seal needs to bind to a known-good Secure Boot state, not an
unenrolled one.

Treat this as beta: nix-community's lanzaboote itself flags sharp
edges on non-`main` channels. This host was chosen to go first
specifically because it's the easiest to physically recover if boot
breaks (vs. homelab's always-on services or torrent's daily-driver
desktop role).
