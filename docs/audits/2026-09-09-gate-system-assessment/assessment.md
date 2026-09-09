# First-principles assessment of the docs/plans/ + workflow-gate apparatus

Assessed 2026-09-09 by a fresh session, per the handoff in
`2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md`
("Pick-up point, 2026-09-09"). I did not build any of this. Everything below
was checked read-only in the worktree `map-plan-docs-channel-routing` at
commit `a55977e`; nothing was fixed or changed.

## Verdict, in one paragraph

This is not a ball of mud — it is the opposite failure. It is a coherent,
well-tested, internally consistent system whose enforcement layer has become
autocatalytic: the gates generate the defects the gates then find, the
review loop generates the fixes that re-trigger the review loop, and the
last several sessions of work produced 8,230 changed lines of which zero
touched the five NixOS hosts the whole thing exists to protect. **The plan
corpus is the asset. The blocking enforcement is the liability.** Keep the
record; demote the gates from blocking to advisory; delete the two lower
floors of the test-the-tester tower, which exist only to make blocking
gates safe to trust; replace the freeze/checksum machinery with a five-line
"no diffs under done/" check. The review subagents earned their keep on day
one as *tools*; they became a livelock only when their stamps became *locks*.

## 1. The handoff's numbers, verified

The handoff told me to run its commands rather than believe it. I did.

| Claim | Measured | Status |
|---|---|---|
| Gate machinery 5,140 lines | 5,056 (`wc -l scripts/gate-* docs/skills/*/scripts/* .githooks/*`) | ✓ (drift ≤2%) |
| Fleet 9,414 lines | 9,449 (`find hosts modules -name '*.nix' \| xargs wc -l`) | ✓ |
| Branch: 2,635 gate lines, ~6.3k plan prose, **0 fleet lines** | 2,635 / 6,374 / **0** (`git diff --numstat cfe6106..HEAD`) | ✓ exactly |
| This plan file 4,288 lines, 81 findings | 4,385 (grew with the handoff itself), 81 `### F` headings | ✓ |
| 255 findings across non-frozen corpus | 255 | ✓ |
| 52 non-frozen plans (41 todo, 11 in-progress); 102 total, 50 frozen | 41 / 11 / 102 / 50 | ✓ |
| gate-tests 136/0/4, ~1.6s | 136 passed / 0 failed / 4 residues, 2.1s | ✓ |
| gate-mutants 60 caught / 0 escaped, ~17s | 60/0, 17.1s wall — but **2m12s user CPU** | ✓ |
| verify-ladder ~25s per commit | 26.3s | ✓ |
| All 50 frozen checksums verify | all OK | ✓ |
| PR #69 red on plan-gate only | OPEN, single failing check: plan-gate | ✓ |
| Workflow docs 1,393 lines | 1,093–1,503 depending on which docs count; no command given | ~ (order right, basket unspecified) |

Two corrections to the incumbent framing, both small but directional:

- "56 of this plan's 81 findings are defects in the gate machinery itself"
  is an **undercount**. Reading all 81 titles: every single one concerns the
  gate scripts, the plan schema, or docs *about* the gates. Zero concern the
  fleet. The remaining 25 are doc-staleness findings about the apparatus's
  own documentation.
- "A 60-mutant catalogue run on every push" (the task framing) is not quite
  right: `.githooks/pre-push` runs `checks.gate-mutants` only when the push
  touches `scripts/ docs/skills/ .githooks/ tests/ modules/flake/`. The
  cost is conditional — though in recent history, nearly every push touched
  those paths, because nearly every push *was* gate work.

One second-order fact the handoff doesn't state: six of the 81 findings
(F25, F51, F58, F66, F79, F80) are the *same finding recurring* — "every
harness number quoted in the docs is a session old again." The system
requires its docs to quote its own measurements, its measurements change
every session, and the review loop flags the drift every time. That is
machinery generating its own maintenance, on the record, six times.

## 2. Outside the repo

The handoff is right that this is the largest gap: every rule here was
derived from this repo's own incidents, none checked against practice or
evidence. Checked now.

### Code review (Bacchelli & Bird ICSE 2013; Sadowski et al. ICSE-SEIP 2018)

At Microsoft, finding defects is the top *stated motivation* for review,
but the measured *outcomes* are dominated by comprehension, knowledge
transfer, and team awareness; defect discussion is a minority of review
content. Google's decade of convergent practice: small changes, usually
one reviewer, fast turnaround, and review valued substantially for
education and maintaining norms.

