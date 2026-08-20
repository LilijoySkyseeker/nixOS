# secrets

sops-encrypted secrets. See `docs/procedures/secret-rotation.md` for
adding/removing recipients or rotating values, and the repo-root
`.sops.yaml` for the recipient key list and `path_regex` this folder is
governed by.

## Inventory

Secrets are split per-host so each host's age key only decrypts what that
host actually consumes (`modules/profiles/default.nix` picks the right
file per `networking.hostName`; wireguard_vps_homelab_psk gets an explicit
`sopsFile` override since it's shared). Never edit any of these directly —
only through `sops secrets/<file>.yaml`, which handles decrypt/re-encrypt
around your edits.

- `homelab.yaml` — homelab-only: `homelab_backblaze_rclone_config`,
  `homelab_backblaze_restic_password`, `homelab_discord_webhook`,
  `homelab_vps_deploy_key`, `homelab_wireguard_private_key`,
  `tailscale_authkey_homelab`, `minecraft_username`, `factorio_game_password`,
  `factorio_token`, `factorio_username`, `cloudflare_octodns_token`.
- `vps.yaml` — vps-only: `vps_wireguard_private_key`, `vps_caddy_env`,
  `vps_discord_webhook`, `tailscale_authkey_vps`.
- `shared-vps-homelab.yaml` — decryptable by both homelab and vps:
  `wireguard_vps_homelab_psk`.
- `pc.yaml` — decryptable by thinkpad and torrent (both run
  `modules/profiles/PC.nix`): `git_username`, `git_email`,
  `tailscale_authkey_thinkpad`, `tailscale_authkey_torrent`.
- `legacy.yaml` — entries with no current nix consumer, kept decryptable by
  every host as before: `open_weather_key`, `restic`, `nextcloud_admin_pass`,
  `webdav_lilijoy`, `winapps_password`, `tailscale_authkey_isoimage`. Move
  each into its owning host's file if it's still needed, or delete it if not.
- `secrets.yaml` — the old flat store. Keep it decryptable
  (`.sops.yaml`'s catch-all rule) only until every key above has been moved
  out and every `sops.secrets.*` declaration confirmed working against its
  new file, then delete it and drop the catch-all `creation_rules` entry.

## Migration steps (manual — run these yourself)

1. `sops secrets/secrets.yaml` — copy out each secret's decrypted value as
   you go (or `sops -d secrets/secrets.yaml` to dump all of them at once
   to inspect, but don't leave that output lying around unencrypted).
2. For each new file above: `sops secrets/<file>.yaml` (creates it fresh,
   encrypted to the key group `.sops.yaml` already defines for that path)
   and paste in just the keys that belong there.
3. Run a `nixos-rebuild build` (per-host) to confirm every
   `sops.secrets.*` declaration resolves against its new `sopsFile` /
   `defaultSopsFile` before switching anything.
4. Once every host builds clean and secrets are confirmed readable, delete
   `secrets/secrets.yaml` and remove the catch-all `creation_rules` entry
   from `.sops.yaml`.

## Gotchas

- Adding a new recipient (new host, key rotation) requires updating
  `.sops.yaml` at the repo root first, then running `sops updatekeys
  secrets/<file>.yaml` for the relevant file(s) — editing this folder
  alone doesn't grant access to a new key.
- `path_regex` order in `.sops.yaml` matters — sops uses the first match,
  so host-specific rules must stay above the `legacy`/catch-all rules.
