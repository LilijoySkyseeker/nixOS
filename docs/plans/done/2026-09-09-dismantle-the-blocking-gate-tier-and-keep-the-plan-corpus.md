---
slug: dismantle-the-blocking-gate-tier-and-keep-the-plan-corpus
created: 2026-09-09
status: done
frozen: true
kind: task
priority: normal
blocked_by:
---

# dismantle the blocking gate tier and keep the plan corpus

## State

**2026-09-09, complete and merged.** Filed, ratified (D1-D5 that day, D5
refined to option (b) in discussion; D6 answered at merge time), executed
in eight stages on `worktree-gate-teardown` (based on PR #69's head,
deliberately — `G5`), and landed: PR #69 merged first via a temporary
ruleset bypass (added and removed the same hour), then PR #70 with the
whole teardown. Master's required `plan-gate` check is now the advisory
gate. The one defect found during close-out is recorded under `D6`'s
restored heading: a stage-1 edit silently consumed the `### D6` heading
line, and no surviving check flags a prose reference to a heading that
does not exist. What exists now:

- `plan-gate` blocks on exactly two rules — an unresolved CRITICAL/HIGH
  security finding in a cited plan, and any modification/deletion under
  `done/` or `rejected/` — and prints everything else as NOTEs. Stamps,
  required-agents obligations and ordinary findings no longer gate.
- The checksum manifest, `plan-repair`, `plan_record_checksum` and the
  manifest audit are deleted; frozen-by-residence is enforced at
  pre-commit, verify-ladder and the plan-gate CI range check.
- `gate-mutants` and its flake check are deleted; `pre-push` builds hosts
  only. `gate-tests` went 1,432 → 1,055 lines and 136 → 108 assertions —
  larger than the "couple hundred lines" this plan sketched, deliberately:
  the rung/State/lint/citation sections encode four sessions of real
  regressions in readers that still gate freezing, so they stayed; only
  the sections testing deleted machinery went. Suite green locally and as
  `checks.gate-tests` in the sandbox.
- `plan-lint`/`plan-citations` are warn-only in verify-ladder;
  `plan-freeze`/`plan-move done` hard-gate only on State, the rung
  declaration and critical findings (decisions and ordinary findings
  warn); the freeze-time lint subprocess was removed outright — the
  ladder already warns, and an advisory call inside a write-path gate
  made its git failures look like the gate's own (caught by the sabotage
  sweep).
- ADR-0002 (`0002-reviews-advise-two-checks-block.md`) records the
  governance decision. The docs pass covered both skills, testing-changes,
  GIT_WORKFLOW and both agent definitions; `security`'s brief now says
  its `**Severity:**` rating carries the one blocking rule.
- Twelve 2026-09-06 gate-hardening plans are rejected with reasons citing
  this file; the provenance plan stayed (G3's note).

Verified to rung 3 (ran it locally, output inspected): `gate-tests`
108/0/4 both direct and via `nix build .#checks.x86_64-linux.gate-tests`;
`verify-ladder` green end-to-end at ~25s; `plan-citations` resolves all
citations; the new plan-gate exercised against a critical-finding
fixture (blocks), a parked-finding fixture (passes with NOTE), a
tampered done/ file (blocks) and PR #69's formerly-red range (passes
with NOTEs). Rungs 4-5 do not apply: no host-visible behaviour changed
— the only `.nix` diffs delete a flake check.

Nothing is open. The follow-on work that outlives this plan lives in its
own files: the ADR backfill
(2026-09-05-migrate-existing-architectural-decisions-into-docs-adr.md),
the D4 probation review of the small hooks, and the provenance plan that
stayed in `todo/`.

## Original plan

The assessment's verdict: the apparatus is not a ball of mud — it is
coherent and well-tested — but its blocking enforcement tier has become
autocatalytic. All 81 of the schema plan's findings concern the apparatus
itself, none the fleet; the current branch changed 8,230 lines of which
zero touch `hosts/` or `modules/`; the review loop's livelock is
structural (findings cannot be parked, every fix re-stales both stamps),
and was stopped by hand after three rounds. The outside evidence points
the same way: DORA finds formal change-approval buys no stability for
real throughput cost; code-review research (Bacchelli & Bird ICSE 2013,
Sadowski et al. ICSE-SEIP 2018) shows "reviewed" is mostly a
knowledge-transfer claim, which supports the plan *corpus*, not the
*gates*; Google's mutation-testing practice (Petrović & Ivanković) is the
inverse of a permanently growing all-caught catalogue; and no comparable
NixOS config repo — including Mic92's heavily agent-driven one — runs
anything beyond CI builds plus an instructions file.