**Transfer:** partial, and it cuts both ways. "Reviewed" is mostly a
knowledge-transfer claim, not a defect-finding claim — so a *mandatory,
blocking* review subagent is being asked to deliver something reviews
mostly don't deliver. But the knowledge-transfer half transfers in a
mutated form: agent sessions are amnesiac, so "transfer to the team"
becomes "write durable context for the next session." That is an argument
for the *plan corpus*, not for review *gates*.

### Mutation testing (Petrović & Ivanković, Google; Just et al. FSE 2014)

Just et al. establish mutation testing's validity (mutant detection
correlates with real-fault detection independent of coverage), so the idea
isn't junk. But Google's industrial practice is the *shape* evidence:
diff-based, at most one sampled mutant per line, arid lines filtered out,
"unproductive" mutants actively suppressed, no mutation score — because
developer attention is the scarce resource and unproductive mutants burn
it. This repo runs the opposite shape: a hand-curated, permanently growing
60-entry catalogue, all entries already caught, re-run on every gate-touching
push at ~3 CPU-minutes per run, whose maintenance produced three defects in
the catalogue runner itself (F42–F44) and whose own author had to invent a
policy for equivalent mutants (the "contract granularity" lesson in the
2026-09-08 pick-up) that Google's tooling handles by suppression.

**Transfer:** strong. One operator plus a finite agent budget *is* the
scarce-attention regime Google's filtering exists for.

### Change approval (DORA / Accelerate)

The clearest external result, and the most damning. Formal external change
approval correlates negatively with lead time, deploy frequency, and
restore time, with **no** improvement to change-failure rate; organizations
with it are 2.6× more likely to be low performers; the recommended
substitute is intra-team peer review plus automation. `plan-gate` — which
blocks merge on unresolved findings *and* stale stamps from two obligatory
reviewers — is structurally a change-approval board for one person.

**Transfer:** the study population is teams, and the "external body" here
is a process rather than people, so the numbers don't transfer literally.
But the *mechanism* of harm DORA identifies — approval friction → larger
batches → slower lead time → no stability gain — is visibly reproducing
here: PR #69 is 23 commits and 8,230 lines, red for days on two stamps,
with nobody blocked on its content.

### Decision records (Nygard ADRs; RFC/PEP processes)

