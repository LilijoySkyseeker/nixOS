---
slug: close-deferred-logging-blind-spots-game-ports-nfs-auditd
created: 2026-09-05
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# close deferred logging blind spots game ports NFS auditd

## State

**2026-09-05, not started.** All three blind spots are open. Identified
during the 2026-09-05 fleet exposure analysis; none is a regression, all
are pre-existing gaps.

## Original plan

Three classes of security-relevant activity currently produce **no log
signal at all**, so no alert on them is possible regardless of how good
the log pipeline is. Each was deliberately left out of the initial
monitoring build because closing it costs more than a config one-liner.

Deferred out of
`2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D17`
(2026-09-05), which closed the two cheap blind spots (Samba
`log level = auth:3`, and a TLS catch-all vhost on vps for SNI probes)
and punted these.

**Ordering.** Depends on
`2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md`
being live — there is no value in generating these logs before something
collects and alerts on them. Blocks nothing.

## Progress

- [ ] DNAT'd game ports: decide whether to log drops — see D1
- [ ] NFS access logging — see D2
- [ ] auditd on torrent and thinkpad — see D3

## Decisions (D)

### D1 — do the DNAT'd game ports get a `LOG` target?

25565/tcp, 19132/udp and 34197/udp are DNAT'd straight to homelab's
container game servers, **bypassing Caddy, Anubis and CrowdSec's INPUT
chain entirely**. hashlimit drops there are silent: no `LOG` target, no
CrowdSec visibility, so abuse of these ports is invisible today.

The tension: these are deliberately public ports facing the open
internet, so a `LOG` target risks real volume — which then interacts with
the journald rate limit and the 24h buffer sizing
(`...loki-grafana-alloy.md#G6`). Possibly rate-limited logging rather
than unconditional.

### D2 — does NFS get access logging?

NFS is exported with `sec=sys` and a published `gid 999` — no
authentication and no access log. Tailnet-only, so the exposure is
bounded by the tailnet trust boundary, but a compromised tailnet device
would leave no trace of what it touched.

This is an architectural change, not a logging toggle: meaningful NFS
auditing probably means changing the auth model, not just turning on a
log. May be better reframed as an NFS hardening plan.

### D3 — does auditd go on torrent and thinkpad?

auditd runs on homelab and vps via `profile-server`; the two PC hosts
have none. Its own project, with its own unanswered question — the audit
trail is local-only and tamper-able, so adding auditd without shipping
its output somewhere immutable buys less than it appears to.

Note this one interacts with the log pipeline directly: shipping audit
logs to Loki would partly answer the tamper-resistance question, since
the copy on homelab is outside the audited host's control.

## Gotchas (G)

### G1 — a blind spot is only worth closing if the alert would be acted on

Each of these adds log volume, and volume interacts with the journald
rate limit, the 24h journal buffer and Loki retention. Turning on a
firehose nobody reads makes the pipeline worse, not better — the test for
each is whether a resulting alert would actually change what you do.

## Findings (F)
*(populated by security/docs-updater when invoked)*
