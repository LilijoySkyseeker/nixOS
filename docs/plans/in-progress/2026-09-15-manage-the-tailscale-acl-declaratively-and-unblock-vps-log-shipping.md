---
slug: manage-the-tailscale-acl-declaratively-and-unblock-vps-log-shipping
created: 2026-09-15
status: in-progress
frozen: false
kind: task
priority: normal
blocked_by:
---

# manage the tailscale ACL declaratively and unblock vps log shipping

## State

**2026-09-15: D1 researched and answered; D2 still open and blocking.**
D1 recommends option 3 — an `octodns`-shaped oneshot on homelab pushing
the repo's policy file to the Tailscale API under an OAuth client with
the `policy_file` scope. Terraform and the GitHub Action were both
evaluated and rejected, for state-management and trust-direction
reasons respectively; tailnet lock turns out not to interact at all and
is not enabled here anyway. Nothing has been implemented and no console
change has been made.

The root cause is now pinned down and it is narrower than "the ACL is
opaque": `docs/tailscale-acl.json` already shows `tag:vps` appearing
only as a grant *destination*, never as a *source* (G2), and the
comment there says that is intentional. So D2 is a deliberate reversal,
not a bug fix, and remains the user's call. Two implementation
preconditions are recorded before anything is pushed (G3, G4).

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

- [x] research whether the tailnet policy can live in this repo (D1)
- [ ] decide whether vps may initiate to homelab, and by which shape (D2)
- [ ] implement whichever the answers pick, verify vps logs actually
      arrive in Loki (`host` label gains `vps`)
- [ ] re-measure Alloy's memory on vps once it is really shipping —
      `2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#G12`'s ~73MB was taken while pushes failed

## Decisions (D)

### D1 — can the tailnet ACL be managed declaratively from this repo, and is it worth it?

Yes, and the smallest honest shape is an API push of the file this repo
already keeps, following the `octodns` pattern already running on
homelab. Researched 2026-09-15 against provider docs, Tailscale's API
and KB pages, and the pinned nixpkgs; recommendation is option 3 below.

**Option 1 — Terraform `tailscale_acl`.** Real and maintained. The
provider is in the pinned unstable nixpkgs as
`terraform-providers.tailscale_tailscale` (v0.29.2), alongside
`terraform` 1.16.0 and `opentofu` 1.12.6, so nothing new enters the
flake. The resource takes JSON or HuJSON (comments survive), the API
validates syntax and the policy's own `tests` at plan time, and
`reset_acl_on_destroy` / `overwrite_existing_content` control the
destroy and first-adopt behaviour. The cost is not the provider, it is
Terraform: this repo has no state file, no state backend, and no
locking story, and adding all three to manage exactly one file buys
nothing the API call below doesn't. Reconsider only if more of the
tailnet (auth keys, devices, DNS) ever moves under management.

**Option 2 — `tailscale/gitops-acl-action`.** Purpose-built for GitHub
Actions: GitHub secrets, `id-token: write` for federated identity, and
push/PR triggers on `main`. Less alien than the Original plan assumed —
this repo *does* run Actions (`.github/workflows/plan-gate.yml`). The
genuine benefit is that `test` runs on the PR, so a policy change is
validated before it can land, which is the same shape as plan-gate.
The genuine cost is the direction of trust: `apply` runs in GitHub's
runner, so the credential that can rewrite the fleet's access policy
lives at GitHub and the tailnet's ACL becomes something a GitHub
compromise can change. Against `docs/threat-model.md` that is a real
widening, and it is the reason this is not the recommendation despite
being the best-documented path.

**Option 3 (recommended) — API push from homelab, `octodns`-shaped.**
`POST /api/v2/tailnet/{tailnet}/acl` accepts the policy file directly
as HuJSON. `GET` returns an `ETag`; passing it back as `If-Match`
makes the write fail rather than clobber a concurrent console edit.
`POST .../acl/validate` is a dry run, and `tests` / `sshTests` blocks
inside the file are checked server-side — a failing test rejects the
update outright, so the policy carries its own regression suite.
Auth is an OAuth client with the `policy_file` scope (or
`policy_file:read` for validate-only), exchanged via
`grant_type=client_credentials` for a one-hour token; unlike an API
key it does not expire every 90 days, which matters for an unattended
timer. All of this maps onto `modules/services/octodns.nix` almost
line for line: sops-held credential, dedicated system user, hardened
`Type=oneshot` unit plus a timer, and the declared source of truth
living in the repo. No new platform, no new state store, and the same
operational pattern the fleet already runs for DNS.

**Tailnet lock: no interaction, either way.** Verified on this machine
— `tailscale lock status` reports `Tailnet Lock is NOT enabled`. It
would not constrain the choice even if enabled: lock signs *node keys*
so peers can verify each other without trusting the coordination
server, and the policy file is explicitly outside its scope. Tailscale's
own whitepaper concedes a compromised control plane can still
"distribute an access control policy which denies access to all
nodes", and the open feature request to have ACLs signed by trusted
nodes (tailscale/tailscale#11153) is exactly the gap. So declarative
ACL management neither weakens nor is blocked by lock.


**DISCUSSED 2026-09-15:** researched against provider/API/KB sources and the pinned nixpkgs; recommends option 3, an octodns-shaped API push under an OAuth policy_file client. Not user-confirmed.

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

### G2 — the drop is already explained by the reference copy in this repo, and it is deliberate

`docs/tailscale-acl.json` lists `tag:vps` under `tagOwners` and as a
`dst` in exactly one grant, and never once as a `src` in any grant.
Every other grant names `tag:thinkpad, tag:torrent, tag:homelab` as
sources and omits `tag:vps`. That is precisely the `no rules matched`
drop, and it explains why the restriction is host-shaped rather than
port-shaped — vps cannot open 22 to homelab either, while torrent
reaches 3100 and NFS fine. The comment above that grant states the
intent outright: vps "doesn't need outbound access to anything beyond
what the internet grant below already covers". So D2 is a reversal of a
recorded decision, not the repair of an oversight, and should be argued
on those terms.

### G3 — adopting the repo copy as source of truth needs a one-time reconcile first

`docs/tailscale-acl.json` is described in its own header as a reference
copy that is "not applied by Nix", kept in sync by hand. It has been
maintained (it records the 2026-08-27 `tag:isoimage` removal and the
2026-08-26 `ssh` block removal), but hand-sync has no mechanism behind
it, so it cannot be assumed to match the live tailnet. Promoting it from
documentation to source of truth means: `GET` the live policy, diff it
against this file, decide which side is right for each difference, and
only then enable any push. Pushing first would silently apply whatever
drift exists to the live tailnet in one shot.

### G4 — whichever option is picked, lock the console editor or it drifts straight back

Tailscale's GitOps documentation is explicit that manual admin-console
edits are not reflected back into the repo and are overwritten by the
next apply. The admin console has a "lock the policy file editor"
setting under Policy file management that makes the automation the only
writer, with an admin emergency override retained. Without it the repo
copy re-acquires exactly the drift problem that makes the current
click-ops setup unreviewable — the automation would just make the drift
overwrite things instead of merely diverging.

## Findings (F)
*(populated by security/docs-updater when invoked)*
