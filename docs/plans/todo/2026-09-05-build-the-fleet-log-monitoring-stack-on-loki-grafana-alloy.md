---
slug: build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy
created: 2026-09-05
status: todo
frozen: false
---

# build the fleet log monitoring stack on Loki Grafana Alloy

## Original plan

Fleet-wide log monitoring covering three goals at once: security
alerting, operational alerting, and centralized search for retrospective
debugging. Loki + Grafana on homelab as the receiver; Alloy shippers on
vps, torrent and thinkpad; alerts out through the Discord webhook that
`myHealthAlerts` already uses.

Designed 2026-09-05 in a grilling session, from a greenfield start — the
repo had no Prometheus, Grafana, Loki, Alloy or ELK anywhere.

**Ordering.** This plan is **blocked on**
`2026-09-05-adopt-zfs-policy-tiers-and-a-mydatasets-registry.md`, which
must land first: Loki's chunk store needs `zroot/persist/loki` to exist
and the registry to generate its persistence entry. Nothing else blocks
this. Two follow-ups are deliberately deferred out of it:
`2026-09-05-close-deferred-logging-blind-spots-game-ports-nfs-auditd.md`
(security events that currently produce no log signal at all) and
application-level alert rules (D13).

## State

**2026-09-05, not started.** Design fully settled; every decision below
is answered and no code has been written. Blocked on the ZFS tier plan
landing first (see Ordering).

The one genuinely unknown quantity is whether Alloy fits on vps
alongside CrowdSec, Caddy and zram inside 1GB — upstream publishes no
minimal-footprint number, so this is measured rather than assumed (D16),
with a pre-agreed fallback if it does not fit (D15).

## Progress

- [ ] Loki + Grafana on homelab, storing to `zroot/persist/loki`
- [ ] Grafana: anonymous read-only, sops-managed admin login — see D12
- [ ] firewall: Loki + Grafana scoped to `tailscale0` only — see D10, D11
- [ ] Alloy shipper module, pinned to nixpkgs-stable fleet-wide — see D18
- [ ] journald: `Storage=persistent`, `SystemMaxUse` sized for a 24h
      burst on each host — see D9, G6
- [ ] journald: raise the rate limit on sshd/caddy/kernel — see D7, G1
- [ ] persistence entries for Alloy's cursor on **all** hosts, including
      the two with no impermanence yet — see G3
- [ ] VM test the whole pipeline, then measure Alloy's RSS on vps against
      the 100MB line — see D15, D16
- [ ] Loki ruler rules for the launch alert set — see D13
- [ ] Samba `log level = auth:3`; TLS catch-all vhost on vps — see D17
- [ ] verify the `run0` escalation message pattern live before writing
      its rule — see G7
- [ ] verify Jellyfin's console sink actually reaches journald — see G8
- [ ] document the deferred blind spots in their own plan — see D17

## Decisions (D)

### D1 — what is this for, and how much of the fleet?

All three of security alerting, operational alerting and centralized
search, across the whole fleet (vps, homelab, torrent, thinkpad).
`isoimage` is not a monitoring target. A single host's logs are much less
useful in isolation, and the per-host cost is one shipper.


**ANSWERED 2026-09-05:** security + operational + search, whole fleet minus isoimage

### D2 — push, pull, or both?

Both. Push (Discord) for anything needing same-day attention; the Grafana
dashboard for browsing and retrospective digging.


**ANSWERED 2026-09-05:** both push alerts and a dashboard

### D3 — central retention

30 days. Long enough to catch a slow-burn issue, short enough that disk
use stays predictable. This is also a statement that the data is
expendable, which is what justifies its `persist` tier.


**ANSWERED 2026-09-05:** 30 days central retention

### D4 — which host aggregates?

homelab. It is the only host with real storage headroom, is already the
fleet's backup target, and is online the vast majority of the time.


**ANSWERED 2026-09-05:** homelab aggregates

### D5 — which stack?

