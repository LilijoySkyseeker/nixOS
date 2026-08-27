# Lessons — read before starting

Every item here is a mistake actually made during the 2026-08-26 run,
or a trap that run walked into. They are cheap to avoid once named and
expensive to discover twice.

---

## Verification traps

### A silent permission failure looks exactly like a clean result

Running `ip6tables -S nixos-fw 2>/dev/null` as an unprivileged user
returned **nothing**, which read as "the firewall chain is empty" — an
alarming finding. It was `Permission denied`, swallowed by the
redirect. Reporting an empty ruleset on that basis would have been
badly wrong.

**Rule:** never report an absence without confirming the read
succeeded. Drop the `2>/dev/null`, check the exit code, or run a
control query you know should return something.

### A pipeline hides the exit code you care about

```bash
if nixos-rebuild build --flake ".#$h" | tail -6; then echo OK; fi
```

This reports **OK on every failure**, because the pipeline's status is
`tail`'s. It printed four green builds on four broken ones. The error
was only caught because a later `nix eval` failed and the message
pointed at a file that "built fine".

**Rule:** capture the real exit code. No pipe on the command whose
status matters, or use `PIPESTATUS`.

### Building is not verifying

A config that builds is a config that *parses and evaluates*. It is not
a config that does what you meant. Every fix in Wave 1 was checked with
`nix eval` against the merged config afterwards, and that is what
proved, for example, that the `disk` group had actually moved off the
user and onto the unit — and that it correctly evaluated to `[]` on the
host where `checkSmart` is false.

**Rule:** build, then `nix eval` the specific option you changed, on
every affected host.

### `''` terminates a Nix indented string, including inside a comment

Adding a shell `case` pattern of `'' | *[!0-9]*)` inside a
`deployGuardsScript = ''...''` broke evaluation. Fixing it by writing a
*comment* that mentioned `''` broke it again — Nix does not know the
comment is a shell comment.

**Rule:** inside `''...''`, use `""` for an empty shell pattern, and
never write a bare `''` anywhere in the fragment, prose included.

---

## Reasoning traps

### Check the grant exists before rating it

The threat model asserted that `docker` group membership on the login
user was a root-equivalent privilege path. `PC.nix` does list
`"docker"` in `extraGroups` — but `users.groups.docker` is never
declared anywhere in the repo, so the group does not exist and the
membership is inert. `getent group docker` returns nothing.

Meanwhile the two grants that *were* live — `input` (a raw keylogger,
because `/dev/input/event*` is `root:input 0660` with no uaccess ACL)
and `libvirtd` (arriving transitively via an import, invisible in
`PC.nix`'s own group list) — were missed on the first pass.

**Rule:** verify the grant resolves. And read the *evaluated* group
membership, not the file — transitive grants do not appear where you
expect them.

### "It builds and it's been fine for a year" is not evidence

Three mechanisms turned out to have never worked at all:

- `flake-update-test` had **zero** successful runs in 1371 commits, for
  two independent reasons (missing `openssh` on the unit PATH;
  `ProtectSystem = "strict"` making `/root/.cache/nix` unwritable).
- `myIsoAutobuild.triggeredBy` rendered a phantom
  `pull-deploy.service.service` unit, so the recovery ISO had never
  been rebuilt by the mechanism that exists to rebuild it.
- A `systemd.tmpfiles` rule was silently rejected (`Invalid age
  'root'`, because a `-` in the user field shifted every subsequent
  field right), leaving `/srv` at `0755` for its entire life — with
  game-server credentials in it.

None of these produced a build failure. All three were found by asking
"does this actually do anything?" rather than "is this configured?"

**Rule:** for anything whose job is to happen periodically, look for
evidence it has *happened* — a commit, an artefact, a journal entry.

### Age is anti-evidence for environment assumptions

A rule written when the network had no public addressing is *more*
suspect than a new one, not less, because the environment moved
underneath it. Both the homelab and torrent findings were of this
shape.

**Rule:** for any control justified by a belief about the environment,
re-verify the belief now, live.

### Distinguish the coincidence from the control

torrent's 102 host-wide ports are not currently reachable from the
internet — the ISP router filters inbound IPv6. That is a
*coincidence*: unversioned, unmanaged, invisible to `nixos-rebuild`,
and worth nothing to a laptop on a café network. Reporting it as "not
exposed" would have been true and useless.

**Rule:** say what is actually holding the property, and whether you
control it.

---

## Process traps

### Prose in a threat model gets dropped at consolidation

Phase 0's cross-cutting findings were initially written as narrative.
They would have been read as context and lost. Rewriting them into the
standard schema as `F-P0-01..08` is what got them into the final
ranking.

**Rule:** anything that is a finding goes in the schema, wherever it
was found.

### Compensating controls have to be verified too

Several findings' mitigation was effectively "we would notice". The
alerting path turned out to stamp an alert as sent *before* sending it,
abort the remaining checks on failure, wipe its dedup state every boot,
and not be enabled on two of four hosts at all. The audit independently
found three silent failures nothing had alerted on.

**Rule:** when a finding leans on detection, audit the detector.

### Fixing a dormant mechanism makes it live

Repairing `flake-update-test` means it will now, for the first time,
auto-merge upstream input updates to `master` — which is unattended
fleet root. Correct fix, real new behaviour.

**Rule:** when repairing something that has never run, say explicitly
what it will now start doing, and check that is wanted.

### Cite `file:line`, then check the citations

Nine of twenty-eight citations in the first draft of the threat model
were off. They were caught by a script that re-read every cited line.
Wrong references in a document eight agents treat as authoritative are
worse than no references.

**Rule:** validate citations mechanically before publishing anything
others will build on.
