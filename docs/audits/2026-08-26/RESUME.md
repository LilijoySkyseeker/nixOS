# Audit state / resume point

Pick-up point for the 2026-08-26 fleet-wide security audit. Last updated
during **Phase 3, wave 1**.

**Branch:** `worktree-worktree-security-audit-plan`
**Worktree:** `.claude/worktrees/worktree-security-audit-plan`
**Plan of record:** the 2026-08-26 entry at the top of `TODO.md`
**Nothing has been switched.** Every change is build-verified only.

| Phase | State |
|---|---|
| 0 — threat model | **done** — [`00-threat-model.md`](00-threat-model.md), [`P0-findings.md`](P0-findings.md) |
| 1 — part audits | **done** — all 8 (P1–P8), 158 findings |
| 2 — consolidation | **done** — [`findings.md`](findings.md) (C/H/M), [`findings-tail.md`](findings-tail.md) (LOW/INFO + needed/used) |
| 3 — remediation | **in progress** — see below. Plan: [`remediation.md`](remediation.md) |
| 4 — docs harvest | not started — `findings.md` §4 has the eleven rules to fold into `docs/hardening.md` |

Live evidence gathered along the way is in
[`live-verification.md`](live-verification.md).

---

## Phase 3 progress

### Landed — build-verified on all four hosts, not switched

| Commit | What | Findings |
|---|---|---|
| `b51e328` | `health-check`'s `disk` group moved from the *user* to the unit via `SupplementaryGroups`, and gated on `checkSmart` along with `CAP_SYS_RAWIO` | F-P3-02, F-P2-05, F-P7-05 |
| `b51e328` | Arithmetic-injection guard in `check_min_switch_interval` — the remote-supplied timestamp is validated as a decimal integer, failing closed | F-P7-03 |
| `3f2c418` | `/srv` tmpfiles rule fixed — it was rejected as `Invalid age 'root'`, so `/srv` sat at 0755 its whole life, exposing factorio's token and jellyfin's config | tail / PROMO-03 |
| `3f2c418` | `iso-autobuild`'s phantom `pull-deploy.service.service` unit — the `.service` suffix is now stripped, so the ISO rebuild can actually fire | tail |
| `3f2c418` | `flake-update-test` given `openssh` on PATH and `/root` in `ReadWritePaths`; it had never completed a single run | tail |
| `5682087` | Tailscale routing default inverted to `"client"`; homelab `mkForce "both"`; vps's redundant override deleted; homelab's redundant explicit sysctls removed in the same commit | F-P0-06, F-P1-06, F-P5-08, F-P3-20 |
| *this commit* | `initialPassword = "123456"` removed from `PC.nix` | F-P1-03 |
| *this commit* | Inert `ssh` block deleted from the tailnet ACL reference copy | F-P0-05, F-P8-12 |

### Still to do in wave 1

- **1.4** — interface-scope `PC.nix`'s host-wide openings: avahi, Steam
  remote play, and KDE Connect's 1714–1764 range (106 ports). The
  mechanism is already proven on these hosts, since port 22 is
  interface-qualified on torrent and nothing else is.
- **1.7** — drop the nine declared-but-unconsumed `sops.secrets`
  declarations (`F-P8-11`); verify no consumer first.
- **1.8** — pin `github.com` and `vps` in `programs.ssh.knownHosts` so
  the deploy path stops re-TOFUing every boot (`F-P7-04`, `F-P3-05`).
- **1.9** — enable `myHealthAlerts` on both laptops (`F-P7-09`): today
  nothing anywhere reports a failed or skipped deploy.

Waves 2–4 unstarted; see [`remediation.md`](remediation.md).

---

## Consequences of the fixes so far — read before deploying

- **`5682087` fails silently, not loudly.** If homelab's `mkForce
  "both"` is ever lost while the advertise flags stay, the exit node and
  the `192.168.1.0/24` subnet route stop working with a perfectly clean
  build. Check `tailscale status` on homelab after any deploy of it.
- **`3f2c418` makes a dormant mechanism live.** `flake-update-test` has
  never once run to completion; it now can, and it **auto-merges
  upstream input updates to `master` on build success alone**. Per
  F-P0-01, `master` is unattended fleet root. Decide whether that should
  continue before deploying, rather than inheriting it by accident.
- Removing `initialPassword` does **not** change an already-set
  password — it only stops publishing the value. thinkpad still needs
  checking; see below.
- The ACL edit touches only the **reference copy** in this repo. The
  live policy lives in the Tailscale admin console and must be changed
  there too, or the two have merely drifted further apart.

---

## Actions only the user can take

Ordered by value. None of this is agent work.

1. **Rotate the ten credentials** exposed by `F-P8-02`, at each
   provider: Backblaze, Cloudflare, tailscale, both WireGuard keypairs
   and the PSK, the Discord webhook, the vps-deploy and zrepl keypairs.
   Re-keying `.sops.yaml` does nothing retroactively.
2. **`chmod 600 ~/.config/sops/age/keys.txt`** — currently 0644 on the
   daily driver, verified live.
3. **Rotate the zrepl key, and only then** remove
   `/tmp/homelab_zrepl_key`; deleting it does not retract the 40
   snapshots and the offsite copy that already hold it.
4. **Restructure `.sops.yaml`** into per-path `creation_rules`, and
   attribute or retire the five unattributable recipients (`F-P8-05`).
5. **`passwd -S lilijoy` on thinkpad** when it is next online — the one
   verification this audit still owes (`F-P1-03`).
6. **Check GitHub branch protection.** With no CI anywhere (confirmed),
   this is the only remaining control on fleet root.
7. **Delete the `ssh` block in the Tailscale console** to match the
   reference copy.
8. Decisions D1–D8 in [`findings.md`](findings.md) §5.

---

## Rules that carry into any resumed session

- Read-only with respect to live hosts unless the user says otherwise.
  Never `switch`. Never decrypt or edit `secrets/*`
  (`docs/procedures/secrets.md`).
- SSH to homelab and vps is permitted (granted 2026-08-26) but
  **read-only in practice** — do not mutate a running machine even
  reversibly. A sysctl flip on the live subnet router was considered
  during this audit and rejected on those grounds.
- **Verify the fix, not just the build.** Several fixes here would have
  passed a build while doing nothing at all. Check the *evaluated*
  config (`nix eval …config.…`) and, where it matters, read the pinned
  nixpkgs source.
- **Two verification traps hit during this audit.** `if cmd | tail`
  takes `tail`'s exit status and reported green on four failed builds.
  And an unprivileged `ip6tables -S` returns what looks like an empty
  chain when it is really `Permission denied` swallowed by
  `2>/dev/null`.
- **A bare `''` inside a Nix indented string terminates it** — including
  inside what reads to a human as a shell comment. Cost two failed
  builds here.
- Commit messages must match Conventional Commits with a subject of ≤88
  characters, and `security` is a *type*, not a scope.
