---
slug: halve-plan-citations-by-harvesting-headings-in-the-scan-pass
created: 2026-09-06
status: rejected
frozen: true
kind: task
priority: normal
blocked_by:
---

# halve plan-citations by harvesting headings in the scan pass

## State

Not started. Filed 2026-09-06 from a `/simplify` efficiency finding, with
measurements. Below the correctness/security bar that the originating
branch was fixing inline, so it was filed rather than done there.

## Original plan

`docs/skills/plan/scripts/plan-citations` runs on every `verify-ladder`
pass, so it sits in front of every non-trivial commit. Measured at 132.5
ms (mean of 20 runs, 260 files, 233 citations), it decomposes as:

| stage | cost |
|---|---|
| `git ls-files` over 260 paths | 1.3 ms |
| the `awk` scan + `sort -u` | 33.2 ms |
| anchor resolution (`plan_has_heading` forks) | **~98 ms** |

`plan_has_heading` costs 1.17 ms per call against the 1400-line active
plan, and the tree holds 64 distinct `file#id` anchors across just 9
target files. 64 × 1.17 ≈ 75 ms — **57% of the runtime spent forking
`grep` to answer a question the scan already had the data for.**

The script's own header makes exactly this argument about the *scanning*
half:

> One awk over every file rather than awk|grep|sort per file: the
> per-file form spawned ~650 processes and took 0.4s on a gate that runs
> before every commit.

and then leaves the *resolving* half doing the per-item form.

### The change

Plan files are already in the scan set via `PLAN_DOC_GLOBS`, so the awk
program can emit headings on the same pass at no extra I/O:

```awk
/^### [DGF][0-9]+([[:space:]]|$)/ { print "HEAD\t" FILENAME "\t" $2 }
```

The shell then resolves anchors against a map built from those records
instead of forking.

**Measured:** the awk stage goes 33.2 ms → 38.0 ms with heading emission
added, and the 75 ms of greps disappears — **plan-citations ≈ 67 ms, a
2× improvement.**

Cheaper variant, if restructuring the awk program is unattractive:
memoise per *target file* rather than per anchor — 9 greps instead of 64,
measured at 11 ms against 75 ms. Most of the win, a fraction of the
change.

### The catch worth designing around

Both variants move "what counts as a real heading" out of
`plan_heading_re`, which
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F32`
and its neighbours deliberately centralised after finding six spellings
of that regex in the repo. Re-introducing a seventh, inside an awk
program where nothing can check it against the others, would undo that.

So either the awk pattern carries a comment tying it explicitly back to
`plan_heading_re`, or `plan_heading_re` gains a companion that lists all
headings in a file and both callers use it. Decide which before writing
the awk.

### Not urgent

132 ms on a gate whose next step is `nix flake check` (seconds) is not a
problem anyone is feeling. This is filed because the measurement exists
and the fix is known, not because the gate is slow.

## Progress

- [ ] decide how the heading pattern stays tied to `plan_heading_re`, as
      a `### D1`
- [ ] implement whichever variant that decision favours
- [ ] re-measure; confirm the citation count is unchanged (233 at time of
      filing) and that broken citations still fail

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

**REJECTED 2026-09-09:** superseded: plan-citations is warn-only now, so its runtime no longer sits in a blocking path -- 2026-09-09-dismantle-the-blocking-gate-tier-and-keep-the-plan-corpus.md#D4
