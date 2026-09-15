---
slug: alert-on-destructive-octodns-sync-runs-not-just-failed-ones
created: 2026-09-15
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# Alert on destructive octodns-sync runs, not just failed ones

## State

**2026-09-15, not started.** Logged from the security review of the
Google Workspace mail DNS work; see the cited finding for the full
reasoning and evidence.


## Original plan

**Carried out of `2026-09-15-re-add-google-workspace-mail-dns-records-to-octodns.md`#F10.** The 2026-09-12 wipe of
the Google Workspace mail records was a *successful* `octodns-sync` run --
exit 0, `Deletes=3`, never entering systemd's failed state.
`modules/nixos/health-alerts.nix:263` alerts on `systemctl --failed`, so
the exact event that broke mail was structurally invisible.

Now that the zone carries MX and DKIM, the same silent success deletes
inbound mail routing and breaks outbound DMARC alignment, globally within
the 300s TTL. Wanted: an alert keyed on `octodns-sync` reporting any
delete at all, since a delete is never routine for a declarative zone.


## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
