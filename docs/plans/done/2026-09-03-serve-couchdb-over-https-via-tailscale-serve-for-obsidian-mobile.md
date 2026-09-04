---
slug: serve-couchdb-over-https-via-tailscale-serve-for-obsidian-mobile
created: 2026-09-03
status: done
frozen: true
---

# Serve CouchDB over HTTPS via tailscale serve for Obsidian mobile

## Original plan

Follow-up to `2026-09-03-self-host-obsidian-sync-via-couchdb-on-homelab.md`:
Obsidian's Self-hosted LiveSync mobile client requires HTTPS, and the
deployed CouchDB is currently plain HTTP only (`http://homelab:5984`).
Add HTTPS without any public exposure, staying inside that plan's D1
(Tailscale-only) boundary — via Tailscale's own "HTTPS Certificates" +
`tailscale serve` (not `funnel`, which goes public), terminating TLS
within tailscaled itself and reverse-proxying to CouchDB's existing plain
HTTP on `127.0.0.1:5984`. Must be wired declaratively (a systemd unit),
not a hand-run CLI command, per this repo's trust-hierarchy corollary.

## State

**2026-09-03, live research done on the real host, confirmed viable,
no code written yet.** Confirmed via live testing on `homelab` (pinned
tailscale `1.98.10`), not assumption:
- HTTPS Certificates is already enabled for this tailnet — `tailscale
  cert` successfully pulled a real Let's Encrypt cert for
  `homelab.taila4ae6c.ts.net`.
- `tailscale serve --bg --https=443 http://127.0.0.1:5984` works
  end-to-end: `tailscale serve status` showed `(tailnet only)`, and
  `curl https://homelab.taila4ae6c.ts.net/obsidian` returned a real
  Let's Encrypt cert, HTTP/2, and a `401` (auth still enforced through
  the proxy, not bypassed).
- **No firewall change needed** — `iptables -S | grep 443` showed
  nothing before or after enabling serve. `tailscale serve` is handled
  entirely within tailscaled's own userspace netstack on the tailscale
  interface, the same way `tailscale ssh` bypasses the kernel
  socket/netfilter path `networking.firewall` governs — confirmed live,
  not assumed from docs.
- Test config was `tailscale serve reset` afterward — nothing left
  hand-configured on the live host; the real config needs to come from
  Nix.

Next: write the declarative systemd unit (idempotent, ordered after
`tailscaled.service` + `couchdb.service`, re-asserting the same `serve`
config every boot — safer than relying on it surviving in tailscaled's
persisted state alone), verify, deploy, confirm the same live checks
pass again from the Nix-declared unit.

**2026-09-03, unit built, reviewed, deployed and verified live; a real
permission bug found and fixed along the way (G3).** `/simplify` (2
parallel agents) and `security` both ran clean after fixes — F1
(`CapabilityBoundingSet=[""]`), F2 (documented root justification), F3
(oneshot drift-detection gap, accepted as out of scope). Separately,
live client testing on `torrent` surfaced a real, unrelated bug in the
*predecessor* plan's design: `obsidian-sync` was provisioned as a plain
database *member*, but CouchDB restricts writing `_design/*` documents
to database *admins* even for members of that same database, and
LiveSync's setup flow writes design documents — this produced a `403`
that had nothing to do with HTTPS. Fixed live (re-applied after a
LiveSync "fresh start" destroy-recreate wiped `_security` back to its
admin-only default, losing 361 pending files' first push attempt in the
process — the *second* attempt, using real admin credentials for that
one-time step, landed all 4007 documents including content chunks) and
corrected in `couchdb-provision-obsidian`'s Nix source so the fix
survives reboots. `docs-updater` ran clean (F4, no drift). Deployed via
`nixos-rebuild switch --target-host root@homelab`, verified live (see
Progress) including that the G3 fix and the vault's 4007 documents both
survived the actual switch, not just a hand-patch. User confirmed the
corrected `sls+https://...` connection string is correct and has it
in hand for other devices.

## Progress
- [x] live-tested `tailscale cert` + `tailscale serve` on the real host,
      confirmed HTTPS works end-to-end and needs no firewall change
