# secrets

sops-encrypted secrets. See `docs/procedures/secrets.md` for
adding/removing recipients or rotating values, and the repo-root
`.sops.yaml` for the recipient key list and `path_regex` this folder is
governed by.

## Inventory

- `secrets.yaml` — the encrypted secrets store. Never edit directly —
  only through `sops secrets/secrets.yaml`, which handles decrypt/
  re-encrypt around your edits.

## Gotchas

- Adding a new recipient (new host, key rotation) requires updating
  `.sops.yaml` at the repo root first, then running `sops updatekeys
  secrets/secrets.yaml` — editing this folder alone doesn't grant
  access to a new key.