Loki + Grafana + Alloy.

**Promtail was excluded on verified grounds, not preference.** Grafana's
own docs record it as end-of-life since 2026-03-02, with all future
development moving to Alloy; nixpkgs has correspondingly deleted
`services.promtail` entirely, and its own removal message points at
`services.alloy`. Two independent sources, checked against the pinned
trees rather than recalled.

VictoriaLogs was the serious alternative and is genuinely lighter, but
its footprint advantage applies to the *receiver*, and the receiver is
homelab — 16GB RAM and a 4x12TB array, where that pressure does not bind.
The only tight host is vps, which runs the lightweight shipper either
way. Loki wins on ecosystem coherence instead: search, dashboards and
alerting in one product family, one datasource, one set of concepts.


**ANSWERED 2026-09-05:** Loki + Grafana + Alloy; promtail EOL verified, VictoriaLogs rejected on ecosystem coherence

### D6 — alerting engine, and its relationship to `myHealthAlerts`

Loki ruler → the existing Discord webhook, kept **separate** from
`myHealthAlerts` rather than merged into it.

Rebuilding infra-health checks on Loki would make alerting depend on the
log pipeline being healthy in order to tell you things are unhealthy —
the wrong failure mode. `myHealthAlerts` keeps ZFS/SMART/failed-unit/
staleness duties untouched; Loki owns log-content rules. One notification
stream, two independent detection paths.


**ANSWERED 2026-09-05:** Loki ruler to Discord, kept separate from myHealthAlerts

### D7 — journald rate limiting

Raise substantially on the security-relevant units, do not disable. A
safety valve against a pathological log-spam bug is still worth keeping;
the default 10000/30s is what caused the incident in G1.


**ANSWERED 2026-09-05:** raise journald rate limit substantially, do not disable

### D8 — what gets shipped?

Everything in the journal, with known-chatty low-value sources filtered
at the shipper. The logs most needed at 3am are the ones nobody predicted
needing; filtering is an optimisation to apply after seeing real volume,
not upfront. homelab's storage makes volume a non-issue.


**ANSWERED 2026-09-05:** ship everything, filter noisy sources at the shipper

### D9 — behaviour when homelab is unreachable

Guaranteed backfill, bounded at **24 hours** — persistent journal plus a
persisted Alloy cursor on every host, sized so a 24h outage backfills on
reconnect. homelab is online the vast majority of the time, so a longer
buffer would cost disk on vps for a case that does not happen. See G6 for
what this bounds.


**ANSWERED 2026-09-05:** guaranteed backfill bounded at 24h

### D10 — Grafana exposure

Tailnet-only, bound and firewall-scoped to `tailscale0`. Matches the
fleet's existing default, and a log dashboard is precisely the thing
whose compromise would hand an attacker the entire security-event
history. Phone access, if wanted later, is Tailscale on the phone — not a
public vhost. Explicitly rejected: publishing through vps's Caddy, which
today has no authentication layer at all (Anubis is a proof-of-work bot
filter, not auth).


**ANSWERED 2026-09-05:** Grafana tailnet-only

### D11 — Loki push endpoint authentication

None; tailnet plus interface-scoped firewall only. The fleet already
treats the tailnet as the trust boundary for NFS, Samba and SSH. A log
endpoint is not more sensitive than those, and adding a bespoke auth
story here would be inconsistent without raising the floor anywhere.


**ANSWERED 2026-09-05:** no auth on Loki push, tailnet-scoped

### D12 — Grafana authentication

Anonymous read-only, admin login required to change anything, password
via sops following the `octodns` pattern. Keeps browsing frictionless on
the tailnet while preventing an accidental dashboard or alert-rule
deletion from a phone browser.


**ANSWERED 2026-09-05:** Grafana anonymous read-only plus sops admin login

### D13 — what earns a notification

Security and operational classes at launch; application-level error-rate
rules deferred. App thresholds need real baseline data before a
non-noisy number can be picked, and alerting on too much trains you to
ignore it — a worse outcome than not alerting.

