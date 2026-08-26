# Audit state / resume point

Written so this audit can be picked up cleanly in a new session. Last
updated 2026-08-26, after **all eight Phase 1 part reports landed**.

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
| 1 — part audits | **DONE — all 8 in** (P1..P8) |
| 2 — consolidation | not started — produces `findings.md` |
| 3 — remediation waves | not started |
| 4 — documentation harvest | not started |

**Next action: Phase 2 consolidation** — dedupe the nine reports
(P0..P8) into a single ranked `findings.md`, separating systemic
findings (a class repeated across hosts, which become new
`docs/hardening.md` rules) from one-offs. Roughly 145 findings across
~11,000 lines of report.

---

## Running tally — all 8 parts

**3 CRITICAL, 19 HIGH**, ~145 findings total. By part: P1 3H/3M/6L/4I ·
P2 1H/7M/6L/7I · P3 3H/7M/7L/7I · P4 1H/5M/5L/4I · P5 6H/1M/7L/4I ·
P6 1C/3H/3M/5L/3I · P7 5H/6M/6L/1I · P8 2C/3H/6M/6L/6I · plus P0 F-P0-01..08.

### Worst single finding — F-P8-02 (CRITICAL)

**Three *retired* vps age keys decrypt today's live credentials out of
public git history.** `secrets/secrets.yaml` has had 14 distinct age
recipients across its 72 revisions; only 7 are current. P8 established
by ciphertext comparison alone — no decryption — that each of the three
vps keys retired during the 2026-08-25 reinstall was a recipient of a
public revision containing the **byte-identical current** ciphertext for
`homelab_vps_deploy_key`, `homelab_zrepl_key`,
`homelab_backblaze_restic_password`, `cloudflare_octodns_token`, both
WireGuard private keys, the PSK, and three tailscale auth keys.

The reinstall rotated the *recipient* three times and rotated exactly
**one value out of thirty-one** (`tailscale_authkey_vps`). That is the
concrete, already-happened instance of F-P0-08's "rotation is not
retroactive": the ciphertext is public and permanent, so retiring a key
accomplishes nothing unless the *values* are rotated at the provider.

Remediation is value rotation at each provider (Backblaze, Cloudflare,
tailscale, WireGuard, and the deploy/zrepl keypairs), not re-keying.
Manual, per `docs/procedures/secrets.md`.

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
repo. thinkpad has no FDE. Found independently by **five** parts — P6
(F-P6-01), P1 (F-P1-02), P3 (F-P3-01), P2 (F-P2-01) and P8 (F-P8-01,
which owns the three-step remediation: restructure `.sops.yaml` → move
values → **rotate at the provider**, since re-keying alone fixes
nothing retroactively).

Two shorter paths to the same place, both CONFIRMED:
`/home/lilijoy/.config/sops/age/keys.txt` is an age secret key at mode
**0644** on the daily driver (verified live; parent dirs 0755, so only
`/home/lilijoy` being 0700 protects it) — P5 F-P5-02, P8 F-P8-03. And
`~/.ssh/id_ed25519` on torrent is **byte-identical** to the third entry
in `flake.vars.publicSshKeys`, i.e. root on homelab/vps/isoimage plus
`origin/master` push, with no passphrase — P5 F-P5-01, P8 F-P8-04. A7
needs no escalation at all.

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
- **Tailnet ACL drift is live, not hypothetical** — P8 found an
  untagged Android phone (`Pixel 6a`) is a tailnet member covered by
  `autogroup:member` in all four grants and appears nowhere in the
  repo. Also: the highest-value fix for F-P0-04 is not the ACL but
  `trustedInterfaces = ["tailscale0"]` on vps, which leaves that host
  with no packet filter at all from the tailnet.
- **torrent's 102 host-wide ports are not currently internet-reachable**
  — probed from vps, filtered by the ISP CPE (see
  `live-verification.md`). But the CPE is a coincidence, not a control:
  unversioned, unmanaged, and worth nothing to thinkpad when roaming.

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
