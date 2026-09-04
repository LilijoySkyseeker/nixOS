# Adding a new service

No scaffolding or generator exists for this — it's a plain file
following the pattern already in `modules/services/` (`jellyfin.nix`,
`immich.nix`, `copyparty-iso.nix`, `factorio.nix`, `minecraft.nix`,
`octodns.nix`, `nfs.nix`, `samba.nix`).

1. Create `modules/services/<name>.nix`, registering as
   `flake.modules.nixos.<name> = { ... }: { ... };`. Unless the config
   needs to be parameterized across multiple hosts with different
   settings, the inner module should be a plain config attrset setting
   NixOS module options directly — no custom `options`/`config`
   surface. See `docs/style-guide.md` for when a real options module
   (the `my<Name>` pattern) is actually warranted instead.
2. Add its registration key to whichever host's `modules = [ ... ]`
   list in `modules/flake/hosts.nix` needs it. Creating the file makes
   it discoverable (`import-tree` picks up any `.nix` file under
   `modules/`) but not used by any host until it's listed there.
3. If the service is genuinely reusable/parameterized across hosts, it
   likely belongs in `modules/nixos/` instead, following the
   `my<Name>` options convention — see `docs/style-guide.md` and
   `docs/architecture.md`'s module-organization boundary.
4. Validate with `nixos-rebuild build --flake .#<host>` (never
   `switch` unprompted — see `AGENTS.md`).
5. If the service writes state on an impermanence host (currently
   homelab), check the new state paths against that host's
   persistence list before deploying.
6. Apply the security-hardening conventions in `docs/hardening.md`
   (dedicated service user, systemd sandboxing, etc.) by default, not
   just when asked.

There's no service-specific README requirement — `modules/services/`
has no README of its own (see `docs/procedures/updating-documentation.md`).
Re-run `scripts/doc-host.sh <host>` to refresh the affected host's
`hosts/<host>/README.md` "Host Inventory" block; a non-obvious gotcha
worth a longer note goes in that host's README instead.
