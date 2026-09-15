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

**2026-09-15: both decisions answered, module built and disabled,
nothing applied to the tailnet yet.**

**D1** — the policy can live here, `octodns`-shaped. Built:
`modules/services/tailscale-acl.nix` pushes `docs/tailscale-acl.json`
to the Tailscale API (validate first, then `If-Match` against the live
ETag so a concurrent console edit is refused rather than clobbered),
triggered by content change via `restartTriggers` rather than a timer —
so the tailnet policy moves when a reviewed commit is deployed, never on
its own. It ships with `enable = false`; homelab's build output is
byte-identical to the build without it, which is the intended property.

**D2** — reversed mid-session and now a narrow tailnet grant, not
WireGuard. The first answer picked wg0 believing it was narrower; the
`security` review showed it was not (F1) and that the wg0 allow was not
even peer-limited because vps SNATs everything leaving the tunnel onto
the address homelab would have trusted (F2). The wg0 change was reverted
in full before it was ever pushed. `docs/tailscale-acl.json` now carries
`src: ["tag:vps"], dst: ["tag:homelab"], ip: ["tcp:3100"]`.

**Nothing is live.** vps still ships no logs. The grant is declared in
the repo but not applied, because applying it needs either the console
(the operator's, by standing rule) or this module enabled — and enabling
the module needs an OAuth client with the `policy_file` scope, its
credentials in sops, and the G3 reconcile of this file against the live
policy, which must happen *before* any first push.

Findings F1/F2/F5 are resolved. **F3, F4 and F6 are parked, not
fixed** — F3 in particular is the one worth a decision: `auth_enabled =
false` means a compromised vps can not only read the fleet journal but
assert any `host` label it likes, which the D2 risk note did not cover.

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
- [x] decide whether vps may initiate to homelab, and by which shape (D2)
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

~~**Answered 2026-09-15 (user): over WireGuard, not the tailnet.**~~

**Superseded the same day, 2026-09-15, after the `security` review.**
The WireGuard answer below was chosen on the belief that it was
*narrower* than a tailnet grant. That belief was wrong, and F1/F2 say
why: `tag:vps` names exactly one device, so a grant scoped to it is the
same breadth as the wg0 peer set, while wg0 is worse on revocation
speed, gets no per-packet node-key enforcement, and hides the decision
from the very file this plan is about. F2 went further and showed the
wg0 allow was not even peer-limited — vps forwards at kernel-default
ACCEPT and SNATs everything leaving wg0 onto `10.100.0.1`, the exact
source address homelab's rule would have trusted, which is the same
exposure `modules/services/immich.nix` explicitly declines.

**The decision is now: a narrow tailnet grant.**
`src: ["tag:vps"], dst: ["tag:homelab"], ip: ["tcp:3100"]` — one source
tag naming one device, one destination port, no reverse — added to
`docs/tailscale-acl.json`. The wg0 change was reverted in full before
it was ever pushed. Residual risk is unchanged and still accepted: Loki
runs `auth_enabled = false`, so this grants a compromised vps
unauthenticated read of the fleet journal and the ability to assert any
`host` label (F3); the erase path stays closed.

This also re-couples D2 to D1: the grant is applied through the policy
file, so it lands properly once the push module is enabled, and in the
meantime the console change is the operator's to make.

~~Original wg0 reasoning, kept for the record:~~

The tailnet asymmetry stays exactly as it is — `tag:vps` is still never
a grant source, and no tailnet-wide grant is added. vps ships its
journal over the existing `wg0` tunnel instead:
`networking.firewall.interfaces.wg0.allowedTCPPorts = [ 3100 ]` on
homelab, and vps's `myAlloy.lokiUrl` pointed at `10.100.0.2` rather
than the MagicDNS name.

Why this shape over the three alternatives:

- It is **fully declarative today**, with no Tailscale admin-console
  step, no OAuth client, and no dependency on D1 landing first. That
  matters because the console change is the one thing in this whole
  chain an agent cannot make and cannot verify.
- The tunnel is **always dialled homelab → vps**, because homelab is
  behind CGNAT. The initiating direction on the wire therefore still
  matches push-deploy, which is what the reverse-tunnel alternative was
  trying to buy — without a bespoke daemon whose death would silently
  stop log shipping again.
- The rule is **interface-scoped**, so this does not make 3100 reachable
  from the tailnet at large. A narrow tailnet grant would have been a
  wider blast radius for the same capability, since a grant is evaluated
  per-tag and every tagged device shares the tailnet.

Residual risk accepted, unchanged from the narrow-grant option: a
compromised vps can read the whole fleet's 30-day journal through
Loki's unauthenticated query API — `#F4`'s read surface. `#F4`'s
*deletion* surface was already closed on 2026-09-10
(`limits_config.deletion_mode = "disabled"`), so a compromised vps can
read the central record of its own intrusion but cannot erase it, which
is the property that mattered most for `#G4`.

Note this decision does **not** retire D1. Managing the tailnet policy
declaratively is wanted on its own merits — it is click-ops, invisible
to the repo, and not restorable by any of the DR work — and remains
open regardless of how logs travel.


**ANSWERED 2026-09-15:** ship over wg0, not the tailnet: interface-scoped firewall rule plus an IP-based lokiUrl, leaving the tailnet asymmetry intact and requiring no console change

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

### F1 — the wg0 route is not narrower than the narrow tailnet grant it was chosen over; on three properties it is wider

- **File:** `modules/services/loki.nix:178-188`, this plan's D2 third bullet
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** a future operator revoking vps's log-shipping access, and anyone auditing the fleet's connectivity graph — the grant is now expressed in a place neither the tailnet policy file nor `tailscale status` will ever show.
- **Rule:** n/a (D2's own stated rationale)
- **Finding:** D2 justifies wg0 over the narrow-grant alternative with "a
  grant is evaluated per-tag and every tagged device shares the tailnet",
  i.e. that a grant would have "a wider blast radius for the same
  capability". That is not true of the grant that was actually on the
  table. `docs/tailscale-acl.json:30-35` shows `tag:vps` is owned by
  `autogroup:admin` and, per `modules/profiles/default.nix`,
  `--advertise-tags=tag:<hostname>` means exactly one device carries it.
  A grant `src:["tag:vps"] dst:["tag:homelab:3100"]` therefore names one
  source device and one destination port — the same breadth as
  `interfaces.wg0.allowedTCPPorts = [ 3100 ]`, whose peer set is also
  exactly one (`hosts/homelab/configuration.nix:763`,
  `allowedIPs = [ "10.100.0.1/32" ]`). The two options are equal on
  breadth. They differ on three things, and the wg0 route loses all three:

  1. **Revocation.** The ACL is revocable from the control plane in
     seconds, with no host touched. The wg0 rule is revoked only by
     editing homelab's Nix config and completing a rebuild+switch on
     homelab — a CGNAT'd host reachable only over the tailnet or the
     tunnel. Revoking access to a compromised vps is precisely the moment
     you want the fast control.
  2. **Enforcement granularity.** A tailnet grant is enforced per packet
     by `tailscaled` against the peer's *node key* identity; the observed
     `Drop: TCP{…} no rules matched` in this plan's Original section is
     that enforcement working. The wg0 rule is enforced only by "arrived
     on wg0", which resolves to "source is 10.100.0.1" via cryptokey
     routing — and vps manufactures that source address for traffic it did
     not originate. See F2.
  3. **Auditability.** `docs/tailscale-acl.json` is described in its own
     header as the fleet's reference copy of who may reach whom, and D1
     exists to promote it to source of truth. After this change that file
     is authoritative and wrong: it says `tag:vps` "doesn't need outbound
     access to anything beyond what the internet grant below already
     covers" (lines 51-54), while vps in fact has a standing TCP path to
     homelab's central log store. A declarative ACL that omits a live
     grant is worse than click-ops, because it invites belief.

  Note also that D2's second bullet ("the tunnel is always dialled
  homelab → vps … the initiating direction on the wire therefore still
  matches push-deploy") conflates the WireGuard *handshake* direction with
  the TCP *connection* direction. With `persistentKeepalive = 25`
  (`hosts/homelab/configuration.nix:769`) the tunnel is continuously up,
  and vps originates the TCP connection to homelab:3100. The property the
  pull-model alternative was buying — that a compromised vps cannot
  initiate into the home network — is not preserved by the handshake
  direction.
- **Fix risk:** reversing to a narrow tailnet grant re-introduces the
  admin-console step D2 was avoiding and makes D2 depend on D1. Keeping
  wg0 but recording the grant in `docs/tailscale-acl.json`'s comments
  costs nothing and fixes (3) only. Anything that changes the transport
  needs vps's `myAlloy.lokiUrl` and homelab's firewall changed together,
  and verified by `host="vps"` appearing in Loki, not by a clean build.


**FIXED 2026-09-15:** accepted the argument and reversed D2: the wg0 route was dropped in full and replaced by a narrow tailnet grant (src tag:vps -> dst tag:homelab, tcp:3100), which is the option F1 argued for

### F2 — homelab's wg0 allow is not peer-limited: vps forwards unfiltered and SNATs everything onto 10.100.0.1

- **File:** `modules/services/loki.nix:188`, `hosts/vps/configuration.nix:392-412` and `:443-444`, `hosts/homelab/configuration.nix:744-770`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the configuration facts; PLAUSIBLE for the off-vps leg (see Reachability)
- **Axis:** hardening
- **Reachability:** (a) CONFIRMED — any process on vps, at any uid, including the unprivileged ones behind the internet-facing surface (caddy, anubis, crowdsec, an sshd session); nothing on either side restricts *which* vps process may use the tunnel, and Loki needs no credential. (b) PLAUSIBLE — any host that can get an IPv4 packet with destination `10.100.0.2` onto vps's external interface: an L2 neighbour in the provider's segment, or anything able to induce vps to route for it. The end-to-end (b) path is very likely blocked today by DigitalOcean's vNIC destination filtering, which is a control this repo neither owns, documents, nor verifies.
- **Rule:** violates `docs/hardening.md` #5 ("Scope every firewall rule to an interface … A rule justified by a belief about the network is a rule that will silently become wrong")
- **Finding:** the in-code comment claims that because the tunnel is always
  dialled homelab → vps, "permitting this port inside it adds no new
  externally-reachable surface". The interface-scoping is correct and is
  not the issue; the claim about what is behind the interface is. Four
  facts, each read from the pinned source or the repo:

  - `networking.nat.enable = true` on vps sets
    `net.ipv4.conf.all.forwarding = true` at `mkOverride 99`
    (`nixos/modules/services/networking/nat.nix:200`, pinned
    nixpkgs-unstable `3ed67ec0a4d3`).
  - The iptables firewall never touches `FORWARD` —
    `networking.firewall.filterForward` is asserted to require nftables
    (`firewall.nix:324-325`), and `firewall-iptables.nix` contains no
    `FORWARD` rule at all. vps runs no container runtime (its module list
    at `modules/flake/hosts.nix:104-117`; a grep of `virtualisation.*`
    across `hosts/vps` and both profiles returns nothing), so nothing sets
    the `FORWARD` policy to DROP either. `FORWARD` is at the kernel
    default, ACCEPT.
  - `hosts/vps/configuration.nix:443-444` adds
    `iptables -t nat -A POSTROUTING -o wg0 -j SNAT --to-source 10.100.0.1`
    with **no `-s`, no `-p`, no `--dport`**. Every packet leaving wg0 —
    forwarded as well as locally generated — acquires source 10.100.0.1.
  - homelab's peer entry accepts `allowedIPs = [ "10.100.0.1/32" ]`, and
    the rendered firewall rule is
    `ip46tables -A nixos-fw -p tcp --dport 3100 -j nixos-fw-accept -i wg0`
    with no source match (`firewall-iptables.nix:156-166`, pinned
    nixpkgs-stable `a3116115851d`).

  So the trust decision homelab makes is "source is 10.100.0.1", and vps
  writes that source onto anything it relays. A packet
  `X:p → 10.100.0.2:3100` arriving on vps's external interface is
  forwarded (ACCEPT), SNAT'd to `10.100.0.1:p'`, passes cryptokey routing,
  passes the new firewall rule, and reaches Loki; conntrack reverses the
  SNAT on the reply, so the TCP session completes in both directions. The
  raw-table `vps-ratelimit` chain does not stop it — its port matches are
  25565/19132/34197/80/443, and only the CrowdSec blacklist rule is
  port-agnostic.

  This is not a new door — jellyfin's 8096
  (`modules/services/jellyfin.nix:125`) and the DNAT'd game ports already
  sit behind the same one — and `modules/services/immich.nix:168` shows
  the repo already treats "has a wg0 rule" as meaning "reachable through
  vps's public Caddy+Anubis path" and declines it on exactly those
  grounds. The finding is that the new rule enters that category while its
  comment asserts the opposite, and that the property being relied on (a
  provider-side destination filter) is undocumented and is precisely the
  kind of belief-about-the-network rule 5 was written for. Leg (a) needs
  no such belief and is unconditional.
- **Fix risk:** the smallest honest fix is documentation — state that wg0
  membership means "reachable from vps, and from anything vps forwards",
  matching immich's comment. A real narrowing would be FORWARD filtering
  on vps scoped to the three DNAT'd game ports plus the anubis→8096 path
  (a source match of `-s 10.100.0.1` on homelab buys nothing, since that
  is the laundered address). That is genuinely risky: a FORWARD
  default-deny on vps that misses a flow silently breaks the public game
  ports and the Jellyfin proxy, and must be VM-tested against all four
  flows before it goes near the live host.


**MOOT 2026-09-15:** the wg0 allow was reverted before it was ever pushed, so the unqualified SNAT onto 10.100.0.1 no longer has a homelab rule trusting it. The underlying vps FORWARD/SNAT looseness is untouched and pre-existing -- it is not created or worsened by this change, and is worth its own plan

### F3 — `deletion_mode = "disabled"` closes the erase surface but not the blind-and-forge surface, which shares the same port

- **File:** `modules/services/loki.nix:108`, `:149-156`, `:188`; `modules/nixos/alloy.nix:134-145`; `hosts/homelab/configuration.nix:800-803`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for label forgery, shared tenancy and the missing quota; PLAUSIBLE for the ingester lifecycle endpoints
- **Axis:** hardening
- **Reachability:** an adversary with any code execution on vps — the fleet's only internet-facing host — reaching `10.100.0.2:3100` over the path this change opens. No credential is needed: `auth_enabled = false`.
- **Rule:** n/a (revises this plan's D2 residual-risk statement and `2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#F4`)
- **Finding:** D2 accepts the read surface explicitly and correctly, and
  then states that the deletion surface "was already closed on 2026-09-10
  … so a compromised vps can read the central record of its own intrusion
  but cannot erase it, which is the property that mattered most for
  `#G4`." `deletion_mode = "disabled"` disables Loki's *delete-request
  API* only. Three ways to defeat the same record survive on the same
  port, which an interface-scoped firewall rule cannot separate from
  `/push`:

  1. **Label forgery (CONFIRMED).** With `auth_enabled = false`, stream
     labels are entirely client-asserted — `modules/nixos/alloy.nix:138`
     sets `labels = {host = "…"}` client-side, and Loki validates only
     cardinality. A compromised vps can push
     `{host="homelab", unit="sshd.service"}` lines. Every ruler rule in
     `modules/services/loki.nix` selects on `host=`/`unit=`/`identifier=`,
     so forged entries both fire alerts (`Run0Escalation` and
     `SopsDecryptFailure` are fleet-wide, `host!=""`) and, more usefully
     to an attacker, bury real ones in noise. The `#F7` mitigation covers
     a forged `UNIT` *within* a host's own journal; nothing covers a
     forged `host`.
  2. **Shared-tenant ingestion budget (CONFIRMED structurally).**
     `modules/services/loki.nix:17-18` records that everything lands in
     the single `fake` tenant. Loki's ingestion rate/burst limits are
     per-tenant, and `limits_config` sets only `retention_period` and
     `deletion_mode` — so a flooding vps spends the budget the other three
     hosts share, and the resulting 429s land on them. (The exact default
     rate is PLAUSIBLE; the single-tenant structure is not.)
  3. **Disk (CONFIRMED).** `zroot/persist/loki` is declared with a tier
     and a mountpoint and **no `quota`/`refquota`**
     (`hosts/homelab/configuration.nix:800-803`; `modules/nixos/datasets.nix`
     sets none per tier). Loki's store shares free space with the rest of
     `zroot`, including `/nix/state`.
  4. **Lifecycle endpoints (PLAUSIBLE — not verified against the pinned
     binary, which is not realised in this store).** Loki 3.x serves
     `/flush`, `/ingester/shutdown`, `/log_level` and `/config` on
     `http_listen_port`. If present in 3.7.7 they are an unauthenticated
     stop-ingest for anything that can reach 3100.

  Net: the property D2 believed it retained — "can read but cannot erase"
  — holds only against the delete API. "Cannot be made unreadable" is a
  stronger claim than the config supports.
- **Fix risk:** a `refquota` on `zroot/persist/loki` is cheap and
  non-breaking but must be sized above 30 days of real ingest or it turns
  into silent log loss (the same trap `docs/hardening.md` #10 records for
  container `--memory`). Server-side enforcement of the `host` label
  requires a per-tenant setup (`auth_enabled = true` plus an
  `X-Scope-OrgID`-injecting proxy per shipper), which is a real redesign,
  changes every shipper, and would need the `fake` tenant's existing 30
  days migrated or abandoned.

### F4 — nothing detects the new dependency failing, and the link it now depends on has a recorded history of dying silently

- **File:** `hosts/vps/configuration.nix:923`, `modules/services/loki.nix:19-89`, `modules/nixos/health-alerts.nix`, `hosts/homelab/configuration.nix:752-769`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** an adversary on vps who wants the four vps-scoped security alerts off — or, with no adversary at all, an ordinary CGNAT re-mapping. `VpsDeployRejected`, `PolkitVpsDeployGrant`, `CrowdSecDown` and `AnubisDown` all select `host="vps"` and all stop firing, silently, the moment vps stops shipping.
- **Rule:** new-rule candidate; same shape as `docs/hardening.md` #11 ("watch the result the guard exists to produce" — a check that only watches units cannot distinguish a run from a skip)
- **Finding:** two facts already recorded in this repo combine badly under
  the new transport. (i) `hosts/homelab/configuration.nix:752-769`
  documents that this exact tunnel "silently died for hours despite
  persistentKeepalive" when vps's auto-learned endpoint went stale. (ii)
  This plan's own `#G1` records that the shipper side is silent about push
  failure: "Alloy logs no push error loud enough to notice". Nothing
  closes the loop: every ruler rule in `modules/services/loki.nix` is a
  `count_over_time(...) > N` presence test, with no `absent_over_time`
  anywhere, so zero logs from a host is indistinguishable from a quiet
  host; and `myHealthAlerts` checks ZFS, SMART, failed units, backup
  staleness and stuck switches — an up-but-dead wg0 and a
  retrying-forever Alloy put no unit into `failed`. Before this change vps
  shipped nothing at all, so this is not a regression; it is a gap that
  becomes load-bearing the moment vps starts shipping, because the alerts
  covering "the only remote-root path into vps" now have a network
  single-point-of-failure with no alarm on it.
- **Fix risk:** an `absent_over_time({host="vps"}[30m])` ruler rule is the
  obvious shape and is cheap, but it fires on every legitimate vps reboot
  and every homelab Loki restart, so the window needs choosing against
  observed behaviour rather than guessed — an alert that cries wolf is how
  the real one gets muted. Note the rule must live on homelab's own ruler,
  so it cannot cover "homelab's Loki is down".

### F5 — three places now describe the transport incorrectly, one of them in a decision answered in this same change

- **File:** `modules/nixos/alloy.nix:1-4` and `:49-53`; `docs/tailscale-acl.json:51-54`; `2026-08-26-do-a-full-security-audit-hardening-pass-on-homelab.md` (the 2026-09-15 D1 answer)
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** the next person reasoning about the fleet's connectivity graph, or about whether homelab needs an IDS — all three statements mislead in the safe-sounding direction.
- **Rule:** `docs/agents/security/reference.md` severity rubric, INFO ("documentation that no longer matches the config")
- **Finding:**
  - `modules/nixos/alloy.nix:3` still says Alloy "pushes it to Loki on
    homelab over the tailnet", and the `lokiUrl` option's own description
    is "Loki push endpoint, tailnet MagicDNS name." The value on vps is
    now neither, and the description is the text an option-reference
    reader sees.
  - `docs/tailscale-acl.json:51-54` states vps "doesn't need outbound
    access to anything beyond what the internet grant below already
    covers." That is now false in intent as well as in fact, and this is
    the file D1 proposes to promote to source of truth.
  - The D1 answer added to the 2026-08-26 audit plan in this same change
    argues no IDS is needed on homelab because "every listener on homelab
    is interface-scoped to `tailscale0` or `wg0` … so there is no port for
    a network-level IDS to watch that an unauthorized party can reach — an
    IDS there would mostly be watching traffic that already passed tailnet
    device authentication." The `wg0` half does not follow: wg0's far end
    is the internet-facing host, whose traffic passed no tailnet device
    authentication at all, and per F2 also carries anything vps forwards.
    The conclusion may still be right; the premise as written is not, and
    it is cited as unblocking `docs/accepted-risks.md`.
- **Fix risk:** none beyond the usual — two are comments and one is prose.
  The D1 answer is the one worth re-wording rather than merely annotating,
  since it is the stated basis for accepting a risk.


**FIXED 2026-09-15:** all three corrected: alloy.nix's tailnet/MagicDNS wording is accurate again now that wg0 is reverted; tailscale-acl.json's 'vps needs no outbound' comment is rewritten to state the reversal explicitly; and the 2026-08-26 audit D1 answer had its false 'interface-scoped therefore unreachable' premise struck and replaced

### F6 — Loki binds 0.0.0.0, so one iptables chain is the whole boundary

- **File:** `modules/services/loki.nix:110-115`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** anything on 192.168.1.0/24 during any window in which homelab's `nixos-fw` chain is not armed — `systemctl stop firewall` restores INPUT to ACCEPT, and the existing `FirewallFailed` ruler alert exists precisely because that window is considered real.
- **Rule:** `docs/hardening.md` #4/#10 in spirit ("publish to an address, never `0.0.0.0`"); not literally in scope, since Loki is not a container
- **Finding:** `http_listen_address = "0.0.0.0"` means Loki listens on
  homelab's LAN NIC as well as on wg0 and tailscale0, and the only thing
  keeping 3100 off the LAN is the two `networking.firewall.interfaces`
  rules. `grpc_listen_address` is correctly pinned to `127.0.0.1` with a
  comment, which shows address-pinning was considered and declined for
  HTTP — presumably because a single listen address cannot cover two
  interfaces, which is true. Recorded here so the next reader does not
  re-derive it: this is a known single-control boundary, not an oversight,
  and adding a second interface to that boundary (as this change does) is
  the moment to say so. Note the rendered rule is `ip46tables`, so an
  inert IPv6 twin also exists; wg0 carries no IPv6 address
  (`ips = [ "10.100.0.2/24" ]`), so it grants nothing today.
- **Fix risk:** binding to an explicit address is not available without
  dropping one of the two interfaces Loki must serve. No fix proposed; the
  finding is the record.

### Checked and clean

Reviewed the full diff against `tailscale-acl-d1-research`
(`modules/services/loki.nix`, `hosts/vps/configuration.nix`, and the four
plan-file edits), plus the current full contents of
`modules/services/loki.nix`, `modules/nixos/alloy.nix`,
`hosts/vps/configuration.nix` and `hosts/homelab/configuration.nix` rather
than only the changed lines.

Found fine and not raised above: the firewall rule **is** interface-scoped,
as `docs/hardening.md` #5 requires, and the pre-existing `tailscale0` rule
is still needed (thinkpad, torrent and homelab ship over it) — nothing
became dead config. The `lokiUrl` override is a plain option set, adds no
secret reference and removes none. No new systemd unit, user, group,
capability or `sops.secrets` entry appears anywhere in the diff, so the
dedicated-service-user, unit-sandboxing and secrets rules have no new
surface; Alloy's existing override block (`modules/nixos/alloy.nix:25-43`)
already carries the repo's full sandbox stack and is untouched. Using an IP
rather than the MagicDNS name is correct and deliberate — `homelab` resolves
to the tailnet address, which is the path that does not work. Reverse
direction checked: homelab runs docker, which sets the `FORWARD` policy to
DROP, so vps cannot pivot from wg0 onto 192.168.1.0/24 through homelab; and
`useRoutingFeatures` is `"client"` fleet-wide with homelab the sole
`"both"` override, so vps is not a subnet router and no tailnet peer can
route an RFC1918 destination to it. vps's
`net.ipv6.conf.all.forwarding = false` and the tunnel's IPv4-only addressing
mean none of F2 has an IPv6 half. The `vps-ratelimit` raw-table chain and
its `extraStopCommands` teardown are unaffected. `tests/loki-pipeline.nix`
substitutes a host-wide port for the interface-scoped rule and says so at
its line 53 — so no VM test asserts the scoping, which is a pre-existing
documented limitation rather than something this change introduced.

Secrets were neither read nor decrypted at any point; no `secrets/*` file
was opened. Verified against the pinned trees (`nixpkgs-stable
a3116115851d` for homelab, `nixpkgs-unstable 3ed67ec0a4d3` for vps) by
reading `nat.nix`, `firewall.nix` and `firewall-iptables.nix` directly —
`nix eval` is blocked in this worktree-isolated session, so every
option-level claim above is sourced from the module text plus the repo's own
assignments, and anything that would have needed the evaluated merge or the
realised Loki binary is marked PLAUSIBLE.

_security finished 2026-09-15T18:59:03Z (code 4669d58690d73516) -- see Findings above._
