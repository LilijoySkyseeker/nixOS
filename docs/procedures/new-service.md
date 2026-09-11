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
   persistence list before deploying. If it warrants its own dataset
   (rollback/replication/backup should be decided for this service
   independently of its neighbours), add a `myDatasets` entry instead
   of a bare directory — see
   `docs/adr/0001-zfs-policy-tiers-and-the-mydatasets-registry.md`.
   `myDatasets` generates the disko entry, the ZFS properties and (where
   needed) the persistence entry, but **not** the dataset itself:
   disko only creates datasets when it formats a disk, so a new entry
   still needs a manual, one-time
   `zfs create -o mountpoint=<mountpoint> <dataset>` on the live host
   before the next deploy, or the path stays an ordinary directory
   inside its parent dataset instead of its own — silently defeating
   the whole point (plan:
   2026-09-05-adopt-zfs-policy-tiers-and-a-mydatasets-registry.md#G2).
   `<mountpoint>` is the entry's own
   `mountpoint` field verbatim if that path is already under
   `persistRoot` (the flat `/nix/state/<service>` convention new
   services use, e.g. Loki); otherwise it's `persistRoot` + that field
   (`modules/nixos/datasets.nix`'s `diskoMountpoint`), e.g.
   `/var/lib/docker` becomes `/nix/state/var/lib/docker`.
   `myZfsDatasetProperties` reapplies the rest
   (`com.sun:auto-snapshot`, etc.) on the next switch. If the path
   already held data (a reclassification, not a new service), that
   data is not carried over; only do this for state that's fine to
   start empty.

   `myDatasets`' `owner`/`group` fields only take effect on a
   *generated persistence entry* (a path outside `persistRoot`). A
   flat `/nix/state/<service>` dataset -- the convention new services
   should default to -- gets no persistence entry and so is **not**
   chowned by the registry at all; it mounts root:root unless the
   service module itself arranges ownership (a `systemd.tmpfiles.rules`
   entry, or a service that manages its own directory permissions on
   start). Don't assume declaring `owner` here is enough.
6. Apply the security-hardening conventions in `docs/hardening.md`
   (dedicated service user, systemd sandboxing, etc.) by default, not
   just when asked.

There's no service-specific README requirement — `modules/services/`
has no README of its own (see `docs/procedures/updating-documentation.md`:
only the `hosts/<name>/README.md` files and the root `README.md` exist).
Re-run `scripts/doc-host.sh <host>` so the host's inventory block picks
up the new service; a non-obvious host-specific gotcha goes in that
host's `hosts/<name>/README.md`.
