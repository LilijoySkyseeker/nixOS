---
slug: build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy
created: 2026-09-05
status: in-progress
frozen: false
kind: task
priority: normal
blocked_by:
---

# build the fleet log monitoring stack on Loki Grafana Alloy

## State

**2026-09-10, built and VM-verified on branch
`worktree-loki-grafana-alloy`; not yet deployed anywhere.** The branch
stacks on `worktree-zfs-policy-tiers-mydatasets-rebased` (PR #76),
which provides `zroot/persist/loki`.

What exists: `modules/services/loki.nix` (Loki 3.7.7 on homelab,
tsdb/v13 schema, 30d retention via compactor, ruler with the 11-rule
launch alert set, localhost Alertmanager 0.31 delivering to the
existing Discord webhook through a root oneshot that extracts the bare
URL from the curl -K secret), `modules/nixos/alloy.nix` (`myAlloy`:
stable-pinned Alloy shipper on all four hosts, journald
Storage=persistent + burst-sized SystemMaxUse, 10x per-unit rate limits
on sshd fleet-wide and caddy on vps, cursor persistence entries
everywhere incl. the not-yet-impermanent hosts, DynamicUser swapped for
a real `alloy` user so impermanence can bind-mount its state), and
`modules/services/grafana.nix` (anonymous-Viewer + sops admin login;
**unwired** pending two operator-added sops keys — G9). Server-side log
lines were added where events were previously invisible (dispatcher
`logger`, `polkit.log()`), Samba prints auth failures (`1 auth:3`), and
vps gained a `tls internal` HTTPS catch-all vhost.

Verified: all five hosts `nixos-rebuild build` green;
`tests/loki-pipeline.nix` (in `nix flake check`) boots a 2-node VM
pipeline and passes end-to-end — shipper journal line arrives in Loki
with the expected labels, ruler loads the rules, and a synthetic run0
PAM line raises a real alert in Alertmanager. First memory data point
is over the D15 line — see G10.

Outstanding, in order: user adds the two Grafana sops keys and wires
`nixosModules.grafana` into homelab (G9); deploys (homelab first, then
shippers — never done unprompted); D16's real-vps RSS measurement
against the 100MB line, with D15's pre-agreed fallback; first-fire
tuning of the best-effort alert patterns (sops/tailscale/jellyfin
message texts are sourced but not yet observed live).

The one genuinely unknown quantity is whether Alloy fits on vps
alongside CrowdSec, Caddy and zram inside 1GB — upstream publishes no
minimal-footprint number, so this is measured rather than assumed (D16),
with a pre-agreed fallback if it does not fit (D15). G10 is the first
(over-the-line, but overstated) data point.

Reviews (2026-09-10): /simplify applied (query-cost fixes, comment
trims, RemoveIPC/RestrictSUIDSGID gap in the DynamicUser replacement);
docs-updater applied (host READMEs regenerated, architecture.md per-host
map fixed incl. pre-existing drift — F1–F3); security found F4–F11:
the HIGH (F4, live Loki deletion API) and F5/F6/F7/F11 are fixed —
note F5 removed the TLS catch-all again as live-verified inert, so
that D17 half is honestly re-deferred to the blind-spots plan. F8
(local Alertmanager silencing), F9 (no ingestion/dataset quota — worth
a `zfs set quota=` at dataset-creation time), and F10 (anonymous
Viewer = full Loki read once Grafana wires in) are parked open,
none above MEDIUM. The VM test re-passed after all fixes.

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

## Progress

- [x] Loki on homelab, storing to `zroot/persist/loki`
      (`modules/services/loki.nix`); Grafana written
      (`modules/services/grafana.nix`) but unwired pending the two
      operator-added sops keys — see G9
- [x] Grafana: anonymous read-only, sops-managed admin login — see D12
      (in the unwired module, G9)
- [x] firewall: Loki + Grafana scoped to `tailscale0` only — see D10, D11
- [x] Alloy shipper module, pinned to nixpkgs-stable fleet-wide
      (`modules/nixos/alloy.nix`, `myAlloy`, enabled on all four hosts)
      — see D18
- [x] journald: `Storage=persistent`, `SystemMaxUse` sized for a 24h
      burst on each host (2G default, 1G on vps) — see D9, G6
- [x] journald: raise the rate limit on sshd fleet-wide + caddy on vps
      (10x, per-unit); kernel stays covered by vps's already-capped
      iptables LOG rule — see D7, G1
- [x] persistence entries for Alloy's cursor on **all** hosts, including
      the two with no impermanence yet — see G3
- [ ] VM test the whole pipeline (`tests/loki-pipeline.nix`), then
      measure Alloy's RSS on vps against the 100MB line — test written
      and wired into checks; run pending; the on-vps measurement needs
      the real deploy — see D15, D16
- [x] Loki ruler rules for the launch alert set — see D13; the
      vps-deploy and polkit events needed server-side log lines added
      (dispatcher `logger`, `polkit.log()`) before rules could match
      anything
- [x] Samba `log level = 1 auth:3` — see D17. The TLS catch-all half
      was attempted (`tls internal` vhost), live-verified inert by the
      security review, and removed again — that blind spot is
      re-deferred, see F5
- [x] verify the `run0` escalation message pattern live before writing
      its rule — see G7 (verified 2026-09-10, PAM anchor)
- [x] verify Jellyfin's console sink actually reaches journald — see G8
      (verified 2026-09-10)
- [x] document the deferred blind spots in their own plan — see D17
      (`2026-09-05-close-deferred-logging-blind-spots-game-ports-nfs-auditd.md`
      exists in todo/)

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

**Verified live 2026-09-10** against a real `run0` escalation in
homelab's journal (the 2026-09-03 deploy): the reliable anchor is the
PAM line `pam_unix(systemd-run0:session): session opened for user
<target>(uid=N) by (uid=M)` — the `systemd-run0` PAM service tag is
unique to run0 and carries both identities. The transient unit start
appears as `systemd[1]: Starting [run0] <command>...` (description
prefix `[run0]`, not a `run-u*.service` unit name in the message
body). The rule matches the PAM line.

### G8 — Jellyfin's logging destination needs confirming

Jellyfin failed logins are in the launch alert set, but Jellyfin also
writes to `/srv/jellyfin/log`, and whether its console sink actually
reaches journald has not been verified. If it does not, the rule cannot
see the events and the shipper needs a file source instead.

**Verified live 2026-09-10**: homelab's journal carries jellyfin's
console output (`jellyfin[pid]: [HH:MM:SS] [INF] [n] Emby.Server...`
lines present, same-day). The journald transport works; no file source
needed. The failed-login message text itself still gets confirmed when
the rule first fires (or via a deliberate wrong-password login), but
the pipeline can see it.

### G9 — sops key presence is checked at build time, so Grafana ships unwired

Found 2026-09-10 while building: `sops-install-secrets` validates the
manifest against `secrets/secrets.yaml` inside the *build* (no
decryption needed to see a key is absent), so declaring
`grafana_admin_password`/`grafana_secret_key` fails
`nixos-rebuild build --flake .#homelab` outright until the keys exist.
Agents never edit secrets, so `modules/services/grafana.nix` is
complete but deliberately **not** in homelab's module list. Enabling it
is two operator steps: add both keys via the `sops` runbook
(`docs/procedures/secrets.md`; `grafana_secret_key` is Grafana's
cookie/state signing key — generate a long random string), then add
`nixosModules.grafana` to homelab in `modules/flake/hosts.nix` where
the comment marks the spot.

### G10 — first Alloy memory data point is over the 100MB line

The VM pipeline test (`tests/loki-pipeline.nix`) runs its shipper node
at 1GB like vps and prints Alloy's cgroup `MemoryCurrent`: **~145MB at
idle** (2026-09-10, stable Alloy 1.16.0, full-journal config). That is
cgroup memory, not RSS — it includes reclaimable page cache, so it
overstates the D15 budget number — but it is enough signal that the
real-vps measurement (D16) should be expected to land near or over the
line, and D15's first lever (scope reduction on vps only) is the likely
outcome. Measure on vps before reaching for it.

## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 — architecture.md's per-host table and module inventories had drifted; refreshed against hosts.nix

`docs/architecture.md`'s "Composition point" table did not list this
change's additions (`loki` + `alloy` on homelab, `alloy` on
thinkpad/torrent/vps), and on inspection had older drift too:
`health-alerts` missing from thinkpad/torrent, `docker-publish-guard`,
`datasets` and `beets` missing from homelab, `brother-mfc-l2740dw` and
the `audio-switch` home-manager module missing from torrent. Rewrote the
rows wholesale from the current `modules/flake/hosts.nix`. Also in the
same file: added beets/loki/grafana to the `modules/services/`
enumeration (noting grafana is wired to no host yet), noted `loki.nix`'s
single `myLoki.alertWebhookFile` option as the one exception to that
directory's "No options surface" rule, and added `alloy.nix` to the
options-module example lists in both `docs/architecture.md` and
`docs/style-guide.md` (those lists were already non-exhaustive in
practice — `zrepl.nix`, `datasets.nix` etc. also define options — so
they now say "among others").

