# Audit state / resume point

Self-contained pick-up point for the **2026-08-26 fleet-wide security
audit + needed/used review**. Written to be read cold: everything a new
session needs is here or linked from here.

## Where things are

- **Branch:** `worktree-worktree-security-audit-plan`, pushed to origin,
  fully committed. The worktree it was built in has been released — make
  a new one from the branch (`git fetch && EnterWorktree`, then check the
  branch out) or work on the branch directly.
- **All audit output:** `docs/audits/2026-08-26/`
- **Plan of record:** the 2026-08-26 entry at the top of `TODO.md`
- **Nothing has ever been switched.** Every change is build-verified
  only, on homelab, vps, torrent and thinkpad.

| File | What |
|---|---|
| [`00-threat-model.md`](00-threat-model.md) | Adversaries (§5), trust boundaries (§4), **severity rubric (§6)**, recurring failure modes (§7), open questions (§8). Read §6 before rating anything. |
| [`findings.md`](findings.md) | **Start here.** Consolidated CRITICAL/HIGH/MEDIUM by root cause. §4 = eleven systemic rules for Phase 4. §5 = the eight user decisions. §6 = what is verified clean. |
| [`findings-tail.md`](findings-tail.md) | LOW/INFO consolidated + the **needed/used rollup** (§5.1 broken, §5.2 unused). |
| [`P0-findings.md`](P0-findings.md) | Cross-cutting findings + the finding schema. |
| `P1..P8-*.md` | The eight part reports, ~13,700 lines total. |
| [`remediation.md`](remediation.md) | The wave plan. |
| [`user-actions.md`](user-actions.md) | **Everything only the user can do**, as a live checklist: the free-and-reversible items, the ten credentials to rotate, the `secrets/*` edits agents may not make, and decisions D1–D11. Keep it current as remediation turns up more. |
| [`live-verification.md`](live-verification.md) | Every live check run, with commands and results. |

## Phase status

| Phase | State |
|---|---|
| 0 — threat model | **done** |
| 1 — eight part audits | **done** — 158 findings |
| 2 — consolidation | **done** |
| 3 — remediation | **wave 1 done**; wave 2 in progress; waves 3–4 not started |
| 4 — docs harvest | **not started** — `findings.md` §4 has the eleven rules to fold into `docs/hardening.md` |

Headline counts: **3 CRITICAL, 31 HIGH, 38 MEDIUM, 53 LOW, 35 INFO**,
consolidated into 3 CRITICAL clusters, 10 HIGH clusters, and 34 tail
entries.

---

## The three CRITICAL clusters, in one paragraph each

**C1 — the secrets architecture.** `.sops.yaml` has one
`creation_rules` entry naming all seven age recipients, so every host
decrypts all 31 secrets. The repo is **public**, so the ciphertext and
all 72 of its revisions are permanently downloadable, which makes
rotation **non-retroactive**. This has already bitten: `F-P8-02` proves
by ciphertext comparison (no decryption) that three *retired* vps age
keys were recipients of public revisions holding the byte-identical
**currently-live** values for ten credentials. The 2026-08-25 reinstall
rotated the recipient three times and one value out of thirty-one. Five
of eight parts found this independently.

**C2 — the desktop user is already fleet root, with no exploit needed.**
`~/.ssh/id_ed25519` on torrent is byte-identical to a key in
`flake.vars.publicSshKeys` (root on homelab/vps/isoimage, plus
`origin/master` push) and has no passphrase. Reading one file is the
whole attack. Plus root via the pull-deploy checkout four ways, the
`input` group as a keylogger, and `libvirtd` arriving invisibly via
`PC.nix:18` → `virtual-machines.nix:11`. **The `input` half is fixed**
in `d6236cb` — plover was declared unused, so the grant is gone rather
than narrowed. The rest of C2 stands.

**C3 — no backup copy is out of reach of a single root.** Live `zdata`,
`zbackup` and the offsite Backblaze copy all answer to the same uid 0 on
homelab. No `zfs allow`, no Object Lock, no append-only key, no offline
medium — and `ExecStartPre` sets B2 `daysFromHidingToDeleting=1`,
cutting offsite history to 24h.

---

## Phase 3 — what has landed

All build-verified on all four hosts. **Not switched.**

