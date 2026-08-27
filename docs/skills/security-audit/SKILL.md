---
name: security-audit
description: Run a full multi-agent security and dead-config audit of this repo — threat model, parallel part audits, consolidation, remediation waves, documentation harvest. Use when asked for a security audit, a hardening pass, a "what's exposed" review, or an "is this config still needed" sweep across the fleet. Also use when re-auditing after major architectural change.
---

# Fleet security audit

The method used for the 2026-08-26 fleet-wide audit, written down so it
can be re-run. That audit produced 158 findings across ~6.9k lines of
Nix, of which three were CRITICAL and several were things that had been
silently broken for the entire life of the config.

**Read [`reference/lessons.md`](reference/lessons.md) before starting.**
It is short, and every item in it is a mistake that was actually made
during the last run — including two of mine that would have shipped
wrong conclusions if they hadn't been caught by checking.

## When this is worth running

- After a structural change (a new host, a migration, a
  refactor like the dendritic move).
- When something turns out to be exposed that you believed was not —
  the last run was triggered by discovering homelab's LAN NIC had a
  real public IPv6 address, which invalidated an assumption behind
  every host-wide firewall rule on the box.
- Periodically, because the needed/used axis decays continuously.

Not worth running for a single service or a single suspicion — just
look at that thing.

## The shape of it

Five phases. Do not skip Phase 0; it is what makes the eight parallel
reports comparable instead of eight private opinions.

```
Phase 0  threat model              (single agent, you)
Phase 1  part audits               (one subagent per part, parallel)
Phase 2  consolidation             (you; delegate the LOW/INFO tail)
Phase 3  remediation, in waves     (you, build-gated)
Phase 4  documentation harvest     (you)
```

Output lives in `docs/audits/<date>/`. The last run's is the worked
example throughout this document — read it alongside this.

---

## Phase 0 — threat model

Write `docs/audits/<date>/00-threat-model.md` **before looking for
findings**. Its job is to make severity mean one thing across every
later report.

It must contain, at minimum:

1. **Assets, ranked.** What is worst to lose. Last run put the backup
   pools first, because losing those turns every other incident
   permanent.
2. **An exposure map** — per host: real public v4, real public v6, what
   actually listens. This is the section most likely to be
   misremembered, and misremembering it is what caused the finding that
   triggered the audit. Verify it live rather than reading it out of
   the config.
3. **Principals** — the distinct identities that can cause something to
   happen. Not Unix users: `origin/master` is a principal here, because
   a commit to it becomes root on four hosts.
4. **Trust boundaries, and what crossing one buys.** The useful
   question is never "is X reachable" but "if X falls, what falls with
   it".
5. **Adversaries**, labelled `A1..An`, with a judgement about
   plausibility for *this* fleet. Later findings cite these by id.
6. **A severity rubric** — see [`reference/finding-schema.md`](reference/finding-schema.md).
7. **Recurring failure modes** — patterns this repo has produced at
   least once. This is the highest-value section: it tells the part
   agents what to actively hunt for rather than passively notice.

**Anything you assert here gets cited `file:line` and verified.** Last
run, nine of twenty-eight citations were wrong on first write and were
corrected before publishing. A threat model with wrong references
teaches eight agents wrong things.

Phase 0 will itself produce findings — cross-cutting ones no single
part would see. Write them into `P0-findings.md` in the standard
schema, not as prose, or consolidation will drop them.

---

## Phase 1 — part audits

### Splitting

Split so each part is **coherent enough to audit without the others**,
and assign every cross-cutting concern to exactly one owner so findings
don't arrive eight times. The split used last time, with sizes, is in
[`reference/part-split.md`](reference/part-split.md).

The principle that mattered most: split by *blast radius and trust
role*, not by directory. `modules/profiles/` is its own part because
every host inherits it. The deploy machinery is its own part because it
is "what can run code as root fleet-wide".

### Dispatching

One subagent per part, in parallel. Use
[`reference/subagent-brief.md`](reference/subagent-brief.md) as the
prompt template — it is the one from the last run, which produced
usable reports from all eight agents on the first attempt.

Non-negotiable elements of the brief:

- **Read the threat model, the finding schema, and `docs/hardening.md`
  first.** In that order.
- **Read-only with respect to config.** No edits, no `switch`, never
  decrypt `secrets/*`.
