---
slug: troubleshoot-fail2ban-vps-closed-port-scan-journal-stall
created: 2026-09-03
status: in-progress
frozen: false
---

# troubleshoot fail2ban vps-closed-port-scan journal stall

## Original plan

`vps`'s `services.fail2ban.jails.vps-closed-port-scan`
(`hosts/vps/configuration.nix:860`) is supposed to zero-threshold-ban any
source hitting a closed port, reading `networking.firewall
.logRefusedConnections` kernel log lines via the `systemd-journal`
backend, feeding bans into CrowdSec's decision list via the `cscli`
action. Live investigation (prior conversation turn, not yet written up
as a plan) found:

- The kernel journal has 451k+ `refused connection:` lines since the
  2026-08-26 boot — scanning traffic is real and constant.
- `fail2ban-regex` against a live sample of those lines matches the
  jail's filter cleanly (5/5).
- `fail2ban-client status vps-closed-port-scan` stays at `0 failed / 0
  banned` even across a live window where two more matching lines landed
  in the kernel journal seconds apart, with jail loglevel bumped to
  DEBUG — no filter-processing log lines appeared at all.
- The jail's own startup log says `Jail is in operation now (process new
  journal entries)` and `Added journal match for: '_TRANSPORT=kernel'` —
  looks healthy from the outside, but the filter thread appears to not
  be consuming events at all.
- Separately confirmed (not part of this bug): CrowdSec's own SSH
  scenario correctly sees zero external SSH hits because the live
  `iptables nixos-fw` chain only accepts port 22 on `tailscale0` — no
  public accept rule exists. That's working as designed, not part of
  this investigation.

Goal: find why the `systemd-journal` filter backend isn't processing
events for this jail, and fix it so `vps-closed-port-scan` actually bans.

## State

Scope grew substantially past the original one-line anchor fix after the
`security` subagent's F1 finding (see below): the anchor fix alone was
judged correct-but-dangerous, since it reactivates a SYN-spoofing
collateral-DoS gap that predates this plan (matches the 2026-08-26 audit's
open `F-P2-03`, plus a separate open bug `F-P2-04` where fail2ban's
`actionunban` deletes *all* CrowdSec decisions for an IP, not just its
own). Decided path (D2): stop patching the fail2ban jail and instead
delete it, replacing it with CrowdSec's own official
`crowdsecurity/iptables` collection (`iptables-scan-multi_ports` scenario:
15 distinct ports/5s corroboration, not a one-packet trigger) reading the
same kernel LOG source — closes F1 and F-P2-04 in one move. Extra scope
added on top (D3): `crowdsecurity/cdn-whitelist` and CAPI registration.
Also added (D4, done): a rate limit on the `refused connection:` LOG rule
itself, unrelated to the CrowdSec swap but touching the same firewall
code, addressing a journald-overrun amplifier noted in the same F-P2-03
writeup.

D2/D3/D4 are all now implemented and build-verified (`verify-ladder`
clean, including a real `nixos-rebuild build --flake .#vps`). The
original anchor-only edit is gone from the tree -- `jails.
vps-closed-port-scan` and the whole `services.fail2ban` block plus its
`cscli.conf` action were deleted outright, not patched, since D2
superseded that approach. Verification fork confirmed `labels.type =
"syslog"` is correct for the new kernel acquisition too (same as
sshd/caddy -- `crowdsecurity/iptables-logs`'s parser keys off
`evt.Parsed.program == 'kernel'`, populated by the syslog-logs s00-raw
stage, not a dedicated label) and that CAPI registration has a real
declarative option (`settings.capi.credentialsFile`, wired into
`online_client.credentials_path`) -- no hand-rolled oneshot needed,
simpler than originally assumed. Manually confirmed against the actual
rendered `crowdsec.yaml` and `local_acquisisions.yaml` in the nix store
(not just that it built) that all three land correctly: the kernel
acquisition entry, `online_client.credentials_path` pointing at
`/var/lib/crowdsec/online_api_credentials.yaml`, and `pull.blocklists/
pull.community/sharing` all `true` (module defaults once
`capi.credentialsFile` is set).

`/simplify` (4 parallel angles) ran against the full diff and caught a
real bug in D4's own implementation (G4, above) that none of nixfmt/
statix/deadnix/nix-flake-check/nixos-rebuild-build could have caught --
fixed and re-verified against the actual rebuilt firewall-start script's
rule order, not just that it builds. Reuse and simplification passes
came back clean; altitude flagged the SPOF tradeoff addended to D2
above, not a code change.