- [x] declarative systemd unit `couchdb-tailscale-serve` drafted in
      `modules/services/couchdb.nix` (G1)
- [x] `nixfmt` / `nix flake check` / `nixos-rebuild build --flake
      .#homelab` clean
- [x] `/simplify` run — reuse+simplification and efficiency+altitude
      agents in parallel; applied `tailscaled-autoconnect` ordering fix
      and hoisted `tailscaleBin`; recorded G2 for the altitude finding
      (`services.tailscale.serve` checked, deliberately not used)
- [x] `security` subagent run — F1 (root with no `CapabilityBoundingSet=`,
      fixed), F2 (root justification undocumented, fixed via comment),
      F3 (oneshot can't detect config drift — accepted, out of scope for
      this pass, would need a reconciliation timer)
- [x] G3 discovered + fixed live during actual client testing:
      `obsidian-sync` needed database-admin not member-level access
      (design-document write restriction); Nix source corrected to match
- [x] `docs-updater` run — F4 (checked and clean, no fixes needed)
- [x] deployed + verified live — `nixos-rebuild switch --flake .#homelab
      --target-host root@homelab`. `systemctl --failed` empty;
      `couchdb.service`/`couchdb-provision-obsidian.service`/
      `couchdb-tailscale-serve.service` all active;
      `https://homelab.taila4ae6c.ts.net/obsidian` returns a valid
      Let's Encrypt cert + `401` (HTTPS live, auth still enforced,
      `CapabilityBoundingSet=[""]` didn't break the unit); the vault's
      4007 documents and the G3 `_security` permission fix both survived
      the real switch, not just a live hand-patch
- [x] user given the corrected mobile client URI
      (`sls+https://obsidian-sync:<password>@homelab.taila4ae6c.ts.net/?db=obsidian`,
      no port) once live

## Decisions (D)


## Gotchas (G)