The launch set is deliberately scoped to what CrowdSec **cannot** produce
(see G4), since CrowdSec already handles SSH brute force, Caddy HTTP
abuse and closed-port scans:

1. `vps-deploy` dispatcher rejection — the only remote-root path into vps
2. firewall / ipset fail-open — see G5
3. CrowdSec or its firewall-bouncer down or restart-looping — see G4
4. sops decryption failure — WireGuard, Samba, restic, the Discord
   webhook and the tailscale authkey all fail closed behind it
5. tailscale auth failure/expiry — losing the tailnet loses all SSH
   access fleet-wide
6. Anubis challenge failures / Caddy 502s — the only gate in front of
   personal media
7. Jellyfin failed logins — internet-reachable auth surface whose lockout
   is inert on first boot
8. Samba auth failures; polkit escalations for the `vps-deploy` subject;
   `run0` escalations — see G7

`docs/hardening.md` rule 11 applies throughout: alert on the outcome, not
merely on unit state.


**ANSWERED 2026-09-05:** security and operational at launch, application-level deferred

### D14 — avoiding duplicate notifications

Role-split by default: Loki does not re-detect generic unit failures,
because `myHealthAlerts` already sweeps `systemctl --failed` without
depending on the log pipeline.

**Two deliberate exceptions**, where redundant detection is worth the
duplicate ping: firewall fail-open and CrowdSec-down. Both are severe
enough, and `myHealthAlerts`' 15-minute poll is slow for a window in
which SSH may be publicly exposed.


**ANSWERED 2026-09-05:** role-split, duplicate only for firewall fail-open and crowdsec-down

### D15 — contingency if Alloy does not fit on vps

Decided **before** measuring, so the result cannot turn into an
open-ended redesign. Budget: **~100MB RSS** is the line.

First lever is scope reduction on vps only — ship just
sshd/caddy/kernel/CrowdSec rather than everything, partially walking back
D8 for that host alone. It costs no new tooling, and vps is the host
where what matters is best understood. Second lever is Vector, also
present in the pinned trees, at the cost of a second shipper to maintain.


**ANSWERED 2026-09-05:** scope reduction first, vector second, 100MB RSS budget

### D16 — how the vps measurement is done

VM test first, per the repo's VM-test-before-real-deploy convention, then
measure real RSS on vps under real log volume, capturing a *before*
baseline of free RAM so the delta is attributable.

Extrapolating from torrent was rejected: the question is contention with
CrowdSec, Caddy and zram inside 1GB, which is specific to vps.


**ANSWERED 2026-09-05:** VM test then measure on vps with a before baseline

### D17 — which logging blind spots get closed now

Two cheap ones now, the rest deferred and documented.

Now: Samba `log level = auth:3` (below which auth failures never print),
and a TLS catch-all vhost on vps so HTTPS/SNI probes to unlisted
hostnames produce a log line — currently the biggest single blind spot on
the public edge, since the `:80` catch-all has no TLS counterpart.

Deferred to
`2026-09-05-close-deferred-logging-blind-spots-game-ports-nfs-auditd.md`:
a `LOG` target for the DNAT'd game ports (risks real volume on a
deliberately public port), NFS access logging (architectural — `sec=sys`,
no auth today), and auditd on torrent/thinkpad (its own project, with its
own tamper-resistance question). Adding a blind spot to the pipeline only
pays if the resulting alert would actually be acted on.


**ANSWERED 2026-09-05:** samba auth:3 and TLS catch-all now, rest deferred to its own plan

### D18 — Loki/Alloy version skew across the two nixpkgs trees

Pin Alloy to **nixpkgs-stable fleet-wide**, matching the tree homelab
already tracks.

