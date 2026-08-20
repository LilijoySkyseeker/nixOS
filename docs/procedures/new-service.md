# Adding a new service

No scaffolding or generator exists for this — it's a plain file
following the pattern already in `services/` (`jellyfin.nix`,
`copyparty-iso.nix`, `factorio.nix`, `minecraft.nix`, `octodns.nix`,
`nfs.nix`).

1. Create `services/<name>.nix`. Unless the config needs to be
   parameterized across multiple hosts with different settings, this
   should be a plain config attrset setting NixOS module options
   directly — no custom `options`/`config` surface. See
   `docs/style-guide.md` for when a real options module (the `my<Name>`
   pattern) is actually warranted instead.
2. Import it from the `imports` list of whichever host's
   `configuration.nix` needs it.
3. If the service is genuinely reusable/parameterized across hosts,
   it likely belongs in `modules/nixos/` instead, following the
   `my<Name>` options convention — see `docs/style-guide.md` and
   `docs/architecture.md`'s `modules/` vs `services/` split.
4. Validate with `nixos-rebuild build --flake .#<host>` (never
   `switch` unprompted — see `AGENTS.md`).
5. If the service writes state on an impermanence host (currently
   homelab), check the new state paths against that host's
   persistence list before deploying.

There's no service-specific README requirement — one-line entries in
`services/README.md`'s inventory (see `docs/README-template.md`) are
enough unless the service has non-obvious gotchas worth a longer note.
