---
slug: add-the-zone-hardening-records-caa-mta-sts-and-tls-rpt
created: 2026-09-15
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# Add the zone hardening records CAA, MTA-STS and TLS-RPT

## State

**2026-09-15, not started.** Logged from the security review of the
Google Workspace mail DNS work; see the cited finding for the full
reasoning and evidence.


## Original plan

**Carried out of `2026-09-15-re-add-google-workspace-mail-dns-records-to-octodns.md`#F12 and #F13.**

- **CAA** -- L-09 of the 2026-08-26 audit flagged the missing CAA record.
  It has to be declared in `modules/services/octodns.nix` or the hourly
  authoritative prune removes it. Needs to name whichever CA Caddy
  actually uses on the vps before it is safe to add.
- **MTA-STS / TLS-RPT** -- the MX now carries inbound mail protected only
  by opportunistic TLS. Note the outage mode: `mode: enforce` with an
  unreachable policy host makes conforming senders refuse delivery, so
  start at `testing`.


## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
