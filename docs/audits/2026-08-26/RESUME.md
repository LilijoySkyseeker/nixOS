# Audit state / resume point

Self-contained pick-up point for the **2026-08-26 fleet-wide security
audit + needed/used review**. Written to be read cold: everything a new
session needs is here or linked from here.

**Last updated: 2026-08-27, end of the fourth session.**

---

## READ THIS FIRST — two clocks are running

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

- **Branch:** `worktree-worktree-security-audit-plan`, pushed, clean,
  **42 commits ahead of master**. Live worktree at
  `.claude/worktrees/worktree-security-audit-plan` — enter that rather
  than making a new one.
- **All audit output:** `docs/audits/2026-08-26/`
- **Plan of record:** the 2026-08-26 entry at the top of `TODO.md`
- **homelab is deployed** (first switch of this audit, 2026-08-27).
  `vps`, `torrent` and `thinkpad` are **build-verified only, never
  switched**.

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
  now a `TODO.md` entry. **It fires Wed Sep 2.**

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

## What is left

### Agent-doable, unblocked

1. **`push-deploy-vps` sandboxing** — the last third of wave 2 item 2.6,
   deferred on purpose. Needs a VM test with a **real remote target**,
   because `PrivateTmp` + `ProtectSystem = "strict"` can break the SSH
   control-master path and nix's fetcher cache. A wrong guess means vps
   silently stops updating — though that is now *detectable*, since vps
   watches its own profile mtime (see item 2).
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
5. **Deploy `vps`, `torrent`, `thinkpad`** if the user wants — all
   build-verified, never switched. vps still carries a stale DNAT rule
   for the deleted 34198. **homelab is now one deploy behind this
   branch too**: the fourth session's changes are build- and VM-verified
   but not switched anywhere.

### User-only

`user-actions.md` is the live checklist, and its **§0 is time-critical**
— the two timers above. Unchanged headline: **rotate the
ten credentials from `F-P8-02`** — the largest unmitigated risk in the
audit, and nothing an agent does moves it. The repo is public, so only
rotation at each provider retracts anything.

Still open: **D1, D2, D4, D5, D6, D7, D8, D11, D12**, plus **D15**
(container `--memory` ceiling — blocks half of the resource-ceilings
item) and **D16** (confirm the new deploy-staleness thresholds; not
blocking), both added in the fourth session. **D11 is time-critical.**
Also the factorio
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

- **Log the plan and its state in [`TODO.md`](../../../TODO.md)**, not
  only in this file. It is the repo-root entry point a session reaches
  for before assuming a described feature is deployed.

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
- **When verifying a rendered unit, grep the payload, not the wrapper.**
  A `.service` file usually only holds
  `ExecStart=/nix/store/…-unit-script-<name>-start/bin/<name>-start`, and
  that store path is a *directory*. The fourth session twice concluded a
  change had not landed — once for `health-check`, once for the container
  `--memory`/`--pids-limit` flags — because it grepped the `.service` or
  the directory rather than `…/bin/<name>-start`. Both had landed
  correctly. A false "the fix did not apply" costs as much as a false
  "it did".
