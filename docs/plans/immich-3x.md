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
Migration detail (database steps, what to check):
`docs/plans/todo/2026-09-24-migrate-homelab-s-immich-from-the-eol-2-x-to-3-x.md`.

## Next

When 26.11 is out: move homelab's stable input to it, drop the
`immich-2.7.5` exemption in `modules/services/immich.nix`, and follow the
migration plan, watching the database migration on the first switch.
Also drop the 26.05 journald spellings: the `extraConfig` branch in
`modules/profiles/default.nix` and vps's `extraConfig` cap in
`hosts/vps/configuration.nix` (back to `settings.Journal.SystemMaxUse`).
