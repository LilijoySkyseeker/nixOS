# Audit state / resume point

Self-contained pick-up point for the **2026-08-26 fleet-wide security
audit + needed/used review**. Written to be read cold: everything a new
session needs is here or linked from here.

**Last updated: 2026-09-01, end of the thirteenth session.**

> ## START HERE — state as of the thirteenth session
>
> **Branch:** `worktree-worktree-security-audit-plan`, worktree
> `.claude/worktrees/worktree-security-audit-plan`. **Merged to master via
> PR #39 as of the twelfth session** (`6a68cb3`) — everything through the
> eleventh session (waves 1-2, credential rotation, the two LOW findings,
> the `.zfs`-traversal fix, the disko unification) is on `master` now.
> This branch is currently **one commit ahead of master**: `d470a61`,
> explicit WIP `push-deploy-vps` sandboxing — **not build-broken, but not
> VM-verified and not deployed anywhere.** All five `nixosConfigurations`
> build.
>
> **NEXT UP: finish item 1, `push-deploy-vps` sandboxing (F-P7-06 / wave 2
> item 2.6).** Read "What happened in the twelfth session" below in full
> before touching anything — it has the exact mechanism (grounded in
> `nixos-rebuild-ng`'s own source), the six real bugs the VM test already
> caught and fixed, and the specific thing it's currently blocked on (a
> from-scratch `glibc`/`stdenv` rebuild inside the sandboxed test VM) plus
> a concrete next step to try. **Do not deploy the current hardening to
> vps** — it is unverified beyond a local build, which is exactly the
> risk this item was deferred to avoid. Item 4 (`userns-remap`) is the
> other agent-doable item, also deferred pending its own VM test;
> everything else needs either a user decision or a live host.
>
> **`TODO.md` no longer exists.** Master retired it for the plan-file
> system (`docs/plans/{todo,in-progress,done,rejected}/`) — see the `plan`
> and `workflow` skills. Plans are cited by **bare filename**, and
> filenames are **date-first** (`2026-08-28-<slug>.md`). Older text in
> this file still says `TODO.md`; read that as "the plan files".
>
> **Credential rotation is done.** **10 done, 2 not required** — see
> [`rotation-runbook.md`](rotation-runbook.md) for the table. Item 9
> (`homelab_zrepl_key`), the last one, closed 2026-09-01 once the user had
> physical access to both laptops. Two extra items were added and
> completed during the audit: **11** (`tailscale_authkey_isoimage`,
> revoked) and **12** (factorio credentials, proven disclosed and
> rotated). **Fully closed 2026-09-01** — the stale `/tmp/homelab_zrepl_key`
> on torrent has been deleted too. Nothing outstanding from rotation.
>
> **Deployed:** all four hosts — homelab, vps, torrent, and thinkpad — are
> switched to this branch as of the ninth session (including the restic
> `312h` threshold, `c6116ca`), zero failed units, WireGuard tunnel and
> zrepl replication both healthy on rotated keys. **L-01/L-02 (eighth
> session) and D1's `snapdir=disabled` fix (tenth session) are the only
> build/VM-verified-but-undeployed changes left** — none need a host
> switch to be true statements, only to take effect.
>
> **All scheduled deploys remain OFF fleet-wide** (`scheduleEnable =
> false`). Manual deploys are the only path anything takes. That is not
> merely a state note — it is why a deploy killed the weekly backup this
> session (see below).
>
> ### The three things most worth knowing before you touch anything
>
> 1. **A clean activation log is not evidence a rotated secret reached its
>    consumer.** Hit three times: the WireGuard interface (`61f55cb`), the
>    factorio container (`3dd1aa4`), and earlier the Discord webhook. Each
>    logged `modifying secrets: …` with zero failed units while the
>    service kept using the old value. The fix is `restartUnits`; the
>    *lesson* is that verification means exercising the credential.
>    Item 10 (restic) was the one case where no restart was needed — and
>    that was checked, not assumed.
> 2. ~~**The offsite backup has not succeeded since 2026-08-21**… **Expect
>    the staleness alarm to page ~2026-09-03**.~~ **Resolved: the user ran
>    a manual backup that completed cleanly** (started 22:50 on
>    2026-08-29, off-schedule, confirming manual; finished 9h56m later,
>    `no errors were found`, exit 0). `last-success` is now 2026-08-30
>    08:46 — the alarm will not fire at 312h from that mark until
>    ~2026-09-12, past the next scheduled run. D3's revisit condition in
>    `2026-08-28-a-manual-deploy-kills-the-in-flight-weekly-restic-.md`
>    was met.
> 3. ~~**The factorio credentials were proven readable by any local uid**
>    through `/nix/state/.zfs`… The *mechanism* is not fixed…~~
>    **Mechanism fixed 2026-09-01, servers only, not yet deployed.**
>    `snapdir=disabled` on `zroot/local/state` closes it on homelab; PCs
>    (`zroot/local/home` on torrent/thinkpad) deliberately excluded, see
>    `2026-09-01-extend-the-zfs-snapshot-traversal-fix-to-the-pc-hosts-without.md`.
>    Full detail: `2026-08-28-nix-state-zfs-snapshot-dir-is-world-traversable-ex.md`.
>
> **The user works rotation items interactively.** Do not batch them. Each
> is "user does the provider + sops half, agent does the repo + deploy +
> verify half", and the verification is the point — it has now caught five
> real problems.

---

## READ THIS FIRST — two clocks are running

> **RESOLVED 2026-08-27 — both clocks are stopped.** homelab was
> deployed on the user's explicit instruction (generation **346**), and
> `switch-to-configuration` reported `stopping the following units:
> auto-switch.timer, flake-update-test.timer, push-deploy-vps.timer`.
> Verified live afterwards: `systemctl list-timers auto-switch
> flake-update-test push-deploy-vps --all` returns **0 timers listed**.
>
> **Neither deadline below can now fire.** They are left in place as the
> record of why the work happened, not as live warnings. The three
> *services* remain (`linked`), so manual deploys still work — only the
> clocks are gone. Re-arming is `scheduleEnable = true`, and should not
> happen before the new pipeline exists (`TODO.md`).
>
> The rest of the fleet — vps, torrent, thinkpad — is **still on the old
> configuration with its timers armed**, since only homelab was
> deployed. Their `pull-deploy`/push timers stop when they are next
> deployed.


The audit branch is **deployed on homelab and nowhere else**, and
homelab's `/etc/nixos` was deliberately left on `master`. Two timers will
act on that without anyone doing anything:

| When | What fires | Consequence |
|---|---|---|
| **Wed 2026-09-02 03:00** | `flake-update-test` | `git reset --hard origin/master` in `/etc/nixos`, `nix flake update`, and **if it builds, merges and pushes to `master`** — unattended, on a build-success gate alone. This is **D11, which is deliberately undecided**. |
| **Thu 2026-09-03 03:00** | `auto-switch` | Builds `master` and switches homelab to it — **reverting this branch's deploy entirely**. |

**Both of these are live *because* of this session's work**, which is the
single most important thing to understand before touching anything:

- `auto-switch` and `push-deploy-vps` were **both failing as of
  2026-08-27 03:00** (see "The deploy outage" below — the fourth session
  corrected the dates and duration originally recorded here). While
  broken, they could not have reverted anything.
- Commit `929efa3` fixed them, and homelab now runs it. **The revert
  mechanism is functional again.**

So: if the branch should survive past Thu, it must be **merged to
master** before then, or the timers stopped. That is a user decision and
has not been made. If the deploy was only ever meant as a test, the
revert is a free rollback and nothing needs doing.

Both are tracked as checkboxes in
[`user-actions.md`](user-actions.md) **§0**, which is where the user
works through them — keep the two in sync rather than only updating this
file.

---

## Where things are

- **Branch:** `worktree-worktree-security-audit-plan`, pushed, clean.
  ~~42 commits ahead of master~~ **merged to master via PR #39, twelfth
  session** (`6a68cb3`) — now just **one commit ahead** (`d470a61`,
  WIP `push-deploy-vps` sandboxing, not yet VM-verified). Live worktree
  at `.claude/worktrees/worktree-security-audit-plan` — enter that
  rather than making a new one.
- **All audit output:** `docs/audits/2026-08-26/`
- **Plan of record:** ~~the 2026-08-26 entry at the top of `TODO.md`~~ —
  now `docs/plans/in-progress/2026-08-26-do-a-full-security-audit-hardening-pass-on-homelab.md`
  (TODO.md retired 2026-08-28)