Nygard's original proposal is one or two pages per architecturally
significant decision, plain prose, cheap to write, status changes instead
of edits. RFC/PEP-style processes assume a large community that must reach
consensus asynchronously. This repo's D/G/F item scheme — typed, numbered,
per-file, script-managed, lint-enforced, citation-checked, with resolution
markers, carry chains, and a provenance-system plan on the backlog — is a
heavier mechanism than PEPs use, for an audience of one human and their
agents. And the repo *already knows this*: `docs/adr/` exists with
ADR-0001, a README, a sane bar ("hard to reverse, surprising without
context, a real trade-off"), and an open migration plan
(`2026-09-05-migrate-existing-architectural-decisions-into-docs-adr.md`).
The conventional solution is already installed and idling next to the
bespoke one.

### Agent-governed repos (AGENTS.md and kin)

The convention that actually settled by 2026: a single instructions file
(AGENTS.md, now Linux-Foundation-stewarded, ~60k repos), plus ordinary CI.
The one measured effect: human-written agent context files improve task
success ~4% (ETH Zurich 2026). Nothing resembling stamp fingerprints,
review livelocks, or frozen-plan checksum manifests has emerged anywhere
as practice. This repo is not behind the convention; it is off to one
side of it, unaccompanied.

### The empirical comparison: real NixOS config repos

Checked directly via the GitHub API, 2026-09-09:

- **Misterio77/nix-config**, **EmergentMind/nix-config**,
  **oddlama/nix-config**, **hlissner/dotfiles** — no `.github/workflows`
  at all. Zero CI.
- **wimpysworld/nix-config** — a TOML-schema lint, an on-demand image
  builder, a flake-input freshener.
- **Mic92/dotfiles** — the most instructive, because Mic92 is among the
  heaviest agent users in the Nix world: an `@claude` GitHub-app trigger,
  auto-merge, on-demand debug sessions, host builds handled by external
  buildbot infrastructure, asynchronously. No plan corpus, no gates.

So the baseline for even sophisticated, agent-driven personal NixOS repos
is: *flake check / host builds in CI, an agent instructions file, and
nothing else*. What this repo gets for the difference, on the evidence of
its own finding log, is protection of the apparatus from the apparatus.

## 3. The internals, on their own terms

### What was it built to prevent? (origin)

`2026-08-27-establish-the-workflow-and-plan-file-system.md` records a user
request for structure — citeable plan files replacing TODO.md, hard-gated
workflow, review subagents — informed by real incidents: unreliable skill
auto-invocation (G1/G2), an agent deleting the checksum manifest during
testing (G4), footer leaks, work drifting uncited. Two things stand out:

1. **The day-one value was real and came from the reviews-as-tools, not
   the gates.** The first `security` invocation found an SMB password hash
   needlessly flowing into offsite backups and an IPv4-only `hosts allow`
   pair inert for Tailscale IPv6 — genuine fleet findings.
2. **The system's own weak-points catalogue concedes the enforcement can't
   stop a non-cooperative agent.** Its entries: every hook is
   `--no-verify`-bypassable by design (G3); the `security` agent's
   read-only guarantee rests on prompt trust because it holds Bash (F19);
   a commit can satisfy `plan-touch-guard` with an unrelated plan and
   `plan-gate` with silence, "governed by no plan at all" (F36+G1). So the
   gates are soft against the misbehaving session and hard against the
   cooperative one — they tax exactly the sessions that don't need them.

The failure class that *is* worth hard enforcement in a single-operator
NixOS repo — pushing a config that doesn't build onto machines you'll sit
down at later — is guarded by the conventional part (pre-push host builds,
flake checks, VM tests), which predates none of this controversy and works.

### What does it cost now?

- **Stock:** 5,056 lines of machinery + ~1.1–1.5k lines of docs about it,
  guarding 9,449 lines of fleet. Within the machinery, `gate-tests` (1,432)
  + `gate-mutants` (619) = 2,051 lines — **40% of the machinery exists to
  test the machinery.** The actual enforcement (plan-gate, plan-lint,
  hooks, verify-ladder) is ~1,000 lines; `lib.sh` is 890 more.
- **Flow:** verify-ladder 26s per non-trivial commit; pre-push builds up
  to five hosts on fleet-touching pushes and runs the 17s (3 CPU-min)
  mutation catalogue on gate-touching pushes.
- **Attention (the real cost):** this branch consumed multiple sessions,
  produced 81 findings and 8,230 changed lines, and advanced the fleet by
  zero lines, while 52 plans of real fleet work sat untouched. Roughly 16
  of the 41 todo plans are about the apparatus itself, including twelve
  filed on a single day (2026-09-06) and one that exists to measure
  whether the review loop is spinning.

### Does the recursion terminate?

Formally, three levels: gates → `gate-tests` (tests the gates) →
`gate-mutants` (tests gate-tests). Defects were found at every level,
including in the mutation runner itself (F42–F44), and the finding log
already points at level four: F75 — "the runner of the mutation catalogue
is the one gate with no gate-tests case and no gate-mutants entry."
Each level manufactures the justification for the next. Every defect any
level ever found was a defect in the apparatus.

The regress is not madness — it is the *price of making the gates
blocking*. A blocking gate that fails open is worse than no gate, so
blocking gates genuinely do need the fail-closed sweeps and the harness;
F47 (23 call sites silently running with an empty repo root) and F73
(new-branch pushes building no host at all) prove those sweeps work. But
that logic runs equally well in reverse: **demote the gates to advisory
and the reliability requirement collapses, and the whole tower has
nothing to hold up.** The recursion terminates by removing its reason,
not by winning it.

### The livelock is the model being wrong, not a bug in one gate

The design docs confirm the handoff's structural description: any
actionable finding restarts the loop at `/simplify`; a finding can only
end FIXED, MOOT, or ACCEPTED; ACCEPTED needs the user; every fix moves a
fingerprint that covers comments, re-staling both reviewer stamps. The
designed escape valve — "if the same finding recurs across passes, seek
the user's sign-off" — *is* manual intervention; the loop cannot terminate
autonomously unless a pass finds literally nothing.

The hidden assumption is that reviewer findings are a monotonically
draining queue of pre-existing defects. With LLM reviewers that assumption
is false: on any nontrivial surface they have a positive floor rate of
findings, and the repo measured this itself — the churn plan records that
later rounds' findings were consequences of earlier rounds' fixes, that
two of the most serious findings all session were defects *the loop
introduced*, and that convergence is "indistinguishable, from the outside,
from the loop spinning." Round counts 11 → 10 → 3 → 2 (the last two being
a cost comment 0.4s stale and an incomplete gloss) ended by the user
pulling the cord. F80's own title concedes the design flaw: "neither is
worth a fingerprint cycle on its own" — the system contains findings that
its own rules make unparkable and its own author judges not worth the
cycle they force. When a system's finding log argues with its gate rules,
the model is wrong. Verdict on Q4: **evidence the model is wrong**, not a
bug in plan-gate.