### G1 — `tailscale serve` needs no `networking.firewall` rule, unlike a normal listening service
Confirmed live (see State): serve traffic on port 443 never appears in
`iptables -S`. Don't add a `networking.firewall.interfaces.tailscale0.
allowedTCPPorts` entry for 443 — there is nothing for it to open; adding
one would be a harmless no-op at best, but worth noting so a future pass
doesn't "fix" an imagined gap.

### G2 — `services.tailscale.serve` (the first-party NixOS option) was checked and deliberately not used
The pinned nixpkgs — confirmed against the exact `nixpkgs-stable` rev
`homelab` actually builds against
(`nixos/modules/services/networking/tailscale-serve.nix`), not just
unstable — ships a declarative `services.tailscale.serve.services.<name>`
option. Not used here because it implements Tailscale's newer *Services*
model: every entry gets prefixed `svc:<name>` and (per the module's own
config generation) is reachable at a `svc-name.<tailnet>.ts.net`-shaped
name, not the node's own tailnet identity. That's a different hostname
scheme than the classic per-machine `tailscale serve --https=443 <url>`
this plan already live-verified end-to-end against
`homelab.taila4ae6c.ts.net` — switching would mean re-verifying
reachability under an unconfirmed new hostname for no real benefit over
the already-working hand-rolled unit. Recorded here so a future pass
doesn't mistake the hand-rolled unit for an oversight.

### G3 — `obsidian-sync` needs database-*admin*, not member, on the vault db -- CouchDB restricts design-document writes to admins
Discovered live during actual client setup on `torrent`: with `obsidian-sync`
as a plain `members.names` entry (the original design), the LiveSync client
got a `403`/"Forbidden" partway through its first-run setup. CouchDB
restricts creating/modifying `_design/*` documents to database admins,
even for a user who is already a member of that same database — members
can read/write ordinary documents but never design documents. LiveSync's
setup flow writes design documents as part of initializing a vault.
Fixed by putting `obsidian-sync` in `_security.admins.names` instead of
`members.names` for the `obsidian` database specifically — this is still
scoped to *that one database*, not a server admin: it can't touch other
databases, `_users`, or server config. `modules/services/couchdb.nix`'s
`couchdb-provision-obsidian` script updated to match (it was still
writing the old `members`-based `_security` document, which would have
silently reverted a live hand-fix on the next boot/switch had this not
been caught).

Separately, and worth remembering for next time: CouchDB's `PUT /db`
(re)creation resets `_security` back to its bare default (`_admin`-role
only, i.e. *no* non-admin access at all) — LiveSync's own "fresh start"/
rebuild setup flow does a destroy-then-recreate of the remote database,
which wiped the `_security` document this plan's predecessor had set,
requiring it to be re-applied by hand after that rebuild completed. The
declarative `couchdb-provision-obsidian` unit re-asserts `_security` on
every boot/switch regardless, so this only bites between "a rebuild ran"
and "the host's next boot/switch" — a live-only window, already closed
now that the Nix source itself is fixed.

## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 — `couchdb-tailscale-serve` runs as root with no `CapabilityBoundingSet=`, unlike this fleet's own precedent for similar units

- **File:** `modules/services/couchdb.nix:196-227` (the new `systemd.services.couchdb-tailscale-serve`)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (absence in the diff/current file) for the gap itself; PLAUSIBLE for exploitability/fix-safety
- **Axis:** hardening
- **Reachability:** Root is genuinely required here — verified directly against pinned `tailscale` `1.98.10` source (`nix eval .#nixosConfigurations.homelab.config.services.tailscale.package.version`; confirmed via GitHub `tailscale/tailscale@v1.98.10`, `ipn/ipnauth/access.go`'s `IsReadonlyConn` and `ipn/ipnserver/actor.go`'s `connIsLocalAdmin`): a non-root LocalAPI caller only gets write access if it's the daemon's own UID, a configured `--operator=` UID, or (Linux) a member of an "admin"/"administrators" group — the Linux branch of `isLocalAdmin` unconditionally returns `no system admin group found`, so there's no non-root path here at all without an operator, and this fleet configures none (`grep -rn operator` found nothing; `security.sudo.enable = false` also rules out the "operator + sudo" fallback). So `User=` can't be dropped. Given that, the residual risk is *what root keeps that it doesn't need*: with no `CapabilityBoundingSet=`, a compromise of the `tailscale` CLI process during its brief oneshot run (supply-chain compromise of the pinned package, or a bug in tailscaled's own LocalAPI/JSON response handling reachable by whatever can write to the control socket) inherits the *full* root capability set (`CAP_SYS_ADMIN`, `CAP_NET_ADMIN`, `CAP_DAC_OVERRIDE`, etc.), not just what a LocalAPI `serve-config` POST actually needs (nothing beyond DAC access to the already-root-owned socket — `IsLocalAdmin`'s check is UID-based, not capability-based, so it would keep working with capabilities dropped). This repo already has fleet precedent for exactly this hardening step on a comparable root/CLI-wrapper oneshot unit: `hosts/vps/configuration.nix:858`, `CapabilityBoundingSet = [ "" ]` on the CrowdSec bouncer-registration unit.
- **Rule:** new-rule candidate (extends `docs/hardening.md`'s "Custom `systemd.services` sandboxing" bullet, which lists the `Protect*`/`Restrict*` stack but doesn't currently call out `CapabilityBoundingSet=` for root-running units specifically) — precedent at `hosts/vps/configuration.nix:858`
- **Finding:** the unit correctly needs `root` (see Reachability), but doesn't pare down what root brings with it. `CapabilityBoundingSet = [ "" ]` (or a short explicit allowlist if testing shows one is needed) would leave the unit's own privilege matched to what it actually exercises — a Unix-socket RPC to tailscaled — rather than the full root capability set by default.
- **Fix risk:** low-probability but worth testing rather than assuming: `tailscale serve --bg` shouldn't need any Linux capability beyond ordinary DAC access to the socket, but this wasn't traced with `strace`/`capsh` against the real binary. Before promoting, `nixos-rebuild build --flake .#homelab`, deploy to a VM, and confirm `systemctl start couchdb-tailscale-serve` still succeeds and `tailscale serve status` shows the expected config with `CapabilityBoundingSet = [ "" ]` set — if it fails, the specific missing capability will show up in the unit's own journal/exit code, not silently.


**FIXED 2026-09-03:** Added CapabilityBoundingSet = [ "" ] to couchdb-tailscale-serve's serviceConfig, matching the hosts/vps/configuration.nix CrowdSec bouncer-registration precedent. Root is still required (tailscaled's LocalAPI has no non-root path without a configured --operator=), but the process no longer retains capabilities beyond ordinary DAC access to the control socket.

### F2 — root justification for `couchdb-tailscale-serve` isn't recorded anywhere in-repo (only asserted in the launching prompt)

- **File:** `modules/services/couchdb.nix:189-195` (unit's leading comment block); `docs/plans/in-progress/2026-09-03-serve-couchdb-over-https-via-tailscale-serve-for-obsidian-mobile.md` `## Decisions (D)` (currently empty)
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** not an external-adversary path — this is a maintainability/regression risk. `docs/hardening.md`'s "Dedicated service users" rule requires noting *why* root is unavoidable when it can't be avoided (its own standing example is `zrepl`, documented in `docs/backups.md`). Here the code comment explains *what* the unit does and *that* it needs root ("needs access to tailscaled's control socket" — but that specific line only appears in the task prompt that launched this review, not in the diff itself), but no `D` entry in this plan and no comment in `couchdb.nix` records the actual mechanism (the `IsLocalAdmin`/`IsReadonlyConn` check traced in F1) that makes it true. A future contributor (human or agent) revisiting this unit — e.g. to apply a blanket "give services their own user" pass, or to copy this unit's shape for a different `tailscale serve`-adjacent use case where an operator *is* configured — has nothing in-repo to check against before either dropping root incorrectly (breaking the unit) or copy-pasting root into a context where it isn't actually required.
- **Rule:** violates `docs/hardening.md` "Dedicated service users" ("If root genuinely can't be avoided, note why in the commit message")
- **Finding:** the justification exists and is correct (see F1's Reachability), it just isn't written down anywhere durable yet. This is fixable in the eventual commit message and/or a `D` entry in this plan file before it's merged/frozen.
- **Fix risk:** none — pure documentation, no config change.


**FIXED 2026-09-03:** Added a comment above couchdb-tailscale-serve tracing the actual mechanism (tailscaled LocalAPI's UID-based auth check, no --operator= configured fleet-wide) and citing F1/F2 by anchor, so a future pass has something durable to check against before dropping or copy-pasting root.

### F3 — `couchdb-tailscale-serve`'s oneshot assert-once shape can't detect config drift away from the tailnet-only boundary it exists to enforce

- **File:** `modules/services/couchdb.nix:196-227`
- **Severity:** LOW
- **Confidence:** PLAUSIBLE (architecture inferred from `Type=oneshot`/`RemainAfterExit=true` semantics and systemd's own unit restart-propagation docs; not independently tested by actually toggling `tailscale funnel` against the live host, which this review must not do)
- **Axis:** hardening
- **Reachability:** anyone who already has root shell access to `homelab` (the same privilege level this plan's own "State" section used for live testing, and the same level any future debugging session — human or agent — would use) who runs `tailscale funnel --bg --https=443 http://127.0.0.1:5984` instead of `serve` (a one-word typo/copy-paste slip away, given `funnel` reuses the same `ServeConfig` shape and CLI syntax as `serve`), or who runs `tailscale serve reset`/`down` and forgets to restore it, silently moves CouchDB across the tailnet-only boundary this whole plan (and the frozen predecessor plan's D1) exists to hold — or silently drops the mobile HTTPS path entirely. `couchdb-tailscale-serve.service` would still show `active (exited)` in `systemctl status` in either case, because a `Type=oneshot`/`RemainAfterExit=true` unit only records that `ExecStart` last exited 0, not that the state it asserted is still true. Nothing here re-checks `tailscale serve status`/`funnel status` periodically or before reporting healthy — the same "attempt vs. outcome" gap `docs/hardening.md` rule 11 documents for `deploy-guards.nix`, just applied to a network-boundary assertion instead of a deploy guard. It's an existing repo-wide pattern (matches the sibling `couchdb-provision-obsidian` oneshot, and is not unique to this diff), but the stakes are categorically different here: `couchdb-provision-obsidian` drifting silently loses a DB record, whereas this unit drifting silently loses (or falsely claims) the tailnet-only network boundary D1 established as this feature's core security decision.
- **Rule:** violates `docs/hardening.md` rule 11's spirit ("A guard that declines to act must be watched by something that measures the outcome, not the attempt") — written for deploy guards specifically, extended here by analogy rather than literal violation
- **Finding:** no fix is proposed here (read-only review), but a fix would need to distinguish "asserted once at boot/switch" from "still true now" — e.g. a periodic timer unit that diffs `tailscale serve status --json`'s `AllowFunnel`/proxy target against the declared config and alerts/re-asserts on mismatch, following the same shape as this repo's existing health-alert units.
- **Fix risk:** n/a (no fix applied); a reconciliation timer would need to avoid fighting a legitimate hand-run `tailscale serve reset` during active debugging (e.g. skip re-assertion for some grace window, or make the check advisory/alerting-only rather than self-healing) — worth deciding deliberately rather than defaulting to instant self-heal.

**Checked and clean (security review, 2026-09-03):** Read the new
`couchdb-tailscale-serve` unit in full against `docs/hardening.md` and
`docs/agents/security/reference.md`. Verified against pinned nixpkgs
(`e4bae1bd`, `nix eval .#nixosConfigurations.homelab.config.services.
tailscale.package.version` → `1.98.10`) and upstream `tailscale/tailscale`
source at that exact tag, not from memory:
- **No new network exposure beyond D1's tailnet-only boundary.** Traced
  the `IsLocalAdmin`/`IsReadonlyConn` LocalAPI auth path in
  `ipn/ipnauth/access.go` and `ipn/ipnserver/actor.go` (v1.98.10) —
  confirms `require_valid_user`/basic-auth enforcement is untouched by
  TLS terminating inside tailscaled (it's a byte-level reverse proxy,
  Authorization header passes through), and that `tailscale serve`'s
  netstack-intercept design (packets handled before re-entering the
  kernel's normal socket/interface path) is consistent with this plan's
  own live-tested claim that no `networking.firewall` rule is needed —
  did not independently re-test this against the live host (out of
  scope for a read-only review), but found nothing in source or
  `docs/hardening.md`'s "Docker-published ports"/"Scope every firewall
  rule" rules (4, 5) that contradicts it, and the mechanism is
  architecturally distinct from the Docker-DNAT case those rules cover
  (no host-visible listening socket on a routable interface at all,
  versus a DNAT rule that bypasses one specific netfilter table).
- **`ExecStop`/teardown ordering is correct.** `After=tailscaled.service`
  means the reverse (stop) ordering runs `couchdb-tailscale-serve`
  before `tailscaled.service` on shutdown, so `tailscale serve
  --https=443 off` always runs against a still-live control socket.
  `Requires=couchdb.service` also means a `systemctl restart
  couchdb.service` (e.g. from a sops secret rotation's `restartUnits`)
  correctly restarts `couchdb-tailscale-serve` too, per systemd's own
  documented `Requires=` semantics ("this unit will be stopped (or
  restarted) if one of the other units is explicitly stopped (or
  restarted)") — not a stop-only propagation that would strand the unit
  down until next boot, which was the initial (wrong) hypothesis;
  corrected after reading `systemd.unit.xml` directly rather than
  assuming.
- **Sandboxing stack is not merely cosmetic on a root unit.** The full
  `Protect*`/`Restrict*` stack (`ProtectKernelModules`,
  `ProtectKernelTunables`, `RestrictNamespaces`, etc.) constrains root
  via mount-namespace/seccomp mechanisms that don't depend on DAC
  permission checks, so it meaningfully reduces blast radius here even
  though the unit runs as root — not decorative. (F1 is about the one
  gap in that stack — `CapabilityBoundingSet=` — not about the stack as
  a whole being pointless.)
- **No secrets touched.** This diff adds no `sops.secrets`/`sops.
  templates` and reads no existing ones; nothing here required following
  or checking `docs/procedures/secrets.md` beyond confirming that (a
  copy of the CouchDB admin credential flow untouched by this change).
- **`services.tailscale.serve` (first-party option) correctly not used**
  — already reasoned through in this plan's own G2 against the pinned
  `nixpkgs-stable` (`nixos-26.05`) module source, independently spot
  read and agreed with (`svc:<name>` hostname scheme is a genuinely
  different, unverified reachability target vs. the already-live-tested
  per-node hostname this unit uses).

_security finished 2026-09-04T05:01:07Z -- see Findings above._

**ACCEPTED 2026-09-03:** User is actively blocked on getting sync working; a periodic reconciliation timer to detect config drift (funnel vs serve, or a reset) is real but meaningfully larger scope than this pass, and the sibling couchdb-provision-obsidian unit already carries the identical assert-once limitation unaddressed. Accepted as a known limitation, not fixed now -- lower priority than unblocking the user's actual sync.

### F4 — checked and clean: `couchdb-tailscale-serve`/`couchdb-provision-obsidian` comments, plan citations, and homelab's Host Inventory

- **File:** `modules/services/couchdb.nix:189-227` (the `couchdb-tailscale-serve` unit's leading comment block and its `CapabilityBoundingSet=` comment), `modules/services/couchdb.nix:196-202` (the corrected `_security` PUT's comment); `hosts/homelab/README.md` (`<!-- inventory:start -->`/`<!-- inventory:end -->` block)
- **Axis:** docs
- **Finding:** all comments touched by this diff match shipped/deployed behavior, are terse and technical per `docs/style-guide.md` (no multi-sentence rationale prose inline), and cite the plan by bare-filename+anchor form (`#F1,F2`, `#F1`). Specifically verified, not assumed:
  - "Runs as root: tailscaled's LocalAPI only grants a non-root caller write access via a configured `--operator=`, which this fleet has none of" — `grep -rn operator modules/ hosts/` found zero matches, confirming the claim.
  - "tailscaled-autoconnect ordering matches the upstream tailscale module's own documented idiom ... see its tailscaled-set unit" — checked directly against the pinned `nixpkgs-stable` tarball (`nixos-26.05.8846.a3116115851d`, rev `a3116115851d68b8952a2a4221cc25a84e56b532`, matching the rev already cited in the frozen predecessor plan's F6): `nixos/modules/services/networking/tailscale.nix` line 88 states this exact ordering rule in `authKeyFile`'s option description, and the real `tailscaled-set` unit (line 237-241) uses `after = [ "tailscaled.service" "tailscaled-autoconnect.service" ]` — an exact match.
  - The `_security` comment ("syncUser is a *database* admin ... not a members.names entry") matches the actual PUT body in the diff (`admins.names = [syncUser]`, `members.names = []`).
  - `scripts/doc-host.sh homelab` re-run (required per the docs-updater "Host Inventory freshness" rule, since `couchdb.nix` — a module `homelab` pulls in — changed): produced **no diff**. Expected, not a gap — the inventory's "Services (enabled)" section is generated from `services.*.enable`-shaped NixOS options only (confirmed by reading `scripts/doc-host.sh`'s own `apply_rest` Nix lambda), and neither `couchdb-tailscale-serve` nor its sibling `couchdb-provision-obsidian` is such an option; both are raw `systemd.services.*` units, which the script doesn't enumerate. The firewall section is likewise unaffected — port 443 correctly does not appear there, matching G1 (tailscale serve traffic never touches `networking.firewall`'s netfilter path). The script itself ran clean (no new upstream compat-shim `abort` case).
  - No structural change (no new module category, no new per-folder doc convention) — `AGENTS.md`'s docs table and `docs/procedures/updating-documentation.md` don't need updates for this diff.
- **Fix:** none needed — no drift found, nothing changed.

_docs-updater finished 2026-09-04T05:34:17Z -- see Findings above._

_docs-updater finished 2026-09-04T05:34:48Z -- see Findings above._

**MOOT 2026-09-03:** Pure checked-and-clean sign-off, no defect found -- nothing to fix.