The fresh `security` re-review (scope had changed substantially since the
first pass) found one more real, HIGH-severity bug: F3 --
`crowdsecurity/cdn-whitelist` is a hub *postoverflow*, not a collection,
and putting it in `hub.collections` would have made `cscli collections
install` fail hard, unguarded, in `crowdsec-setup`'s `set -euo pipefail`
`ExecStartPre` -- meaning `crowdsec.service` (sshd/caddy/linux/iptables
detection, all of it, not just the new port-scan piece) could never
start, invisible to everything this plan had run up to that point. Fixed
(moved to `hub.postOverflows`); then, per a related finding (F4, that
`cdn-whitelist` is architecturally a no-op on this box since vps's
Cloudflare usage is DNS-only) and the user's explicit choice, dropped
entirely rather than kept as harmless dead weight. Two more findings (F5:
the rate limit also throttles a human's live-tail visibility during an
incident, not just journald load; F6: CAPI's exact sharing payload wasn't
independently verifiable from nixpkgs alone) were resolved properly, not
waved through -- F5 via an actual numeric trade-off analysis (raised
10/sec/burst-30 to 50/sec/burst-100, user's choice from the analysis);
F6 via a second research fork reading CrowdSec's actual v1.8.0 Go source
directly (not docs), confirming the payload is genuinely minimal by
default. All of F1-F6 are now resolved (F1/F2 MOOT, F3-F6 FIXED).

Also since: rebased cleanly onto master (moved substantially while this
plan was in flight, PRs #51-56, none touching `hosts/vps/configuration.nix`)
and regenerated `hosts/vps/README.md`'s machine-generated Host Inventory
block to drop the stale `fail2ban` listing. Then D6 (VM-test this end to
end): built `tests/vps-refused-connection-logging.nix`, a two-node
`runNixOSTest` proving the firewall-side fix with a real client
connection over the test LAN (loopback bypasses `nixos-fw-log-refuse`
entirely, so a single-node test would prove nothing) -- 6 subtests, all
passing, directly targeting G4's bug class (a rule that builds clean and
never fires) and covering what's genuinely offline-testable. Explicitly
does *not* attempt to prove CrowdSec's scenario fires a real ban --
`crowdsec.service`'s `ExecStartPre` needs live internet access to fetch
hub content that this repo's sandboxed VM-test build cannot reach; scoped
and documented as an accepted limit under D6, not silently skipped.

Remaining before this can move to `done`: commit. Not yet deployed to the
live host -- `nixos-rebuild build`/VM-tested only, per this repo's
test-before-switch convention; `nixos-rebuild switch`/reboot-testing on
the real box, plus the D5 post-deploy `cscli decisions delete --all`
step, are separate follow-ups for whoever deploys this.

## Progress

- [x] D1
- [x] Re-confirm the stall live on `vps` before changing anything
- [x] Root-cause the systemd-journal filter stall
- [x] D2 -- decide fail2ban-jail fix vs CrowdSec-collection redesign
- [x] D3 -- decide extra CrowdSec scope (cdn-whitelist, CAPI)
- [x] D4 -- rate-limit the refused-connection LOG line (implemented, build-verified)
- [x] Verify crowdsecurity/iptables-logs acquisition labels + cscli capi register idempotency
- [x] Remove fail2ban jail/service + cscli.conf action entirely (supersedes the anchor-only edit)
- [x] Remove /var/lib/fail2ban from impermanence persistence list
- [x] Update hosts/vps/README.md's fail2ban reference
- [x] Add crowdsecurity/iptables collection + kernel journal acquisition
- [x] Add crowdsecurity/cdn-whitelist collection (later dropped entirely -- F3/F4)
- [x] Add declarative CAPI registration (settings.capi.credentialsFile)
- [x] verify-ladder (re-run after full implementation)
- [x] /simplify (re-run -- caught and fixed a real bug, see G4)
- [x] security review (re-run -- found F3 HIGH: crowdsecurity/cdn-whitelist miscategorized under hub.collections, would have prevented crowdsec.service from ever starting)
- [x] resolve F1 (MOOT -- the jail this finding was about no longer exists)
- [x] resolve F2 (MOOT -- the jail/comment this finding was about no longer exists)
- [x] fix F3 (moved to hub.postOverflows, then per F4+user choice dropped entirely; re-verified against rebuilt crowdsec-setup script)
- [x] resolve F4 (FIXED -- dropped, user's choice)
- [x] resolve F5 (FIXED -- rate limit raised to 50/sec burst 100 after trade-off analysis, user's choice)
- [x] resolve F6 (FIXED -- verified directly against v1.8.0 Go source, not docs; payload confirmed minimal by default, see G5 for the version-citation correction that preceded this)
- [x] Rebase onto master (moved substantially -- PRs #51-#56, homelab/immich/jellyfin/keyboard-layout work, none touching hosts/vps/configuration.nix) via `git rebase --autostash origin/master`, clean, no conflicts. Regenerated hosts/vps/README.md's machine-generated Host Inventory block (`scripts/doc-host.sh vps`, itself added to master since this plan started) to drop the stale `fail2ban` service/package listing. Re-ran verify-ladder: identical vps toplevel store hash to pre-rebase, confirming no semantic effect on this host.
- [ ] commit
- [x] D5 -- decide post-deploy decision-list cleanup scope
- [ ] POST-DEPLOY (not this session, live-host action): `cscli decisions delete --all` on `vps` after this plan's diff is switched, not just built
- [x] D6 -- design and run the VM test (tests/vps-refused-connection-logging.nix, 6 subtests, all passing -- see D6 for what's covered vs. the accepted network-access scope limit)

## Decisions (D)

### D1 -- Fix approach once root cause is known
Not yet reached — need to know *why* the filter stalls before deciding
whether the fix is a jail-config change, a fail2ban version/package pin,
switching this jail to a different backend (e.g. a real logfile instead
of journal), or something else.


**ANSWERED 2026-09-03:** Root cause found empirically on vps: FilterSystemd.formatJournalEntry() (fail2ban/server/filtersystemd.py) prepends '<hostname> kernel: [<monotonic-ts>] ' before the kernel MESSAGE text for any _TRANSPORT=kernel entry (since SYSLOG_IDENTIFIER=kernel triggers its monotonic-timestamp branch). The jail's failregex is anchored with ^refused connection:, which never matches that prefixed line -- confirmed live: fail2ban-regex against the exact live-formatted line gives 0 matched/1 missed with the anchor, 1 matched with it removed. Fix: drop the ^ anchor. Filter's own journalmatch (_TRANSPORT=kernel) plus the LOG prefix's specificity means dropping the anchor introduces no false-positive risk.

### D2 -- How to resolve F1 (the SYN-spoofing gap the anchor fix reactivates): patch, mitigate, or redesign
The `security` subagent's F1 finding (below) showed the anchor-only fix
reactivates a design gap that predates this plan and matches the
2026-08-26 audit's still-open `F-P2-03`. Presented four options: ship
as-is with accepted-risk sign-off, bump `maxretry`, decouple from
CrowdSec's shared decision list, or hold the fix and redesign detection
to require handshake completion. User asked for detail on the redesign
option; research (fork) found full handshake-completion tarpits
(`portspoof`) are real but absent from nixpkgs (no package, no module)
and disproportionate for a single-admin 1vCPU/1GB droplet, while
CrowdSec's own hub already ships a purpose-built scenario for exactly
this detector class: `crowdsecurity/iptables-scan-multi_ports` (15
distinct destination ports from one source within 5s, not a one-packet
trigger; CrowdSec's own hub metadata rates it `spoofable: 3`, i.e. not
claimed spoof-proof, just materially harder to trigger by accident or a
single forged packet).


**ANSWERED 2026-09-03:** Delete the fail2ban jail entirely; replace it with CrowdSec's crowdsecurity/iptables collection (iptables-scan-multi_ports scenario) reading the same networking.firewall.logRefusedConnections kernel LOG source CrowdSec's own iptables-logs parser is built to consume. Chosen over a from-scratch tarpit build (real infra work, nothing to reuse in nixpkgs) and over patch-in-place options (maxretry bump doesn't stop a determined spoofer who can just as easily send N packets instead of 1; ship-as-is needed a risk sign-off this avoids needing). Bonus: also closes the separately open F-P2-04 (fail2ban's actionunban deleting all CrowdSec decisions for an IP, including CrowdSec's own longer-running ones) -- removing fail2ban's cscli action removes that interference entirely, not just the spoofing gap.

**2026-09-03 addendum (from `/simplify`'s altitude pass):** this also
collapses closed-port-scan detection from two independent processes
feeding one shared decision list down to one -- everything now depends
on the single `crowdsec` process; if it crashes/OOMs, no *new* bans of
any kind get generated (the separate `crowdsec-firewall-bouncer` still
*enforces* existing decisions, it just can't add more). Worth naming
explicitly even though the practical loss is smaller than it sounds:
per D1, the fail2ban side of that redundancy had already been silently
dead for 8 straight days before this plan started, and SSH detection
was already CrowdSec-only (`jails.sshd.enabled = false`) even when
fail2ban worked. The only real change is that the closed-port-scan
detector, once fixed, now lives in the same process as everything else
instead of a second one -- an accepted tradeoff, not an oversight.

### D3 -- Extra CrowdSec scope beyond the core detector swap
Given D2 already meant touching `services.crowdsec.hub.collections` and
researching CrowdSec more broadly, user asked what else this box's
CrowdSec config is missing (a broader best-practices pass, not just the
port-scan scenario). Research (fork) covered CAPI/Console enrollment,
AppSec/WAF, benign-scanner allowlisting, and notification plugins.


**ANSWERED 2026-09-03:** Add two items to this same plan: crowdsecurity/cdn-whitelist (cheap, reduces false-positive noise from real CDN ranges, no known downside) and CAPI registration (community blocklist consumption; mainstream and low-cost in data shared for unmodified hub scenarios, per CrowdSec's own docs). CAPI registration needs an idempotent systemd oneshot rather than a declarative module option, since NixOS's services.crowdsec enrollment path has an open upstream bug (nixpkgs #446764) making the declarative route a no-op -- user explicitly asked for the idempotent-oneshot approach given that constraint, mirroring this file's existing crowdsec-allowlist-tailnet unit pattern. Explicitly out of scope, per research + user steer: full Console enrollment (low value for one box, one admin), AppSec/WAF (real value for the caddy-fronted surface, but an always-on extra process needing sizing on a 1vCPU/1GB droplet -- separate future work, not bundled here), Discord ban notifications (no built-in plugin, only a Slack-webhook-repurposing hack), and allowlisting Censys/Shodan (CrowdSec maintainers state on their own forum this is deliberately left to each operator, not something CrowdSec opts users into -- a values call, not a defect to fix).

**2026-09-03 correction (F3/F4):** the fresh `security` pass found
`crowdsecurity/cdn-whitelist` is a hub *postoverflow*, not a collection
-- putting it in `hub.collections` as originally implemented would have
made `cscli collections install` fail hard and `crowdsec.service` never
start at all (F3, HIGH). Fixed by moving it to `hub.postOverflows`, the
correct option. Separately (F4), even correctly typed it turned out to
be architecturally a no-op on this box -- vps's Cloudflare usage is
DNS-only, no CDN proxying in front of caddy, so there's nothing in this
box's actual traffic for a CDN-IP whitelist to match. Presented both
options (keep it harmlessly vs. drop it); user chose to drop it
entirely. `crowdsecurity/cdn-whitelist` and `hub.postOverflows` are no
longer in the config. CAPI registration (the other half of this
decision) is unaffected by either finding.

### D4 -- Rate-limit the refused-connection LOG line
User asked (while D2/D3 research was still pending) whether the
`networking.firewall.logRefusedConnections` LOG rule needed rate
limiting, given the same 2026-08-26 audit's F-P2-03 writeup separately
flagged it: the module's generated rule has no `-m limit`, so under a
real scan it can outrun journald's own rate limit (10000/30s) and start
silently dropping the exact messages either detector (fail2ban today,
CrowdSec after D2) reads.


**ANSWERED 2026-09-03:** Add -m limit --limit 10/sec --limit-burst 30 to the LOG rule, via networking.firewall.logRefusedConnections = false (suppresses the module's own unlimited version) plus a hand-written rate-limited replacement with the identical log-prefix, appended into the existing networking.firewall.extraCommands block (see G2 -- a second, separate extraCommands = ... assignment in the same file does not merge and fails the build). User's one hard constraint, twice repeated: this must not touch the pre-existing vps-ratelimit game-port hashlimit values in that same block, especially factorio's --hashlimit-above 2000/second --hashlimit-burst 1000 (raised previously to fix real in-game issues) -- confirmed byte-for-byte unchanged in the built firewall-start script after merging. 10/sec, burst 30 chosen as well under journald's ~333/sec effective limit with headroom for a real scan's opening burst; user confirmed these numbers directly.

**2026-09-03 addendum (F5, numbers revised):** the fresh `security`
pass (F5) noted the rate limit also throttles what a human sees live
during an actual scan, not just journald load -- a real cost D4's
original reasoning didn't weigh. User asked for the trade-off to be
analysed properly rather than just accepted or rejected. Analysis: the
10/sec choice left ~33x headroom under journald's real ~333/sec ceiling
(confirmed not overridden anywhere in this repo --
services.journald.rateLimitBurst/rateLimitIntervalSec both unset, so the
systemd default of 10000/30s applies), while CrowdSec's own
iptables-scan-multi_ports only needs ~3/sec (15 distinct ports/5s) to
detect a scan -- so the original cap was never actually protecting
detection, it was trading away live visibility for margin nobody was
spending. Raised to 50/sec, burst 100 (user's choice from the presented
options) -- still ~6.5x headroom under journald's ceiling, comfortably
above CrowdSec's detection floor, materially better live-tail visibility
during an incident. Re-verified against the rebuilt firewall-start
script: correct values, still `-I ... 1` (G4), factorio's hashlimit
still byte-for-byte unchanged.

### D5 -- Post-deploy: wipe CrowdSec's decision list to undo the spoofed-ban damage
The old `vps-closed-port-scan` jail, once its anchor bug was fixed
(intermediate step, since superseded by D2), was live and spoofable for
some window before D2 replaced it -- and separately, per F1, was
_already_ theoretically vulnerable in its original 2026-08-25 design the
whole time it happened to be silently dead. Either way, `vps`'s current
live CrowdSec decision list (not this worktree's build -- the box as it
stands right now, pre-this-plan's-deploy) cannot be trusted to contain
only legitimately-detected bans; some entries may be innocent third
parties caught by a spoofed SYN. Asked whether to clear only
fail2ban-tagged decisions (`--reason "fail2ban-<jailname>"`, leaving
CrowdSec's own sshd/caddy/scenario bans untouched) or wipe everything.


**ANSWERED 2026-09-03:** Wipe the entire decision list post-deploy, not just fail2ban-tagged entries -- user's explicit choice, made after the narrower alternative was presented. Command, verified against the pinned cscli 1.8.0's own --help (not assumed): cscli decisions delete --all. This is a live-host action against the real vps box, to run only after this plan's diff is actually deployed (nixos-rebuild switch, not build) -- out of scope for this session, which stays build-only per this repo's test-before-switch convention. Whoever deploys this plan's changes must run it as a distinct follow-up step; it is not part of the Nix config and cannot be captured declaratively.

### D6 -- VM-test this end to end, once the security re-review is resolved
User: this diff should be VM-tested end to end, to do once the fresh
`security` pass lands -- not just `nixos-rebuild build`, which only
proves the config evaluates and renders, not that the runtime behavior
is real (exactly the class of gap `/simplify` just caught in G4: a rule
that built cleanly and was completely dead at runtime). Closest existing
precedent in this repo: `tests/docker-publish-guard.nix`
(`pkgs.testers.runNixOSTest`, multi-node `nodes.client`/`nodes.machine`,
proves real netfilter behavior with an actual client connection rather
than trusting rendered rules, and explicitly includes a "restarting
converges instead of duplicating rules" subtest -- directly relevant
here given G4's `-I ... 1` fix depends on the chain being freshly
flushed every firewall restart).

Known open constraint, not yet resolved: `crowdsecurity/iptables` and
`crowdsecurity/cdn-whitelist` are fetched live from CrowdSec's hub at
service start (`cscli hub update`/`hub install`), not vendored in the
nix store -- unclear yet whether this repo's sandboxed VM-test build
environment has real internet access to fetch hub content, which
determines whether the *scenario-detection* half of this test
(CrowdSec actually banning a simulated multi-port scan) is even
possible offline, versus only being able to test the parts that don't
need the hub (the rate-limited LOG rule firing/not-duplicating, the
acquisition being read, CAPI credentials file behavior). Needs
investigation before the test can be scoped/designed, not before it's
useful -- this D stays open until that's resolved and a concrete test
plan exists.


**ANSWERED 2026-09-03:** Confirmed the network constraint: pkgs.testers.runNixOSTest builds inside Nix's standard sandboxed derivation build, which blocks real internet access by design (matches every existing test in this repo being fully offline). crowdsec.service's ExecStartPre genuinely cannot fetch hub content (crowdsecurity/iptables's parser/scenario) in this sandbox, so CrowdSec actually starting and its scenario actually firing a ban is real-deploy territory, not build-time-testable here -- documented as an explicit, accepted scope limit rather than attempted. Built tests/vps-refused-connection-logging.nix instead, scoped to everything that IS offline-testable and has real value: a two-node (client/machine) VM test, same shape as tests/docker-publish-guard.nix (loopback bypasses nixos-fw-log-refuse entirely via the module's own -i lo accept rule, so a single-node test proves nothing -- needs a real client connection over the test LAN). Six subtests, all passing: (1) a refused connection is actually refused, not silently accepted by the -I ...1 insertion; (2) it produces a rate-limited LOG line; (3) that line is scoped to _TRANSPORT=kernel, matching CrowdSec's own acquisition filter exactly; (4) a fast 250-port SYN burst is capped near the 100-packet limit, not logged unbounded; (5) restarting the firewall twice does not duplicate the rate-limited rule (directly targets G4's fix, which depends on the chain being freshly flushed every restart); (6) refusal still works after a restart. Registered as checks.vps-refused-connection-logging in modules/flake/checks.nix. Ran via nix build .#checks.x86_64-linux.vps-refused-connection-logging -- passed clean, confirmed by reading the actual test driver log, not just a zero exit code. One real bug caught and fixed during test-writing itself: the first version asserted 'exactly one' LOG line per probe, which failed at 4 -- nc's own TCP stack retransmits a SYN it never gets an RST for during its timeout window, so multiple LOG lines from one client-side probe is correct behavior, not a bug; relaxed to 'at least one' and the burst subtest covers the actual rate-cap claim.

## Gotchas (G)

### G1 -- `nft` is not on PATH on `vps`; the box uses `iptables`
The live firewall is iptables-nft under the hood but only the `iptables`
binary is present in root's non-interactive SSH `PATH`
(`/run/current-system/sw/bin/iptables`) — `nft list ruleset` silently
returns nothing (command not found, swallowed by a piped `grep`) rather
than erroring loud. Use `iptables -L nixos-fw -n -v` on this host, not
`nft`.

### G2 -- `networking.firewall.extraCommands` (types.lines) only merges across separate module definitions, not two `=` assignments in one file

Assumed a second `networking.firewall.extraCommands = ''...'';` block
later in the same flat attrset would auto-concatenate with the first,
same as `types.lines` options merge across genuinely separate modules.
Wrong: writing the same attribute path twice via plain `=` in one
attrset literal is a hard Nix-level conflict (`attribute ... already
defined`), caught immediately by `nix flake check` -- NixOS's
cross-module merge behavior for `types.lines` never enters into it
within a single file's flat set. Fix: merge the new lines into the one
existing `extraCommands` string instead of adding a second definition.
Reusable lesson for this repo: this pattern (`cfg.foo = ''...'';` set
more than once) only merges automatically when the definitions come from
distinct imported modules, not from repeating the attrpath in the same
`{ }`.

### G3 -- nixpkgs' own `services.crowdsec` CAPI-idempotency guard has a stray `]`, but it's inert for this use

Verification fork read the pinned nixpkgs `crowdsec.nix` module directly
(`nixos/modules/services/security/crowdsec.nix`, `crowdsec-setup`
activation script) and found the check that gates `cscli capi register`
(so re-running activation doesn't blindly re-register with a fresh
machine identity every time) is malformed: `if ! grep -q password
"$credentialsFile" ]; then` -- a trailing `]` with no matching `[`, not
a real test-construct. Traced the actual runtime effect rather than just
flagging it: `grep -q`'s documented behavior is to exit 0 immediately on
the *first* matching file, even if a later file argument errors -- so
when `$credentialsFile` already contains "password", grep matches and
exits 0 before ever touching the bogus `]` argument (skip re-register,
correct). When it doesn't yet contain "password" (not yet registered),
grep falls through to `]` as a second file, which doesn't exist, and
exits nonzero anyway (still triggers registration, also correct). Both
branches land on the right outcome despite the typo -- this is a
pre-existing nixpkgs bug (not introduced by this plan), confirmed
cosmetic for this specific single-`grep -q` usage, not something this
plan needs to work around. Not upstreamed/reported as part of this plan;
worth a note if anyone later touches this file for an unrelated reason.

### G4 -- `-A` on the module-owned `nixos-fw-log-refuse` chain is unreachable dead code; needed `-I ... 1` instead

`/simplify`'s efficiency pass caught a real correctness bug in D4's own
implementation, not just style: the module's `nixos-fw-log-refuse` chain
already ends in an unconditional `-A nixos-fw-log-refuse -j
nixos-fw-refuse` (a terminal REJECT/DROP) by the time `extraCommands`
runs (`firewall-iptables.nix` builds the chain body at lines 97-115,
`extraCommands` splices in at line 235). Appending the new rate-limited
LOG rule with `-A` put it *after* that terminal jump in the chain --
every packet was already refused before ever reaching it, making the
whole rule permanently unreachable. This would have silently starved the
new CrowdSec kernel acquisition of any data too (nothing to log means
nothing to ban), which is exactly the class of bug this entire plan
started from (a detector that looks wired correctly but never fires) --
caught only because `/simplify` was run as a mandatory step, not because
the build or `nixfmt`/`statix`/`deadnix` caught it (none of them can;
this is a runtime rule-ordering question `nix flake check`/`nixos-rebuild
build` cannot see). Fixed by changing both the `iptables` and `ip6tables`
lines from `-A nixos-fw-log-refuse ...` to `-I nixos-fw-log-refuse 1
...` (insert at the front instead of appending at the end) --
re-verified against the actual rebuilt `firewall-start` script's rule
order this time, not just that it builds, confirming the LOG rule now
sits ahead of the chain's own refuse/reject rules.
Reusable lesson: when hand-writing a rule into a chain someone else's
code also populates, always check the *actual built script's* final
rule order for that specific chain, not just that each individual line
you added looks right in isolation and the whole thing compiles/builds.

### G5 -- The fresh `security` pass cited the wrong crowdsec/cscli version (v1.7.2) for a source lookup; actual pinned version is v1.8.0

F3's writeup cites `cscli`'s install source "at the exact pinned crowdsec
version (`cmd/crowdsec-cli/cliitem/cmdinstall.go`, `crowdsecurity/crowdsec`
tag `v1.7.2` -- matches `pkgs.by-name/cr/crowdsec/package.nix`'s pinned
`version = "1.7.2"` exactly)". Checked this directly before trusting it
for a follow-up lookup (F6's CAPI payload research): the actual locally
built binary reports `cscli version` = **v1.8.0**, not v1.7.2 --
confirmed by running the real binary
(`/nix/store/l5503qygq2xbdx5rzfsdan799p6w8n8h-crowdsec-1.8.0/bin/cscli
version`), not by reading a package.nix file (which may not have existed
at the path the citation named -- `find` for that exact path came back
empty in this worktree's nixpkgs checkout). F3's own core finding
(cdn-whitelist categorized wrong, install fails hard) is independently
re-confirmed against the actual rebuilt `crowdsec-setup` script either
way, so this version error didn't invalidate F3 -- but it would have sent
F6's follow-up research to the wrong GitHub tag if not caught first.
Reusable lesson: a subagent's own "verified against pinned source" claim
is still worth a cheap re-check (run the real binary's own `--version`)
before citing that exact version number again downstream, especially
when about to fetch external source at a specific tag.

## Findings (F)

### F1 -- Removing the anchor activates a pre-existing SYN-spoofing collateral-DoS design gap (jail goes from dead to live)

- **File:** `hosts/vps/configuration.nix:863-882` (jail definition); root cause mechanism confirmed against `fail2ban/server/filtersystemd.py:211-247` in the pinned `fail2ban` 1.1.0 source (nixpkgs rev `e4bae1bd10c9c57b2cf517953ab70060a828ee6f`, `pkgs.by-name/fa/fail2ban/package.nix`, hash-verified against `github:fail2ban/fail2ban/1.1.0`); LOG rule confirmed at `nixos/modules/services/networking/firewall-iptables.nix:99-115` in the same nixpkgs checkout (`-p tcp --syn -j LOG --log-prefix "refused connection: "` — SYN packets only, no completed-handshake check).
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (mechanism: LOG rule fires on SYN alone with no source verification, `cscli decisions add --ip <ip>` takes the log-derived IP unauthenticated, `rp_filter` provides no protection for a single-uplink host since the reverse route to any external address also egresses the same WAN interface) — PLAUSIBLE that a given real-world attacker has access to a spoofing-permissive upstream (not independently tested from this review).
- **Axis:** hardening
- **Reachability:** any unauthenticated internet host that can source packets through a network that doesn't filter egress (BCP38-noncompliant transit, common among some VPS/bulletproof providers) can send a single raw TCP SYN with a spoofed `SRC=<victim-ip>` to any closed port on vps's public interface. The kernel logs "refused connection: ... SRC=<victim-ip> ..." (`_TRANSPORT=kernel`), the now-unanchored failregex matches on first sight (`maxretry=1`), and `cscli decisions add --ip <victim-ip> --duration <bantime>s --type ban` bans the victim's real IP from vps's public services (caddy on 80/443, and indirectly the DNAT'd game ports, since the comment at `hosts/vps/configuration.nix` says this feeds "the same [decision list]...the DNAT'd game ports already consult") for 4h, escalating via `bantime-increment` (up to 90d) if the attacker repeats the spoof. No authentication, no prior compromise, and no rate limit stands between the attacker and an arbitrary third party losing access to vps for up to 90 days.
- **Rule:** new-rule candidate — `docs/hardening.md` has no existing rule against feeding an escalating, shared, zero-threshold ban action from evidence an off-path attacker can forge for free (an unacknowledged SYN, logged via a kernel LOG target with no handshake completion or challenge). Candidate: any first-sight/zero-threshold ban action fed from unauthenticated, spoofable protocol evidence (raw SYN, ICMP, UDP) needs either a completed-handshake source (TCP data after SYN-ACK, not the SYN itself) or a secondary corroboration step (rate threshold, multiple independent sources) before it's allowed to write into a *shared* ban/decision list.
- **Finding:** This design gap (banning on a raw refused SYN, which is trivially spoofable and was never designed with the handshake-completion caveat) predates this diff — it was present in the jail's original design. But the jail was **completely non-functional** for the 8 days before this fix (0 failed/0 banned per the plan's own D1), so the gap was latent and unreachable in practice: the vulnerable code path (unanchored match -> action=cscli) never executed. This diff's entire effect is to make that code path execute for the first time. The fix is very likely still the right call — the jail exists specifically to ban closed-port scanners — but merging this diff is what turns a latent design flaw into a live, exploitable one, and that tradeoff isn't called out anywhere in the plan or the diff's own comment. The comment added by the diff explains *why* the anchor was wrong but says nothing about the SYN-spoofing exposure it reactivates.
- **Fix risk:** Any fix here (e.g. switching to a handshake-verified signal, adding a corroboration/threshold step before the first-sight ban, or scoping bans to fail2ban's own decision list instead of CrowdSec's shared one) changes the jail's detection semantics and needs to be checked against the jail's whole stated purpose ("ban on first sight, no legitimate traffic can trigger this filter") — a naive fix (e.g. bumping `maxretry`) would blunt the intended fast response to genuine scanners, not just the spoofing exposure. Needs a decision from whoever owns the CrowdSec/fail2ban design, not a mechanical patch.


**MOOT 2026-09-03:** The fail2ban jail this finding was about (services.fail2ban.jails.vps-closed-port-scan, plus its cscli.conf ban action) was deleted outright by D2, not patched -- confirmed via the current diff (git diff HEAD -- hosts/vps/configuration.nix): no services.fail2ban block, no environment.etc."fail2ban/action.d/cscli.conf" remain anywhere in the file. The SYN-spoofing gap F1 described is specific to that jail's one-packet/zero-corroboration trigger; it no longer exists to be reactivated. Residual risk in the replacement (crowdsecurity/iptables-scan-multi_ports, spoofable: 3, 15 distinct ports/5s) is a materially different, narrower design and is not a re-statement of F1 -- see new finding F3 for what actually is wrong with the replacement (an unrelated hub-item-type bug, not a spoofing gap).

### F2 -- "No false-positive risk" claim in D1/comment is slightly overbroad; caveat is low-value but real

- **File:** `hosts/vps/configuration.nix:863-871` (new comment); plan D1 answer.
- **Severity:** INFO
- **Confidence:** CONFIRMED (mechanism) / not independently exploitable as a privilege escalation.
- **Axis:** hardening
- **Reachability:** requires a process on vps already able to write to `/dev/kmsg` (root or `CAP_SYSLOG`, gated by `kernel.dmesg_restrict`) to forge a `_TRANSPORT=kernel` entry containing `refused connection: ... SRC=<arbitrary-ip> ` and get an innocent IP banned by proxy. Any principal with that capability already has effective root on the box, so this isn't a meaningful escalation path — noted for completeness, not as something to act on.
- **Rule:** n/a
- **Finding:** D1's claim that "dropping the anchor introduces no false-positive risk" is true for coincidental substring collisions with unrelated kernel messages (the `"refused connection: "` LOG prefix is unique to this one iptables rule, confirmed at `firewall-iptables.nix:99-115`, and no other kernel subsystem plausibly emits that literal string), but doesn't fully cover a deliberate on-host forgery via `/dev/kmsg`. Low value to an attacker who'd already need root, so this doesn't change the overall risk assessment — logged here so the D1 claim isn't taken as unconditionally true if it's cited again later.
- **Fix risk:** n/a (informational only).


**MOOT 2026-09-03:** F2 was about the anchor-drop comment/D1 claim on the now-deleted fail2ban jail's failregex (hosts/vps/configuration.nix, the removed vps-closed-port-scan jail). That jail, its filter, and the comment F2 quoted no longer exist in the tree -- confirmed via the current diff. The replacement path (crowdsecurity/iptables-logs parser + iptables-scan-multi_ports scenario reading the same kernel LOG source) has its own, different false-positive surface (governed by CrowdSec's own parser/scenario code, not a hand-written anchored regex), which this pass reviewed separately and found no equivalent issue in -- nothing to carry forward from F2's specific claim.

### F3 -- hub.collections includes crowdsecurity/cdn-whitelist, which is actually a postoverflow, not a collection -- cscli collections install fails hard, and CrowdSec never starts

- File: hosts/vps/configuration.nix (services.crowdsec.hub.collections list, the crowdsecurity/cdn-whitelist entry added alongside crowdsecurity/linux/sshd/caddy/iptables).
- Severity: HIGH
- Confidence: CONFIRMED
- Axis: hardening / needed-used (both -- a broken activation script is also a "config that doesn't do what it claims")
- Reachability: n/a in the usual adversary sense -- this is a self-inflicted denial of the box's own detection stack, reachable simply by deploying this diff (nixos-rebuild switch) and starting/restarting crowdsec.service (including any reboot, or the unit's own RestartSec = 60 retry loop). The practical adversary who benefits is anyone probing/attacking vps's public surface (caddy 80/443, and indirectly the DNAT'd game ports and any future scenario) after this ships, since none of it gets detected or banned going forward -- not just the new port-scan detector, but the pre-existing crowdsecurity/sshd/crowdsecurity/caddy/crowdsecurity/linux collections too, which worked fine before this diff.
- Rule: new-rule candidate -- docs/hardening.md has no existing rule about validating hub-sourced (or any externally-namespaced) item-type references before they land in a hub.<category> list, since nothing in this repo's nix flake check/nixos-rebuild build/nixfmt/statix/deadnix ladder can catch a wrong-category name -- it's a plain string list, validated only at runtime against CrowdSec's own hub index.
- Finding: Fetched the live CrowdSec hub index (raw.githubusercontent.com/crowdsecurity/hub/master/.index.json) and confirmed crowdsecurity/cdn-whitelist exists only under postoverflows (postoverflows/s01-whitelist/crowdsecurity/cdn-whitelist.yaml, a Cloudflare-IP-range whitelist for overflow alerts) -- there is no collections/crowdsecurity/cdn-whitelist.yaml at all. The diff instead adds it to services.crowdsec.hub.collections, not hub.postOverflows (nixpkgs' crowdsec.nix exposes both as separate options; confirmed at nixos/modules/services/security/crowdsec.nix:359-364 and the corresponding cscli postoverflows install branch at :573-577 of the same file, pinned nixpkgs rev e4bae1bd10c9c57b2cf517953ab70060a828ee6f). The rendered crowdsec-setup script (nixpkgs crowdsec.nix:559-561) runs a single cscli collections install crowdsecurity/linux crowdsecurity/sshd crowdsecurity/caddy crowdsecurity/iptables crowdsecurity/cdn-whitelist command with no --ignore flag. Read cscli's install implementation directly at the pinned crowdsec version (cmd/crowdsec-cli/cliitem/cmdinstall.go, crowdsecurity/crowdsec tag v1.7.2 -- matches pkgs.by-name/cr/crowdsec/package.nix's pinned version = "1.7.2" exactly): for each name in the argument list it calls hub.GetItem("collections", name); on the first name that returns nil (i.e. crowdsecurity/cdn-whitelist, which only exists as type postoverflows) it does return errors.New(msg) immediately, before plan.Execute() is ever reached -- so none of the four valid collections queued ahead of it in the same call get installed either, not just the invalid one. crowdsec-setup is pkgs.writeShellScriptBin with set -euo pipefail as its first line (nixpkgs crowdsec.nix:610-612), and is wired as ExecStartPre on crowdsec.service (:834-838) -- a failing ExecStartPre means the unit never starts. This install line runs unconditionally on every service start (no "already installed" guard, unlike the CAPI-register/LAPI-machine-add/console-enroll steps in the same script, which do have idempotency checks) -- so this isn't a one-time bootstrap failure, it is permanent: crowdsec.service can never successfully start with this config, on any start attempt, until the entry is moved. nixos-rebuild build/nix flake check cannot catch this (confirmed: hub.collections is types.listOf types.str, no validation against the hub's content at Nix eval time), and the plan's own verification (verify-ladder, /simplify, a real nixos-rebuild build --flake .#vps) is described as having passed clean -- none of those steps execute ExecStartPre scripts, so this bug is invisible to everything short of an actual nixos-rebuild switch + service start/restart on real hardware.
- Fix risk: The fix itself is narrow (move "crowdsecurity/cdn-whitelist" from hub.collections to hub.postOverflows) and low-risk in isolation, but this needs a real deploy-and-observe verification step (systemctl status crowdsec.service actually active, not just nixos-rebuild build succeeding) before this plan can be considered fixed -- the class of bug here is exactly "looks wired correctly, never actually runs," which is what the whole plan started from. Also worth an explicit test that crowdsec-firewall-bouncer (which depends on the LAPI crowdsec.service normally provides) degrades sanely -- not verified in this pass -- when crowdsec.service is down at boot, since that determines whether the pre-existing ipset-based ban enforcement (feeding the DNAT'd game ports and caddy) also stops, or just stops getting new decisions.


**FIXED 2026-09-03:** Moved crowdsecurity/cdn-whitelist from hub.collections to hub.postOverflows (the correct option per the pinned nixpkgs services.crowdsec module, nixos/modules/services/security/crowdsec.nix:359-364/573-577). Re-verified against the actual rebuilt crowdsec-setup script, not just that it builds: now renders as two separate calls -- 'cscli collections install crowdsecurity/linux crowdsecurity/sshd crowdsecurity/caddy crowdsecurity/iptables' (all valid collection names) and a separate 'cscli postoverflows install crowdsecurity/cdn-whitelist' -- confirming the HIGH-severity ExecStartPre failure this finding identified no longer occurs.

### F4 -- Once F3 is fixed, crowdsecurity/cdn-whitelist is architecturally a no-op on this box

- File: hosts/vps/configuration.nix (same crowdsecurity/cdn-whitelist addition as F3).
- Severity: LOW
- Confidence: CONFIRMED (architecture) / PLAUSIBLE (that this remains true if the box's edge setup ever changes)
- Axis: needed-used
- Reachability: n/a -- not exploitable, just unneeded scope.
- Rule: n/a
- Finding: crowdsecurity/cdn-whitelist's content (fetched from the hub) whitelists evt.Overflow.Alert.Source.IP against Cloudflare's published IPv4/IPv6 ranges at the s01-whitelist postoverflow stage -- it exists to stop CrowdSec from banning a CDN's own edge IP when the CDN proxies traffic to the origin (i.e. when the origin's apparent "client IP" for every request is actually the CDN's, not the real visitor's). This repo's own audit trail states plainly that vps's Cloudflare usage is DNS-only, with no cloudflared/tunnel/proxying in front of caddy (docs/audits/2026-08-26/user-actions.md:294: "no cloudflared anywhere; superseded by the vps/Caddy edge"). caddy therefore sees real client IPs directly, so this postoverflow has essentially nothing to match in this box's actual traffic pattern (an attacker would need to genuinely source packets from within Cloudflare's own IP space to benefit, which they don't control) -- harmless once correctly categorized, but adds hub-fetch surface and config for no operational benefit given the current architecture. Not worth reverting on its own, but worth noting it isn't earning its place the way D3's writeup implies ("reduces false-positive noise from real CDN ranges" only applies to a CDN-fronted origin).
- Fix risk: n/a -- informational; removing it entirely would be equally safe as keeping it (once correctly typed) given the current edge architecture.


**FIXED 2026-09-03:** User's call, presented both options from this finding: dropped crowdsecurity/cdn-whitelist entirely rather than keeping it as a harmless no-op. hub.postOverflows removed from the config; re-verified against the rebuilt crowdsec-setup script that only one cscli collections install line remains (crowdsecurity/linux sshd caddy iptables), no postoverflows call at all. If vps's edge architecture ever adds real CDN proxying in front of caddy, this is a one-line re-add (to hub.postOverflows, not hub.collections -- see F3).

### F5 -- Rate-limiting the refused-connection LOG line (10/sec, burst 30) also throttles what a human sees live during an actual scan, not just what floods journald

- File: hosts/vps/configuration.nix:405-426 (networking.firewall.extraCommands, the new -m limit --limit 10/sec --limit-burst 30 LOG rule).
- Severity: LOW
- Confidence: CONFIRMED (mechanism) -- -m limit drops non-matching packets from hitting the LOG target at all past the token bucket, this is standard iptables limit-match behavior, not journald-side dropping.
- Axis: hardening (observability, per docs/hardening.md rule 11's spirit -- a guard/detector's visibility to a human operator, not just its automated action)
- Reachability: n/a as an attacker path; this affects an operator's ability to see what's happening during a live incident, not detection correctness. CrowdSec's own iptables-scan-multi_ports still fires reliably even under this cap (its threshold is 15 distinct ports/5s = 3/s average, well inside the 10/s+30-burst budget), so automated banning is not affected -- confirmed against the scenario's own hub metadata (capacity: 15, leakspeed: 5s, fetched live from crowdsecurity/hub).
- Rule: n/a -- not a hardening-doc violation, just a side effect worth naming since it wasn't discussed in D4's own reasoning (D4 only reasoned about journald's rate limit and the detector's own needs, not a human reading journalctl -f live).
- Finding: During a scan aggressive enough to exceed roughly 10 refused-SYN/sec sustained (e.g. a fast full-port sweep from one source), the majority of individual probed ports will never produce a LOG line at all -- the -m limit match itself silently drops them before the LOG target runs, not journald. CrowdSec's scenario still bans correctly (it only needs 15 distinct ports within 5s, comfortably inside the burst), but an operator tailing the kernel log live during that same incident would see a small, non-representative sample of the actual scan rather than the full picture -- a reasonable and probably correct trade-off (that's the whole point of rate-limiting), but worth recording explicitly since D4's stated rationale didn't mention this cost, only the journald-overrun benefit.
- Fix risk: n/a -- informational; if this ever needs revisiting, the options are the usual ones (bump the limit, or log to a separate always-on channel for forensics), each with its own journald-load trade-off already covered by D4.


**FIXED 2026-09-03:** User asked for the trade-off to be analysed rather than picked from the two options. Analysis (see D4 addendum): the original 10/sec left ~33x headroom under journald's real ~333/sec ceiling (default unmodified, confirmed) while CrowdSec's own detection floor is only ~3/sec -- the cap was trading away live visibility for margin nobody needed. Raised to 50/sec, burst 100: ~6.5x headroom retained, detection floor still comfortably clear, meaningfully better live-tail visibility during an incident. Re-verified against the rebuilt firewall-start script.

### F6 -- CAPI sharing: true's actual payload contents are not verifiable from the pinned nixpkgs module alone

- File: hosts/vps/configuration.nix (services.crowdsec.settings.capi.credentialsFile); plan D3's characterization ("mainstream and low-cost in data shared for unmodified hub scenarios").
- Severity: INFO
- Confidence: CONFIRMED that sharing, pull.community, pull.blocklists all default to true once capi.credentialsFile is set and general.api.server.enable = true (read directly at nixos/modules/services/security/crowdsec.nix:661-668, pinned nixpkgs rev) / PLAUSIBLE for what "sharing" actually transmits.
- Axis: hardening (data exposure to a third party)
- Reachability: n/a -- not an attacker-reachable path; this is about what vps discloses to CrowdSec's own central infrastructure once CAPI is registered, not about a hole an outside adversary can use.
- Rule: n/a
- Finding: The nixpkgs module only proves the three flags default true -- it says nothing about the actual signal payload's contents (which fields of an alert get sent: source IP, scenario name, and GeoIP enrichment are near-certain per CrowdSec's own public docs, but exact scope, e.g. whether context-style enrichment or caddy request-path/user-agent fields could ever ride along for a caddy-sourced alert, lives in CrowdSec's own Go application logic (pkg/apiserver), not in anything the pinned nixpkgs tree pins or exposes). This repo currently sets no localConfig.contexts, so no extra enrichment fields are configured to be attached -- but that's a fact about this repo's config, not a guarantee about what CrowdSec's sharing code path independently decides to include for a "signal." D3's characterization is plausible and matches CrowdSec's own public positioning, but should be treated as PLAUSIBLE, not CONFIRMED, if it's ever cited as a basis for a data-sensitivity decision later.
- Fix risk: n/a -- informational only; if this matters for a future decision, verify against crowdsecurity/crowdsec's pkg/apiserver push-signal code directly, not against nixpkgs.


**FIXED 2026-09-03:** User asked to verify further rather than accept on CrowdSec's docs alone, given this is data leaving the box to a third party. Verified directly against the actual pinned v1.8.0 Go source (not v1.7.2 -- see G5), not docs: alertToSignal() (pkg/apiserver/apic.go:148) builds every CAPI signal from Message (a synthesized summary string via a fixed template, not raw content), Scenario/ScenarioHash/ScenarioVersion, Source (ASN/country/GeoIP/IP), timestamps, MachineID, ScenarioTrust, and Decisions -- matching CrowdSec's public claims exactly. The one vector for raw content, signal.Context (populated from alert.Meta, where a raw HTTP path/user-agent/etc could live), is only attached if ShareContext is true -- confirmed in pkg/csconfig/console.go that this defaults false on every code path, and this repo sets no localConfig.contexts/console config, so it stays false. Payload confirmed genuinely minimal by default from source, not assumed from marketing.

## Checked and clean

Reviewed the full diff (`git diff HEAD -- hosts/vps/configuration.nix`, the
only substantive change: dropping the leading `^` from the
`vps-closed-port-scan` jail's `failregex`). Confirmed the stated root cause
against the pinned source rather than the plan's own account: pulled
nixpkgs `e4bae1bd10c9c57b2cf517953ab70060a828ee6f` (this flake's locked
rev) and `fail2ban` 1.1.0 from `github:fail2ban/fail2ban/1.1.0` (hash
matches the pinned `pkgs.by-name/fa/fail2ban/package.nix` exactly), and
read `FilterSystemd.formatJournalEntry()` directly
(`fail2ban/server/filtersystemd.py:211-247`) — it does prepend
`"<hostname> kernel: [<monotonic-ts>] "` ahead of `MESSAGE` for any
`_TRANSPORT=kernel`/`SYSLOG_IDENTIFIER=kernel` entry, so the anchored
regex could never have matched; the fix is correctly targeted at the
actual bug. Also read `firewall-iptables.nix:99-115` in the same nixpkgs
checkout to confirm the `"refused connection: "` LOG prefix only ever
fires on `-p tcp --syn` packets refused by `nixos-fw`, is unique to this
one rule, and that DNAT'd/forwarded traffic (game ports) never reaches it
(FORWARD chain, not INPUT) — so journalmatch scoping and prefix
specificity are as tight as the plan claims for the *coincidental*
false-positive question (checked under axis 1 of the task, findings F2
covers the one caveat found). No other change in the diff hunk beyond the
anchor removal — no jail settings, no ignoreregex, no action changed.
Did not touch `secrets/*` or decrypt anything; did not run
`nixos-rebuild` or contact the live `vps` host. Confirmed via `git diff
HEAD --stat` that this worktree's only changes are
`hosts/vps/configuration.nix` (the reviewed diff) and this plan file
itself — nothing else in scope.

_security finished 2026-09-03T21:50:53Z -- see Findings above._

## Re-review addendum (this pass, 2026-09-03)

Re-reviewed the full current diff (git diff HEAD -- hosts/vps/configuration.nix hosts/vps/README.md), not just the plan's own account, against the pinned nixpkgs rev (e4bae1bd10c9c57b2cf517953ab70060a828ee6f, confirmed via flake.lock and nix flake prefetch to match exactly) and the pinned crowdsec version (1.7.2, from pkgs.by-name/cr/crowdsec/package.nix) and its own upstream Go source at tag v1.7.2, plus the live CrowdSec hub index and the specific hub items touched (crowdsecurity/iptables, crowdsecurity/iptables-logs, crowdsecurity/iptables-scan-multi_ports, crowdsecurity/cdn-whitelist).

Confirmed clean: (1) F1's SYN-spoofing gap and F-P2-04's actionunban-deletes-everything bug both fully go away with the fail2ban block and cscli.conf action deleted outright -- grepped the current file for cscli/decisions/actionban/actionunban and found only the unrelated, pre-existing crowdsec-allowlist-tailnet unit's cscli allowlists calls, nothing resembling an unscoped decisions delete. (2) The replacement detector (crowdsecurity/iptables collection: iptables-logs parser + iptables-scan-multi_ports scenario) is correctly wired end-to-end -- read the parser and scenario source directly from the hub: the parser's filter (evt.Parsed.program == 'kernel' and message contains 'IN=', not ACCEPT) and the scenario's threshold (capacity 15, distinct dst_port, leakspeed 5s, groupby source_ip, labels.spoofable: 3) both match the plan's claims exactly. Independently verified the labels.type = "syslog" acquisition choice is correct by reading CrowdSec's own journalctl acquisition source (pkg/acquisition/modules/journalctl/journalctl.go at v1.7.2): it runs plain journalctl --follow -n 0 <filters> with no -o flag, so it inherits journalctl's default short-format output (timestamp/hostname/SYSLOG_IDENTIFIER-derived program/message), which the syslog-logs s00-raw parser's SYSLOGLINE grok correctly extracts program="kernel" from for _TRANSPORT=kernel entries -- same mechanism as the working sshd/caddy acquisitions, not a new failure mode. (3) The -I nixos-fw-log-refuse 1 fix (G4) is correct: read nixpkgs' firewall-iptables.nix startScript directly and confirmed the chain's own rules (pkttype-non-unicast jump, then the unconditional terminal jump to nixos-fw-refuse) are both already -A-appended by the time extraCommands splices in, and that -I ... 1 places the new LOG rule exactly where the module's own logRefusedConnections=true branch would have put it if left enabled -- LOG doesn't terminate iptables chain traversal, so this is provably inert with respect to actual accept/refuse decisions, only affects what gets logged. (4) Diffed the pre-existing game-port hashlimit rules (minecraft 15/minute burst 10, geyser 1000/second burst 500, factorio 2000/second burst 1000, http-new 120/minute burst 60, plus the IPv6 http-new6 counterpart) explicitly against the current extraCommands block -- none of those lines appear with a +/- prefix in the diff at all, confirming byte-for-byte unchanged, matching the user's hard constraint from D4. (5) Confirmed the CAPI defaults claim (pull.blocklists/pull.community/sharing all true) directly against nixpkgs crowdsec.nix:661-668 -- accurate as stated, though the exact contents of a shared "signal" payload are outside what nixpkgs can confirm (see new finding F6).

Found new: F3 (HIGH) -- crowdsecurity/cdn-whitelist is a hub postoverflow, not a collection, and listing it under services.crowdsec.hub.collections makes cscli collections install fail hard on every crowdsec.service start (confirmed against the pinned cscli's actual install-loop source), which prevents the entire CrowdSec agent -- not just the new port-scan detector, but the previously-working sshd/caddy/linux collections too -- from ever starting. This is a build-invisible regression (nixos-rebuild build/nix flake check cannot see it) and should block this plan moving to done until fixed and re-verified with an actual service start, not just a build. F4/F5/F6 are lower-severity/informational notes (an inert postoverflow given this box's DNS-only Cloudflare usage; a live-incident-visibility trade-off from D4's rate limit that wasn't discussed in D4's own reasoning; and an unverifiable-from-nixpkgs caveat on exactly what CAPI "sharing" transmits). F1 and F2 resolved MOOT via plan-resolve -- both were about the now-fully-deleted fail2ban jail and its comment, and don't carry forward to the replacement design.

Did not decrypt or read any secrets/* content, did not run nixos-rebuild or contact the live vps host, and made no configuration edits -- this file (the plan) is the only file touched by this pass.

_security (re-review) finished 2026-09-03 -- see F3-F6 above; F1/F2 resolved MOOT._

_security finished 2026-09-04T00:07:33Z -- see Findings above._