### Counterfactual

Strip the apparatus back to the conventional baseline (flake checks,
pre-push/CI host builds, AGENTS.md, ADRs, a todo list) and replay the last
two weeks:

- The ~4 sessions this branch consumed would have been available for the
  actual backlog: backups/restore, ZFS restructuring, log monitoring, the
  security audit, `/srv` permissions.
- Every defect the gates found would be moot, because every defect the
  gates found was in the gates.
- The two real fleet findings from day one would survive, because they
  came from *invoking* a review subagent, which needs no gate.
- The genuinely valuable knowledge — the USB/UAS investigation, the ZFS
  decisions, the audit — would exist in plainer files, since it was
  written by sessions, not extracted by enforcement.
- What would actually be lost: the frozen-history tamper-guard (whose
  threat — an agent quietly editing an old note — is bounded by git
  history anyway) and the guarantee that no PR merges with an unresolved
  security finding (recoverable with a far smaller mechanism; see below).

## 4. Recommendation

**Keep, as-is:**

- **The plan corpus.** 102 files of real operational memory. It is the one
  part of this apparatus that the outside evidence (review-as-knowledge-
  transfer, measured value of agent context files) actually supports, and
  it is the part no comparison repo has. Nothing below deletes a word of it.
- **Pre-push host builds, flake checks, diff-scoped statix/deadnix, VM
  tests.** Conventional, aligned with DORA's "automation over approval,"
  and guarding the one failure that really hurts. If the 5-host build
  latency chafes, move it to async CI (the Mic92 pattern) — a placement
  change, not a policy change.
- **The review subagents as invocable tools.** `security` on
  secrets/exposure-adjacent diffs demonstrably pays. Run them because they
  find things, not because a stamp is owed.

**Cut:**

- **Stamp fingerprints, stamp staleness, and blocking on them.** This is
  the CAB-for-one, and both the DORA evidence and this repo's own three
  rounds of livelock say it buys no stability for real throughput cost.
  With it goes the structural livelock, PR #69's redness, and the entire
  "harness numbers are a session old again" finding family.
- **The mandatory-finding-resolution merge block, in its current form.**
  Findings become parkable: a finding may be left open with a note, and
  the human merges when satisfied. If one hard rule is kept, keep the
  narrowest: block only on *unresolved CRITICAL/HIGH security findings* —
  a ~20-line check, not the current apparatus.
- **`gate-mutants` and most of `gate-tests`.** They are the tower's lower
  floors; advisory gates don't need a mutation-tested test suite. Keep a
  small smoke test for whatever scripts survive. This alone removes ~2,000
  lines, the 3-CPU-minute push tax, and the F42–F44/F75 class of work
  forever.
