---
slug: manage-the-tailscale-acl-declaratively-and-unblock-vps-log-shipping
created: 2026-09-15
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# manage the tailscale ACL declaratively and unblock vps log shipping

## State

**2026-09-15, not started.** Raised because the fleet log-monitoring
stack is blocked on a tailnet policy change and this repo has no
declarative handle on that policy at all.

## Original plan

vps cannot reach `homelab:3100`, so the log stack deployed on
2026-09-11 monitors homelab only and the fleet's internet-facing host
ships nothing. The drop happens above the host firewall — homelab's
`tailscaled` logs `Drop: TCP{100.80.252.80:… > 100.98.142.41:3100} no
rules matched` — i.e. the **tailnet policy file** in the Tailscale admin
console refuses it. The restriction is vps-specific, not port-specific:
vps cannot open port 22 to homelab either, while torrent reaches both
3100 and NFS 2049. Full evidence:
`2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#G11`.

Two questions, in order, and the first is why this is its own plan:

**1. Can the tailnet policy be managed declaratively from this repo?**
The fleet's standing preference is declarative-first, and right now the
single control governing which host may reach which is click-ops in a
web console — invisible to the repo, unreviewable, and not restorable
by any of the DR work. Worth researching properly before changing
anything by hand:
- Tailscale's GitOps route (the `tailscale/gitops-acl-action` flow) and
  whether a self-hosted equivalent fits a repo that is not on GitHub
  Actions for this purpose today
- the Terraform provider's `tailscale_acl` resource, and whether pulling
  Terraform in is proportionate for one file
- whether a plain `policy.hujson` in this repo pushed via the API with
  an OAuth client/API key (sops-managed) is the smaller honest answer
- how any of these interact with tailnet lock and with the existing
  `tagged-devices` tags, which is what actually expresses the current
  asymmetry
Answer against real sources (provider docs, API docs, the pinned
nixpkgs if anything exists there), not recall.

**2. Should vps be allowed to initiate to homelab at all?**
This is the user's decision and is genuinely load-bearing, so it should
not be smuggled in as part of doing (1). The current asymmetry is a real
security control: it is what contains
`2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#F4`/`#F10` — a compromised tailnet node reading
or deleting the whole fleet journal — and vps is the node most likely to
be compromised, being the only internet-facing one. Allowing
`vps → homelab:3100` buys log coverage of the host that most needs it,
at the cost of an inbound path from the exposed host into the home
network.

Alternatives worth costing before defaulting to "open the port":
- a pull model (homelab scrapes vps) so the initiating direction stays
  homelab→vps, matching the existing push-deploy direction
- shipping vps's logs over the existing WireGuard tunnel rather than the
  tailnet
- a narrower ACL: vps→homelab:3100 only, no other port, no reverse

**Ordering.** (1) is research and can land on its own; it makes (2)
reversible and reviewable whichever way it goes. Do not make the policy
change by hand in the console and call it done — that is the "not
declarative and reproducible is no fix at all" corollary.

## Progress

- [ ] research whether the tailnet policy can live in this repo (D1)
- [ ] decide whether vps may initiate to homelab, and by which shape (D2)
- [ ] implement whichever the answers pick, verify vps logs actually
      arrive in Loki (`host` label gains `vps`)
- [ ] re-measure Alloy's memory on vps once it is really shipping —
      `2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#G12`'s ~73MB was taken while pushes failed

## Decisions (D)

### D1 — can the tailnet ACL be managed declaratively from this repo, and is it worth it?

Open. Research question; see Original plan for the specific options to
evaluate.

### D2 — may vps initiate to homelab, and in what shape?

Open, and the user's call. See Original plan for the trade and the
alternatives to cost first.

## Gotchas (G)

### G1 — the drop is invisible from the shipper's side

vps's Alloy logs no push error loud enough to notice: the failure looks
like a plain timeout, and `tailscale status` shows the peer `active;
direct`, so the link appears healthy. The diagnosis only works from the
receiving side, where `tailscaled` logs `no rules matched`. Anything
similar in future — a tailnet service that "should" work but times out —
should be checked from the receiver's journal first.

## Findings (F)
*(populated by security/docs-updater when invoked)*