So: **keep the corpus, the host builds, the flake checks, the diff-scoped
lints, VM testing, and the review subagents as invocable tools. Dismantle
the blocking tier and the recursion that exists to make blocking safe.**
Each stage below should delete more than it adds; if one doesn't, it is
being done wrong. This is one teardown executed once, not a new era of
gate work.

The staged shape (each stage is one PR, master never left unprotected
mid-transition — see `G2`):

1. **Stamps become advisory.** `plan-gate` stops blocking on stale review
   stamps and missing obliged agents; it keeps at most the narrow finding
   block `D1` picks. The review loop in `workflow` becomes "run the
   reviewers, fix what's worth fixing, park the rest with a note" —
   findings gain a parkable state that does not block merge.
2. **Freeze by convention, not checksum.** Replace the `.checksums`
   manifest, `plan-freeze`'s hashing, `plan-repair`, and the pre-commit
   frozen check with a single check that a PR's diff touches nothing under
   `docs/plans/done/` or `docs/plans/rejected/` (`D2`). Git history is the
   integrity mechanism; this subsystem produced the largest defect cluster
   in the finding log (F54-F65, F77-F78 of the schema plan) defending
   files git already content-addresses.
3. **Delete the mutation tier.** `scripts/gate-mutants`, its
   `checks.gate-mutants` registration, and the pre-push hook section that
   runs it. Advisory gates do not need a mutation-tested test suite.
4. **Shrink `gate-tests` to a smoke test** of whichever scripts survive
   (`plan-new`/`plan-move`/the done-immutability check), on the order of
   a couple hundred lines, still run by `verify-ladder`.
5. **Demote `plan-lint` and `plan-citations` to warn-only** (or delete,
   `D4`). A dangling citation in a personal knowledge base is a broken
   link, not a build failure.
6. **Decisions move to `docs/adr/`.** Execute the already-open
   2026-09-05-migrate-existing-architectural-decisions-into-docs-adr.md;
   new architecturally significant decisions get an ADR; the D/G/F scheme
   stops growing in new plans (`D5`). The existing corpus is not touched.
7. **Docs pass** rewriting `AGENTS.md`, both skills' `SKILL.md`/
   `reference.md`, `docs/procedures/testing-changes.md`,
   `docs/GIT_WORKFLOW.md`, and `docs/agents/*.md` to describe the smaller
   system — and deleting the doc text that exists only to narrate the
   removed machinery.
8. **Close out the mooted backlog.** The gate-hardening plans this
   supersedes get `plan-reject` with a reason citing this file (`G3`),
   not silent deletion.

What stays untouched throughout: the 102-file plan corpus, pre-push host
builds (`D3` decides placement only), `nix flake check`, diff-scoped
statix/deadnix, the VM-test trust hierarchy, secrets policy, hardening
conventions, and the `security`/`docs-updater` agents themselves.

## Progress

- [x] Stage 0: user answers `D1`-`D6`; scope is ratified
      *(D1-D5 answered 2026-09-09; D6 answered at merge time the same
      day; hand-ticked because plan-tick correctly refuses the ambiguous
      D-references on this line)*
- [x] Stage 1: plan-gate advisory on stamps; findings parkable — see D1
- [x] Stage 2: done/-immutability check replaces freeze checksums — see D2
- [x] Stage 3: gate-mutants tier deleted
- [x] Stage 4: gate-tests shrunk to a smoke test
      *(landed at 1,055 lines, not ~250 — see State for why)*
- [x] Stage 5: plan-lint / plan-citations warn-only or deleted — see D4
- [x] Stage 6: ADR migration started; D/G/F frozen for new plans — see D5
      *(as refined: ADR-0002 written, notation stays optional-not-frozen;
      the 0005 backfill plan remains its own todo item)*
