---
slug: dismantle-the-blocking-gate-tier-and-keep-the-plan-corpus
created: 2026-09-09
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# dismantle the blocking gate tier and keep the plan corpus

## State

**2026-09-09, not started.** Filed from the first-principles assessment the
user commissioned in
2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md
("Pick-up point, 2026-09-09"), run by a session that built none of the
machinery. Every number in that handoff reproduced (see `G4` for the
baseline). Nothing has been dismantled; every decision below is open and
`D1`-`D6` are the user's calls. PR #69 is still open and red on two stale
stamps.

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

- [ ] Stage 0: user answers `D1`-`D6`; scope is ratified
- [ ] Stage 1: plan-gate advisory on stamps; findings parkable — see D1
- [ ] Stage 2: done/-immutability check replaces freeze checksums — see D2
- [ ] Stage 3: gate-mutants tier deleted
- [ ] Stage 4: gate-tests shrunk to a smoke test
- [ ] Stage 5: plan-lint / plan-citations warn-only or deleted — see D4
- [ ] Stage 6: ADR migration started; D/G/F frozen for new plans — see D5
- [ ] Stage 7: docs pass over AGENTS.md, skills, procedures, agents
- [ ] Stage 8: mooted gate plans plan-reject'ed with reasons — see G3
- [ ] PR #69 disposition executed — see D6

## Decisions (D)

### D1 — what, if anything, still blocks a merge?

Options: (a) nothing — reviews are purely advisory; (b) **recommended:**
block only on an unresolved CRITICAL/HIGH `security` finding, a ~20-line
check in `plan-gate`, everything else parkable; (c) keep the full
unresolved-findings block but drop only stamp staleness. The assessment
recommends (b): it keeps the one guarantee with teeth (the day-one samba
findings are the class it protects) while removing the livelock, whose
driver was trivia that could not be parked.

### D2 — replacement for the freeze/checksum machinery

**Recommended:** delete `docs/plans/.checksums`, `plan-repair`, the
pre-commit frozen/manifest checks, and `plan-freeze`'s hashing; add one
check (in `plan-gate` CI, so it holds for every tool and human) that a
PR's diff contains no path under `docs/plans/done/` or
`docs/plans/rejected/`. Alternative: keep the manifest as-is and accept
its defect surface. Note `plan-move ... done` still needs *some* freeze
semantics — under the recommendation it just moves the file, and
immutability is enforced at the merge boundary instead of at write time.

### D3 — where do host builds run?

Keep the local pre-push five-host build (current behaviour), or move it
to async CI in the buildbot style Mic92 uses. **Recommended:** keep local
for now; this is a placement question orthogonal to the teardown, and the
local build is the single highest-value gate in the repo.

### D4 — fate of plan-lint and plan-citations

Warn-only (keep the scripts, print, never block) or delete outright.
**Recommended:** warn-only for one probation period, delete if the
warnings are only ever noise. `required-agents`, `subagent-stamp`,
`plan-touch-guard`, `footer-guard` and `mark-trivial` follow the same
choice: with nothing blocking on their output, keep only the ones whose
output is still read.

### D5 — do new plans keep the D/G/F item scheme?

**Recommended:** new plans use plain prose plus ADRs for real
architectural decisions; D/G/F, `plan-decide`, `plan-resolve`,
`plan-carry` and the resolution-marker vocabulary stop being required
(existing files keep resolving forever — nothing is renumbered or
migrated). Alternative: keep the scheme as optional structure for large
plans only.

### D6 — PR #69

It is red on two stale stamps and nothing else; the branch is green
locally. Options: merge it on its merits once Stage 1 makes stamps
advisory; sign off on the stamps now and merge before the teardown;
or close it and fold its schema work into this plan's docs pass.
The assessment deliberately did not review its content as a change, so
merging it needs whatever review the user actually wants — as a decision,
not an obligation.

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
weakening-the-CI-gate) plus
2026-08-28-design-a-provenance-system-for-d-f-resolution-markers.md.
The known-weak-points catalogue stays: most of its entries describe the
parts being deleted, which resolves them better than fixing would have.

### G4 — the measured baseline this plan was decided against (2026-09-09)

Machinery 5,056 lines + ~1.1-1.5k doc lines vs. 9,449 fleet lines;
`gate-tests` 1,432 + `gate-mutants` 619 = 40% of machinery testing
machinery; verify-ladder 26.3s per commit; gate-mutants 17.1s wall /
2m12s CPU per gate-touching push; branch `cfe6106..HEAD` = 8,230 changed
lines, 0 in fleet config; 81/81 schema-plan findings about the apparatus;
52 non-frozen plans outstanding of which ~16 todo items are about the
apparatus itself. If a future session doubts the teardown, re-measure
these before re-litigating.


## Findings (F)
*(populated by security/docs-updater when invoked)*