### F2 — new-service.md pointed at a modules/services/README.md that has never existed

`docs/procedures/new-service.md`'s closing paragraph instructed adding
"one-line entries in `modules/services/README.md`'s inventory", but no
such file exists anywhere in history for `modules/services/`, and
`docs/procedures/updating-documentation.md` explicitly states there are
no per-module-folder READMEs. Directly relevant to this change, which
adds two `modules/services/` files a reader would try to inventory
there. Replaced with the real mechanism: re-run `scripts/doc-host.sh
<host>` for the inventory block, host-specific gotchas go in
`hosts/<name>/README.md`.

### F3 — two comment-accuracy fixes in the new files

- `tests/loki-pipeline.nix` called the number it prints "Alloy's RSS",
  but it prints cgroup `MemoryCurrent`, which G10 records as
  overstating RSS (includes reclaimable page cache) against the D15
  100MB budget — a reader could mistake the printed figure for the
  binding D16 measurement. Header and subtest now say MemoryCurrent
  and point at G10.
- `modules/services/grafana.nix`'s header said "Grafana on homelab",
  but the module is deliberately wired to no host (G9); header now
  says so and its plan citation is anchored to #G9.

_docs-updater finished 2026-09-10T17:44:28Z (code e42a411ebd29585d) -- see Findings above._