- [x] Stage 7: docs pass over AGENTS.md, skills, procedures, agents
- [x] Stage 8: mooted gate plans plan-reject'ed with reasons — see G3
      *(12 rejected; the provenance plan stayed, see G3's note)*
- [x] PR #69 disposition executed — see D6
      *(#69 merged 2026-09-09 via temporary ruleset bypass, then #70;
      hand-ticked, same plan-tick ambiguity as Stage 0)*

## Decisions (D)

### D1 — what, if anything, still blocks a merge?

Options: (a) nothing — reviews are purely advisory; (b) **recommended:**
block only on an unresolved CRITICAL/HIGH `security` finding, a ~20-line
check in `plan-gate`, everything else parkable; (c) keep the full
unresolved-findings block but drop only stamp staleness. The assessment
recommends (b): it keeps the one guarantee with teeth (the day-one samba
findings are the class it protects) while removing the livelock, whose
driver was trivia that could not be parked.


**ANSWERED 2026-09-09:** user said proceed with the plan's recommendations (2026-09-09): option (b), block only unresolved CRITICAL/HIGH security findings

### D2 — replacement for the freeze/checksum machinery

**Recommended:** delete `docs/plans/.checksums`, `plan-repair`, the
pre-commit frozen/manifest checks, and `plan-freeze`'s hashing; add one
check (in `plan-gate` CI, so it holds for every tool and human) that a
PR's diff contains no path under `docs/plans/done/` or
`docs/plans/rejected/`. Alternative: keep the manifest as-is and accept
its defect surface. Note `plan-move ... done` still needs *some* freeze
semantics — under the recommendation it just moves the file, and
immutability is enforced at the merge boundary instead of at write time.


**ANSWERED 2026-09-09:** proceed as recommended: delete checksum machinery, enforce done/-immutability at the merge boundary in plan-gate CI

### D3 — where do host builds run?

Keep the local pre-push five-host build (current behaviour), or move it
to async CI in the buildbot style Mic92 uses. **Recommended:** keep local
for now; this is a placement question orthogonal to the teardown, and the
local build is the single highest-value gate in the repo.


**ANSWERED 2026-09-09:** proceed as recommended: host builds stay in the local pre-push hook, unchanged

### D4 — fate of plan-lint and plan-citations

Warn-only (keep the scripts, print, never block) or delete outright.
**Recommended:** warn-only for one probation period, delete if the
warnings are only ever noise. `required-agents`, `subagent-stamp`,
`plan-touch-guard`, `footer-guard` and `mark-trivial` follow the same
choice: with nothing blocking on their output, keep only the ones whose
output is still read.


**ANSWERED 2026-09-09:** proceed as recommended: plan-lint/plan-citations warn-only probation; small hooks kept as-is during probation, disposition reviewed after

### D5 — do new plans keep the D/G/F item scheme?

**Recommended:** new plans use plain prose plus ADRs for real
architectural decisions; D/G/F, `plan-decide`, `plan-resolve`,
`plan-carry` and the resolution-marker vocabulary stop being required
(existing files keep resolving forever — nothing is renumbered or
migrated). Alternative: keep the scheme as optional structure for large
plans only.


**ANSWERED 2026-09-09:** proceed as recommended: new plans use plain prose plus ADRs; D/G/F and its scripts become optional, existing corpus untouched

**Refined 2026-09-09, in discussion with the user:** option (b) — the
*notation* stays, the *lifecycle* goes. D/G/F remains the house
convention for new plans (anchors stay citeable, `plan-decide`/
`plan-resolve` stay as conveniences, `**ANSWERED**` keeps meaning "the
user confirmed" — the sign-off-provenance value), but nothing requires
items, sequential numbering, or full drainage. Freeze semantics under
this: `plan-move ... done` still *refuses* on a missing/empty `## State`,
a missing rung declaration, or an unresolved CRITICAL/HIGH security
finding; unresolved ordinary findings and open decisions *warn* instead
of blocking. Security findings keep their structured `### F<N>` +
`**Severity:**` shape in whatever plan they land in — the `D1` merge
block parses exactly that. ADRs take only the decisions that meet the
ADR bar; small in-task decisions stay as D items.

### D6 — PR #69

*(Heading restored 2026-09-09: the stage-1 edit that appended D5's
refinement note accidentally consumed this heading line, leaving the
body below orphaned under D5. Nothing caught it — the lint has no rule
for a prose reference to a heading that no longer exists.)*

It is red on two stale stamps and nothing else; the branch is green
locally. Options: merge it on its merits once Stage 1 makes stamps
advisory; sign off on the stamps now and merge before the teardown;
or close it and fold its schema work into this plan's docs pass.
The assessment deliberately did not review its content as a change, so
merging it needs whatever review the user actually wants — as a decision,
not an obligation.


**ANSWERED 2026-09-09:** user chose: merge #69 first, then #70 -- both merged 2026-09-09. #69 needed a temporary repo-admin bypass actor on the master ruleset (rulesets ignore gh's --admin; added, used, removed, restored state verified as bypass_actors: []). #70 then retargeted onto master and merged. The old gate's stale-stamp block was bypassed deliberately rather than fed another review round

## Gotchas (G)

### G1 — the full assessment report lives outside the repo and is ephemeral

The complete written assessment (verified-numbers table, literature and
repo-survey citations, transfer analysis, uncertainty list) was delivered
as `gate-system-assessment.md` from a background job's tmp directory,
which is deleted with the job. If it should survive, copy it into the
repo (e.g. `docs/audits/`) before deleting the job; this plan restates
its conclusions but not its full reasoning.

### G2 — plan-gate is CI's only required check; never leave a stage with master unguarded

`plan-gate.yml` is the sole workflow and the sole required status check on
`master`. Stages 1 and 2 both edit it. Each stage must land the new check
in the same PR that removes the old one, and the ruleset's
required-check name must keep matching, or master briefly has either no
gate or an unsatisfiable one — the exact failure class
2026-09-06-stop-a-pr-from-weakening-the-ci-gate-it-is-judged-by.md
catalogues.

### G3 — the backlog this moots, to reject rather than delete

If this plan lands as recommended, these todo plans are superseded and
should each get `plan-reject` citing this file: the twelve 2026-09-06
gate-hardening plans (fingerprint-less stamp blocking, halve
plan-citations, invert the reviewable code set, CI tree-hashing,
plan-gate fingerprint-algorithm survival, fingerprint symlink coverage,
frozen-plan-guard renames, hooks fail-closed, review-loop churn
measurement, git path quoting, shrink the CI trusted set, stop-a-PR-
weakening-the-CI-gate) ~~plus
2026-08-28-design-a-provenance-system-for-d-f-resolution-markers.md~~.
The known-weak-points catalogue stays: most of its entries describe the
parts being deleted, which resolves them better than fixing would have.

**2026-09-09:** the provenance plan comes off this list. `D5`'s refined
answer keeps the resolution-marker notation and its "the user confirmed
this" meaning, so that plan's motivating concern survives the teardown;
it stays in `todo/` on its own merits. Twelve rejections remain.

### G4 — the measured baseline this plan was decided against (2026-09-09)

Machinery 5,056 lines + ~1.1-1.5k doc lines vs. 9,449 fleet lines;
`gate-tests` 1,432 + `gate-mutants` 619 = 40% of machinery testing
machinery; verify-ladder 26.3s per commit; gate-mutants 17.1s wall /
2m12s CPU per gate-touching push; branch `cfe6106..HEAD` = 8,230 changed
lines, 0 in fleet config; 81/81 schema-plan findings about the apparatus;
52 non-frozen plans outstanding of which ~16 todo items are about the
apparatus itself. If a future session doubts the teardown, re-measure
these before re-litigating.

### G5 — the teardown branch is stacked on PR #69, and merge order matters

`worktree-gate-teardown` was branched from PR #69's head, not master:
the teardown deletes and rewrites the same gate scripts #69 hardened, so
branching from master would have manufactured conflicts against work the
user may still merge, and building on the freshest machinery state made
the deletions clean. Consequences:

- Until #69 merges, a PR from this branch shows #69's commits plus the
  teardown's. **Merging #69 first is the clean sequencing**: the
  teardown PR then reduces to its own eight commits.
- The new frozen-by-residence range check flags #69's own range — it
  edited 27 done/ plans through the now-deleted `plan-repair` mechanism,
  legally under the checksum regime. That is another reason #69 merges
  *before* the teardown, not after.
- CI pins `plan-gate` from the base branch, so both PRs are judged by
  master's *old* blocking gate until the teardown lands. #69 stays red
  on its stale stamps unless merged past the check (the teardown cannot
  un-red it retroactively); the teardown's own commits carry no `Plan:`
  trailers, which the old gate treats as nothing-to-gate — the exact
  F36 shape its own weak-points catalogue documented. After the teardown
  merges, the advisory gate judges everything that follows.

## Findings (F)
*(populated by security/docs-updater when invoked)*