homelab is on nixpkgs-stable (Loki 3.7.7) while the three shippers are on
nixpkgs-unstable (Alloy 1.17.1 vs stable's 1.16.0). Rather than testing
push-API compatibility across that skew and re-testing it on every bump,
remove the skew. Deterministic, and costs nothing here.


**ANSWERED 2026-09-05:** pin alloy to nixpkgs-stable fleet-wide to remove the skew

## Gotchas (G)

### G1 — journald's rate limit silently dropped security-relevant lines

journald's default 10000 lines/30s per unit caused CrowdSec to miss a
port-scan burst on vps — the incident behind
`...vps-fail2ban-vps-closed-port-scan-journal-stall.md`. Dropped lines
are invisible: no error surfaces, the detection simply does not fire.

Directly relevant here, since this pipeline exists partly to catch that
class of event. It is also why D7 raises the limit and why G6's sizing
must assume bursts.

### G2 — vps's root is tmpfs, so its journal and cursor are volatile

vps persists to `/persist` under impermanence; anything not persisted is
gone on reboot. Without explicit persistence, both the journal and
Alloy's read cursor vanish on every boot — silently losing exactly the
security logs this is built to capture, on the one internet-facing host,
which also has no backup of any kind.

### G3 — torrent and thinkpad will become impermanent later

Neither has impermanence today, so Alloy's cursor persists for free on a
durable root. If
`2026-08-18-migrate-torrent-and-thinkpad-to-impermanence.md` lands
without the persistence entries already in place, the cursor and journal
start evaporating on every boot and log delivery regresses **silently**,
months later, with no obvious cause.

So the entries are written now on all hosts even where inert. The repo
already has precedent for inert-looking persistence scaffolding being
mistaken for working config: thinkpad's `environment.persistence`
evaluates to `{}` with a decorative `@blank` and no rollback in its
initrd.

### G4 — CrowdSec cannot report its own absence

CrowdSec is the fleet's detection layer on vps, ingesting sshd, caddy and
kernel journals. If it is down or restart-looping — and a boot-race here
is documented and real — detection stops silently and nothing says so.

This is the strongest argument for the whole pipeline: the monitor needs
a monitor, and it has to be an independent one. Same reasoning makes
CrowdSec-down one of the two deliberate duplication exceptions in D14.

### G5 — sshd binds `0.0.0.0:22`; only the packet filter keeps it private

vps's sshd listens on all interfaces with `openFirewall = false`; only
`trustedInterfaces = ["tailscale0"]` makes it reachable. **A firewall or
ipset failure therefore exposes SSH to the internet**, which makes
firewall fail-open an alertable security condition in its own right, not
just an ordinary failed unit.

Related, and not covered by anything today: the DNAT'd game ports
(25565/tcp, 19132/udp, 34197/udp) bypass Caddy, Anubis and CrowdSec's
INPUT chain entirely.

### G6 — 24h is a hard ceiling on guaranteed delivery, and bursts eat it faster

D9 bounds backfill at 24 hours: if homelab is unreachable longer, those
logs are gone permanently — including vps's, the security-critical host
with no backup. Accepted knowingly on the basis of homelab's uptime.

`SystemMaxUse` must be sized against a **burst**, not steady state. D7
raises the rate limit precisely so floods are not dropped, which means a
port scan can consume the 24h budget far faster than average-rate
arithmetic suggests. The cap and the rate limit are one decision, not
two.

### G7 — the `run0` escalation log pattern must be verified live

`sudo` is genuinely absent fleet-wide, so `run0` is the only interactive
escalation path and worth alerting on. Its exact journald message shape
(polkit authorization plus a transient `run-u*.service` start) needs
confirming against a real escalation before the rule is written — a
guessed pattern produces a rule that silently never fires, which is worse
than no rule.

### G8 — Jellyfin's logging destination needs confirming

Jellyfin failed logins are in the launch alert set, but Jellyfin also
writes to `/srv/jellyfin/log`, and whether its console sink actually
reaches journald has not been verified. If it does not, the rule cannot
see the events and the shipper needs a file source instead.

## Findings (F)
*(populated by security/docs-updater when invoked)*
