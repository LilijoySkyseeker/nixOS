---
slug: harden-the-workflow-system-against-the-failure-classes-it-exposed
created: 2026-09-06
status: todo
frozen: false
---

# harden the workflow system against the failure classes it exposed

## Original plan

Building the mechanical review system in
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md`
produced 40 findings across four `security` passes and five
`docs-updater` passes. This file is not a list of those findings — they
are recorded there, resolved. It is the **classification**, because the
individual fixes are done and the classes are not.

The headline: **almost every defect was a gate that failed in a way that
reported the wrong answer**, not a gate that was missing. The system's
weakness is not coverage. It is that its failure modes were untested,
and both directions of failure are worse than having no gate at all.

### Class 1 — the gate reports success when it did not check

Eight instances, and this is the one to design against.

| finding | what reported "pass" |
|---|---|
| `#F3` | `required-agents` turned a failed `git diff` into "no agents obliged" |
| `#F4` | `plan-gate` printed "nothing to gate" for a ref it could not resolve |
| `#F5` | `plan-citations` printed `OK (N citations)` over a scan that aborted early |
| `#F32` | the fingerprint returned **empty with rc=0** whenever the sort-last path was not a regular file |
| `#F37` | `plan_worktree_files` returned rc=0 and a *plausible subset* when a `git diff` leg failed |
| `#F34` | a `.nix` file with a non-ASCII name obliged **no** review agent, because git C-quotes the path and the quoted form matches no glob |
| `#F31` | four `.claude/skills/*` symlinks oblige review but never move the fingerprint |
| — | `plan_code_fingerprint` from a subdirectory returned a *different hash* with rc=0 (fixed under `#F37`) |

The shared shape: **a shell construct whose exit status does not mean
what it looks like it means.** A `while` loop exits with its last body
command's status. A `{ a; b; c; }` group exits with `c`'s. A command
substitution swallows the inner exit. `2>/dev/null` on an `awk` hides an
abort. None of these are exotic; all of them are invisible in review
unless you go looking for them specifically.

**What would help:** a test harness that runs each gate script against a
deliberately broken environment — bad ref, missing file, locked index,
non-ASCII filename, path with a newline, subdirectory cwd — and asserts
each one *fails*. Every finding above would have been caught by a
ten-line test. The repo has eight VM tests for NixOS behaviour and zero
tests for the scripts that gate every commit.

### Class 2 — the gate blocks in a way nothing can clear

Four instances. Equally damaging, because the escape is always the same:
drop the `Plan:` trailer and the whole gate switches off
(`2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md#G42`).

- `#F1` — a frozen plan plus a stale fingerprint. `plan-move done`
  freezes the plan, `subagent-stamp` refuses to write to a frozen plan,
  so any later drift is unfixable in-system.
- `#F2` — the mandated agent order guaranteed a stale `security` stamp,
  because `docs-updater` edits the code the fingerprint covers. Red on
  the first honest attempt, every time.
- `#F28` — `.claude/settings.local.json`, written by the harness on a
  "don't ask again" grant, entered the local fingerprint and can never
  exist in CI.
- `#G5` — `verify-ladder` was un-passable on master for any change, for
  environmental reasons.

**What would help:** the same harness, asserting the *positive* case —
that an honest sequence of steps ends green. `#F2` was found by reasoning
rather than by running the sequence, and `#F1` is still only half fixed
(a stale stamp on a frozen plan degrades to a NOTE; the freeze boundary
itself is untouched).

### Class 3 — documentation describing code that has since changed

**Twelve instances**, the most frequent class by count. Every one was a
comment or doc that was true when written and silently false afterwards.

The three that matter structurally:

- The same fact rendered in two channels drifts. `#F21` and `#F40` are
  the *same sentence* in `reference.md` going wrong in opposite
  directions two passes apart — once by listing a stale glob set, once by
  dropping half the current one.
- A comment can assert a relationship the code no longer has. `#F29`
  claimed three consumers shared one glob set immediately after a pass
  deliberately split them.
- It reaches plan files too, not just comments. `#F38` — a follow-up plan
  described work as unbuilt after half of it had landed. That is the most
  dangerous instance: the next agent reads the plan, not the diff.

There is also a distinct sub-shape worth its own guard: `#F39`, where a
comment rewrite left the *pre-rewrite text spliced into the new text
mid-sentence*. That is not a stale comment, it is a botched edit, and it
is visible in the diff without reading any code.

**What would help:** the fix that actually worked was structural, not
disciplinary — `#F21`/`#F24` changed the docs from *restating*
`PLAN_CODE_GLOBS` to *pointing at* it, and that particular drift stopped
recurring immediately. Generalise it: prose should cite the array, the
script, the plan anchor. `plan-citations` already verifies the pointers
resolve; nothing verifies a paraphrase.

### Class 4 — the loop generates its own work

Roughly half the findings after the first pass were consequences of
earlier fixes in the same session, not pre-existing defects. Widening the
code set made three docs stale; fixing those changed code; the next
reviewer met a new surface. Two of the most serious findings all session
(`#F28`, `#F15`) were defects the loop **introduced and then caught**.

That is the loop working, and it is indistinguishable from the loop
spinning unless someone is counting. Already filed as
`2026-09-06-measure-whether-the-review-loop-is-converging-or-churning.md`.

### Class 5 — gaps that remain by design, and should be labelled as such

Not defects; deliberate limits that must not be mistaken for coverage.

- **`/simplify` is obliged on every code change and stamped by nothing.**
  A slash command fires no `SubagentStop`. The one honour-system leg in a
  system built to remove honour-system legs.
- **`spec-check` does not exist**, so its leg of the loop is unenforced
  by construction.
- **A stamp is a record, not proof** (`#F7`). One `printf` forges one,
  and `SubagentStop` fires for a no-op prompt.
- **A PR can weaken the CI workflow that judges it** (`#F25`), since
  GitHub resolves a `pull_request` workflow from the PR's own ref.
- **Worktree sessions run hooks from the main checkout** (`#F12`), so a
  PR that changes hook behaviour is never exercised by the sessions
  developing it.
- **The code set is an allowlist**, twice found incomplete
  (`#G11`), inversion filed separately.

The honest framing, worth writing into `reference.md` as a threat model:
this system defends against **an agent that forgets a step**. It does not
defend against one that lies, and several of the above are only
defensible under that assumption.

## State

Not started. Written 2026-09-06 at the user's request, at the close of
the session that produced the findings, while the evidence was still in
hand. It is a classification of
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md`'s
40 findings, not a re-litigation of them — every individual finding there
is already resolved.

The single highest-value item is the test harness in Class 1: it would
have caught eight findings mechanically, and the repo currently has more
tests for its NixOS VMs than for the scripts gating every commit.

## Progress

- [ ] build the failure-mode harness for the gate scripts (Class 1 and 2)
      — bad ref, missing file, non-ASCII path, newline path, subdirectory
      cwd, broken git; assert each gate *fails*, and assert an honest
      sequence ends green
- [ ] decide whether prose may ever paraphrase a mechanism, or must
      always cite it, as a `### D1` (Class 3)
- [ ] add a guard for the spliced-rewrite shape (Class 3, `#F39`)
- [ ] write the threat model into `reference.md` (Class 5)
- [ ] cross-check the seven already-filed follow-up plans against these
      classes; fold any that are really the same item

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
