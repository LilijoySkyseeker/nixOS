# Audit state / resume point

Written so this audit can be picked up cleanly in a new session. Last
updated 2026-08-26, after Phase 1 part reports P1, P3, P4, P6, P7
landed.

**Branch:** `worktree-worktree-security-audit-plan`
**Worktree:** `.claude/worktrees/worktree-security-audit-plan`
**Plan of record:** the 2026-08-26 entry at the top of `TODO.md`

---

## ACT ON THIS FIRST — live key exposure

Not a finding to schedule. A live credential sitting in plaintext.

`/tmp/homelab_zrepl_key` on **torrent**, mode `0600`, dated 2026-08-23.
Verified: its fingerprint
`SHA256:JS5LDYWdmPp6XL7nGRvm7hg/LpqwXmANuM/iSnemX6I` matches
`vars.zreplPullerKey` (`modules/flake/vars.nix:14`) exactly — this is
the live private half of homelab's zrepl pull key, which holds
forced-command root SSH on torrent and thinkpad.

`/tmp` is not a separate mount on torrent, so the file lives on the ZFS
root dataset: **40 snapshots of `zroot/local/root` contain it**, and
those replicate to homelab's `zbackup` and onward into the offsite
Backblaze restic repository.

Deleting the file does not retract it. Remediation is rotation:
generate a new keypair, update `vars.zreplPullerKey` and the
`homelab_zrepl_key` sops secret (manually — agents never touch
`secrets/*`), redeploy both source hosts so the old public half stops
being authorised, then deal with the snapshot copies. Found by P7
(F-P7-02); P6 owns the rotation mechanics.

---

## Phase status

| Phase | State |
|---|---|
| 0 — threat model | **done** — `00-threat-model.md`, `P0-findings.md` (F-P0-01..08) |
| 1 — part audits | **5 of 8 in**: P1, P3, P4, P6, P7. **Outstanding: P2 (vps), P5 (workstations), P8 (supply chain/secrets)** |
| 2 — consolidation | not started — produces `findings.md` |
| 3 — remediation waves | not started |
| 4 — documentation harvest | not started |

If resuming with P2/P5/P8 still missing, check whether their report
files exist in `docs/audits/2026-08-26/`. If a file is absent, that
part must be re-dispatched; the prompts follow the pattern recorded in
`TODO.md`'s Phase 1 section, and every agent must be given
`00-threat-model.md` + `P0-findings.md` (schema) + `docs/hardening.md`
to read first.

---

## Running tally (5 of 8 parts)

**2 CRITICAL-or-equivalent, 11 HIGH.** Counts by part: P1 3H/3M/6L/4I ·
P3 3H/7M/7L/7I · P4 1H/5M/5L/4I · P6 1C/3H/3M/5L/3I · P7 5H/6M/6L/1I.

### The through-line

Three findings from three independent parts converge on the same
thing, and it is the audit's headline:

**`.sops.yaml` has a single `creation_rules` entry naming all seven age
recipients.** Every host decrypts every secret. Combined with F-P0-08
(the repo is public, so the ciphertext and all 72 of its revisions are
permanently downloadable, and rotation is therefore *not retroactive*),
any single age key ever obtained decrypts the fleet's entire secret
history. P3 adds that homelab's age key *is* its SSH host key and exists
in plaintext in four places including inside the offsite Backblaze
repo. thinkpad has no FDE. Found independently by P6 (F-P6-01,
CRITICAL), P1 (F-P1-02) and P3 (F-P3-01). **P8 owns the remediation
design and had not reported at the time of writing.**

### Other items needing a human decision

- **F-P0-01** — unsigned `origin/master` is unattended fleet root.
  P7 confirmed there is **no CI anywhere, ever** (full-history scan,
  zero workflow files), so no PR-trigger path exists — but branch
  protection is console state only the user can check. P7 also found
  that nothing would alert on a failed deploy: `myHealthAlerts` is not
  enabled on torrent or thinkpad at all.
- **F-P0-03 / F-P7-01 — CONFIRMED**, four independent mechanisms. The
  simplest needs no trick at all: `git merge --ff-only` is a silent
  no-op exiting 0 when HEAD is ahead, so `lilijoy` commits locally on
  `master` and root builds and boots it. Fix required regardless of the
  F-P0-01 decision.
- **F-P6-03 / F-P3-03** — the fleet cannot survive root on homelab.
  Live `zdata`, `zbackup` and the Backblaze copy all answer to the same
  uid 0; `ExecStartPre` sets B2 `daysFromHidingToDeleting=1`. No Object
  Lock, no append-only key, no offline medium.
- **F-P3-10** — answers the standing TODO question: **no**, homelab is
  not gated entirely by tailscale. `wg0` and vps's DNAT put A1/A3 on
  homelab code with no device authorization in the path.

### Corrections already folded into the threat model

- §4.3 path 1 (`docker` group) **refuted** — the group is never
  declared, so the membership is inert. Replaced by `input` (keylogger,
  HIGH) and `libvirtd` (arrives transitively, invisible in `PC.nix`).
- §2/§2.1 — the "CGNAT illusion" is **not homelab-only**; torrent holds
  a live routable IPv6 GUA with a v6 default route.
- `docs/hardening.md` says `AllowTcpForwarding` defaults to `no`. It
  defaults to **`yes`** (pinned OpenSSH 10.4p1). Any conclusion resting
  on that sentence needs rechecking — a Phase 4 doc fix.

---

## Rules that must carry into any resumed session

- Read-only with respect to config. No `switch`. Never decrypt or edit
  `secrets/*` (`docs/procedures/secrets.md`).
- SSH to homelab and vps is permitted (user granted 2026-08-26),
  read-only. Do not escalate to root locally on torrent.
- **A silent permission failure can look like a clean result.** An
  unprivileged `ip6tables -S` returned what appeared to be an empty
  firewall chain; it was `Permission denied` swallowed by `2>/dev/null`.
  Never report an empty ruleset without confirming the read succeeded.
- Live checks belong in `live-verification.md` with the commands used.
- Severity comes from `00-threat-model.md` §6, naming an adversary from
  §5. CONFIRMED vs PLAUSIBLE labels must stay honest.