- **Verify against the pinned nixpkgs, not from memory.** Option
  defaults differ by version and that is exactly where a hardening
  assumption silently fails. `nix eval .#nixosConfigurations.<host>.config.<option>`
  gives the *effective merged* value, which frequently differs from
  what any single file says. This is the single most valuable
  instruction in the brief.
- **Both axes.** Hardening *and* needed/used. Dead config is a finding:
  an unowned firewall hole or group membership is attack surface
  either way.
- **CONFIRMED vs PLAUSIBLE, honestly.** A consolidation pass that
  cannot trust the labels is worthless.
- **Name an adversary from §5.** "An attacker could" is not a
  reachability statement.

### Feeding corrections mid-flight

Agents start cold and run for 20–40 minutes. When something material
changes — last run it was learning the repo is public on GitHub —
message every running agent with the correction. That single message
changed severity ratings across all eight parts.

---

## Phase 2 — consolidation

Do this yourself. It is judgement work and fragmenting it defeats the
point.

1. **Extract the schema fields mechanically first.** ~13,700 lines of
   report will not fit in context. Parse `### F-` blocks into an index
   of id/severity/title/reachability, then read full text only where
   dedup and ranking need it.
2. **Cluster by root cause, not by part.** The most important result of
   the last audit was that a handful of causes accounted for nearly all
   the severity — five of eight parts independently arrived at the same
   `.sops.yaml` finding.
3. **Promote deliberately, and show the reasoning.** Three clusters
   were promoted above their parts' ratings. A promotion that hides its
   logic is just an assertion.
4. **Separate systemic from local.** Systemic = one class of mistake
   repeated across hosts. Those become `docs/hardening.md` rules and
   matter far more than their individual severity suggests.
5. **Validate coverage mechanically.** Check every cited id exists and
   every CRITICAL/HIGH/MEDIUM finding is carried over. Last run this
   caught four dropped findings and one bad cross-reference.

Delegating the LOW/INFO tail to one subagent is worthwhile — it is
mechanical clustering over ~86 findings, and keeping that detail out of
your context is the point. It also produced the two best *classes* of
the whole audit, which were only visible reading the tail as a whole.

---

## Phase 3 — remediation

Waves, not one branch. See
[`reference/wave-planning.md`](reference/wave-planning.md).

Ordering that worked: **Wave 0** live/out-of-repo actions →
**Wave 1** zero-decision config fixes → **Wave 2** things needing a VM
test → **Wave 3** user decisions and manual secret work.

Gates, per this repo's own rules:

- `nixos-rebuild build --flake .#<host>` for **every** affected host.
- **Verify the fix in the evaluated config, not just that it builds.**
  Building proves it compiles. `nix eval` proves it does what you
  meant. These are different, and the gap is where wrong fixes hide.
- VM test where *behaviour* changes.
- **Never `switch`** without being asked.

---

## Phase 4 — documentation harvest

The audit's durable output is not the fixes, it is the knowledge.

- Systemic findings → new rules in `docs/hardening.md`, phrased the way
  that file phrases rules: imperative, with the reason.
- Corrections to existing rules. Last run found `docs/hardening.md`
  stated `AllowTcpForwarding` defaults to `no`; it defaults to `yes`.
  A wrong default in the standing rulebook propagates into every future
  service.
- The threat model becomes a durable doc — every future "should I
  expose this?" decision is a question about it.
- **Accepted risks get written down with their reasoning**, so a future
  pass doesn't re-litigate them.
- Deferred remediation → `TODO.md`.
- Add a row to `AGENTS.md`'s "Where things live" table for anything new.

---

## Generalizing this to a different repo

This document is deliberately specific to this repo — the examples are
real findings, and that is what makes them teachable. Adapting it
elsewhere is a substantial edit, not a search-and-replace. What
transfers unchanged, and what doesn't:

**Transfers as-is:** the five-phase shape; Phase 0 preceding all
findings; the finding schema; CONFIRMED vs PLAUSIBLE; both axes;
cluster-by-root-cause; systemic vs local; build-then-*verify*; every
item in `lessons.md` except the Nix-syntax one.

**Needs rewriting:** the part split (derive from that repo's blast-radius
structure); "verify against pinned nixpkgs" becomes "verify against the
pinned dependency versions" — lockfile, image digest, vendored tree,
whatever pins that stack; the gates (`nixos-rebuild build` → that
repo's build/test); `docs/hardening.md` → wherever its conventions
live.

**Needs re-deriving entirely:** the threat model, the adversary list,
and the recurring failure modes. Those are properties of the system,
not of the method, and copying another system's are worse than having
none.
