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
| [`live-verification.md`](live-verification.md) | Every live check run, with commands and results. |

## Phase status

| Phase | State |
|---|---|
| 0 — threat model | **done** |
| 1 — eight part audits | **done** — 158 findings |
| 2 — consolidation | **done** |
| 3 — remediation | **wave 1 nearly done**; waves 2–4 not started |
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
`PC.nix:18` → `virtual-machines.nix:11`.

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
- Removing `initialPassword` does **not** change an already-set
  password. thinkpad still needs checking.
- The ACL edit touched only the **reference copy**; the live policy is
  Tailscale console state and must be changed there too.

## Phase 3 — what is left

**Wave 1 remainder**
- **1.7** drop the nine declared-but-unconsumed `sops.secrets`
  declarations (`F-P8-11`); verify no consumer first.
- **1.9** enable `myHealthAlerts` on both laptops (`F-P7-09`) — today
  nothing anywhere reports a failed or skipped deploy. Needs a webhook
  secret reachable from each laptop; check what is declared first.

**Wave 2** (nine items, each needs a VM test — see
[`remediation.md`](remediation.md)): docker publishing past the firewall,
image/mod pinning, laptop sshd baseline, `input` → `hardware.uinput`,
NFS mount options, three under-sandboxed root units, the fail-open
`ipset create`, `zfs hold` on `@blank` + `recv.properties.override`, and
**2.9** the firewall interface-scoping moved out of wave 1.

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

1. **`chmod 600 ~/.config/sops/age/keys.txt`** — currently 0644 on the
   daily driver, verified live. Free, reversible, should not wait.
2. **Rotate the ten credentials** from `F-P8-02` at each provider:
   Backblaze, Cloudflare, tailscale, both WireGuard keypairs + PSK, the
   Discord webhook, the vps-deploy and zrepl keypairs. Re-keying
   `.sops.yaml` does nothing retroactively.
3. **Rotate the zrepl key, then** remove `/tmp/homelab_zrepl_key` — it is
   the live private half of `vars.zreplPullerKey`, mode 0600, dated
   2026-08-23, and sits on the ZFS root so **40 snapshots** plus the
   offsite copy already contain it. Deleting does not retract it.
4. **Restructure `.sops.yaml`** into per-path `creation_rules`; attribute
   or retire the five unattributable recipients (`F-P8-05`).
5. **`passwd -S lilijoy` on thinkpad** when it is next online — the one
   verification this audit still owes (`F-P1-03`).
6. **Check GitHub branch protection.** There is no CI anywhere and never
   has been (confirmed by full-history scan), so this is the only
   remaining control on fleet root.
7. **Delete the `ssh` block in the Tailscale console** to match the repo.
8. Decisions **D1–D8** in [`findings.md`](findings.md) §5.

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
- **Known doc error:** `docs/hardening.md` says `AllowTcpForwarding`
  defaults to `no`. It defaults to **`yes`** (pinned OpenSSH 10.4p1).
  Fix in Phase 4.
- **Corrected during the audit:** the threat model originally claimed
  `docker` group membership on `lilijoy` was a privilege path. It is
  not — the group is never declared, so the membership is inert. Dead
  config, not a path.
- Commit messages: Conventional Commits, subject **≤88 chars**,
  `security` is a *type* not a scope.
