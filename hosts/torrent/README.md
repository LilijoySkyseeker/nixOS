# torrent - (Main Desktop)

## Hardware

- CPU: Ryzen 7 9800x3D 8x, AMD
- GPU: RX 7900XTX 24 GB, XFX SPEEDSTER MERC 310
- RAM: 96 GB (2x48GB) DDR5 6000MHz CL30, CORSAIR VENGEANCE
- SSD: 4 TB M.2, SAMSUNG 990 PRO
- Motherboard: X870 ATX LGA 1718, GIGABYTE AORUS ELITE ICE
- CPU Cooler: NH-D15 G2, Noctua
- Thermal Paste: PTM 7950
- Power Supply: 1000W ATX 80 PLUS PLATINUM, Super Flower Leadex VI
- Case: Torrent Black Solid, Fractal Design
- Monitors: 3x 27" 4K 60Hz, Dell S2721QS
- Keyboard (Gaming): WOOTING TWO HE
- Keyboard (Work): faux fox keyboard v4, fingerpunch
- Mouse: MM710 PMW3389, Cooler Master
- Headphones: WH-1000XM4 (Wired), Sony
- Speakers: A5+, Audioengine
- Microphone: AT2020, Audio-Technica
- Interface: RC-505MKII, BOSS

## Secure Boot setup (lanzaboote, one-time manual steps)

`configuration.nix` declares `boot.lanzaboote.enable = true`, but
lanzaboote can't take effect purely declaratively — it needs manual
steps on this physical machine, in this order (see
nix-community/lanzaboote's own `docs/getting-started/`), done after
thinkpad proved the process out:

1. `sudo sbctl create-keys` — generates this machine's Secure Boot
   keys into `/var/lib/sbctl` (the `pkiBundle` path this config
   points at), before the first `nixos-rebuild switch` carrying this
   config.
2. `nixos-rebuild switch` — replaces systemd-boot with lanzaboote's
   signed UKI entries. Firmware enforcement isn't on yet, so this
   boots fine either way.
3. Reboot into the GIGABYTE AORUS ELITE ICE firmware and put Secure
   Boot into *Setup Mode*. Desktop/ASUS-family boards (this is the
   same UEFI generation as the boards lanzaboote's docs call out)
   typically don't expose an explicit "Setup Mode" toggle — instead
   erase/reset the existing Platform Key (PK) under the Secure Boot
   settings; that puts the firmware in Setup Mode. **Do not** wipe the
   Forbidden Signature Database (dbx) while doing this — check exact
   menu wording on this board's firmware version, it varies. Save and
   exit.
4. Boot back into NixOS, then `sudo sbctl enroll-keys --microsoft`.
5. Reboot. Verify with `sudo sbctl verify` and `bootctl status`
   (`Secure Boot: enabled (user)`).

Only after this is confirmed working should the TPM2 auto-unlock work
(Phase 2, not yet implemented) be enrolled on this host. Treat this as
beta — same caveats as thinkpad's README.
