---
slug: make-ci-hash-the-tree-it-was-told-to-gate
created: 2026-09-06
status: rejected
frozen: true
kind: task
priority: normal
blocked_by:
---

# make CI hash the tree it was told to gate

## State

Not started. Filed 2026-09-06 from a `/simplify` altitude finding. The
fix is a two-line CI change whose failure mode is fail-open, so it needs
a real PR to verify rather than a local test.

## Original plan

In `.github/workflows/plan-gate.yml`, two halves of the same check read
two different trees.

- `required-agents` is handed explicit refs:
  `plan-gate "origin/$BASE_REF" "$HEAD_SHA"`, so the obligation set comes
  from the **PR head**.
- `plan_code_fingerprint` hashes whatever is on disk, and
  `actions/checkout@v4` on a `pull_request` event with no `ref:` checks
  out `refs/pull/N/merge` — the **merge result**, head merged with the
  current base.

So `plan-gate` compares a stamp written against the head tree with a
fingerprint computed over the merge tree. Any commit landing on the base
branch while a PR is open, touching any file in `PLAN_CODE_GLOBS`, shifts
`current_fp` to a value no local agent could ever have stamped.

Raised by `/simplify` (altitude) on 2026-09-06 while reviewing
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md`.

### Why it matters more since the glob widening

The defect predates the widening — `*.nix` alone produces it. But
`flake.lock` is now in the code set, so a routine `nix flake update`
merged to master invalidates the stamps on **every** open PR, over a file
nobody on those PRs touched. That converts a rare race into a routine
one.

### This is not the already-filed fingerprint plan

`2026-09-06-make-plan-gate-survive-a-pr-that-changes-the-fingerprint-algorithm-or.md`
covers base-`lib.sh` versus head-`lib.sh` disagreeing on the **algorithm**.
This is the same algorithm computing over a **different tree**. Fixing
either leaves the other.

### The obvious fix, and why it was not applied inline

Adding `ref: ${{ github.event.pull_request.head.sha }}` to the checkout
step makes the hashed tree the gated tree.

It was **not** applied when found, deliberately. The pin step resolves
`origin/$BASE_REF` to fetch the trusted copies of `plan-gate`, `lib.sh`
and `required-agents`. If specifying `ref:` changes which remote-tracking
refs `actions/checkout` creates, `git cat-file -e "origin/$BASE_REF:..."`
fails, the step takes its `found=false` branch, prints "nothing to gate"
and **exits 0**.

That failure is silent and fail-open: a change made to fix a staleness
bug would instead disable the gate entirely, on every PR, with a green
check. Against this repo's own standard — an unverifiable claim sits at
the bottom of the trust hierarchy, and a gate that passes when it should
block is the worst available outcome — that is not a change to make
without running it.

### Candidate approaches

1. **`ref:` on the checkout**, plus an explicit assertion in the pin step
   that `origin/$BASE_REF` resolved — turning the fail-open into a hard
   failure. The assertion is worth adding regardless of this plan.
2. **Keep the default checkout**, and add a `git checkout $HEAD_SHA` step
   *after* pinning. The fetch and the pin both run under today's known
   behavior; only the working tree moves.
3. **Have `plan_code_fingerprint` take a ref** and hash
   `git ls-tree`/`git cat-file` output instead of the working tree. Most
   correct, and the largest change; it would also close the
   untracked-file skew noted in
   `2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#G10`.

(2) is the cheapest safe option. (1) is cleaner if the ref behavior is
confirmed. Either way, **add the `origin/$BASE_REF` assertion first** —
it is independently valuable and makes the rest testable.

### Verification

Must be tested with real PRs, not reasoned about:

1. Open a PR, confirm the gate still finds the pinned scripts.
2. Land an unrelated `.nix` or `flake.lock` commit on master.
3. Confirm the open PR's stamps do **not** go stale.
4. Confirm a genuinely stale stamp still blocks.

## Progress

- [ ] add the `origin/$BASE_REF` resolution assertion to the pin step
      (independently valuable, makes the rest testable)
- [ ] decide between the checkout approaches, as a `### D1`
- [ ] verify with a base-branch commit landing under an open PR
- [ ] confirm a genuinely stale stamp still blocks afterwards

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

**REJECTED 2026-09-09:** superseded: the tamper-resistance program around plan-gate's blocking role ended with the blocking role -- residual risk accepted under ADR-0002; see 2026-09-09-dismantle-the-blocking-gate-tier-and-keep-the-plan-corpus.md
