# files

Static assets. Most of these are consumed by external tools rather
than by Nix — don't assume "not referenced from a `.nix` file" means
"unused" (see `AGENTS.md`). Only one file here is actually wired into
Nix; the rest are read by whatever external app they're formatted for,
based on filename/extension convention. No in-repo pointer records
exactly which install of that app consumes each one — that mapping
lives in the ecosystem convention (VIA/Vial, AutoEQ, Picard), not in
this repo.

## Inventory

- `gruvbox-dark-rainbow.png` — used directly in `profiles/PC.nix` as a
  stylix/wallpaper image. The one file in this folder actually
  referenced from `.nix`.
- `doio.vil`, `ffkb.vil`, `sval_ColemakDH_WIP.vil`,
  `sval_HD-G_ORIGINAL.vil`, `sval_HD-N.vil` — VIA/Vial keyboard layout
  configs, loaded into the respective keyboard's firmware tool, not
  read by Nix.
- `A5+-autoeq.txt`, `ER4XR-B&K5128-5128DF-AutoEQ+BB.txt`,
  `ER4XR-Maiky76-Harman.txt` — AutoEQ parametric EQ profiles for
  specific IEMs/headphones, loaded into EQ software (not Nix).
- `S2721Q.icm` — ICC color profile for the S2721Q monitor, loaded by
  the OS/display color management stack.
- `PicardNamingScript.txt` — MusicBrainz Picard file-naming script,
  pasted into Picard's own settings.
- `480x480_profile.png`, `profile.png`, `scaled_profile.png` — profile/
  avatar images for external use, not consumed by any `.nix` file.

## Gotchas

- Nothing in this repo documents which specific external-tool install
  reads each file — if a file here stops being useful for its
  consuming app, check that app directly (VIA/Vial, an EQ tool,
  Picard) before assuming it's dead.
