# services

One-off NixOS service configs, mostly for things run on homelab. No
options surface — imported directly by whichever host's
`configuration.nix` needs them. See `docs/architecture.md` for the
`modules/` vs `services/` boundary and `docs/procedures/new-service.md`
for adding one.

## Inventory

- `copyparty-iso.nix` — no-auth whole-filesystem file server, for the
  recovery ISO only.
- `factorio.nix` — Factorio dedicated server.
- `jellyfin.nix` — Jellyfin media server, NVENC/NVDEC primary
  transcoder with Intel QSV/VAAPI fallback.
- `minecraft.nix` — Minecraft server + Geyser Bedrock listener,
  whitelist/ops driven from a sops-templated secret.
- `minecraft-geyser-config/` — Geyser-Fabric mod config data (not Nix).
- `nfs.nix` — tailnet-only NFSv4 server for `/storage` and
  `/storage-bulk`.
- `octodns.nix` — DNS zone management; zone data is Nix-rendered, keyed
  off `vars.domain` from `flake.nix`.

## Gotchas

- `copyparty-iso.nix`'s no-auth config is safe only because it's
  ISO-only ephemeral state — do not reuse this file's shape on a
  persistent host.
- `factorio.nix` re-patches `server-settings.json` fields on every
  container start, because the upstream factoriotools image only
  seeds that file once on first run — a stale image-seeded value
  wouldn't otherwise get corrected.
