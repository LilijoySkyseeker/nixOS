# Secrets: rotation

## Rotation runbooks

No dedicated rotation script or automation exists beyond what's below
— this is a manual, low-frequency operation.

### Adding a recipient (new host, or rotating a compromised host's key)

1. Get the host's age public key (via `ssh-to-age` from its SSH host
   key, or from `sops.age.keyFile` if it already has one).
2. Add it to `.sops.yaml`'s `keys:` block as a new named YAML anchor,
   then reference it from the relevant `creation_rules` entry (matched
   by `path_regex: secrets/[^/]+\.(yaml|json|env|ini)$`).
3. Run `sops updatekeys secrets/secrets.yaml` so the file is
   re-encrypted for the updated recipient list. This is the only
   command needed — it doesn't touch the plaintext values, just who
   can decrypt them.

### Decrypting with a YubiKey (every host lost)

Both YubiKeys (keychain 5C NFC, torrent's 5C Nano) are recipients, each
through its own PIV identity, so either one alone opens the secrets from
any computer with `nix`:

```
nix shell nixpkgs#sops nixpkgs#age-plugin-yubikey
SOPS_AGE_KEY="$(age-plugin-yubikey --identity | grep '^AGE-PLUGIN')" \
  sops -d secrets/secrets.yaml
```

It asks for the PIV PIN and a touch. The plugin talks to the key through
the smart-card daemon `pcscd`. The PCs (`services.pcscd.enable`) and the
TOOLBOX stick's Rescue System run it, with `sops` and
`age-plugin-yubikey` installed; a borrowed system may not. If
`--identity` finds no YubiKey, start one by hand in a second terminal:

```
sudo env PCSCLITE_HP_DROPDIR="$(nix build --no-link --print-out-paths nixpkgs#ccid)/pcsc/drivers" \
  "$(nix build --no-link --print-out-paths nixpkgs#pcsclite.out)/bin/pcscd" --foreground
```

From there, add a new host's key
and `sops updatekeys` as above. `age-plugin-yubikey` 0.5.1 needs a TDES
PIV management key (`ykman piv access change-management-key -a TDES
--generate --protect`); firmware 5.7 defaults to AES.

### Removing a recipient (decommissioning a host, revoking access)

Same shape in reverse: remove the key/anchor from `.sops.yaml`, then
run `sops updatekeys secrets/secrets.yaml` again.

> ### Removing a recipient **requires** rotating every value it could read
>
> **This repository is public.** Every prior revision of
> `secrets/secrets.yaml` is permanently downloadable by anyone, with no
> account and no trace. `updatekeys` re-wraps only the *data key* for
> the new recipient set — it does not change the encrypted values, and
> it cannot un-publish anything. So a retired recipient key can still
> decrypt every value it was ever a recipient of, forever, from history.
>
> **Removing a recipient is therefore not a revocation.** It is only a
> revocation once every value that recipient could read has been rotated
> **at its provider**. Until then the access is intact and merely
> undocumented, which is worse.
>
> This is not theoretical: the 2026-08-26 audit found three
> retired vps age keys that were recipients of public revisions holding
> the **byte-identical, currently-live** ciphertext for ten fleet-total
> credentials — proven by ciphertext comparison, with no decryption. The
> reinstall that retired them rotated exactly one value out of
> thirty-one.
>
> Two practical rules follow:
>
> - **Pair the two operations.** Recipient rotation and value rotation
>   are one task, not two. Sequence each value **add-new → verify →
>   remove-old**.
> - **Do the recipient update once, at the end.** A reinstall that
>   churns through host keys should update `.sops.yaml` against the
>   *final* key, not once per intermediate. Each intermediate commit
>   permanently widens the historical recipient set for no benefit —
>   which is exactly how those three keys got there.

Separately, and smaller: a host that has had its decrypt access removed
may already hold decrypted copies on disk from before revocation.

### Rotating a secret's actual value

There's no tooling for this beyond the editor workflow: run `sops
secrets/secrets.yaml`, change the value, save. Anyone who still has
decrypt access via `.sops.yaml` gets the new value on their next
`sops-install-secrets` run (typically at next rebuild/switch or next
boot, depending on the module).