| Commit | What | Findings |
|---|---|---|
| `b51e328` | `health-check`'s `disk` group moved from the *user* to the unit (`SupplementaryGroups`), gated on `checkSmart` along with `CAP_SYS_RAWIO` | F-P3-02/P2-05/P7-05 |
| `b51e328` | Arithmetic-injection guard in `check_min_switch_interval`; remote timestamp validated as a decimal integer, fails **closed** | F-P7-03 |
| `3f2c418` | `/srv` tmpfiles rule fixed — was rejected as `Invalid age 'root'`, so `/srv` sat at 0755 its whole life | tail / PROMO-03 |
| `3f2c418` | `iso-autobuild` phantom `pull-deploy.service.service` unit — suffix now stripped | tail |
| `3f2c418` | `flake-update-test` given `openssh` on PATH and `/root` in `ReadWritePaths` | tail |
| `5682087` | Tailscale routing default inverted to `"client"`; homelab `mkForce "both"`; vps override and homelab's redundant sysctls removed together | F-P0-06/P1-06/P5-08/P3-20 |
| `ba8cd4e` | `initialPassword = "123456"` removed; inert `ssh` block deleted from the ACL reference copy | F-P1-03, F-P0-05/P8-12 |
| `40255bd` | `github.com` host key pinned fleet-wide, verified against GitHub's published fingerprint | F-P7-04/P3-05/P0-07 |
| `abdd049` | `myHealthAlerts` enabled on torrent and thinkpad, `checkSmart = false` on both; `sops.secrets.vps_caddy_env` deleted; `user-actions.md` added | F-P7-09, F-P2-13/P8-18, F-P8-11 |
| `6b623c0` | **wave 2 starts.** Full sshd baseline on both laptops as `settings`, `allowSFTP = false`; `docs/hardening.md`'s false `AllowTcpForwarding` claim corrected | F-P5-07, F-P2-09/P3-18 |
| `516ef31` | `nosuid` + `nodev` on both NFS client mounts; `noexec` considered and declined | F-P6-05 |
| `3ce7d7a` | `zfs-emergency-prune` sandboxed (**VM-tested**); `crowdsec-allowlist-tailnet` sandboxed and moved off root to the `crowdsec` user; `push-deploy-vps`'s false `ReadOnlyPaths` claim corrected | F-P6-06, F-P2-08, F-P7-06 |
| `e5744f5` | vps firewall no longer fails open: `ipset create` moved to its own unit, match-set rules guarded, raw chain torn down on stop (**VM-tested, including the drift scenario**) | F-P2-02 |
| `d6236cb` | **plover removed entirely** (user declared it unused), taking the `input` and `dialout` grants, the `uinput` udev rule, wooting.nix's duplicate grant and the `plover-flake` input with it — nine lock nodes gone | F-P1-01/P8-09, F-P8-21, F-P1-15 |

### Consequences to know before deploying any of it

- **`5682087` fails silently.** If homelab's `mkForce "both"` is ever
  lost while the advertise flags remain, the exit node and the
  `192.168.1.0/24` subnet route stop working with a clean build. Check
  `tailscale status` on homelab after deploying.
- **`3f2c418` makes a dormant mechanism live.** `flake-update-test` had
  never once completed; it now can, and it **auto-merges upstream input
  updates to `master` on build success alone** — and `master` is
  unattended fleet root. Decide before deploying, don't inherit it.
- **`40255bd` fails closed.** If GitHub rotates that key, unattended
  deploys stop until it is updated. That is the intended trade, but it
  is why F-P7-09 (nothing notices a failed deploy) matters.
- **`d6236cb` needs one live check: the Wooting keyboard.** Removing
  `input` from `wooting.nix` should be a no-op, because
  `wooting-udev-rules` grants access with `TAG+="uaccess"` rather than a
  group — but that is source-reading, not a keyboard. After the first
  switch, confirm it still types and that **wootility** still detects
  the device and can read/write profiles; that path talks to `hidraw`
  directly and is the part most likely to notice. Tracked in
  [`user-actions.md`](user-actions.md) §1. If it breaks, the fix is a
  `uaccess`-scoped grant, **not** putting `input` back.
