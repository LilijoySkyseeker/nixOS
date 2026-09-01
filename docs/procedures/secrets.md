# Secrets: storage, rotation, and agent interaction

## Storage model

Secrets live in `secrets/*.{yaml,json,env,ini}` (currently just
`secrets/secrets.yaml`), encrypted with [sops](https://github.com/getsops/sops)
against per-host/per-purpose age keys declared as named anchors in
`.sops.yaml`. `sops-nix` decrypts them at activation time on each host
that has a matching key (see `sops.age.keyFile` / `sops.secrets.*` in
the relevant host/profile modules) — plaintext only ever exists
in-memory on the target host, never in the repo. The pre-commit hook
(`.githooks/pre-commit`) blocks committing a `secrets.yaml` without a
`sops:` metadata block, private key blocks, age secret keys, and a few
common live-token patterns (AWS, Slack, GitHub) as a backstop — it is
not a substitute for the rules below, just a last-resort catch.

## How agents (LLMs) must interact with secrets

These rules apply to Claude Code and any other AI agent working in
this repo, not just human contributors:

- **Never edit `secrets/secrets.yaml` (or any `secrets/*` file)
  directly.** All edits go through `sops secrets/secrets.yaml`, which
  handles decrypt-edit-reencrypt atomically. Editing the ciphertext
  directly (including via a script, `sed`, or writing decrypted
  content back out) corrupts it or defeats the encryption.
- **Never decrypt a secret value to inspect it**, even for debugging
  — no `sops -d`, no `sops exec-env`, no reading a runtime-decrypted
  path under `/run/secrets`. If a secret's value needs to be checked
  or changed, tell the user the exact command to run themselves (e.g.
  `sops secrets/secrets.yaml`, or `sops -d --extract '["key"]'
  secrets/secrets.yaml` if they need just one value) rather than
  running it. This holds even when troubleshooting a live incident —
  the risk is the value ending up in the agent's context/transcript,
  not just in a file.
- **Never stage plaintext secret material inside the repo checkout**,
  even in a gitignored location or a worktree — keep generated key
  material (e.g. a pre-generated host SSH key for a fresh install, see
  `docs/procedures/new-host.md`) entirely outside the repo tree.
- **When a new service needs a new secret**, don't invent a value or a
  placeholder in a tracked file. Tell the user the key name to add
  (following the existing flat-key naming in `secrets/secrets.yaml`,
  e.g. `<host-or-service>_<purpose>`) and the `sops` command to add it,
  and reference the new key from the Nix module via
  `sops.secrets.<name>` — the module change itself (wiring the secret
  in) is normal code an agent can write; only the secret *value* is
  off-limits.
- **Adding/removing recipients is fine for an agent to do directly**
  (it's a `.sops.yaml` edit plus `sops updatekeys`, never touches
  plaintext) — see below.
- If a secret is suspected compromised, don't attempt remediation
  beyond flagging it and pointing at "Rotating a secret's actual
  value" below — value rotation always goes through the user.

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
> This is not theoretical: `F-P8-02` in the 2026-08-26 audit found three
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

## devshell.nix

Only wires the `sops` CLI into the dev shell (`devshell.nix`) — no
wrapper commands or aliases beyond that.