### F4 — the tailscale0:3100 opening exposes Loki's entire unauthenticated HTTP API — query, deletion and ingester admin — not just the push path D11 decided

- **File:** `modules/services/loki.nix:169` (firewall rule), `modules/services/loki.nix:104-163` (`auth_enabled = false`, `retention_enabled`, `delete_request_store`)
- **Severity:** HIGH
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any tailnet device (phone, laptop, or a compromised fleet host — most plausibly vps, the internet-facing one) reaching homelab:3100 over tailscale0; additionally any local process on homelab via loopback, which an interface-scoped rule cannot restrict (e.g. a compromised Jellyfin, internet-reachable through vps's proxy).
- **Rule:** new-rule candidate — "opening a port opens every route the daemon serves on it; enumerate them before scoping the rule"
- **Finding:** D11 authorizes an unauthenticated *push* endpoint. The firewall rule opens the whole Loki HTTP server: (a) the query API — full LogQL read of the fleet's aggregated 30-day journal, including the audit/execve records journald collects on the server hosts (auditd is on there, and the pinned journald module wires `systemd-journald-audit.socket` into journald), so command lines fleet-wide become readable by any tailnet principal with zero auth; (b) the log-entry deletion API — verified against the pinned grafana-loki 3.7.7 binary: `compactor.deletion-mode` defaults to `filter-and-delete` and its help text states the deletion endpoints are active when `retention_enabled` is true, which loki.nix sets together with `delete_request_store = "filesystem"` — so a compromised host can erase the central record of its own intrusion, the exact scenario (G4, "the monitor needs a monitor") this pipeline exists for, and for vps the Loki copy is the only durable one (G2, no backups); (c) ingester admin endpoints (flush/shutdown) on the same port. Nuance: deletion cannot retract an alert that already fired (the ruler runs near-real-time); what it defeats is retrospective forensics and centralized search — one of the plan's three stated goals.
- **Fix risk:** `limits_config.deletion_mode = "disabled"` turns off the deletion endpoints and nothing else — retention pruning by the compactor is a separate mechanism, but re-run the VM test and confirm retention still applies. The read surface is a policy question: if tailnet-wide unauthenticated read is accepted, record it in D11's own terms (the current text reasons only about pushing).


**FIXED 2026-09-10:** limits_config.deletion_mode = disabled; retention machinery unaffected

### F5 — the vps `tls internal` HTTPS catch-all serves no certificate for unlisted SNI: the handshake is refused and nothing is logged, so the D17 blind spot it exists to close is still open

- **File:** `hosts/vps/configuration.nix:671-678`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening (and needed-used: as written the vhost is dead weight)
- **Reachability:** n/a — this is a detection control that does not detect; the adversary it was built to observe (internet HTTPS/SNI probers) stays invisible.
- **Rule:** violates `docs/hardening.md` rule 9, "Verify that config actually takes effect — rendering is not applying"
- **Finding:** Reproduced live against the pinned caddy 2.11.4: a Caddyfile of the same shape (hostless `https://` vhost with `tls internal` + `respond 421`, plus one named vhost holding a real certificate, mirroring vps's single jellyfin vhost) refuses a TLS handshake for any unmatched or absent SNI with a tlsv1 internal-error alert. No per-SNI certificate is minted, no HTTP request is processed, `respond 421` never runs, and no line appears in the access log or in Caddy's process output at the default log level. The in-code comment ("serves a self-signed cert per probed SNI — probes get a cert error") describes behavior Caddy does not have without on-demand issuance, and the Progress list records the item as done. Side note, verified via `caddy adapt`: the catch-all's subject-less internal automation policy sorts *after* the named vhost's policy, so jellyfin's ACME issuance is not hijacked — the vhost is inert, not harmful.
- **Fix risk:** making it real needs a servable certificate for arbitrary SNI — either `tls internal` + `on_demand` with the global on-demand guards (which introduces the per-SNI issuance surface this change deliberately avoided; it must be rate-limited), or a fixed fallback certificate via the `fallback_sni` global option. Either way, verify with curl using a bogus SNI and assert a logged 421 before recording D17 closed.


**FIXED 2026-09-10:** inert tls-internal vhost removed; SNI-probe blind spot honestly re-deferred to the blind-spots plan

### F6 — alertmanager-discord-env runs as unsandboxed root, against the repo's custom-unit baseline

- **File:** `modules/services/loki.nix:208-224`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** no direct path today; the gap is blast radius — a bug in the extraction, or a swapped `myLoki.alertWebhookFile`, feeds a root process attacker-influenced input in a unit with no `NoNewPrivileges`, no `ProtectSystem`, no `PrivateTmp`.
- **Rule:** violates `docs/hardening.md` "Custom systemd.services sandboxing" and "Dedicated service users" (root not strictly required, and no recorded reason)
- **Finding:** The oneshot is a sed + printf writing one file under /run; its job tolerates the full baseline stack (`NoNewPrivileges`, `ProtectSystem = "strict"` with `ReadWritePaths` or better a `RuntimeDirectory`, `ProtectHome`, kernel/namespace protections, `PrivateTmp`). Root is also not strictly required: the `discord_webhook` secret is owned health-check:health-check (`hosts/homelab/configuration.nix:199`), and the rendered env file only has to be readable by the service manager (root reads `EnvironmentFile=` itself), which a `User = "health-check"` unit writing 0400 into its own runtime dir satisfies. The `UMask = "0077"` and root-only output file are right as far as they go, and the extraction never echoes the URL to the journal.
- **Fix risk:** `ProtectSystem = "strict"` without a writable path for the env file breaks the write; moving off root touches secret-ownership assumptions. The VM test covers the extraction end-to-end — run it.


**FIXED 2026-09-10:** oneshot sandboxed to repo baseline, root kept only for the 0400 secret read

### F7 — every launch alert can be forged by an unprivileged process, and the relabel order prefers the forgeable unit field over the kernel-attested one

- **File:** `modules/nixos/alloy.nix:103-128` (relabel block), `modules/services/loki.nix:19-89` (rules), `hosts/vps/configuration.nix:24-31` (dispatcher logger line)
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any unprivileged process or user on any shipper host — journald's native socket and logger(1) accept entries from any uid; over the push API any tailnet principal can additionally forge whole streams including the `host` label (see F4).
- **Rule:** n/a
- **Finding:** Three layers. (1) journald only attests fields with a leading underscore (systemd.journal-fields(7)); `SYSLOG_IDENTIFIER` and `UNIT` are client-supplied, and several rules select on `identifier=` ("systemd", "polkitd", "vps-deploy") or on bare message text with `{host!=""}` (Run0Escalation, SopsDecryptFailure, TailscaleAuthTrouble) — `logger -t systemd ...` or one crafted line raises any of them, from any account. (2) the relabel block deliberately lets `__journal_unit` (the client-suppliable `UNIT` field) win over `__journal__systemd_unit` (the attested `_SYSTEMD_UNIT`) "when both exist", so any process can stamp its lines `unit="tailscaled.service"` and pollute unit-scoped rules and retrospective search; as written the trusted field can never beat the untrusted one — accepting `UNIT` only for entries whose attested unit is `init.scope` would close that. (3) the new dispatcher logger line ships the attacker-chosen `$cmd` (SSH_ORIGINAL_COMMAND, embedded newlines becoming separate journal entries) into the same pipeline, so a probe with a stolen vps-deploy key can embed other rules' match text inside its own rejection. Impact is alert forgery and noise-burial (alert fatigue as cover), not privilege — hence LOW — but it is the integrity ceiling of the whole alert set and worth recording; the logger line itself is still a clear net win.
- **Fix risk:** changing the relabel precedence alters the `unit` label on genuine PID1 messages; the three rules that read those already select on `identifier="systemd"`, so the VM test re-run is the main check.


**FIXED 2026-09-10:** relabel order swapped so kernel-attested _SYSTEMD_UNIT beats client-suppliable UNIT; forged positives remain possible and are accepted as noise, not silencing

### F8 — any local process on homelab can silence the whole Loki alert path through the unauthenticated Alertmanager API

- **File:** `modules/services/loki.nix:174-200`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any uid on homelab (a compromised Jellyfin — internet-reachable through vps — Samba, immich, or any other local service account) POSTing to `127.0.0.1:9093/api/v2/silences`; loopback is inherently exempt from interface-scoped firewall rules.
- **Rule:** n/a
- **Finding:** The 127.0.0.1 binding is the right call, but Alertmanager's API carries no authentication of its own, so a single catch-all silence (`alertname=~".+"`) mutes every log-content notification for an attacker-chosen duration, and nothing alerts on a silence existing. The real mitigation is D6/D14's independence of myHealthAlerts, which this design already provides; the residual gap is exactly the alert classes only Loki carries (deploy rejection, auth failures, CrowdSec-down).
- **Fix risk:** Alertmanager auth means a web-config file with credentials wired into the ruler too; probably not worth it — if declined, record it as an accepted risk next to D6.

### F9 — unauthenticated push with no dataset quota lets any tailnet principal grow the log store ~345GB/day

- **File:** `modules/services/loki.nix:141-149,169`; `hosts/homelab/configuration.nix:737-744`
- **Severity:** LOW
- **Confidence:** CONFIRMED (default per-tenant rate verified against the pinned 3.7.7 binary: 4MB/s, 6MB burst; myDatasets has no quota knob)
- **Axis:** hardening
- **Reachability:** any tailnet device or local homelab process pushing arbitrary streams to :3100.
- **Rule:** n/a
- **Finding:** Retention caps age (720h), not volume. At Loki's default distributor limit a pusher sustains ~345GB/day — ~10TB steady-state inside one retention window — into `zroot/persist/loki`, which the registry creates with no quota/refquota on the pool homelab's system shares. zfs-space-guard/myHealthAlerts would complain about free space only after the pressure exists. Legitimate fleet volume is orders of magnitude lower, so a tighter `ingestion_rate_mb` plus a dataset quota are cheap belt-and-suspenders.
- **Fix risk:** all shippers share the single `fake` tenant, so a low rate limit throttles the 24h backfill burst D9/G6 were sized for (a full 4-host backfill is roughly 7GB of journal; at 4MB/s that clears in ~30 minutes — keep any new limit comfortably above that shape).

### F10 — once Grafana is wired, "anonymous read-only" means unauthenticated fleet-journal read for every tailnet device

- **File:** `modules/services/grafana.nix:24-28,43-54,67`
- **Severity:** INFO
- **Confidence:** PLAUSIBLE (Explore/Viewer defaults for the pinned Grafana 13.0.7 not exercised live; the module is unwired today)
- **Axis:** hardening
- **Reachability:** any tailnet device, no credentials, against homelab:3000 once `nixosModules.grafana` lands (G9).
- **Rule:** n/a
- **Finding:** D12 frames anonymous access as harmless browsing, with accidental edits as the threat. A Viewer-role anonymous org in current Grafana can run arbitrary LogQL through the provisioned Loki connection (Explore is Viewer-accessible by default in modern releases, and the query proxy honors Viewer rights regardless), so "read-only" is "read-everything" — the same read surface as F4, with a UI. D10 itself notes a log dashboard hands over the entire security-event history; if tailnet-wide unauthenticated read is the intent, say so in D12 before wiring; if not, `auth.anonymous` needs revisiting first.
- **Fix risk:** disabling anonymous costs the frictionless phone browsing D12 wanted; a login-required shared Viewer account is the middle ground.

### F11 — `Storage=persistent` in journald extraConfig duplicates the structured option's default

- **File:** `modules/nixos/alloy.nix:144-148`
- **Severity:** INFO
- **Confidence:** CONFIRMED (pinned journald module: `services.journald.storage` defaults to `"persistent"` and renders `Storage=` before extraConfig; journald.conf is last-assignment-wins, so the line is effective but redundant)
- **Axis:** needed-used
- **Reachability:** n/a
- **Rule:** brushes `docs/hardening.md` rule 9's "prefer the module's structured settings"
- **Finding:** The structured option already exists and already defaults to persistent, so the extraConfig `Storage=` line adds nothing; `SystemMaxUse` genuinely has no structured option and is fine where it is. Switch the Storage line to the structured option, or drop it with a comment that the default already persists, so future rule-9 sweeps don't stall on it.
- **Fix risk:** none beyond a rebuild; behavior identical.

**Security review, checked and clean (2026-09-10):** Reviewed the full diff vs ad62698 plus staged state: `modules/nixos/alloy.nix`, `modules/services/{loki,grafana,samba}.nix`, `hosts/{homelab,vps,thinkpad,torrent}/configuration.nix`, `modules/flake/{hosts,checks}.nix`, `tests/loki-pipeline.nix`, docs. Verified against the pinned trees (nixos-26.05 a311611: upstream alloy/loki/alertmanager/journald modules read in full; grafana-loki 3.7.7 and caddy 2.11.4 binaries exercised directly; no secrets read or decrypted). Fine as-built: the DynamicUser-off override correctly re-adds all six implied protections plus the repo's usual sandbox flags, and journal read stays a unit-scoped SupplementaryGroups grant from the upstream module (rule 6); the pinned `alloy` user + `/var/lib/alloy` persistence entries are consistent on all four hosts including vps's `/persist` (whose `/var/log` was already persisted, so `Storage=persistent` lands on durable disk); Loki/Grafana firewall openings are interface-scoped per rule 5 and homelab has no blanket trustedInterfaces; Loki's gRPC and Alertmanager bind loopback; ruler rules load from a read-only store path so the rules API cannot mutate them; the webhook extraction writes 0600 root:root under /run with no secret echoed to the journal, and Alertmanager's PrivateTmp keeps the envsubst-rendered config private; the per-unit LogRateLimit raise leaves journald's global limit as the safety valve (D7); the polkit.log line logs only fixed text plus the matched action id; samba `1 auth:3` adds auth visibility without new exposure; the `caddy adapt` check confirmed the new catch-all does not hijack jellyfin's ACME policy (its failure mode is F5's silence, not breakage); checks.nix's pkgsStable rewiring and the VM test's scoping (test-NIC-only firewall open, fake webhook at a dead loopback port) are sound.

_security finished 2026-09-10T18:02:49Z (code e42a411ebd29585d) -- see Findings above._

**FIXED 2026-09-10:** redundant Storage=persistent line dropped from extraConfig
