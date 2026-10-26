# Scope sops recipients per host

## Goal

No host's key decrypts a secret it doesn't use. Logged from the
2026-09-15 security review of the Workspace mail DNS work: every host,
the internet-facing vps and the roaming thinkpad included, decrypts
`cloudflare_octodns_token`, which controls mail for the domain.

## Your decisions

None yet.

## State

`.sops.yaml` has a torrent-only rule for `secrets/torrent.yaml`. Everything
else in `secrets/secrets.yaml` still sits under one rule that names every
host, against `docs/hardening.md` rule 2.

## Next

Split `secrets/secrets.yaml` into per-host files with per-host rules,
then rotate every value that moves: the repo is public, so older
revisions stay decryptable by the old recipients, and a recipient change
without a value rotation revokes nothing. The re-encryption and
rotations are the owner's (`docs/procedures/secrets.md`).