- **`e5744f5` adds a unit whose failure is now the signal.** If
  `crowdsec-ipset-precreate` ever fails, the firewall still comes up but
  the CrowdSec pre-drop on DNAT'd game traffic is absent. That is the
  intended degradation, and it is why the unit must stay visible in
  `systemctl --failed` — do not "fix" a failing pre-create by adding
  `|| true` to it.
- **`3ce7d7a` changes who runs `crowdsec-allowlist-tailnet`.** It drops
  from root to the `crowdsec` user. If the tailnet exemption ever stops
  applying after deploying it, check that unit first — a CrowdSec that
  bans the admin's own tailnet IP is the failure this unit exists to
  prevent, and it was observed live on 2026-08-26.
- **`6b623c0` changes what SSH to the laptops can do.** Nothing in the
  repo relies on any of it, and nothing can log in interactively there
  today, but if that ever changes: `scp`/`sftp` to torrent and thinkpad
  no longer work (`allowSFTP = false`, and modern `scp` speaks SFTP);
  `ssh -L`/`-D` through them no longer works; and idle sessions are now
  dropped after 5 minutes (`ClientAliveInterval 60` ×
  `ClientAliveCountMax 5`). All three fail immediately and obviously
  rather than silently.
- **`abdd049` starts sending traffic to Discord from two new hosts.** The
  timer is `Persistent`, so a laptop returning from weeks offline fires
  one catch-up batch for everything that failed while it was down — that
  is the intended behaviour, and `cooldownHours = 6` keeps it to a batch
  rather than a repeat every 15 minutes. It also points both laptops at
  `homelab_discord_webhook`; re-point them if the `.sops.yaml`
  restructure gives them their own key.
- Removing `initialPassword` does **not** change an already-set
  password. thinkpad still needs checking.
- The ACL edit touched only the **reference copy**; the live policy is
  Tailscale console state and must be changed there too.

## Phase 3 — what is left

**Wave 1 is complete.** 1.7 and 1.9 landed; see the notes on both in
[`remediation.md`](remediation.md), which record two things a later
session would otherwise re-derive or get wrong:

- **1.7's plan row was wrong.** The nine `F-P8-11` items are *not*
  `sops.secrets` declarations — they are unreferenced keys inside
  `secrets/secrets.yaml`, so there is no repo-side fix and they are now
  tracked in [`user-actions.md`](user-actions.md) §3. The one genuine
  declared-but-unconsumed declaration, `vps_caddy_env`, is deleted.
- **1.9 closes only half of `F-P7-09`.** A *failed* deploy on a laptop
  is now visible; a *skipped* one still is not, because every guard in
  `deploy-guards.nix` ends in `exit 0` and so never enters
  `systemctl --failed`. Do not read "1.9 done" as "deploys are
  observable".

**Wave 2** — nine items, most needing a VM test. See
[`remediation.md`](remediation.md), whose per-item notes carry the
reasoning and the verification for each one done so far.

| # | Item | State |
|---|---|---|
| 2.1 | docker publishing past the firewall | not started |
| 2.2 | image/mod pinning | not started |
| 2.3 | laptop sshd baseline + doc correction | **done** (`6b623c0`) |
| 2.4 | `input` → `hardware.uinput` | **done** (`d6236cb`) — plover removed outright instead |
| 2.5 | NFS mount options | **done** (`516ef31`) |
| 2.6 | three under-sandboxed root units | **2 of 3 done** (`3ce7d7a`); `push-deploy-vps` deferred |
| 2.7 | fail-open `ipset create` | **done** (`e5744f5`) |
| 2.8 | `zfs hold` on `@blank` + `recv.properties.override` | **done** (`{{2.8}}`) — zrepl test extended, all 9 subtests pass |
| 2.9 | firewall interface-scoping (moved out of wave 1) | **blocked** on a user decision |

**Two things a next session should not re-derive.**

