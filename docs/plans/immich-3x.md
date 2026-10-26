# Immich 2.x to 3.x on homelab

## Goal

Get Immich off the end-of-life 2.x line (2.7.5 carries
CVE-2026-59258 and CVE-2026-82272, allowed through a version-exact
`permittedInsecurePackages` exemption, accepted risk AR-9).

## Your decisions

- 2026-10-06: wait for NixOS 26.11 (expected late November 2026) rather
  than pin Immich from unstable now. Immich is tailnet-only, which keeps
  the CVEs hard to reach meanwhile.

## State

homelab is on nixpkgs-stable 26.05 with Immich 2.7.5; unstable has 3.2.4.
A merged stable move switches homelab by itself at the next Tuesday
03:00 pull-deploy, so the database migration runs unattended unless the
switch is done by hand.

## Next

When 26.11 is out:

1. Read Immich's 2.x to 3.x upgrade notes and breaking changes, and check
   the stable NixOS module drives 3.x.
2. Confirm a restorable backup of the Immich database and
   `/storage/immich` (`docs/procedures/backup-restore.md`).
3. VM-test the migration, not just the build.
4. Move homelab's stable input to 26.11, switch and watch the database
   migration on the first switch.
5. Drop the `immich-2.7.5` exemption in `modules/services/immich.nix`,
   check `immich-machine-learning` moved too (the exemption never named
   it), and retire AR-9 in `docs/accepted-risks.md`.

Also drop the 26.05 journald spellings: the `extraConfig` branch in
`modules/profiles/default.nix` and vps's `extraConfig` cap in
`hosts/vps/configuration.nix` (back to `settings.Journal.SystemMaxUse`). Keep
`Storage = "persistent"` when collapsing the branch: 26.11 dropped
NixOS's own default for it.
