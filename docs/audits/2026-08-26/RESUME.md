# Audit state / resume point

Self-contained pick-up point for the **2026-08-26 fleet-wide security
audit + needed/used review**. Written to be read cold: everything a new
session needs is here or linked from here.

**Last updated: 2026-08-27, end of the third session.**

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

- `auto-switch` and `push-deploy-vps` had been **failing on every run
  since 2026-08-25** (see "The deploy outage" below). While broken, they
  could not have reverted anything.
- Commit `929efa3` fixed them, and homelab now runs it. **The revert
  mechanism is functional again.**

So: if the branch should survive past Thu, it must be **merged to
master** before then, or the timers stopped. That is a user decision and
has not been made. If the deploy was only ever meant as a test, the
revert is a free rollback and nothing needs doing.

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
| [`user-actions.md`](user-actions.md) | **Everything only the user can do**, as a live checklist, incl. decisions D1–D14. |
| [`live-verification.md`](live-verification.md) | Live checks with commands and results. |

Documentation harvested out of the audit into standing docs:
`docs/hardening.md` (ten standing rules), `docs/threat-model.md`,
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

**Both halves of the fleet's deploy path had been failing since
2026-08-25 and nothing noticed.** Found by accident while clearing an
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
dotfile another part of the system owns declaratively. And this is
`F-P7-09` demonstrated rather than argued — the failure sat in
`systemctl --failed` the whole time, so **the gap is notification, not
detection**.

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
   silently stops updating.
2. **The skipped-deploy half of `F-P7-09`** — a *failed* deploy is
   visible on the laptops now; a *skipped* one is not, because every
   guard ends in `exit 0`. The outage above argues the real gap is
   **notification**.
3. **Container resource ceilings** — no `--pids-limit`/`--memory`/`--cpus`
   on any container. Needs measured RSS off homelab, not a guess;
   minecraft's `MEMORY = "4G"` is JVM heap only.
4. **`userns-remap` unset** — container uid 0 is host uid 0 on every bind
   mount. Re-maps existing volume ownership, so it needs its own VM test.
5. **Deploy `vps`, `torrent`, `thinkpad`** if the user wants — all
   build-verified, never switched. vps still carries a stale DNAT rule
   for the deleted 34198.

### User-only

`user-actions.md` is the live checklist. Unchanged headline: **rotate the
ten credentials from `F-P8-02`** — the largest unmitigated risk in the
audit, and nothing an agent does moves it. The repo is public, so only
rotation at each provider retracts anything.

Still open: **D1, D2, D4, D5, D6, D7, D8, D11, D12**. Also the factorio
account token is still exposed in ZFS snapshots and restic backups taken
before `/srv/factorio/new` was deleted, and is the **same** credential
`factorio-main` uses.

---

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