- **Prefer the finding over the wave-plan row when they disagree** — it
  has happened three times now (1.7, 2.5, and 2.6's `ReadWritePaths`).
  The rows are summaries; the findings are the analysis written against
  the file, with the `file:line` evidence.
- **`push-deploy-vps` is the one piece of 2.6 left**, and it is deferred
  on purpose, not forgotten. Its misleading comment is fixed; the
  sandbox is not applied. It needs a VM test with a *real remote target*
  because `PrivateTmp` and `ProtectSystem = "strict"` can break the SSH
  control-master path and nix's fetcher cache, and a wrong guess means
  vps silently stops updating with nothing to report it.

**2.9 is blocked on a user decision** — should KDE Connect, Steam remote
play and mDNS keep working on the LAN? It also needs a per-host
LAN-interface option (thinkpad declares no interface names) and thinkpad
online to test. Evaluated port inventory is in `remediation.md`,
including that **UDP 10400/10401 are opened by something outside this
repo and were never attributed**.

**Wave 4 / Phase 4** — fold `findings.md` §4's eleven rules into
`docs/hardening.md`, keep the threat model as a standing doc, write down
accepted risks, add a `docs/audits/` row to `AGENTS.md` (already done),
and log deferred items to `TODO.md`.

---

## Actions only the user can take

**Moved to [`user-actions.md`](user-actions.md)** — a live checklist, so
there is one place to work through rather than a summary here that
drifts from the findings. It carries the four free-and-reversible items,
the ten credentials to rotate, the `secrets/*` edits agents may not
make, and decisions D1–D11.

The four with the best ratio of value to effort, unchanged:

1. **`chmod 600 ~/.config/sops/age/keys.txt`** — currently 0644 on the
   daily driver, verified live. Free, reversible, should not wait.
2. **Rotate the ten credentials** from `F-P8-02` at each provider.
   Re-keying `.sops.yaml` does nothing retroactively; the repo is
   public, so only rotation at the provider retracts anything.
3. **`passwd -S lilijoy` on thinkpad** when it is next online — the one
   verification this audit still owes (`F-P1-03`).
4. **Check GitHub branch protection.** There is no CI anywhere and never
   has been (confirmed by full-history scan), so this is the only
   remaining control on fleet root.

**Agents: when remediation turns up a new user-only action, add a row to
`user-actions.md`.** Do not leave it in a finding or in prose here.

---

## Rules and traps for the next session

- Read-only against live hosts unless told otherwise. **Never `switch`.**
  **Never decrypt or edit `secrets/*`** (`docs/procedures/secrets.md`).
- SSH to **homelab and vps** is permitted (granted 2026-08-26) but
  read-only in practice — do not mutate a running machine even
  reversibly. A sysctl flip on the live subnet router was considered
  during this audit and rejected on those grounds.
- **Verify the fix, not just the build.** Several fixes here would have
  built cleanly while doing nothing. Check the *evaluated* config
  (`nix eval …config.…`) and read the pinned nixpkgs source where the
  behaviour matters.
- **Traps actually hit during this audit:**
  - `if cmd | tail` takes `tail`'s exit status — it reported four green
    builds on four failures. Capture the real exit code.
  - An unprivileged `ip6tables -S` returns what looks like an empty
    chain when it is really `Permission denied` swallowed by
    `2>/dev/null`.
  - **A bare `''` inside a Nix indented string terminates it**, including
    inside what reads as a shell comment. Cost two failed builds.
  - Checking the wrong sysctl key: the tailscale module sets
    `net.ipv4.conf.all.forwarding`, **not** `net.ipv4.ip_forward`.
- ~~**Known doc error:** `docs/hardening.md` says `AllowTcpForwarding`
  defaults to `no`.~~ **Fixed** in wave 2 item 2.3. It defaults to
  **`yes`**, as do `AllowAgentForwarding` and
  `AllowStreamLocalForwarding` — confirmed empirically by running
  `sshd -T` against the *old* rendered config, not just from the man
  page. The doc now also says to write these as `settings` rather than
  `extraConfig`, and to verify with `sshd -T`.
- **Known finding error:** `F-P6-03` says a compromised source sets
  `send.properties: true`. There is no such key — zrepl 0.7.0's is
  `send_properties` (`SendOptions`, `internal/config/config.go:95`), and
  the wrong spelling makes the daemon **refuse to start** rather than
  being ignored. Corrected in the 2.8 note and in the test.
- **Corrected during the audit:** the threat model originally claimed
  `docker` group membership on `lilijoy` was a privilege path. It is
  not — the group is never declared, so the membership is inert. Dead
  config, not a path.
- Commit messages: Conventional Commits, subject **≤88 chars**,
  `security` is a *type* not a scope.
