# Secret rotation

No dedicated rotation script or automation exists — this is a manual,
low-frequency operation. See the "Manual secret management" convention:
never edit `secrets/secrets.yaml` directly outside `sops
secrets/secrets.yaml`; if a secret value needs to change, give the user
the exact `sops` invocation to run rather than trying to script around
the encrypted file directly.

## Adding a recipient (new host, or rotating a compromised host's key)

1. Get the host's age public key (via `ssh-to-age` from its SSH host
   key, or from `sops.age.keyFile` if it already has one).
2. Add it to `.sops.yaml`'s `keys:` block as a new named YAML anchor,
   then reference it from the relevant `creation_rules` entry (matched
   by `path_regex: secrets/[^/]+\.(yaml|json|env|ini)$`).
3. Run `sops updatekeys secrets/secrets.yaml` so the file is
   re-encrypted for the updated recipient list. This is the only
   command needed — it doesn't touch the plaintext values, just who
   can decrypt them.

## Removing a recipient (decommissioning a host, revoking access)

Same shape in reverse: remove the key/anchor from `.sops.yaml`, then
run `sops updatekeys secrets/secrets.yaml` again. Note this does not
rotate the *secret values themselves* — a host that's had its
decrypt access removed may already have decrypted copies on disk from
before revocation. If that matters (compromised host, not just routine
decommissioning), rotate the actual secret values too (see below).

## Rotating a secret's actual value

There's no tooling for this beyond the editor workflow: run `sops
secrets/secrets.yaml`, change the value, save. Anyone who still has
decrypt access via `.sops.yaml` gets the new value on their next
`sops-install-secrets` run (typically at next rebuild/switch or next
boot, depending on the module).

## devshell.nix

Only wires the `sops` CLI into the dev shell (`devshell.nix`) — no
wrapper commands or aliases beyond that.
