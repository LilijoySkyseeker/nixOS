# Remediation waves

Sequence by *risk profile and who must decide*, not by severity. The
highest-severity finding is often the one you can least act on
unilaterally, and a wave that mixes "obviously correct" with "needs the
user's sign-off" stalls entirely.

## The waves

### Wave 0 — live, outside the repo

Things already exposed, where the fix is not a config change. Give
exact commands so nothing has to be re-derived.

From the last run: `chmod 600` on a world-readable age identity; a
leaked private key in `/tmp`; a `passwd -S` check on an offline host; a
GitHub branch-protection check.

**Watch the ordering.** Deleting the leaked key had to come *after*
rotation, not before — removing the file does not retract the copies
already in 40 ZFS snapshots and the offsite backup.

### Wave 1 — zero-decision config fixes

Unambiguous, no judgement call needed from the user, verifiable by a
build. **Land this first**, because it is the wave that can proceed
without blocking on anyone.

Good candidates: a grant that is on a user and belongs on a unit; an
injection fix; a malformed rule that is silently rejected; a broken
unit name; a missing PATH entry. All five of those were real Wave 1
items and all five were mechanical.

### Wave 2 — needs a VM test or staged rollout

*Behaviour* changes, not just config. Anything where getting it
backwards is connectivity-visible but not build-visible.

From the last run: changing how container ports are published;
inverting a fleet-wide default where the wrong direction silently
breaks routing; pinning images; tightening sshd on hosts you reach over
sshd; mount options that could break execution.

### Wave 3 — user decisions and manual secret work

Not agent work at all. Credential rotation, `.sops.yaml` restructuring,
buying immutability, accepting-or-fixing an architectural risk.

Order these by value and state the decision plainly. Do not present
options without a recommendation.

### Wave 4 — documentation harvest

Phase 4 of the audit proper. Systemic findings become standing rules.

## Gates

Every wave, per this repo's own rules:

- `nixos-rebuild build --flake .#<host>` for **every affected host** —
  and capture the real exit code (see `lessons.md`).
- **`nix eval` the specific option you changed**, on every affected
  host. Building proves it evaluates; only this proves it does what you
  meant.
- A VM test (`docs/procedures/vm-testing.md`) where behaviour changes.
- **Never `switch`** without being asked.
- Commit per coherent fix, not per wave — the commit message is where
  the reasoning lives.

## Two things to say out loud

**When a fix makes a dormant mechanism live.** Repairing something that
has never run is correct *and* introduces new behaviour. Last run,
fixing `flake-update-test` meant it would begin auto-merging upstream
updates to `master` — which is unattended fleet root — for the first
time ever. Flag it; don't let it be inherited silently.

**When you cannot verify something.** Say what would settle it and who
can run it. An honest "thinkpad is offline, this one check is
outstanding" is worth more than a confident guess, and it survives into
the next session's resume point.

## Keep a resume point

Long audits span sessions. Maintain `docs/audits/<date>/RESUME.md` with
phase status, what is outstanding, decisions waiting on the user,
corrections already folded in, and the standing rules. Update it when a
phase completes, not at the end — the value is entirely in it being
current when something interrupts.