- **homelab is on gen 358** as of the sixth session (2026-08-28), vps
  redeployed the same day; the lines below record earlier sessions' state
  and are kept for the sequence. **Updated further in the ninth session
  (2026-09-01): torrent and thinkpad are both now switched to this branch
  too** — see "What happened in the ninth session". `torrent`'s "never
  switched" claim two lines below turned out to already be stale before
  this session even started (torrent was independently switched to
  something very close to this branch's HEAD on 2026-08-27, outside the
  audit's own session log) — corrected there rather than silently.
- ~~**homelab is on gen 350 and vps on gen 7** as of the fifth session;~~
  the line below records the fourth session's state and is kept for the
  sequence. homelab and vps are deployed (2026-08-27). homelab was switched
  twice — the audit's first switch, then again for the fourth session's
  work (**generation 346**). vps followed (**generation 4**).
  `torrent` and `thinkpad` remain **build-verified only, never
  switched**, and still carry their own armed `pull-deploy` timers.

| File | What |
|---|---|
| [`00-threat-model.md`](00-threat-model.md) | Adversaries (§5), trust boundaries (§4), **severity rubric (§6)**, recurring failure modes (§7). Read §6 before rating anything. Linked from the stable path `docs/threat-model.md`. |
| [`findings.md`](findings.md) | **Start here.** CRITICAL/HIGH/MEDIUM by root cause. §4 = the eleven systemic rules. §6 = what is verified clean. |
| [`findings-tail.md`](findings-tail.md) | LOW/INFO + the needed/used rollup. |
| `P0..P8-*.md` | The nine part reports, ~13,700 lines. |
| [`remediation.md`](remediation.md) | The wave plan **and the per-item notes**, which carry the reasoning and verification for everything done. |
| [`user-actions.md`](user-actions.md) | **Everything only the user can do**, as a live checklist, incl. decisions D1–D16. Its new **§0 is time-critical** — the two timers below. |
| [`live-verification.md`](live-verification.md) | Live checks with commands and results. |
| [`D11-analysis.md`](D11-analysis.md) | **The benefits/risk analysis for D11** (auto-merge), written in the fourth session. Time-critical — D11 fires Wed 2026-09-02. |

Documentation harvested out of the audit into standing docs:
`docs/hardening.md` (eleven standing rules — the eleventh added in the
fourth session), `docs/threat-model.md`,
`docs/accepted-risks.md`.

## Phase status

| Phase | State |
|---|---|
| 0 — threat model | **done** |
| 1 — eight part audits | **done** — 158 findings |
| 2 — consolidation | **done** |
| 3 — remediation | **waves 1 and 2 complete.** Wave 3 is user-only by definition |
| 4 — docs harvest | **done** (`171d7e5`) |

Headline counts: **3 CRITICAL, 31 HIGH, 38 MEDIUM, 53 LOW, 35 INFO**.

---

## What happened in the third session (2026-08-27)

Nine commits. Six of the fourteen decisions were answered by the user.

| Commit | What |
|---|---|
| `171d7e5` | **Phase 4.** Ten standing rules into `docs/hardening.md`; `docs/threat-model.md` + `docs/accepted-risks.md` created; corrected `remote-access.md`, which claimed the `vps-deploy` forced-command allowlist was a security boundary when root arrives anyway via the polkit grant |
| `41efcfe` | Recorded the user's answers to D13/D9 |
| `59348bd` | **D3, D9, D14.** GitHub ruleset created; avahi removed; minecraft version now follows the mod set |
| `3fdec19` | **2.1** — `myDockerPublishGuard`, filtering published game ports in DOCKER-USER |
| `7a047b7` | **factorio-new removed entirely**, domains simplified to `factorio.<domain>` |
| `012d5bb` | **2.9** — KDE Connect → `tailscale0`, Steam remote play dropped. **Resolved D10** |
| `7854cc1` | Recorded the `/srv/factorio/new` deletion on homelab |
| `929efa3` | **The deploy outage fix** — see below |
| `5bc36ed` | **Egress bug in 2.1's guard** — see below |

### Decisions answered

- **D3 — done.** `master` had **no branch protection and no rulesets at
  all**. A ruleset now blocks force-pushes and deletions, enforcement
  active, **empty bypass list** (`current_user_can_bypass: never`). No
  deploy keys; sole collaborator. Signed commits deliberately **not**
  enabled — that is D2.
- **D9 — done, and smaller than scoped.** Two of three port groups were
  *removed* rather than narrowed, so the per-host LAN-interface option
  the plan assumed was never needed. avahi/mDNS gone entirely (option c
  — static printer address instead); Steam remote play dropped; KDE
  Connect scoped to `tailscale0` via `mkForce` (its nixpkgs module opens
  1714-1764 unconditionally with no toggle).
- **D10 — resolved.** The unattributable UDP 10400/10401 were **Steam
  Remote Play's**, opened by `programs.steam.remotePlay.openFirewall`
  alongside TCP 27036/27037. Found by evaluating
  `options.networking.firewall.allowedUDPPorts.definitionsWithLocations`,
  which names the defining nixpkgs file — grep could never have found it,
  as the numbers appear nowhere as literals in this repo. **Lesson:
  attribute a port to the option that opens it, not to the port number.**
- **D13 — answered "never from the LAN".** Unblocked 2.1.
- **D14 — answered "keep auto-updating", written up as an accepted
  risk** (`accepted-risks.md` AR-7). `VERSION = "LATEST"` replaced by
  `VERSION_FROM_MODRINTH_PROJECTS`, so the game version now *follows* the
  mod set instead of leading it, and fails closed. The version-type
  variable moved off the legacy `MODRINTH_ALLOWED_VERSION_TYPE` name —
  both work for downloading mods, but **the version resolver reads only
  the new name**, so the legacy spelling would have had mods resolving at
  `alpha` while the version resolved at `release`.
- **D11 — deliberately NOT answered.** The user asked for a
  re-evaluation and replan with a benefits/risk analysis instead; that is
  now `docs/plans/todo/2026-08-27-re-evaluate-and-replan-flake-update-test-s-executi.md`.
  ~~**It fires Wed Sep 2.**~~ — **it does not fire.** That clock assumed
  the schedules were armed; `scheduleEnable = false` fleet-wide means
  `flake-update-test` has no timer. Corrected 2026-08-28; nothing is on a
  clock any more except the backup staleness page (~2026-09-03), which is
  expected and covered above.

### The deploy outage (`929efa3`) — the most important find

> **Corrected in the fourth session.** This section originally said both
> units had been failing "since 2026-08-25" and that "nothing noticed for
> two days". homelab's journal says otherwise on both counts: the last
> good runs were 2026-08-25T13:18 (they skipped cleanly), the failures
> were the next *scheduled* runs at 2026-08-27T03:00 and 03:15 — one
> cycle each, ~10 overnight hours — and both **did** enter `systemctl
> --failed`, which `myHealthAlerts` checks every 15 minutes and reported.
> The lesson below still holds; the timeline and the "nothing watches
> this" claim do not. Detail in `remediation.md`, "Note on 1.9's skipped
> half".

**Both halves of the fleet's deploy path failed on their first scheduled
run after the change landed.** Found by accident while clearing an
unrelated failed unit.

```
auto-switch.service       failed
push-deploy-vps.service   failed
error: could not lock config file /root/.config/git/config: Read-only file system
```

`require_clean_master()` opened with `git config --global --add
safe.directory "$(pwd)"`. Root's `~/.config/git/config` is a
**home-manager symlink into the nix store**; git writes its lockfile
beside the target; the store is read-only. The guard died on its first
line, before any of its checks.

**Fix**: the guards now define `git() { command git -c
safe.directory="$PWD" "$@"; }` once, and write nothing. `-c` is
"command" scope, which git-config(1) SCOPES counts as **protected**
configuration — and `safe.directory` is only honoured in protected
scopes, so this genuinely applies where a repo-local value would be
silently ignored. Verified against git's own docs.

**Two things to carry forward.** The underlying mistake was mutating a
dotfile another part of the system owns declaratively. And the failure
sat in `systemctl --failed` the whole time — which, on the fourth
session's re-reading, means the alerting worked and **the gap was
neither detection nor notification but response time** on an overnight
failure. The genuinely unwatched case is a deploy that *skips*, since
every guard exits 0; that is `F-P7-09`'s remaining half and is now
closed.

Covered by `tests/deploy-guards.nix` (6 subtests), two of which assert
the *premise* — that the config really is read-only and git really does
refuse the repo — so the test cannot quietly stop testing anything.

### The egress bug (`5bc36ed`) — found only by deploying

2.1's guard shipped matching on `--dport` alone. That also matches
traffic a container **sends**, for any protocol using the same port at
both ends. Factorio is one: it heartbeats to the public matching servers
with `SPT=34197 DPT=34197`. So the guard was silently dropping the
server's own registration.

```
IN=docker0 OUT=enp3s0 SRC=172.17.0.3 DST=139.162.87.206 SPT=34197 DPT=34197
```

**The failure shape is the lesson**: quiet and asymmetric. Inbound play
keeps working perfectly while the server drops off the public server
list, and the symptom looks like DNS or port-forwarding several layers
from the cause. **The VM tests all passed on the broken version** — it
was caught by reading the guard's own packet counters after deploying
(the DROP rule climbing while the wg0 RETURN rule sat at zero).

Fixed by pinning every rule to the bridge with `-o` (new
`bridgeInterface` option, default `docker0`). Direction is unambiguous
from interfaces:

```
inbound to a container    IN=wg0|tailscale0   OUT=docker0
outbound from container   IN=docker0          OUT=enp3s0
```

**Generalises**: a port-matching rule in a `FORWARD` chain is
direction-agnostic unless you say otherwise, and same-port-both-ends is
common in game and P2P protocols. Match the interface, not just the port.

---

## What happened in the fourth session (2026-08-27)

One commit, closing **`F-P7-09`'s skipped-deploy half** — the only
agent-doable item that was both unblocked and not gated on a live
measurement. Full reasoning in `remediation.md`, "Note on 1.9's skipped
half".

- **Skips are now visible.** The finding proposed a bespoke per-host
  "last successful deploy" marker. Rejected in favour of the marker that
  already exists: `/nix/var/nix/profiles/system`. Its mtime is the last
  *actual* activation by any route — scheduled, push-deployed or manual —
  so a hand-deployed host does not look stale while being current, which
  a unit-scoped marker would have got wrong. All four hosts now watch it
  via the existing `staleMarkerFiles`; **no new mechanism was added.**
- **`OnSuccess=` firing on a skip is fixed, and it was real.** homelab's
  journal has the min-interval guard deferring a switch at
  `2026-08-25T13:18:15` and systemd starting the vps closure build in the
  same second. Replaced with `myAutoUpdate.onDeployUnits`, gated on a
  flag written only after `nixos-rebuild switch` returns, held in a
  per-unit `RuntimeDirectory` so it cannot go stale.
- **The outage account was wrong and is corrected** in place above.
- New `tests/deploy-chain.nix` (6 subtests), driving the **rendered**
  `ExecStartPost` out of the built system. Verified to fail when the gate
  is reverted, per "a passing VM test is not proof".
- New eval-time assertion: `staleMarkerFiles` keys its alert state on
  each path's *basename*, so two same-named markers would silently share
  one alert slot. Verified by adding a collision and watching it refuse.

**Not deployed.** All four hosts build; `deploy-chain`, `deploy-guards`
and `nix flake check --no-build` pass. Nothing was switched.

**Two live findings worth carrying forward** (both from reading the
journal, neither actioned):

- `stat -L` on the profile symlink returns **1** (store paths all have
  mtime 1), so a dereferencing stat in the staleness check would report
  every host permanently stale. The code is correct and now says so.
- `2026-08-25T13:18:17`: `vps-deploy: rejected command: stat -c %Y
  /nix/var/nix/profiles/system` — the forced-command allowlist rejected
  the `stat` that `check_min_switch_interval` needs. Resolved by 13:22
  the same day, but it is a second, independent way that path has
  already broken.

## Second homelab deploy — generation 346 (2026-08-27)

The fourth session's work, deployed on explicit instruction. Verified on
real hardware afterwards:

| Change | Verified |
|---|---|
| Scheduled deploys off | `list-timers auto-switch flake-update-test push-deploy-vps --all` → **0 timers listed**; switch log shows all three being *stopped* |
| Manual paths intact | `auto-switch`, `auto-switch-now`, `push-deploy-vps` all still present (`linked`) |
| Container memory ceiling | `memory.max = 7516192768` (exactly 7 GiB) on **both**, was `max` |
| Container pid ceiling | `pids.max` = **1024** minecraft / **512** factorio, was 19038 |
| minecraft | `Resolved Minecraft version 26.2 from Modrinth projects`, `Done (1.382s)!`, Geyser up, healthy |
| factorio | `Matching server game 1293844 has been created` + `connection resumed` — public listing survived the restart under the new cgroup caps |
| health-check | runs clean, exit 0, no stderr; alert-state dir empty, so the new profile-staleness marker evaluated and found the profile fresh |
| Tailscale | still `offers exit node`; `net.ipv4.conf.all.forwarding = 1` |
| Reboot | not needed — kernel unchanged |
| Overall | **zero failed units** |

Two benign log lines seen and deliberately not chased: factorio's `Got
EOF on stdin` (normal for a container with no TTY) and Carpet's
`ctrlQCraftingFix is not a valid rule`, a pre-existing mod-config warning
unrelated to this change.

**The other three hosts were not deployed** and still have their own
timers armed. Nothing on them can auto-merge or revert homelab, so it is
not urgent — but the fleet is in a mixed state.

## vps deploy — generation 4 (2026-08-27)

**vps is no longer build-only.** Deployed on explicit instruction, from
this worktree with `nixos-rebuild switch --flake .#vps --target-host
root@vps`. Verified after:

| Check | Result |
|---|---|
| Failed units | **zero** |
| `crowdsec-ipset-precreate` (new unit) | active, exit **0** |
| Both ipsets | exist, `hash:net`, `hashsize 1024 maxelem 131072 timeout 300` — unchanged params, refs 1 and 2 |
| IPv4 `vps-ratelimit` | crowdsec match + 25565/19132/34197 limits; **34198 rules gone** |
| IPv6 `vps-ratelimit` | **new chain present** — `crowdsec6-blacklists-0` match + `http-new6` |
| DNAT | 34197 → `10.100.0.2` kept, **34198 removed** |
| `vps_caddy_env` | activation logged `removing secret: vps_caddy_env`; 6 secrets remain |
| CrowdSec | `crowdsec` + bouncer active; allowlist unit exit 0; `trusted-tailnet` intact |
| Public site, IPv4 | `https://jellyfin.skyseekerlabs.net` → **302** via `137.184.45.18` |
| Public site, IPv6 | → **302** via `2604:a880:…` — the new rate-limit path does not break real traffic |
| Tailscale / Caddy | both up |

**Two false alarms worth remembering**, both the same shape — a command
that looks like it proves absence when it proves nothing:

- `ipset list` returned **empty**. `ipset` is not on root's interactive
  `PATH` on vps; via its store path both sets were there all along. Same
  family as the `ip6tables`-looks-empty trap already in this file.
- `curl https://skyseekerlabs.net` failed with a TLS internal error on
  **both** families. That is the **apex**, which has no vhost — Caddy
  serves only `jellyfin.skyseekerlabs.net`. Pre-existing and unrelated;
  the identical failure on v4 and v6 is what ruled out the new v6 chain,
  since that could only have affected one family.

**Prerequisite that nearly went wrong:** `push-deploy-vps` must **not**
be used to deploy this branch. homelab's `/etc/nixos` is on `master`,
**diverged** (1 local commit, 31 behind), so its `git merge --ff-only`
would fail — and if it succeeded it would push *master's* vps config,
undoing the audit changes. See the `/etc/nixos` entry in `TODO.md`.

## What is verified live on homelab (2026-08-27)

All checked after the deploy, on real hardware:

| Change | Verified |
|---|---|
| Publish guard — LAN | **blocked** (timeout = DROP) |
| Publish guard — tailnet | reachable |
| Publish guard — public via vps/wg0 | reachable |
| Factorio public listing | `Matching server game 1293294 has been created` |
| Tailscale (`5682087`, the silent-failure one) | exit node offered, `192.168.1.0/24` advertised, **both forwarding sysctls = 1** |
| Minecraft (D14) | `Resolved Minecraft version 26.2 from Modrinth projects`, world loaded, `Done (1.446s)!` |
| `/srv` perms (`3f2c418`) | now **770** — had been silently 0755 its whole life |
| health-check (`b51e328`) | `SupplementaryGroups=disk` on the **unit**, user not in the group |
| Deploy-guards (`929efa3`) | the **old** code still fails on that host right now; the new mechanism returns `master` cleanly |
| factorio-new | gone; `factorio-main` unaffected |
| Overall | **zero failed units**, both containers healthy |

Use `net.ipv4.conf.all.forwarding`, **not** `net.ipv4.ip_forward` — the
tailscale module sets the former.

---

## What happened in the fifth session (2026-08-27)

**The branch was merged** (PR #24) after syncing `origin/master` in; the
only conflict was `TODO.md`, resolved by keeping both sides' new entries
and dropping master's older copy of the audit entry, which this branch
had already superseded. homelab and vps built to byte-identical store
paths across the merge, proving it changed nothing deployed.

**Scheduled deploys were turned off fleet-wide**, on instruction, while
the pipeline is rebuilt. New `scheduleEnable` option on all three deploy
modules; **not** `enable = false`, because that would also delete
`auto-switch-now`, `pull-deploy` and `push-deploy-vps` as *units*, and
those are the manual deploy paths. Timers are *removed* rather than
un-wanted, so a switch actually stops a running one — confirmed in the
switch log (`stopping the following units: auto-switch.timer, …`).

**Credential rotation started.** Items 1 (`cloudflare_octodns_token`) and
2 (`discord_webhook`) are done and verified live. Item 2 also
**consolidated two sops keys into one**: `homelab_discord_webhook` (read
by homelab, torrent *and* thinkpad) and `vps_discord_webhook` held the
same URL, so the host prefix described nothing. All four hosts now read
one unprefixed `discord_webhook`.

**Debug tooling is now shared.** `modules/flake/debug-tools.nix` is a
single list consumed by both the devshell and every host (via
`profiles/default.nix`), always resolved against **unstable** so tools
behave identically fleet-wide. Currently `jq` and `ipset`. Add a tool
there once and it lands everywhere.

### Things this session got wrong, and what corrected them

Worth reading — the pattern is that the *verification step* caught all of
them, not the reasoning:

- **The rotated Discord webhook was pasted as a bare URL**, but
  `myHealthAlerts` uses `curl -K`, which is config-file mode and needs
  `url = "https://…"`. It fails **silently**, because `notify` only runs
  when something is already wrong and discards curl's output and exit
  status. Filed in `TODO.md`: nothing ever verifies the alert sink works.
- **"Keep the old sops keys until the laptops are deployed" was wrong.**
  The user challenged it. `secrets/secrets.yaml` is version-controlled
  and a built system pins an **immutable store copy**, so removing a key
  cannot affect a host that has not rebuilt, and every commit is a
  self-consistent snapshot. Also moot: neither laptop reads it, since
  `myHealthAlerts` was never deployed there.
- **A missing key fails the *build*, not activation** —
  `sops-install-secrets` validates the manifest at build time. Better
  than documented; `remediation.md` corrected.
- **Rotating the two Tailscale auth keys was unnecessary**, and the
  advice given for it was actively harmful — it said to mint *reusable*
  replacements, which would have turned a spent single-use credential
  into a standing one. See items 3/4 in the runbook.

## What happened in the sixth session (2026-08-28)

Rotation went from "1 and 2 done" to essentially complete, and threw off
four separate findings on the way. The pattern worth carrying forward is
that **every one of them was found by verifying, not by building.**

**Rotation completed:** 5–7 (WireGuard set), 8 (`homelab_vps_deploy_key`),
10 (restic password), 11 (`tailscale_authkey_isoimage`, revoked not
replaced), 12 (factorio credentials, added this session). 9 deferred.

**Findings, each with its own plan file:**

- **Rotated secrets do not reach running consumers.** WireGuard's
  interface is a `RemainAfterExit` oneshot that reads `privateKeyFile`
  once at link creation; the factorio container bakes its credentials into
  `server-settings.json` at start. Both reported success while still using
  the old value. Fixed with `restartUnits` (`61f55cb`, `3dd1aa4`). Note
  `restartUnits` fires on *content change*, so it cannot repair the state
  that exposes it — each needed one manual restart.
- **`/srv` at 0770 root:root broke jellyfin** and masked rather than fixed
  the exposure it was added for. Now
  `2026-08-28-fix-srv-permissions-stop-three-systems-fighting-ov.md`.
- **The factorio credentials were provably disclosed** through
  `/nix/state/.zfs` (0777) across 57 snapshots, read live as uid 65534.
  Mechanism split into
  `2026-08-28-nix-state-zfs-snapshot-dir-is-world-traversable-ex.md`.
- **A manual deploy killed an 8h28m / 66 GB backup run** and left the
  repository locked for a week.
  `2026-08-28-a-manual-deploy-kills-the-in-flight-weekly-restic-.md`, with
  the design lesson carried to the pipeline plan as **D6**.

**Two corrections to earlier audit claims**, both of which would have led
to wrong action: the stray zrepl key is on **torrent**, not homelab, and
was cited as `F-P8-06` when it is `F-P7-02`; and restic does **not** push
the laptop replicas offsite (it mounts only `zroot/local/state` and
`zdata/storage/storage`).

**A guard fired correctly and looked like success.** `push-deploy-vps`
refused to run because `/etc/nixos` was not on master, logged
`skipping this scheduled run`, and exited **0**. That is `F-P7-09`'s
shape observed live. Item 8 was verified by authenticating directly
instead — see the runbook item for the technique.

## What happened in the seventh session (2026-08-28)

Two things, neither deployed anywhere.

**`findings-tail.md` reviewed against current repo state.** Sessions 3-6
fixed several things that consolidation still described as open; a fork
verified each citation against the live repo rather than trusting the
doc, and annotated seven stale entries in place (strikethrough/bracketed
correction, per this file's own "correct the record" rule): the `/srv`
tmpfiles row (fixed, then broke jellyfin, then redesigned — see below),
`factorio-new`'s floating tag (moot, the container is gone), the
container resource-ceiling bullet in SYS-07 (`--memory`/`--pids-limit`
now set), SYS-11's `restartUnits` gap (closed for the wireguard trio and
factorio secrets, the two the audit actually named), PROMO-03 (first leg
fixed differently than suggested), and the `safe.directory` row in the
§5.1 table (superseded by the `git()` wrapper from the deploy-outage
fix). Left alone, confirmed still accurate: the sshd `extraConfig`→
`settings.*` migration (SYS-02) and waydroid's `trustedInterfaces` grant
(SYS-03) — neither has been touched. One item flagged but not annotated:
whether the ISO-staleness finding (L-03) is still live depends on
torrent/thinkpad's deploy state, which needed SSH access to confirm and
wasn't checked. Commit `4e2278c`.

**`boot.tmp.useTmpfs = true` landed fleet-wide**, closing D1 of
`2026-08-28-restructure-zfs-so-ordinary-temp-and-cache-data-is.md` (agreed
2026-08-27, not yet written before this session). One line in
`modules/profiles/default.nix`, which every host imports including vps.
All five `nixosConfigurations` build; the rendered `tmp.mount` was read
back (not just built) on torrent and vps, confirming `Type=tmpfs`,
`size=50%`, `nosuid`, `nodev`.

The `security` subagent's review raised a MEDIUM finding — that
nix-daemon's build scratch space would now compete with tmpfs `/tmp` for
RAM — which **checking the pinned Nix docs against live state refuted**:
Nix 2.34.8 defaults `build-dir` to `$NIX_STATE_DIR/builds`
(`/nix/var/nix/builds`, confirmed to exist, on `/nix` not `/tmp`), not
`$TMPDIR` as older Nix versions did, and `nix-daemon.service`'s rendered
environment sets no `TMPDIR`. Downgraded to INFO in the plan with that
evidence rather than accepting the PLAUSIBLE claim at face value — the
same "check the source, don't assume" discipline this file's obligations
section already asks for. One real residual from that review, LOW and
still open: homelab's restic backup mounts a ZFS snapshot under
`/tmp/restic/$snap`, and nobody has verified that mount-stacking onto the
new tmpfs still works — deliberately not tested live, since a careless
check risks kicking off part of the multi-day backup. Tracked as a
Progress item to check at homelab's next real deploy. Commit `193bbc0`.

**Not deployed anywhere.** Both changes are build-verified only; they
take effect at each host's next switch, whenever the user chooses to
deploy.

## What happened in the eighth session (2026-09-01)

Credential rotation is done except the genuinely-blocked item 9 (see
above, unchanged). This session worked the tail instead: two agent-doable
LOW findings from `findings-tail.md`, both fully fixed and verified
without touching a real host.

**L-01 — caddy's admin API reachable from anubis on vps, fixed and
VM-tested.** `hosts/vps/configuration.nix` now sets
`systemd.services.anubis-jellyfin.serviceConfig = { IPAddressDeny = "any";
IPAddressAllow = [ "10.100.0.2/32" ]; }`. Build-verified on the rendered
unit. Then VM-tested for real, per the finding's own instruction ("needs
a VM test with a real request through caddy, not a unit start"): new
`tests/anubis-admin-egress.nix`
(`checks.anubis-admin-egress`) boots caddy + anubis + a stand-in backend
on a dummy interface at the same address anubis's real `TARGET` uses, and
proves — not just asserts — five things: the restriction renders live;
a real request through caddy's unix-socket reverse proxy still reaches
the backend; a probe shell **migrated into anubis-jellyfin.service's own
cgroup** (`echo $$ > /sys/fs/cgroup<ControlGroup>/cgroup.procs`, the
direct way to exercise a cgroup-attached BPF egress filter rather than
trust the rendered directive) cannot reach a real caddy admin API on
`127.0.0.1:2019`; the same cgroup can still reach the real backend
(ruling out "the probe technique itself is broken"); and clearing the
restriction live with `systemctl set-property` makes the same probe
succeed again, proving causation the same way `docker-publish-guard.nix`
does for the firewall guard. `nix build .#checks.x86_64-linux.anubis-admin-egress`
passes all five subtests.

**L-02 — restic's `/tmp` snapshot mounts, fixed.** The finding said the
unit "already has `RuntimeDirectory`" — checked against the file and that
was wrong; it had `StateDirectory` (persistent `/var/lib/…`, used for the
`last-success` marker), which was never going to help. Corrected in place
in `findings-tail.md`. The actual fix, in
`hosts/homelab/configuration.nix`: added a real
`RuntimeDirectory = "restic-backups-backblazeWeekly"` at `0700` (closes
both halves the finding named — the symlink-plant risk on a hand-rolled
`mkdir -p /tmp/restic`, and the world-traversable `/tmp` exposure for a
mount that can sit for a week); `backupPrepareCommand` mounts under
`$RUNTIME_DIRECTORY` and now sorts snapshots by `-s creation` instead of
by name (the finding's "fragile if the naming scheme ever changes" nit);
`backupCleanupCommand` now unmounts only what this run actually mounted,
read from `/proc/mounts`, instead of piping every snapshot on the system
— including `zbackup`'s replicated ones — into `umount`. `awk` was the
first draft's cleanup tool; the unit's own `path` list carries no `gawk`,
caught by reading the rendered script rather than assumed, so it uses
`grep`+`cut` instead. Verified by reading the rendered
`…/bin/restic-backups-backblazeWeekly-pre-start` and `-post-stop` scripts
out of `nixos-rebuild build`'s `./result`, the audit's own "verify the
fix, not the build" technique — deliberately **not** exercised with a
real restic run, since
`2026-08-28-a-manual-deploy-kills-the-in-flight-weekly-restic-.md`
already decided not to risk kicking off part of a multi-day backup this
way.

**Also folded in**: `2026-08-28-fix-srv-permissions-stop-three-systems-fighting-ov.md`'s
F1 checkbox (rotate the factorio.com token/password) was still unticked
even though `rotation-runbook.md` item 12 had recorded it done since the
sixth session — synced, no new action taken.

**What was looked at and deliberately left alone**: the rest of the tail
(L-03 through L-15, SYS-01 through SYS-12, the promotion candidates, and
the needed/used rollup) — most of it is either a user-only decision, a
provider-side action, or genuinely needs a live host to observe (e.g.
L-04's "check thinkpad for an existing `authorized_keys` file first" —
no SSH access to thinkpad). The four 2026-08-28 plan files' own open
items (the `.zfs`-traversal mechanism decision, the manual-deploy-vs-restic
D1/D2, the `~/.cache`/`Downloads` dataset split, restic's own F2 live
test) are untouched, per their own status — they were already correctly
blocked, not overlooked. `nix flake check --no-build` was run once for a
broad sanity pass; it fails on `checks.zrepl-replication` for an
unrelated, already-tracked reason
(`2026-08-28-nix-flake-check-fails-on-zrepl-replication-test-pk.md`), not
on anything this session touched — confirmed by building and VM-testing
this session's own two checks individually, both clean.

**Not deployed anywhere.** Both fixes are build/VM-test-verified only.

## What happened in the ninth session (2026-09-01)

**Rotation item 9 (`homelab_zrepl_key`) closed — the last rotation item.**
The blocker in the eighth session's "What is left" (below, now corrected)
was cleared simply: the user had physical access to both laptops.

- **First correction: torrent was not actually behind by 40 commits.**
  Before touching anything, live checks (`avahi-daemon` absent, all deploy
  timers reporting 0, and an `nvd diff` against the running system showing
  only `ipset`/`jq`-docs/`tmp.mount` as new) showed torrent's generation
  122 (switched 2026-08-27 21:26, outside this audit's own sessions) was
  already nearly at this branch's HEAD. `RESUME.md`'s repeated "torrent
  has never been switched" claim was stale, not current — corrected here
  rather than carried forward again. The switch itself needed no reboot
  (no kernel change) and was a small diff, not the fourth session's feared
  "first-ever, carries all of wave 1" jump.
- **Both laptops deployed to this branch.** torrent switched locally
  (small diff, confirmed above); thinkpad switched at its own console by
  the user, since it has no remote shell — I could not verify it directly
  the way I did torrent.
- **New keypair generated by the user**; private half re-encrypted into
  `secrets/secrets.yaml`, public half (`homelab-zrepl-puller`) placed in
  `modules/flake/vars.nix`, replacing `homelab-zrepl-pull`.
- **`sops.secrets.homelab_zrepl_key` given `restartUnits = [
  "zrepl.service" ]`** (`hosts/homelab/configuration.nix`) — this secret
  had none, unlike the WireGuard/factorio pair `SYS-11` already closed.
  Go-netssh shells out to the system `ssh` binary per pull attempt, which
  plausibly makes it a per-invocation reader already (unlike WireGuard's
  `RemainAfterExit` oneshot) — not verified either way, and a killed pull
  just retries, so `restartUnits` was added rather than trusting the
  assumption.
- **Build-verified all three hosts before any switch**, including reading
  the rendered `authorized_keys.d/root` on torrent/thinkpad (new key
  present, forced command intact) and the sops manifest on homelab
  (`restartUnits` present, correct `sopsFileHash`) out of `./result` —
  same "verify the fix, not the build" discipline as the rest of this
  audit.
- **Deployed laptops first, then homelab**, per the runbook's fail-safe
  order. All manual `switch`, not the disabled `boot`-mode auto-deploy, so
  the "needs a reboot" caveat in the runbook's original item 9 text did
  not apply — the key took effect immediately. Zero failed units on all
  three.
- **Verified by exercising the credential.** Homelab's activation log did
  show `modifying secret: homelab_zrepl_key` and `zrepl.service`
  restarting — exactly the shape that fooled three earlier rotations in
  this audit into a false "done" — so it was not trusted alone. Forced a
  pull with `zrepl signal wakeup torrent`/`wakeup thinkpad` and watched
  `zbackup`'s replicas directly: both picked up a fresh snapshot
  (`@zrepl_20260901_175824_000` / `…175816_000`) matching each source
  host's own latest local snapshot, within about two minutes.
- **Also landed**: `glow` added to `modules/profiles/default.nix` (fleet
  default profile) for reading markdown docs, build-verified on all five
  `nixosConfigurations`, deployed as part of the same torrent/homelab
  switches above (thinkpad has it build-verified, not yet confirmed live).

**Two commits landed this session** (a third, the `glow` addition, was
authored directly; `secrets/secrets.yaml` changes were committed by the
user on request, since the harness's own classifier — independent of
`AGENTS.md`'s "I never edit or decrypt secrets" rule — blocked the agent
from doing it directly): `4561889` (glow) and `3aa78a8` (zrepl key
rotation). Pushed.

**Cleanup done 2026-09-01:** `/tmp/homelab_zrepl_key` and its `.pub`
deleted on torrent, after the new key. Item 9 is fully closed — nothing
outstanding from rotation. See `rotation-runbook.md` item 9's closure note
for the full detail.

## What happened in the tenth session (2026-09-01)

**Restic's staleness prediction was corrected.** The user ran a manual
backup (2026-08-29 22:50 → 2026-08-30 08:46, `no errors were found`, exit
0) that this file and
`2026-08-28-a-manual-deploy-kills-the-in-flight-weekly-restic-.md` had
both predicted would page ~2026-09-03. It won't — `last-success` is now
2026-08-30, and the alarm at 312h isn't due until ~2026-09-12. Corrected
in place in both files rather than left to mislead the next reader.

**D1 of `2026-08-28-nix-state-zfs-snapshot-dir-is-world-traversable-ex.md`
answered and implemented** — the mechanism behind the factorio
disclosure, not just that one credential. The user asked for research
and empirical testing before any decision, not a guess:

- A first pass (forked, then redirected to test on homelab directly)
  found `chmod 0700` on `.zfs` works but does not persist — the control
  directory is synthesized fresh on every mount, so it silently resets to
  0777 on the next unmount/mount or reboot. Would have needed a custom
  reapply-on-mount unit to mean anything.
- Web research plus direct empirical testing on homelab (throwaway
  datasets, destroyed after, never touching real data) found
  `snapdir=disabled` instead: real dataset metadata, survives a full
  unmount/mount cycle with the block intact, blocks **all** access
  including root's own (`ENOENT`, not a permission check) on a dataset
  never previously touched. One real caveat, also verified empirically
  rather than assumed: an already-cached automount from *before* the
  property changes stays reachable until that dataset's next
  unmount/mount or reboot — flipping the property alone doesn't
  retroactively close it. No regression to restic, confirmed directly:
  its offsite backup mounts snapshots by explicit name
  (`mount -t zfs <snap> <target>`), a mechanism entirely separate from
  `.zfs`, unaffected by `snapdir` either way.
- Applied to `zroot/local/state` on homelab only. New reusable module
  `modules/nixos/zfs-dataset-properties.nix` (`myZfsDatasetProperties`)
  is the actual deliverable requested alongside the fix — a single place
  for declarative ZFS dataset properties across current and future
  hosts, self-healing every boot/switch via a `zfs-mount.service`-hooked
  oneshot, rather than one-off `zfs set` commands that drift out of sync
  host to host. **PCs deliberately excluded** — the user browses backups
  via `.zfs/snapshot` on torrent/thinkpad directly, and `disabled` would
  remove that outright. Carried to
  `2026-09-01-extend-the-zfs-snapshot-traversal-fix-to-the-pc-hosts-without.md`
  as its own backlog plan (D1 there, undecided) rather than left
  unresolved in the closed plan.
- VM-tested (`tests/zfs-dataset-properties.nix`): sandbox baseline, the
  property actually reaching the dataset, the opt-in-only scope (a second
  unconfigured dataset stays untouched), the block itself, and the
  documented remount caveat — all asserted against a real pool, following
  this repo's "verify the fix, not the build" rule the same way every
  other VM test in `tests/` does.

**Not deployed anywhere.** Build-verified on all five
`nixosConfigurations`; torrent/thinkpad/vps are byte-identical to before
(the module is opt-in and only homelab sets it). Commit `47c4f89`, pushed.

**Disko consolidation done, same session, on explicit go-ahead.** The
repeated `rootFsOptions` block (byte-identical across all five zpool
definitions — torrent's and thinkpad's `zroot`, homelab's own
`zroot`/`zdata`/`zbackup`) and the root-SSD disk layout (identical shape
on all three ZFS hosts, differing only in swap size) both now live once
in `modules/flake/vars.nix` (`zfsRootFsOptions`, `mkZfsRootSsd`), matching
the same pattern `vars.zreplPullerKey` already used. Pure refactor,
verified by identical outcome rather than by inspection: all five
`nixosConfigurations` build to **byte-identical store paths** before and
after. vps has no ZFS and is untouched. Commit `718c396`, pushed. Not
deployed anywhere — a no-op refactor has nothing to deploy differently,
but it still rides along with each host's next real switch.

## What happened in the eleventh session (2026-09-01)

**Item 0 of "Agent-doable, unblocked" done** — the disko/
`myZfsDatasetProperties` unification queued at the end of the tenth
session. Full detail and verification steps in
`2026-09-01-unify-myzfsdatasetproperties-and-disko-so-one-declaration-covers-both.md`;
summary here.

`hosts/homelab/disko.nix`'s per-dataset `options` blocks now read
`config.myZfsDatasetProperties."<pool>/<dataset>"` instead of never
referencing it at all — so `snapdir=disabled` on `zroot/local/state`
(closed in the tenth session, live-reapply only) now also seeds at
`disko-install`/`nixos-anywhere` creation time, meaning a *fresh* install
of homelab gets the property from that dataset's very first mount, with
**no** "already-cached automount" window at all (that window is specific
to an already-installed host picking the property up live, see the
`.zfs`-traversal plan's G1/D1).

**Extended further, same session, on explicit ask.** Mid-session the user
asked what else was safe to fold into the same mechanism. Answer worked
out and confirmed: any real ZFS *property* (`zfs`/`zpool` `get`/`set`) is
always safe to reapply idempotently; *structure* (partitioning, `zpool
create`/vdev topology, `ashift` — fixed permanently at vdev creation
despite living in `options.ashift`) is one-shot and must stay disko-only.
`vars.zfsRootFsOptions` (the tenth session's own consolidation — `acltype`,
`xattr`, `atime`, `mountpoint`, `canmount`, `compression`, `devices`,
`sync`, `com.sun:auto-snapshot`) is entirely real properties, so it got
the same treatment for **homelab only**:
`hosts/homelab/configuration.nix` sets
`myZfsDatasetProperties."zroot"/"zdata"/"zbackup" = vars.zfsRootFsOptions;`
and `hosts/homelab/disko.nix`'s three `rootFsOptions` now read that
option instead of `vars.zfsRootFsOptions` directly. `vars.zfsRootFsOptions`
itself is untouched and stays the one literal source — torrent/thinkpad's
`disko.nix` still reads it directly, unaffected, since neither imports
`zfs-dataset-properties` (the PC exclusion is about `snapdir`/backup
browsing specifically, not revisited here).

**Verified, not just built**, per this audit's standing rule:
- `nix build .#nixosConfigurations.homelab.config.system.build.diskoScript`
  rendered to the identical store path before and after the
  `rootFsOptions` change — proof the install-time behavior for
  `zroot`/`zdata`/`zbackup` creation is byte-for-byte unchanged, a pure
  refactor for what disko already did.
- The rendered live-oneshot script
  (`…/bin/zfs-dataset-properties-start`, read out of `nixos-rebuild
  build`'s closure, not assumed from the unit file per this file's own
  "grep the payload, not the wrapper" rule) now has 27 new `zfs set`
  lines (nine properties × three pools) ahead of the pre-existing
  `snapdir=disabled` line.
- All five `nixosConfigurations` build; torrent/thinkpad/vps/isoimage
  render to the exact same store paths as before this session's edits —
  only `hosts/homelab/configuration.nix` and `hosts/homelab/disko.nix`
  were touched, confirmed by outcome, not just by diff.

**Extended a third time, same session, to torrent and thinkpad.** On
further explicit ask, the two remaining ZFS hosts got the identical
treatment, and the per-host `zfsProps` helper (previously a 3-line local
`let` binding duplicated wherever it was needed) was generalized into
`vars.zfsProps` (`modules/flake/vars.nix`) — one definition, each host's
`disko.nix` binds `zfsProps = vars.zfsProps config;` once. Both hosts now
import `nixosModules."zfs-dataset-properties"` (`modules/flake/hosts.nix`)
and set `myZfsDatasetProperties."zroot" = vars.zfsRootFsOptions;` in their
own `configuration.nix`. Importing the module is inert on its own — it
only acts on keys actually set, so thinkpad's own `local/state` dataset
(structurally identical to homelab's, sitting right next to the shared
`zfsProps` wiring) still gets no `snapdir` value, exactly preserving the
PC exclusion from the `.zfs`-traversal plan's D1.

Verified the same way as the first two rounds, not by trusting the build:
homelab's disko script still renders to the identical store path from the
`rootFsOptions` check above (the helper's *definition* moved, not its
*output*); torrent's and thinkpad's rendered disko scripts were read
directly and their `zpool create` commands carry the identical nine `-O`
flags disko always applied (matching `vars.zfsRootFsOptions` verbatim,
verified value-by-value, not just "it built"), with every other dataset's
`options` unchanged from before; both hosts' rendered live-oneshot scripts
are byte-identical to each other and apply exactly those same nine
properties to `zroot` and nothing else, confirmed by reading the actual
payload script out of each host's build (via a distinct `--out-link` per
host, since building both via the shared default `./result` link would
clobber one with the other). `nixfmt --check` clean on every file this
session touched; the `statix`/`deadnix` warnings present are all
pre-existing, on lines this session never edited.

Plan moved to `docs/plans/done/` — D1 answered, every Progress item
checked, nothing left open.
`2026-09-01-unify-myzfsdatasetproperties-and-disko-so-one-declaration-covers-both.md`
citations elsewhere are unaffected (bare-filename citations survive the
move by design).

**Not deployed anywhere.** All three rounds of this session's work are
build-verified only.

## What happened in the twelfth session (2026-09-01)

**Landed PR #39**, closing out the backlog from the fifth through
eleventh sessions (credential rotation, the two LOW findings, the
`.zfs`-traversal fix, the disko/`myZfsDatasetProperties` unification).
`origin/master` had moved on independently (a plan-file-system rework,
including a new `plan-gate` CI check) — merged in first, one real
conflict (`docs/plans/.checksums`, an append-only manifest, resolved as
a union of both sides' lines). `plan-gate` then correctly blocked the PR
on two genuinely unresolved findings (F1, F2) on
`2026-08-28-restructure-zfs-so-ordinary-temp-and-cache-data-is.md`, both
predating `plan-gate`'s own existence: F1 was already reasoned to INFO
in-doc and just needed the formal `plan-resolve` marker; F2 was
genuinely moot, since the code it was about (`/tmp/restic` mounts) had
already been replaced for an unrelated reason (`a4f5e95`, the eighth
session's L-02 fix) — its own `RuntimeDirectory` lives under `/run`,
always tmpfs, independent of `boot.tmp.useTmpfs`. Resolved both, gate
passed, merged (`6a68cb3`).

**Then started item 1, `push-deploy-vps` sandboxing (F-P7-06 / wave 2
item 2.6's deferred third) — in progress, not finished.** Grounded the
design in `nixos-rebuild-ng`'s actual Python source
(`nixos_rebuild/tmpdir.py`, `process.py`) rather than the guesswork the
item was deferred to avoid: it opens its own SSH `ControlMaster=auto`
through a tempdir under `$TMPDIR`/`nixos-rebuild.<rand>`, created once
at import time via `tempfile.TemporaryDirectory()`. `ProtectSystem =
"strict"` alone makes `/tmp` read-only and this fails immediately (a
guaranteed, reproducible break, not a subtle one);  `PrivateTmp = true`
fixes it, since the socket only ever needs to be reachable from this
unit's own process tree, which shares one mount namespace for the life
of a single oneshot run. `nix show-config` confirmed
`use-xdg-base-directories = false` (the pinned default), so nix's own
eval/build cache genuinely has to be `~/.cache`, ruling out an
`XDG_CACHE_HOME` redirect.

Applied to `modules/nixos/push-deploy.nix`:
`ProtectSystem=strict`, `PrivateTmp=true`,
`ReadWritePaths=[flakeDir "/root/.ssh" "/root/.cache"]`, plus
`systemd.tmpfiles.rules` creating `.cache`/`.ssh` — added only after the
VM test (below) proved `ReadWritePaths` does **not** auto-create its
target, and that a `+`-prefixed `ExecStartPre` does **not** help (the
mount namespace is set up once for the whole unit before any
`ExecStartPre` runs — `+` only bypasses privilege-dropping, not
sandboxing). Build-verified on all five `nixosConfigurations`, committed
as explicit WIP (`d470a61`) — **not deployed, and the module's own
sandboxing is not yet proven to actually work end-to-end.**

**`tests/push-deploy-sandbox.nix`, a real two/three-node VM test (the
finding's own stated requirement), is built and registered
(`modules/flake/checks.nix`) but has not yet gone green.** Imports the
real module (not a copy); `deployer` runs the genuine
`push-deploy-target.service` against `target` (an unprivileged `deploy`
user over real ssh, the same run0-alias-plus-polkit elevation vps's own
dispatcher uses); `deployer-broken`, a second node identical except
`PrivateTmp` forced off, is the negative control proving that flag is
load-bearing rather than incidental. Six real, non-obvious bugs were
found and fixed by iterating against actual failures, not guessed:

1. `myPushDeploy.minSwitchInterval`'s type is `positive-int`, not
   `>= 0` — the test's `0` needed to become `1`.
2. `security.run0.enableSudoAlias` needs `security.run0.enable = true`
   *and* `security.sudo.enable = false` alongside it (an assertion
   failure without both — checked against `modules/profiles/default.nix`'s
   own real pattern, not guessed).
3. **The load-bearing one.** `ReadWritePaths` does not create the
   directory it grants access to — on a genuinely fresh root user with
   no prior `.cache`, mount-namespace setup fails outright with ENOENT
   before the script even starts. The first fix attempt (a
   `+`-prefixed `ExecStartPre` to `mkdir -p` it) **also failed with the
   identical error**, empirically disproving the assumption that `+`
   bypasses sandboxing — it only bypasses privilege-dropping. Fixed
   properly with `systemd.tmpfiles.rules`, which runs at boot,
   independent of this unit entirely.
4. A local Python variable in the test script named `log` shadowed the
   test driver's own built-in `log` symbol (its logger) — caught by the
   test driver's static type checker, not a runtime failure. Renamed to
   `unit_journal`.
5. A VM test node boots straight from its built closure and never runs
   a real install/`nixos-rebuild switch`, so
   `/nix/var/nix/profiles/system` — which the script itself `stat`s
   over ssh before proceeding — doesn't exist on `target`. Added the
   symlink in the test setup, plus `touch -h -d @0` to keep its mtime
   from racing `minSwitchInterval`'s skip guard on a same-second
   coincidence.
6. The minimal flake being pushed pulled in NixOS's default
   `documentation.nixos.enable`, which needs `nixos-render-docs`
   (Python) — not pre-cached in the sandboxed test VM, no network to
   fetch a source tarball with. Added `documentation.enable = false;`
   to the pushed flake's module.

**Currently blocked on a seventh issue, not yet root-caused: the pushed
flake's evaluation triggers a from-scratch rebuild of `glibc`/`stdenv`/
Python inside the deployer VM**, rather than reusing store paths already
present in its own closure — even though the flake's `nixpkgs` input is
pinned via `path:${pkgs.path}` to the exact same nixpkgs the VMs
themselves were built from. This is precisely the shape
`remediation.md` originally predicted when it deferred this item
("building a full system closure inside a test VM and pushing it to a
second node, far heavier than the zrepl two-node test and probably
impractical as written") — the *mechanism* under test (SSH/sandboxing)
turned out tractable and caught six real bugs, but the *closure-build*
half is the part proving genuinely heavy, exactly as warned.

**Most promising next step, not yet tried:** force the pushed target's
`toplevel` to already be present in `deployer`'s own store closure
before the test VM ever boots, rather than relying on evaluation
naturally reusing it. Concretely: evaluate the *same* minimal
`nixosSystem` (same `pkgs.path` pin, same module) once in the **outer**
Nix expression that builds `tests/push-deploy-sandbox.nix` itself (not
inside the VM), reference its `.config.system.build.toplevel` from
somewhere in `deployer`'s own node config (e.g.
`environment.etc."prebuilt-target-marker".source = targetToplevel;`) so
it becomes part of `deployer`'s closure and gets copied into the VM at
boot — then when `nixos-rebuild` inside the VM evaluates the identical
flake, it should get the identical derivation, already realized, with
nothing left to build. Two secondary fallbacks if that doesn't pan out:
(a) narrow the test to exercise just the SSH/sandboxing mechanics
directly (control-master, `nix-store --serve --write`, sudo-elevated
`switch-to-configuration`) as literal shell commands under the real
`serviceConfig`, without a full flake evaluation at all — less
end-to-end fidelity, but avoids the closure-build problem entirely; or
(b) accept the audit's original judgment that a full closure-push VM
test is impractical, and instead deploy the current build-verified
hardening to vps directly on the user's explicit go-ahead, watching
vps's own profile-staleness alert (now wired up, see item 2 below) to
catch a wrong guess quickly rather than silently.

**Nothing deployed.** The hardening in `modules/nixos/push-deploy.nix`
must not be treated as done — it is unverified beyond a local build.

## What happened in the thirteenth session (2026-09-01)

Picked the twelfth session's `push-deploy-vps` VM test back up and got it
fully green — `nix build .#checks.x86_64-linux.push-deploy-sandbox -L`
now passes both subtests. Full blow-by-blow (nine distinct bugs, each
found by iterating against a real failure) is in
`2026-09-01-vm-verify-push-deploy-vps-sandboxing-f-p7-06-wave-2-item-2-6.md`,
opened this session specifically so this level of detail didn't live only
in a conversation transcript; summary here:

The twelfth session's own theory (registering a matching closure in
`deployer`'s config so the guest's nix would trust it) turned out
incomplete: nix's `path:` flake fetcher re-copies even an
already-store-resident nixpkgs tree into a freshly-hashed location, so
nixpkgs' own internal `./relative` imports resolve against a *different*
copy than what's already built and registered on the host — the real
reason a from-scratch bootstrap was being triggered, not fixable by
registering a closure computed against the original, un-rewrapped path.
`builtins.storePath`, `builtins.getFlake` on a store path, and a bare
path literal were all tried as ways to reference an already-built path
without re-evaluating nixpkgs at all, and all three are rejected outright
in the pure evaluation `nix build --flake` always runs under. The fix
that actually works: a declared, locked `path:` input with `flake =
false`, pointed at an already-built *leaf* derivation (a finished system
closure, a package) rather than at nixpkgs itself — a leaf has no
internal relative-path references left to re-root, so the fetcher's
re-copy is just a filesystem copy, not a rebuild.

That got the deploy as far as a real `switch-to-configuration switch`
actually running against the real remote target — which then surfaced a
run of five more real bugs, each only visible once the mechanism was
genuinely running end to end: the pushed config silently dropping sshd/
the deploy user (hangs the deploy instead of erroring, since it's killing
the very ssh session driving the switch); the test framework's own
inter-VM network interface and 9p-store overlay torn down by the same
gap (fixed properly by building the pushed config through `nixpkgs.lib.
nixos.evalTest` — the same low-level function `runNixOSTest` itself uses
to build every node — rather than hand-reconstructing each piece of
config, which visibly failed a second time even after a near-exact
reconstruction, since overlayfs can't remount with even identical
parameters); `system.switch.enable` defaulting off for VM test nodes,
silently dropping `switch-to-configuration` from the closure; a genuine
switch attempting real bootloader installation that a test node's normal
kernel/initrd boot never exercises; and an isolated single-node
`evalTest` call computing different network addressing than the real
three-node test, colliding with `deployer`'s own address. Every one of
these, plus the general pattern each teaches, is now in
`docs/procedures/vm-testing.md`'s "Things that will bite you" for the
next VM test author.

**Not deployed to vps.** VM-verified is not deployed — that is still a
separate, explicit user decision, same as always.

## What is left

### Rotation — done

[`rotation-runbook.md`](rotation-runbook.md) has the table. **10 done, 2
not required.** Item 9 (`homelab_zrepl_key`), the last one, closed
2026-09-01 including cleanup — see "What happened in the ninth session"
above and the runbook's own closure note. **Rotation has nothing
outstanding.**

### Still owed by the user

- ~~Delete the **old Cloudflare token** (item 1) and the **old Discord
  webhook** (item 2).~~ **Done 2026-08-28**, and both re-verified after
  deletion: `octodns-sync` succeeded with the new token as the *only*
  valid one, and the Discord webhook returned HTTP 200 from both homelab
  and vps with its snowflake decoding to 2026-08-27 — i.e. the surviving
  webhook is the new one. Items 1 and 2 are now complete end to end,
  provider side included.
- ~~Deploy homelab to pick up the **312h staleness threshold**
  (`c6116ca`).~~ **Done 2026-09-01** — homelab was switched as part of the
  ninth session's zrepl-key rotation, which carried this along.
- ~~Expect the backup staleness page ~**2026-09-03**.~~ **Resolved** — a
  manual backup completed cleanly; see the corrected note above.
- ~~Delete `/tmp/homelab_zrepl_key` and its `.pub` on torrent.~~ **Done
  2026-09-01**, after the new key was already verified working.

### Agent-doable, unblocked

0. ~~**Unify `myZfsDatasetProperties` and `disko.nix`'s per-dataset
   `options`**~~ — **done in the eleventh session**, and extended to
   `vars.zfsRootFsOptions` (pool root datasets) too. See "What happened
   in the eleventh session" above and
   `2026-09-01-unify-myzfsdatasetproperties-and-disko-so-one-declaration-covers-both.md`.
   Build-verified only, not deployed.
1. ~~**`push-deploy-vps` sandboxing**~~ — **VM test fully green as of the
   thirteenth session (2026-09-01).** `nix build .#checks.x86_64-linux.
   push-deploy-sandbox -L` passes both subtests: the real, hardened unit
   builds locally, copies the closure over real ssh, and runs a real
   remote `switch-to-configuration switch` that actually activates on
   `target`; the negative control (`PrivateTmp` forced off) fails exactly
   as predicted (`Read-only file system` creating nixos-rebuild-ng's own
   ssh-controlmaster tmpdir), proving `PrivateTmp` is load-bearing, not
   incidental. F-P7-06 / wave 2 item 2.6 is now fully closed — all three
   deferred items are VM-tested. Getting here took nine more real,
   distinct bugs beyond the twelfth session's six (root-caused, not
   guessed) — the from-scratch-rebuild blocker turned out to be nix's
   `path:` fetcher re-copying nixpkgs into a freshly-hashed location, not
   fixable by registering a matching closure as originally planned; the
   actual fix was building the pushed config through `nixpkgs.lib.nixos.
   evalTest` (the same machinery `runNixOSTest` itself uses) instead of a
   plain `nixosSystem` call, plus five smaller gaps that only that switch
   surfaced. Full detail — every gotcha, the abandoned approaches and why
   they didn't work, worth reading before touching this test again — is
   in `2026-09-01-vm-verify-push-deploy-vps-sandboxing-f-p7-06-wave-2-item-2-6.md`
   (not yet `plan-move`d to `done/`; one formality-only decision, D1, is
   moot now but wants a real `plan-decide` before that move) and in
   `docs/procedures/vm-testing.md`'s own "Things that will bite you".
   **Still not deployed to vps** — VM-verified is not the same as
   deployed, and that remains a separate, explicit user decision.
2. ~~**The skipped-deploy half of `F-P7-09`**~~ — **done in the fourth
   session.** All four hosts watch `/nix/var/nix/profiles/system` for
   staleness, and `onSuccess` is replaced by a gated
   `myAutoUpdate.onDeployUnits`. See below.
3. ~~**Container resource ceilings**~~ — **done 2026-08-27** for
   `--memory` and `--pids-limit`, build-verified, **not deployed**. D15
   answered "no container may exceed 50% of host memory" →
   `--memory=7g` on both, plus `--pids-limit` 512 (factorio) and 1024
   (minecraft). `--cpus` is still unset and undecided. The user framed
   the memory figure as an estimate rather than a measurement, since the
   servers are idle playerwise; see D15 in `user-actions.md` for the
   caveat that both containers share the same 50% cap. Original note
   follows.

   No `--pids-limit`/`--memory`/`--cpus`
   on any container. **First measurement taken 2026-08-27** and recorded
   in `TODO.md`: `factorio-main` peaked at 1.06 GB / 19 pids,
   `minecraft-vanilla-plus` at 4.90 GB / 123 pids, both with
   `memory.max = max` and the host-default `pids.max = 19038`. Minecraft's
   real RSS is ~0.9 GB above its `MEMORY = "4G"` JVM heap, confirming why
   that setting must not be used to size the ceiling.

   `--pids-limit` can be set from this now with huge margin. `--memory`
   **cannot** — the containers had 37 minutes uptime and were idle, and
   `memory.peak` resets on restart, so this is a floor, not a peak.
   Needs either a load-representative window or a user decision on a
   generous blast-radius bound. **That is the open question, and it is
   the user's.**
4. **`userns-remap` unset** — container uid 0 is host uid 0 on every bind
   mount. Re-maps existing volume ownership, so it needs its own VM test.
5. ~~**Deploy `torrent` and `thinkpad`**~~ — **done 2026-09-01**, as part
   of the ninth session's zrepl-key rotation; see above. ~~vps still
   carries a stale DNAT rule for the deleted 34198~~ — **vps deployed
   2026-08-27 (generation 4)**, and that DNAT is gone; see the vps section
   below. All four hosts are now deployed to this branch.

### User-only

`user-actions.md` is the live checklist. ~~Its **§0 is time-critical** —
the two timers above.~~ **Stale, corrected 2026-09-01 (eleventh
session):** both timers were resolved in the third session (see "READ
THIS FIRST" above — `scheduleEnable = false` fleet-wide stopped them),
and this paragraph was never updated to match. ~~Unchanged headline:
rotate the ten credentials from `F-P8-02`.~~ **Also stale, same
correction:** rotation closed 2026-09-01, see "Rotation — done" above —
this line was contradicting that section in the same file.

Still open: **D1, D2, D4, D5, D6, D7, D8, D12**, plus **D15** (container
`--memory` ceiling — blocks half of the resource-ceilings item) and
**D16** (confirm the new deploy-staleness thresholds; not blocking),
both added in the fourth session. ~~D11 is time-critical.~~ **Not
time-critical** — same stale-timer correction above; D11 itself (the
`flake-update-test` auto-merge re-evaluation) is still genuinely
unanswered, just not on a clock. Also the factorio
account token is still exposed in ZFS snapshots and restic backups taken
before `/srv/factorio/new` was deleted, and is the **same** credential
`factorio-main` uses.

---

## Obligations for every session — do these, not just the fix

Each of these was rediscovered the hard way by a later session, usually
because the instruction lived somewhere you only find *after* you needed
it. They are cheap; skipping them is what makes the next pick-up
expensive.

- **Read [`AGENTS.md`](../../../AGENTS.md) first, before the audit
  docs.** It is the map to `docs/`, and it carries two things nothing
  here repeats: **you have real SSH** (`ssh root@homelab` — a bare
  `ssh homelab` fails as `lilijoy` and is *not* evidence of no access),
  and **this machine is `torrent`**, so run local commands rather than
  SSHing to it. The fourth session skipped this, concluded the fleet was
  unreachable, and wrongly marked a live measurement blocked.

- **Record every new user-only decision in
  [`user-actions.md`](user-actions.md)** — that file is the single
  checklist the user works through, and a decision recorded only in a
  commit message or in this file's prose will be missed. Its own header
  says so, but you only read that header if you happened to open it, so
  it is repeated here. The fourth session produced two new decisions
  (D15, D16) and only filed them when asked. Give each one a `D<n>`,
  say what it blocks, and say **why it is the user's** rather than an
  agent's. Note D15/D16 deliberately do *not* go in
  `accepted-risks.md` §2 — that section is for risks that could be
  accepted, not for sizing and threshold choices.

- **Log the plan and its state in a plan file**, not only in this file.
  `TODO.md` was **retired on master 2026-08-28** in favour of
  `docs/plans/{todo,in-progress,done,rejected}/` — load the `plan` skill
  for the scripts and the append-only rules, and the `workflow` skill for
  when a change needs a plan at all. Two things that bite: plans are
  cited by **bare filename with no folder path** (so a citation survives
  the file moving between folders, and a stale one fails *silently*
  rather than loudly), and filenames are **date-first**
  (`2026-08-28-<slug>.md`). Never hand-`mv` a plan or hand-write its
  frontmatter; use the scripts.

- **Correct the record when evidence contradicts it, in place.** Three
  claims in these docs turned out to be wrong when someone finally read
  homelab's journal (the outage duration, "nothing watches this", and
  "nothing anywhere would have told you"). An audit doc that is trusted
  and wrong is worse than one that is obviously stale, and the wrong
  claims here were load-bearing — they changed what the remaining work
  was *for*. Strike through or annotate rather than silently rewriting,
  so a reader can see the correction happened.

- **Harvest anything generalisable into `docs/hardening.md`.** Findings
  that become standing rules move there; risks knowingly left in place
  move to `docs/accepted-risks.md`. Update the rule count in `AGENTS.md`
  when you add one, and **do not renumber existing rules** — several are
  cited by number from `TODO.md` and `remediation.md`.

- **Finish with what only the user can do.** Say plainly what is
  undeployed, what is undecided, and what is on a clock.

## Rules and traps

- **Never `switch` without being asked.** homelab was switched on
  2026-08-27 on explicit instruction; that is the only host, and it was
  the first switch of the whole audit.
- **Never decrypt or edit `secrets/*`** (`docs/procedures/secrets.md`).
- **If it is a human decision, put it to the user** — do not decide it
  and report afterwards. This was corrected during this session.
- **Verify the fix, not the build.** Several fixes here would have built
  cleanly while doing nothing. Check the *rendered* artefact (the
  firewall script, the unit's start script) or the evaluated config.
- **Build locally, deploy with `--target-host`**; leave `--build-host`
  unset (`docs/procedures/workflow.md`).
- Commit messages: Conventional Commits, subject **≤88 chars**, scope
  must be **lowercase** (`[a-z0-9._-]+`, enforced by the hook),
  `security` is a *type* not a scope. **No `Co-Authored-By` or
  `Claude-Session` trailers** (`docs/GIT_WORKFLOW.md`).

**Traps hit across all three sessions:**

- `if cmd | tail` takes `tail`'s exit status — and `grep … | head || echo`
  can never fire its fallback. This produced one **wrong conclusion**
  reported to the user before it was caught. Capture real exit codes.
- An unprivileged `ip6tables -S` returns what looks like an empty chain
  when it is really `Permission denied`.
- **A bare `''` inside a Nix indented string terminates it**, including
  inside what reads as a shell comment.
- `inherit` is a Nix keyword — zrepl's `recv.properties.inherit` must be
  written `"inherit" = [ … ]`.
- `modules/flake/hosts.nix` was **already unformatted at HEAD**; check
  before running `nixfmt` on a file.
- Checking the wrong sysctl key (`ip_forward` vs `conf.all.forwarding`).
- **A passing VM test is not proof.** The egress bug above passed
  eleven-subtest coverage and was caught only by deploying.
- **Exact-string assertions on rendered rules are brittle** — they failed
  on a *correct* change while proving nothing extra. Match components.
- **A failed bare `ssh homelab` is not evidence of no access.** It fails
  as `lilijoy` with "Permission denied (publickey)"; `ssh root@homelab`
  works. `AGENTS.md` says this explicitly and the fourth session still
  briefly concluded the fleet was unreachable and marked a live
  measurement blocked. **This machine is `torrent`** — run local commands
  rather than SSHing to it. `vps` is Tailscale-only; `torrent` and
  `thinkpad` set `PermitRootLogin = "forced-commands-only"` and accept no
  interactive root SSH by design.
- **`nix eval` is unavailable to a sandboxed agent session here** — the
  harness refuses the command. `nixos-rebuild build` plus reading the
  rendered unit out of `./result` gets the same answer, and is what the
  "verify the fix, not the build" rule wanted anyway.
- **A command that prints nothing may not be on `PATH`.** `ipset list`
  returned empty on vps and read as "the sets are gone"; they were fine,
  `ipset` just was not on root's interactive `PATH`. `jq` likewise.
  **Both are now installed fleet-wide** via
  `modules/flake/debug-tools.nix` — if something else is missing, add it
  there rather than reaching for a `/nix/store` path (see `AGENTS.md`).
  `iptables`, `ip6tables` and `ss` were on `PATH` all along.
- **Do not put backticks inside `git commit -m "…"`.** Bash runs them as
  command substitution and silently eats the word — it removed `inputs`
  from one commit message this session. Use a message file, or no
  backticks.
- **`nix eval` and heredocs to paths outside the worktree are refused**
  by the harness in this session type. `nixos-rebuild build` plus reading
  `./result`, and `python3 - <<EOF` writing *inside* the worktree, both
  work.
- **The user pushes back, and is usually right.** Three corrections this
  session (the sops-key ordering, the Tailscale keys, unstable for debug
  tooling) came from being challenged, and each time the challenge was
  correct. Check the claim against the repo before defending it.
**Traps added in the sixth session:**

- **A rotated secret does not reach a running consumer.** Three services
  reported a clean activation (`modifying secrets: …`, zero failed units)
  while still using the old value: WireGuard's `wg0` interface (a
  `RemainAfterExit` oneshot that reads `privateKeyFile` only at link
  creation), the factorio container (bakes credentials into
  `server-settings.json` at start), and earlier the Discord webhook. Use
  `restartUnits` — and note it fires on *content change*, so adding it
  cannot repair the state that revealed the problem; that needs one
  manual restart. Restic was the exception: its wrapper reads
  `passwordFile` per invocation. **Check which kind you have; do not
  assume either way.**
- **A systemd exit code 0 can mean "skipped".** `push-deploy-vps` hit its
  branch guard, logged `Not on master … skipping this scheduled run`, and
  reported `Result=success ExecMainStatus=0`. The credential it was meant
  to test was never used. Read the log, not the status — and prefer
  exercising the credential directly.
- **`myPushDeploy.flakeDir = "/etc/nixos"` makes a live host's working
  checkout an input to deploying a *different* host.** Whatever branch
  someone last used on homelab is what vps gets. This caused a real
  revert: homelab was deployed from a branch without the WireGuard
  rotation, which broke the tunnel and put back a Cloudflare token that
  had been deleted at the provider.
- **`protectedUnits` guards `auto-switch` only.** A manual
  `nixos-rebuild switch` consults nothing and will kill a running restic
  backup — losing the whole run, since restic has no resume, and leaving
  a lock that silently blocks the next *exclusive* operation while reads
  keep working. With schedules off fleet-wide, manual is the only path.
- **Non-exclusive locks make a broken repository look healthy.**
  `restic snapshots` and `key list` succeeded against a repo that had
  been locked for a week with a failed backup. "The credential works" and
  "the service works" are different claims.
- **`/nix/state/.zfs` is 0777 and `snapdir=hidden` is not a boundary** —
  it hides the directory from `readdir` but does not block traversal by
  path. Any local uid can read any snapshot's contents at the permissions
  they had when taken.
- **The harness refuses more shapes than the fifth session recorded**:
  `nix eval` piped into anything, multi-step compound commands it cannot
  prove stay inside the worktree, and heredocs writing outside it. Break
  them into plain separate commands, or use the Read/Edit tools — those
  are not subject to the same check.

- **When verifying a rendered unit, grep the payload, not the wrapper.**
  A `.service` file usually only holds
  `ExecStart=/nix/store/…-unit-script-<name>-start/bin/<name>-start`, and
  that store path is a *directory*. The fourth session twice concluded a
  change had not landed — once for `health-check`, once for the container
  `--memory`/`--pids-limit` flags — because it grepped the `.service` or
  the directory rather than `…/bin/<name>-start`. Both had landed
  correctly. A false "the fix did not apply" costs as much as a false
  "it did".
