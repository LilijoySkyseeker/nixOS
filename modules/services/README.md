# modules/services

One-off NixOS service configs, mostly for things run on homelab. No
options surface — each registers as `flake.modules.nixos.<name>` and
is listed by whichever host needs it in `modules/flake/hosts.nix`. See
`docs/architecture.md` for the module-organization boundary and
`docs/procedures/new-service.md` for adding one.

## Inventory

- `copyparty-iso.nix` — no-auth whole-filesystem file server, for the
  recovery ISO only.
- `factorio.nix` — Factorio dedicated servers: `old.factorio`
  (experimental-branch pin, the long-running world) and `new.factorio`
  (floating `stable` tag, a fresh random world), sharing mods/settings.
- `jellyfin.nix` — Jellyfin media server, NVENC/NVDEC primary
  transcoder with Intel QSV/VAAPI fallback.
- `minecraft.nix` — Minecraft server + Geyser Bedrock listener,
  whitelist/ops driven from a sops-templated secret.
- `minecraft-geyser-config/` — Geyser-Fabric mod config data (not Nix).
- `nfs.nix` — tailnet-only NFSv4 server for `/storage` and
  `/storage-bulk`.
- `octodns.nix` — DNS zone management; zone data is Nix-rendered, keyed
  off `vars.domain` from `flake.nix`.
- `samba.nix` — tailnet-only SMB share of the same `/storage` and
  `/storage-bulk` datasets as `nfs.nix`, for Android clients (no usable
  native NFS client). Declarative sops-managed password via a
  `samba-user-provision` systemd unit.

## Gotchas

- `copyparty-iso.nix`'s no-auth config is safe only because it's
  ISO-only ephemeral state — do not reuse this file's shape on a
  persistent host.
- `factorio.nix` re-patches `server-settings.json` fields on every
  container start, because the upstream factoriotools image only
  seeds that file once on first run — a stale image-seeded value
  wouldn't otherwise get corrected. Applies to both servers.
- `new.factorio`'s mods directory is rsynced from `old.factorio`'s on
  every container start (not a shared/bind-mounted directory) so it
  can still update/add its own mods independently afterwards without
  writing back into `old.factorio`'s volume.