- **The freeze/checksum machinery** (`.checksums` manifest, `plan-freeze`,
  `plan-repair`, the pre-commit frozen check, `plan_record_checksum` and
  its retinue). This one subsystem produced the largest defect cluster in
  the log (F54–F57, F59–F65, F77–F78: manifest destroyed while reporting
  success, space-in-filename bypass, non-atomic cross-device replace,
  duplicate-entry lockout…) to defend historical notes that git already
  content-addresses perfectly. Replace with a convention ("done/ is
  append-never") plus, if wanted, a five-line CI check that a PR's diff
  touches nothing under `docs/plans/done/`.

**Rebuild on the conventional pattern:**

- **Decisions → `docs/adr/`.** The migration plan already exists; execute
  it. New architecturally significant decisions get an ADR; the D-item
  scheme stops growing. G-items become ordinary prose in docs. F-items
  from real reviews become plain "Findings" prose in the plan file —
  un-numbered, un-linted, un-gated.
- **Plan lifecycle → folders plus honesty.** Keep `plan-new`/`plan-move`
  if they're pleasant; drop `plan-lint`/`plan-citations`/`required-agents`
  to warn-only or delete them. A dangling citation in a personal knowledge
  base is a broken link, not a build failure.

**Leave alone:** AGENTS.md and the operational conventions (dedicated
service users, hardening baseline, secrets policy, no-local-restart,
VM-before-deploy). None of this was ever the problem.

**Sequencing note:** this is one deliberate teardown plan executed once —
not a new era of gate work. The single riskiest step is cutting plan-gate
in the same breath as the checksum machinery, so stage it: (1) make stamps
advisory and merge #69's content on its merits, (2) replace freeze
checksums with the done/-immutability check, (3) delete the mutation
tier, (4) shrink gate-tests to a smoke test, (5) start the ADR backfill.
Each step deletes more than it adds or it's being done wrong.

## 5. What I'm uncertain about

- **The counterfactual's discipline effect.** I cannot measure whether the
  plan-file habit is *why* this repo's operational record is unusually
  good. The corpus predates the heavy gates (the audit's citation scheme
  came first), which suggests the habit survives without the enforcement —
  but that is inference, not evidence. If the user finds that without
  blocking gates the sessions stop writing plans, some lighter forcing
  function (a warn-only nag) may be worth re-adding.
- **Agent-compliance drift over time.** The gates exist partly because
  skill auto-invocation is unreliable (~50% per the repo's own research).
  Advisory-only process leans harder on AGENTS.md being followed. The
  measured effect of instructions files is positive but small; whether
  that suffices here is only knowable by trying.
- **The literature's scale.** Every cited study is team-scale. I've argued
  transfer case by case (DORA's *mechanism* transfers; review's
  knowledge-transfer benefit mutates into context-writing; Google's
  mutant-filtering transfers because attention scarcity transfers), but
  none of it was measured on one-human-plus-agents setups. Nobody's was;
  this repo is ahead of the evidence, not behind it.
- **PR #69 itself.** I deliberately did not touch it. Its *content* (the
  schema revision) looked internally sound in everything I read, but I did
  not review it as a change; clearing it was excluded from this task.

## 6. The gates and this assessment (observed, as instructed)

- The session harness required worktree isolation and refused compound
  commands mid-assessment — that's the harness, not the repo's gates.
- The repo's gates never fired on me, because I stayed read-only — which
  is itself the finding: the apparatus is invisible to reading and heavy
  on writing, and the write path is where the fleet work happens.
- The most telling pressure was softest: the `plan` skill's description
  instructs its use "whenever recording a decision/finding," which means
  the default path for recording *this verdict* runs through the machinery
  being judged — and had it been followed, this assessment would now be a
  lint-checked, citation-checked plan file awaiting two review stamps. The
  user preempted that, correctly. A governance system whose evaluation
  reflexively becomes its next governed artifact is the precise shape of
  the recursion problem described in §3.

## Sources

- Bacchelli & Bird, *Expectations, Outcomes, and Challenges of Modern Code
  Review*, ICSE 2013 — https://sback.it/publications/icse2013.pdf
- Sadowski et al., *Modern Code Review: A Case Study at Google*,
  ICSE-SEIP 2018 — https://sback.it/publications/icse2018seip.pdf
- Petrović & Ivanković, *State of Mutation Testing at Google*, ICSE-SEIP
  2018 — https://research.google.com/pubs/archive/46584.pdf
- Just, Jalali, Ernst et al., *Are Mutants a Valid Substitute for Real
  Faults in Software Testing?*, FSE 2014 —
  https://dl.acm.org/doi/10.1145/2635868.2635929
- DORA, *Streamlining change approval* (Accelerate 2019 findings) —
  https://dora.dev/capabilities/streamlining-change-approval/
- Nygard, *Documenting Architecture Decisions*, 2011 —
  https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions
- AGENTS.md convention — https://asdlc.io/practices/agents-md-spec/ (spec,
  adoption, Linux Foundation stewardship); ETH Zurich 2026 measurement via
  https://www.tembo.io/blog/agents-md
- Repo survey via GitHub API, 2026-09-09: Mic92/dotfiles,
  Misterio77/nix-config, EmergentMind/nix-config, oddlama/nix-config,
  hlissner/dotfiles, wimpysworld/nix-config
- This repo: the 2026-09-07 schema plan (81 findings, pick-up points), the
  2026-08-27 origin plan and known-weak-points catalogue, the 2026-09-06
  churn-measurement plan, `docs/skills/workflow/reference.md`,
  `.githooks/pre-push`, and the measurements tabulated in §1.
