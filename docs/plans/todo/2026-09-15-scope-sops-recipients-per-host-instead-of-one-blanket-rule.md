---
slug: scope-sops-recipients-per-host-instead-of-one-blanket-rule
created: 2026-09-15
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# Scope sops recipients per host instead of one blanket rule

## State

**2026-09-15, not started.** Logged from the security review of the
Google Workspace mail DNS work; see the cited finding for the full
reasoning and evidence.


## Original plan

**Carried out of `2026-09-15-re-add-google-workspace-mail-dns-records-to-octodns.md`#F11.** `.sops.yaml` has a single
`creation_rules` entry matching `secrets/[^/]+\.(yaml|json|env|ini)$` and
naming all seven age recipients, so every host's key decrypts every
secret. `cloudflare_octodns_token` is consumed only by homelab, but
thinkpad's and torrent's keys decrypt it, and the encrypted file is in a
public repo.

That token now controls mail for a live Workspace tenant, not just web
and game DNS. Wanted: per-secret or per-host `creation_rules` so a
workstation compromise does not hand over zone control.

**Requires the user** -- re-keying means decrypting and re-encrypting
`secrets/*`, which agents in this repo never do (`docs/procedures/secrets.md`).


## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
