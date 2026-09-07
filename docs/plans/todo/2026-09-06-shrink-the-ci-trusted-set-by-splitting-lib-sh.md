---
slug: shrink-the-ci-trusted-set-by-splitting-lib-sh
created: 2026-09-06
status: todo
frozen: false
---

# shrink the CI trusted set by splitting lib.sh

## Original plan

`.github/workflows/plan-gate.yml` pins `docs/skills/plan/scripts/lib.sh`
**wholesale** from the base branch into `/tmp/plan-gate-trusted/`, so a
PR cannot neuter its own gate by editing the library in the same range it
is judged by. That pinning is correct and must stay.

What it currently pins is ~510 lines spanning three unrelated concerns:

| concern | roughly | does `plan-gate` call it? |
|---|---|---|
| shared constants + path predicates | ~90 lines | yes |
| git / fingerprint helpers | ~110 lines | yes |
| plan-file text manipulation (`plan_set_field`, `plan_append_under_heading`, `plan_slugify`, `plan_do_freeze`, …) | ~200 lines | **no** |

So roughly 200 lines of in-place `awk`-rewrite-and-`mv` helpers sit in
the CI trusted set for no reason. They are not called by `plan-gate` or
`required-agents`; they exist for the interactive `plan-*` editors.

### The change

Split into three sourced files:

- `constants.sh` — every `PLAN_*` array (`STAMPABLE_AGENTS`,
  `AGENT_ORDER`, `CODE_GLOBS`, `DOC_GLOBS`, `NONTEXT_GLOBS`, the derived
  `TEXT_GLOBS`), the relpaths, `plan_path_matches`,
  `plan_is_code_path` / `plan_is_doc_path`, and the derived-set logic
- `git.sh` — `plan_repo_root`, `plan_worktree_files`,
  `plan_existing_files`, `plan_code_fingerprint`
- `lib.sh` — the plan-file text half, sourcing the other two

`plan-gate` and `required-agents` then source only the first two, and the
CI pin covers ~200 lines instead of ~510.

### Why this is worth doing beyond tidiness

Two concrete consequences, not aesthetics:

1. **The pinned surface is the surface a PR cannot be trusted to
   change.** Smaller is strictly better, and 40% of what is pinned today
   is unreachable from the pinned entry points.
2. **It shrinks
   `2026-09-06-make-plan-gate-survive-a-pr-that-changes-the-fingerprint-algorithm-or.md`.**
   That plan is about base-`lib.sh` and head-`lib.sh` computing different
   fingerprints for one tree. If the fingerprint lives in a `git.sh` that
   changes far less often than the text helpers, the window in which that
   disagreement can arise narrows considerably.

**There is no efficiency argument.** Measured: sourcing the whole 510-line
`lib.sh` costs 0.47–0.61 ms, and no `PreToolUse` hook sources it at all —
`plan-touch-guard`, `footer-guard` and `fresh-branch-guard` source only
`hook-lib.sh`. The one hook that does source it, `subagent-stamp`, fires
on `SubagentStop` and immediately spends 6 ms hashing. Do not make the
size argument; it is not true.

### Watch for

`plan-gate` sources through `SCRIPT_DIR`, never `$root`, precisely so the
pinned copy is used. A split means the workflow must pin **all** the
files the entry points source, and the `git cat-file -e` existence probe
must cover each — a missed one takes the workflow's `found=false` path,
which prints "nothing to gate" and **exits 0**. That is a fail-open, so
the pinning step needs an assertion that every expected file arrived,
not just the first.

## State

Not started. Filed 2026-09-06 from a `/simplify` altitude finding at the
close of the session that built the gate. Deferred because it touches the
CI pinning path, whose failure mode is fail-open and which cannot be
tested locally.

## Progress

- [ ] confirm the call graph: which helpers `plan-gate` and
      `required-agents` actually reach
- [ ] split into `constants.sh` / `git.sh` / `lib.sh`
- [ ] update `plan-gate.yml` to pin all three, with an assertion that
      each arrived rather than a silent `found=false`
- [ ] verify on a real PR that the gate still blocks and still passes in
      the cases it should

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
