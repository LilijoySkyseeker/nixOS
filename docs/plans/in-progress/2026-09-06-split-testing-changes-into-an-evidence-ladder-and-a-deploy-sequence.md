---
slug: split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence
created: 2026-09-06
status: in-progress
frozen: false
---

# split testing-changes into an evidence ladder and a deploy sequence

Child 3 of the map
2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md;
the design is settled there as
2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#D6.

## Original plan

`docs/procedures/testing-changes.md`'s six-layer list mixes evidential
depth with deploy chronology -- `nvd diff` sits at position 5 despite
costing seconds where layer 4 costs minutes. Split it per the parent's
D6:

- **An evidence ladder**, five rungs mapping 1:1 onto the trust
  hierarchy in `docs/skills/workflow/reference.md`: documentation,
  source, local build with the output actually inspected, VM, switch.
  Old layers 2, 3 and `nvd` collapse into the one build rung, because
  the hierarchy always described rung 3 as a single thing; splitting it
  across three non-adjacent positions is why nothing could stamp it.
- **A deploy sequence** -- build, `nvd diff`, switch, observe -- which
  is an order of operations, not evidence.
- **Lint is not a rung.** By the old ladder's own words it catches style
  and dead code, not correctness. It gates (`verify-ladder`); it
  warrants nothing.
- **The rung reached becomes a required declaration.** `verify-ladder`
  already enforces the rung-3 floor mechanically (eval plus targeted
  build); inspecting the output, VM runs and switches cannot be
  script-verified, so they take D2's third mechanism form,
  require-declaration: `plan-move ... done` (and `plan-freeze`) refuse
  unless `## State` declares the rung reached. VM testing stays manual
  -- minutes inside a pre-commit gate teaches bypassing -- but the skip
  becomes visible instead of silent.

Declaration form: a `Verified to rung <N> (<label>)` line in `## State`
-- mechanizing the exact practice the parent map's own State and
`docs/audits/2026-08-26/RESUME.md` already follow by hand, rather than
inventing a frontmatter field that would collide with child 2's pending
schema revision. Always satisfiable honestly: a docs-only plan declares
rung 1.

Touched: `docs/procedures/testing-changes.md` (restructure),
`docs/skills/plan/scripts/lib.sh` (`plan_rung_problem`),
`docs/skills/plan/scripts/plan-move` and `plan-freeze` (the new
refusal), plus the docs that describe those gates (`plan/SKILL.md`,
`plan/reference.md`, `workflow/SKILL.md` step 8, `AGENTS.md`'s docs
table row).

## State

**2026-09-06: built and tested.** `plan_rung_problem` lives in `lib.sh`
beside `plan_state_problem`, both reading the section through the shared
`plan_state_body`; `plan-move ... done` and `plan-freeze` refuse without
the declaration. `docs/procedures/testing-changes.md` now carries the
five-rung evidence ladder, the "Declaring the rung" section, and the
four-step deploy sequence, with lint explicitly demoted to a gate. The
five docs describing the close-out gates were updated
(`plan/SKILL.md`, `plan/reference.md`, `workflow/SKILL.md` step 8,
`workflow/reference.md`, `AGENTS.md`'s docs-table row -- the last
trimmed to stay near its word budget).

**The matcher took four tries, and each round narrowed the same
question: does this text *claim* a rung, or merely name one.**
`security` first found it wrong in both directions at once: it refused a
truthfully hard-wrapped declaration (F3) and accepted a negated one
(F4). Widening the preceding-character class fixed those two cases and
bought two more -- a backticked mention passed because the fix stripped
backticks (F8), and the one-character negation guard let `not (yet)`, a
`--` clause and a colon through (F9). Patching characters was losing, so
the rule became structural: **the phrase must open a blank-line block**,
because `## State` is hard-wrapped and a blank line is the only boundary
wrapping cannot move. The fourth round closed what position alone
cannot see -- a mention in *subject* position opens the paragraph too
("Verified to rung 3 is the phrase the gate wants"), so the phrase must
also end the claim, with punctuation or nothing after the number (F13)
-- and fixed a real fail-open one level up: `plan_state_body` re-armed
on every `## State` line and ignored code fences, so a plan with no
State section of its own passed both checks on the strength of a fenced
example (F12). The `/simplify` round after that fix found F12 reopened
twice over -- the fence toggle flipped on any marker, so a nested fence
desynced it, and the rung check was itself fence-blind, so a quoted
example *inside* a real State still counted. Both close in one place:
`plan_state_body` follows CommonMark's same-marker rule and takes a
`skip-fences` mode, so the fence rule has one implementation and the
rung check consumes it rather than re-scanning. F5 and F10 settled rung
3 itself -- one definition, covering work with no closure to build, and
earned by reading the output rather than by a green exit code.

**2026-09-07: the fifth review round closed the last decidable case and
the rest are on the record.** `security` found that the fence dropper
was anchored at column 0, so an indented fence -- three spaces, or the
deeper indent a list-nested fence needs -- hid a quoted example (F17,
fixed; this repo writes dozens of indented fences). Two residues were
accepted by the user rather than closed: a declaration whose later
clause denies it (F18) and an unbalanced fence moving the section
boundary (F19). Both are asserted in `scripts/gate-tests`, so a later
tightening reads as a change instead of a surprise.

The cases no longer live in a scratch directory. They are
`scripts/gate-tests`, built under
2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md
and wired into `verify-ladder`, which is what makes G3's worry moot.

Verified to rung 3 (ran it locally, output inspected) -- the gate was
exercised end to end in a scratch repo (refusal without a declaration
from both `plan-move` and `plan-freeze`, move-plus-freeze with one) and
against a 45-case matrix: sixteen honest forms that must pass (wrapped
mid-phrase, bolded, italic, bulleted, numbered, blockquoted, indented,
lowercase) and twenty-nine that must be refused, including every bypass
F4, F8, F9 and F13 reported. Seven fence and whitespace cases were
checked separately: F12's two reproductions, a nested-fence desync, a
fenced example inside a real State, a trailing space and a bare
declaration with no closing punctuation, and a control proving a real
declaration whose State contains a fenced command block still passes. All nine live
`in-progress/` plans classify as expected -- the two this branch owns
pass, the seven predating the gate refuse (G2). `verify-ladder` passes.
No host-visible behavior changed, so rungs 4-5 do not apply.

## Progress

- [x] `plan_rung_problem` + refusals in `plan-move` and `plan-freeze`
- [x] `testing-changes.md` restructured -- see G1
- [x] gate-describing docs updated


## Decisions (D)


## Gotchas (G)

### G1 - "stamps the rung-3 floor" read as "enforces", not "writes a stamp"

The parent's D6 sentence "`verify-ladder` stamps the rung-3 floor
mechanically" could be read as verify-ladder appending a rung-3 record
to the active plan. Not built that way: a script writing into `## State`
would fight the section's rewrite-in-place ownership, and any mechanical
prose append moves nothing useful -- the hard block *is* the record,
since a commit that reached the workflow's step 6 has by construction
passed the rung-3 floor in step 4. The declared half (output inspected,
rungs 4-5) is the State line the close-out gates now require. If a
written rung-3 record turns out to be wanted, it belongs in child 7's
verify-ladder work, not here.

### G2 - the gate applies to plans written before it existed

Seven of the nine `in-progress/` plans declare no rung, so each needs
one sentence added before it can close. That is deliberate and left
un-backfilled: the declaration is a claim about verification someone
else performed, and an agent writing it on their behalf would be
inventing the exact evidence the gate exists to make explicit -- the
same reason `plan-resolve accepted` requires the user's own sign-off.
Nothing already in `done/` is affected: `plan-freeze` checks
`plan_is_frozen` before the gates, and every frozen plan is already
past them.

### G3 - the matrix that proved this gate has nowhere to live

`plan_rung_problem`'s behavior was settled by a 45-case matrix, run from
a scratch directory and discarded. Thirteen of those cases exist only
because `security` reported a live bypass across four passes (F4, F8,
F9, F13) -- and F8, F9 and F13 were all reachable only through the
*previous fix*, which is exactly the regression class a committed
matrix catches and nothing here will.

The cases themselves are not lost: they are written into
2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md#G1
as that plan's first fixture, so the harness starts from a settled list
rather than re-deriving one.

No fixture was committed *here*, because this repo has no home for a
shell unit test: `tests/` is NixOS VM checks, and inventing a second
convention mid-branch would pre-empt the decision
2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md
exists to make -- its first item is a failure-mode harness for exactly
these gate scripts, and it is the highest-value follow-up the review
identified. This function is a good first case for it: pure, no git
state, and its whole contract is which strings it accepts.

### G4 - what the block anchor still cannot tell apart

One residue, known and left: a paragraph whose first line is an
*indented* code block containing exactly the declaration reads as a
declaration. Closing it means not squeezing the first line's leading
whitespace, so four spaces stay distinguishable from one -- more
structure than the case earns, because this repo's plans fence their
code blocks with backticks, and a fenced block is already refused (the
paragraph then opens with a backtick, not the phrase).

Worth stating plainly: this is a require-declaration gate, so its whole
job is making the claim explicit and dated. Someone who wants to write a
false declaration can, and no string matcher changes that. The bypasses
worth closing are the accidental ones -- a mention that reads as a claim
without anyone intending it -- which is why F8 and F9 mattered and why
this one does not.

Also known and not converted: `plan-lint` tests for the required
sections with `grep -qF "## State"`, which is both substring-based and
fence-blind, so it is a third reader of a boundary `plan_state_body`
now owns. Its failure mode is a lint that passes a malformed plan, not
a gate that lets an undeclared one close, so it is left to the
lib.sh-split work rather than widened into here.

## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 — the rename to "rungs" left the old "layer" vocabulary standing everywhere outside testing-changes.md

- **File:** `docs/procedures/workflow.md:30`, `docs/procedures/vm-testing.md:7-9`, `modules/flake/checks.nix:2`, `docs/skills/workflow/scripts/verify-ladder:2-3`, `docs/skills/workflow/reference.md:289-290`, `docs/skills/workflow/SKILL.md:31`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the restructure renamed the six "layers" to five "rungs" and demoted lint out of the ladder, but only inside `testing-changes.md`. Left stale: `workflow.md` still said "which validation layer to reach for"; `vm-testing.md`'s intro still recited the old six-position sequence (`nixfmt` → `nix flake check` → `nixos-rebuild build` → `nvd diff` → switch) that no longer exists anywhere; `checks.nix`'s header called the VM tests "the layer above `nixos-rebuild build`" while pointing at `testing-changes.md`; `verify-ladder`'s own header claimed to be part of "testing-changes.md's verification ladder" when the new doc says lint is a gate, not a rung, and verify-ladder covers lint plus the rung-3 floor; and `workflow/reference.md` called verify-ladder "the cheap ladder", colliding with the evidence ladder lint was just removed from, and `workflow/SKILL.md` step 4 said "cheap verification
ladder" for the same script. All six rewritten in this pass to the
rung/floor vocabulary.


**FIXED 2026-09-06:** all six references rewritten in the same docs-updater pass: workflow.md says evidence-ladder rung, vm-testing.md names itself rung 4, checks.nix says rung, verify-ladder's header says lint gate plus the rung-3 floor, reference.md says scriptable floor, workflow/SKILL.md step 4 says scriptable verification floor

### F2 — plan/SKILL.md's script table understated two gates it was edited to describe

- **File:** `docs/skills/plan/SKILL.md:25,31`, `docs/skills/plan/scripts/plan-move:5`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** two rows of the table this change touched didn't match the shipped scripts. (1) The `plan-move` row listed unresolved decisions/findings and the missing rung declaration as `done`-refusal reasons but omitted the missing/empty-`## State` check (`plan_state_problem`), which `plan-move` runs itself before hitting the rung check — the `plan-freeze` row named it, the `plan-move` row didn't. `plan-move`'s own header comment was staler still, naming only "any decision is unresolved". (2) The `plan-lint` row still said "Not a gate on anything yet -- run it yourself", but `verify-ladder` has run `plan-lint` against the active plan as a hard block (`testing-changes.md`'s own automation section says so) — pre-existing drift, surfaced by this pass touching the same table.

_docs-updater finished 2026-09-07T05:01:36Z -- see Findings above._

**FIXED 2026-09-06:** same docs-updater pass: plan-move row lists the missing/empty State refusal, plan-move's header names all close-out gates, and the plan-lint row says verify-ladder runs it as a blocking gate on the active plan

### F3 — the rung gate is a single-line substring match, so a truthfully-wrapped declaration is refused

- **File:** `docs/skills/plan/scripts/lib.sh:213-222` (`plan_rung_problem`), `docs/procedures/testing-changes.md:77-83`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening (gate correctness)
- **Reachability:** no network adversary -- the principal is the agent or human running `plan-move <file> done` / `plan-freeze`. Path: this repo hard-wraps prose at ~72 columns, and every plan's `## State` does too, including this one and the map's. A State reading "... the work was, after some back and forth, verified to rung\n3 (local build, output inspected)." is a complete, truthful declaration, and `grep -qi 'verified to rung [1-5]'` refuses it because the phrase straddles a newline. Verified against the shipped function with a fixture: wrapped declaration produces `no verification-rung declaration in ## State`. A double space (`Verified  to rung 3`) fails identically.
- **Rule:** n/a -- new-rule candidate; this is the failure mode 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F1 names, a gate that refuses a correct input and so teaches the operator to fight the string rather than state the truth.
- **Finding:** the gate matches a fixed literal on one physical line. Nothing in `testing-changes.md`'s "Declaring the rung", `plan/reference.md` or `plan/SKILL.md` tells the writer the form is a verbatim single-line substring -- they say the State "carries a line naming the rung" and give examples. The only place the exact required string appears is the refusal message, so the constraint is learned by hitting it. That message also asserts something false about the file ("no verification-rung declaration in `## State`") in precisely the case where the declaration is present and correct, which is what makes it teach bypass rather than teach the format.
- **Fix risk:** normalising whitespace before matching (e.g. `tr -s '[:space:]' ' '` in `plan_rung_problem`, not inside `plan_state_body` -- `plan_state_problem` is insensitive to it today only because it pipes through `tr -d '[:space:]'`, and a future consumer may not be) widens matching across line and paragraph boundaries, so an unrelated "verified" line followed by a "rung 3" line could newly match. Whatever is chosen, the doc that teaches the form and the message that refuses it must state the same constraint. Re-exercise both callers against a wrapped declaration, an unwrapped one, and a State with none.


**FIXED 2026-09-07:** the State body is unwrapped (newlines and repeated spaces collapsed) and stripped of emphasis markers before matching, so a hard-wrapped or bolded declaration is read as one. Verified by a 20-case matrix covering wrapped, double-spaced, bolded, bulleted and blockquoted forms

### F4 — the same substring match counts a negated or quoted mention as a declaration

- **File:** `docs/skills/plan/scripts/lib.sh:219-221`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening (gate correctness)
- **Reachability:** no network adversary -- the principal is again the closing agent, and the path is ordinary phrasing rather than deliberate evasion. `testing-changes.md:57-63` explicitly instructs the writer to record *why* a rung was skipped ("skip only when something concrete prevents it ... a specific, statable blocker is"), so a State reading "Not verified to rung 4 -- sops-backed, the host key isn't in the VM" is the phrasing the doc asks for. Verified against the shipped function: that State passes the gate with no positive declaration anywhere in it. `Verified to rung 12` also passes, since `[1-5]` matches the leading `1`; and any State that merely *quotes* the mechanism -- a future plan-tooling plan quoting the refusal message, which contains `Verified to rung 3` verbatim -- passes for free.
- **Rule:** n/a -- new-rule candidate.
- **Finding:** the gate is deliberately require-declaration rather than require-truth (D6; `testing-changes.md:85-92` says so plainly), and that design knowingly accepts a *false* declaration. It does not intend to accept the *absence* of one. Matching an unanchored substring anywhere in the section collapses "declared rung N", "declined rung N" and "merely mentioned rung N" into one result, which is the single distinction the gate exists to make. This is the mirror of F3 -- one unanchored, line-scoped literal failing in both directions.
- **Fix risk:** anchoring (requiring the match at the start of a line or after a sentence boundary, or rejecting an immediately-preceding negation) makes the gate stricter, so it can newly refuse States already written -- including the three in-progress plans in F5, and any State whose declaration sits mid-sentence. Any tightening needs the accepted forms written into "Declaring the rung" first, and both `plan-move ... done` and `plan-freeze` re-exercised, since the gate runs twice per close-out.


**FIXED 2026-09-07:** the match now requires a sentence start and a non-digit after the rung number, so a negated mention is refused and 'rung 12' no longer reads as rung 1. testing-changes.md's 'Declaring the rung' teaches the positive form and gives the declare-then-say-what-you-skipped phrasing for the case the doc previously invited as a bare negation

### F5 — the ladder the gate cites has no rung for a change that builds nothing, and three closable plans are newly blocked

- **File:** `docs/procedures/testing-changes.md:20-75`, `docs/skills/plan/scripts/lib.sh:213-222`, this plan's own `## State`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** the closing agent, on any plan whose work is shell tooling under `docs/skills/*/scripts/` or `.githooks/` rather than Nix. Rungs 3, 4 and 5 are defined purely in Nix terms (`nix flake check`, `nixos-rebuild build`, `system.build.vm`, an observed switch); rung 2 is reading code and rung 1 is reading a doc. There is no rung for "the script was executed against fixtures and behaved", which is the strongest evidence such a change can produce. Visible in this very change: this plan's `## State` declares "Verified to rung 3 (local build, output inspected) -- the gate was exercised end to end in a scratch repo", but rung 3 as written is eval plus `nixos-rebuild build` plus reading the generated closure/unit output, which is not what was done. The declaration is honest about the work and inaccurate about the rung, because no accurate rung exists.
- **Rule:** n/a.
- **Finding:** two consequences. (1) Every plan-tooling change from here on must map real script-level testing onto a Nix-shaped rung, making the declared number less informative than the prose beside it -- the opposite of what the mechanism is for. (2) The gate is retroactive over open work: of the nine plans in `docs/plans/in-progress/`, seven fail `plan_rung_problem`. Four of those already failed the pre-existing `plan_state_problem` check, but three could be closed at HEAD and cannot be closed now without a backfilled declaration: `2026-08-18-homelab-backup-replication-stack-has-several-compo.md`, `2026-08-28-restructure-zfs-so-ordinary-temp-and-cache-data-is.md`, `2026-09-03-homelab-usb-uas-cksum-residual-risk-ongoing-monitoring-not-fully.md`. That backfill is mentioned nowhere in this plan's Progress or State, so the next session to close one of the three meets the refusal cold. Frozen plans under `done/` are correctly unaffected -- `plan-freeze` dies on `plan_is_frozen` before reaching the gate, and every plan under `done/` is `frozen: true` (checked).
- **Fix risk:** adding a rung, or an explicit "non-Nix change: declare rung 2" carve-out, renumbers or reinterprets a ladder that six other files now cite by number (`vm-testing.md`, `workflow/reference.md`, `workflow/SKILL.md`, `verify-ladder`, `checks.nix`, `AGENTS.md`), so the F1 vocabulary sweep would have to run again. Backfilling the three plans is cheap and independent of that, and can be done without touching the ladder.

**Checked and clean (security, 2026-09-07).** Reviewed the whole
uncommitted delta against HEAD (5eb67ef): `lib.sh`'s new
`plan_state_body` / `plan_rung_problem`, the two new gate calls in
`plan-move` and `plan-freeze`, the `testing-changes.md` restructure, the
comment-only edits to `verify-ladder` and `modules/flake/checks.nix`, and
the prose edits in `plan/SKILL.md`, `plan/reference.md`,
`workflow/SKILL.md`, `workflow/reference.md`, `AGENTS.md`,
`procedures/workflow.md` and `procedures/vm-testing.md`. Confirmed by
reading and by running the shipped functions against fixtures:
`plan_state_body` is byte-identical to the awk `plan_state_problem`
previously inlined, so the refactor preserves the existing State check;
a `## State` that is the file's last section is captured to EOF; a
`### ` subsection does not terminate it; `rung 0` and `rung 6` are
refused; case is ignored; a declaration placed outside `## State` is
correctly not counted. Gate placement checked: `plan-move <file>
in-progress` runs no close-out gate (the whole block sits inside
`if [ "$target" = "done" ]`); `plan-reject` still runs none and calls
`plan_do_freeze` directly rather than `plan-freeze`, so abandoning work
stays deliberately ungated; `plan-freeze` tests `plan_is_frozen` before
the gates, so no already-frozen plan is re-gated; `plan-lint` and
`.githooks/pre-commit` never call `plan_rung_problem`, so in-progress
plans and ordinary commits are unaffected. The double run of the gate
(plan-move gates, then `exec`s plan-freeze, which gates again) is
harmless: the only mutation between the two is `plan_set_field`, whose
awk rewrites frontmatter lines only and cannot reach `## State`. No
injection surface: the grep pattern is a fixed literal with no
interpolation, and the plan path reaches awk only as a file operand
built from `plan_repo_root`, hence absolute, so it can never be parsed
as an awk `var=value` assignment -- verified with a path containing `=`.
Neither caller sets `-e`, so the `[ -n "$x" ] && plan_die` idiom's
exit-1 on the empty case cannot abort the script. `shellcheck -s bash`
over all three changed scripts reports only pre-existing warnings on
untouched lines (SC2034 at `lib.sh:30`, SC2318 at `lib.sh:256`). The two
new functions add ~20 lines to the `lib.sh` that
`.github/workflows/plan-gate.yml` pins wholesale from the base branch,
but neither is reachable from `plan-gate` or `required-agents`, so the
pinned trusted set grows without gaining reach -- noted only because
2026-09-06-shrink-the-ci-trusted-set-by-splitting-lib-sh.md exists to
shrink it. No Nix evaluation semantics changed (`checks.nix`'s edit is
one word inside a `#` comment), no host, service, unit, firewall rule,
capability, user or group was touched, and nothing under `secrets/` or
`.sops.yaml` was read or referenced.

_security finished 2026-09-07T18:49:58Z -- see Findings above._

**FIXED 2026-09-07:** rung 3 now names what it means for a change with no closure to build -- executed against real inputs, accept and refuse cases both observed -- so script work declares it honestly rather than borrowing the Nix wording. The retroactivity half is recorded as G2 and left un-backfilled deliberately: only whoever did the work can honestly declare its rung, and nothing frozen is re-gated

### F6 — three gate-describing docs still named the rung by description after the required form became a fixed phrase

- **File:** `AGENTS.md:33`, `docs/skills/workflow/SKILL.md:62-63`, `docs/skills/plan/SKILL.md:25,29`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** F3/F4 turned the gate into a sentence-anchored match on the literal `Verified to rung <N>`, but the four docs outside `testing-changes.md` that describe the close-out gates kept the pre-tightening description — `workflow/SKILL.md` step 8 said `## State` must "declare the verification rung reached", `plan/SKILL.md`'s `plan-move` row said "lacks a verification-rung declaration" and its `plan-freeze` row "declares no verification rung", none of which tells the writer the form is verbatim. This is the drift class F3 already named (the required string appearing only in the refusal message, so the constraint is learned by hitting it), reintroduced one level out from the doc that was fixed. Separately, `AGENTS.md`'s docs-table row still summarized rung 3 as "build with output inspected", the wording F5 replaced when rung 3 was widened to cover changes with no closure to build, and credited the declaration to `plan-move ... done` alone when `plan-freeze` gates it too. All four rewritten in this pass to name the fixed phrase and the current rung-3 wording. Re-derived rather than trusted: the shipped pipeline was exercised against the doc's own accept examples (plain, bolded, bulleted, hard-wrapped mid-phrase, rung 1/2/3/4, the declare-then-skip form) and every phrasing "Declaring the rung" claims is refused (`Rung 3 verified`, `Verified at rung 3`, `Verified to rungs 3 and 4`, `The work is verified to rung 3`, `It was verified to rung 3`, `Not verified to rung 4`, `Verified to rung 12`) — all three stated rules hold, and the refusal message's wording matches what the doc instructs.


**FIXED 2026-09-07:** all five gate-describing docs now name the fixed phrase rather than 'a verification-rung declaration', and AGENTS.md's rung-3 summary matches F5's widened wording -- fixed in the same docs-updater pass that found them

### F7 — the case matrix is cited with two different sizes across this plan

- **File:** `docs/plans/in-progress/2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md` (G3 heading; `## State`; F3's resolution stamp)
- **Axis:** docs accuracy (docs-updater)
- **Finding:** G3's heading calls it "the 24-case matrix", while `## State` and F3's `FIXED` stamp both say "a 20-case matrix". Since G3 exists precisely because the matrix was discarded rather than committed, the number in the plan is the only surviving record of its size, and it disagrees with itself. Not fixed here: G entries, resolution stamps and `## State` are all off-limits to this pass. Whoever ran it should correct whichever number is wrong.

_docs-updater finished 2026-09-07T19:04:01Z -- see Findings above._

**FIXED 2026-09-07:** both numbers were true when written: the matrix held 20 cases when F3 was resolved, and four near-miss phrasings were added afterwards to prove the doc's own stated refusals. ## State describes now, so it was rewritten to 24, matching G3; F3's marker is append-only and correctly records the count at its own moment

### F8 — F4 is only half closed: a State that merely *quotes* the required phrase still passes, and the fix's own backtick-stripping is what makes it indistinguishable from a declaration

- **File:** `docs/skills/plan/scripts/lib.sh:225-231` (`plan_rung_problem`), `docs/procedures/testing-changes.md` "Declaring the rung"
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening (gate correctness) + needed-used
- **Reachability:** no network adversary — the principal is the agent or human running `plan-move <file> done` / `plan-freeze`, and the path is ordinary prose rather than evasion. Specifically: any plan whose *subject* is this tooling, whose `## State` therefore names the required phrase in code formatting. Thirteen such plans are live in `docs/plans/todo/` right now (`2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md`, `...-shrink-the-ci-trusted-set-by-splitting-lib-sh.md`, `...-make-plan-gate-survive-...`, and ten more), plus child 7's `verify-ladder` work. Exercised against the shipped function: a `## State` of ``Rule: `Verified to rung 3` must start the sentence.`` **passes**, as does ``The gate wants a fixed phrase; `Verified to rung 3` is it.`` Neither contains a declaration.
- **Rule:** n/a — new-rule candidate; same class as this plan's F4, which named this exact case ("any State that merely *quotes* the mechanism ... passes for free") and whose FIXED stamp claims it closed.
- **Finding:** F4's fix closed the verbatim-refusal-message case (that message quotes the phrase in single quotes, `'Verified to rung 3 ...'`, and a `'` is not a sentence-start character, so pasting the refusal into State is correctly refused — checked). It did not close the backticked case, and the fix *created* it: `tr -d '*_`>'` now deletes the backticks, so ``: `Verified`` and `: Verified` are the same string by the time `grep` sees them, and `:`/`;` are sentence-start characters. Backtick-stripping has no accept-case in "Declaring the rung" — that section teaches plain, bold, bulleted and hard-wrapped forms, never a code-formatted one — so on the needed-used axis the backtick in the `tr -d` set buys nothing and its only observable effect is this fail-open. The gate is deliberately require-declaration and knowingly accepts a *false* declaration; it is not supposed to accept the *absence* of one, and a sentence about what the gate wants is an absence.
- **Fix risk:** dropping `` ` `` from the `tr -d` set makes a genuinely code-formatted declaration (``**`Verified to rung 3`**``) refused — nobody writes that today, but it should then be named as refused in "Declaring the rung" alongside `Rung 3 verified` and friends, or the gate teaches string-fighting (map F1). Re-exercise both callers plus all nine `in-progress/` plans; today exactly two pass (`2026-09-05-route-every-fact-...` via a real `**Verified to rung 4 (VM).**`, and this plan), and both must still pass.


**FIXED 2026-09-07:** the backtick-stripping normalization is gone entirely. The matcher now anchors on the blank-line block rather than on preceding punctuation, so a code-formatted mention is refused because it does not open its paragraph, not because of which characters surround it. Both reported forms verified refused in a 35-case matrix

### F9 — the negation guard only inspects one character, so any of `.:;!)-` between the negation and the phrase reopens F4

- **File:** `docs/skills/plan/scripts/lib.sh:229-230`, `docs/procedures/testing-changes.md` "Declaring the rung", third bullet
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening (gate correctness) + needed-used
- **Reachability:** the closing agent again, writing the very prose `testing-changes.md` asks for — it instructs the writer to record what was skipped and why, so hedged and negated sentences about rungs are the expected content of `## State`. Exercised against the shipped function, all of these **pass** with no declaration present anywhere in the section:
  - `We have not (yet) verified to rung 3.` — the `)` of an ordinary parenthetical hedge
  - `Nothing was tested on a host -- verified to rung 3 is what would be needed.` — this repo writes `--` for an em dash in essentially every doc and plan
  - `Blocked: verified to rung 3 is not yet true.`
  - `Careful! verified to rung 3 has not happened.`
  - `The change is un-` / `verified to rung 3.` hard-wrapped across two lines — the F3 unwrapping step joins a hyphenated line break into `un- verified`, which the `-` then accepts
  - `<!-- Verified to rung 3 -->` alone in `## State` — the `-` of the comment opener supplies the sentence start, so a declaration that renders as nothing at all satisfies the gate; a fenced code block containing the phrase passes for the same reason
- **Rule:** n/a — new-rule candidate.
- **Finding:** the guard is `(^ *|[.:;!)-] +)`, i.e. "the phrase is preceded by body-start or by one of six punctuation characters plus space". `testing-changes.md` states the resulting rule as *"Anything else in front of the phrase — `is`, `was`, `not` — means it is not read as a declaration."* That sentence is false as shipped: it holds only when the negation is separated from the phrase by whitespace, and fails whenever it is separated by punctuation. Of the six characters, only `.` and `-` have an accept-case the doc actually teaches (sentence-after-period, and `- ` bullets; `*` bullets are handled by the `tr -d` instead). `:`, `;`, `!` and `)` are unexercised leniency whose only demonstrated effect is to widen this hole — the needed-used half. The distinction between "declared rung N" and "declined rung N" is the single distinction this gate exists to make, and it is decided by one character of context.
- **Fix risk:** requiring a clause with no negation word before the phrase, or matching only at a *line* start of the un-joined body, both tighten the gate and can newly refuse States already written — including this plan's own and the map's, so re-exercise both. Any tightening must land in "Declaring the rung" and in the refusal message *before* it lands in the matcher, or the operator learns the constraint by hitting it, which is the bypass-teaching failure map F1 names. Narrowing the class to `.` and `-` alone is the cheap half and costs no documented accept-case.


**FIXED 2026-09-07:** the one-character negation guard is replaced by a structural rule: the phrase must open a blank-line block, so nothing that precedes it inside a sentence can qualify. All six reported bypasses -- not (yet), the -- clause, the colon and semicolon forms, the HTML comment, and both wrap-split negations -- are refused in the matrix. testing-changes.md drops the false is/was/not claim and states the paragraph rule instead

### F10 — rung 3 defines itself twice and disagrees, and this pass's new "rung-3 floor" wording lets a green `verify-ladder` license the declaration on its own

- **File:** `docs/procedures/testing-changes.md` (rung 3; "Declaring the rung"'s closing paragraph), `docs/skills/workflow/scripts/verify-ladder:2-3`, `docs/skills/workflow/SKILL.md:31`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used (the declaration carries less than it claims)
- **Reachability:** the closing agent at `workflow/SKILL.md` step 8, who ran `verify-ladder` at step 4 and read no output. Path: step 4 is now titled "Run the scriptable verification floor"; `verify-ladder`'s own header now says it is "`testing-changes.md`'s lint gate plus its evidence ladder's rung-3 floor (eval, targeted build)"; `testing-changes.md` says "`verify-ladder` enforces the rung-3 *floor* mechanically". Three files, all touched in this pass, tell that agent it has reached the rung-3 floor. Rung 3 then says "a green build with its output unread is only this rung's floor" — which places an unread green build *at* rung 3 rather than below it.
- **Rule:** n/a.
- **Finding:** rung 3's title and body say the output must have been read ("Ran it locally, output inspected"; "**and the output was actually read**"), and its "One rung, not three" sentence says an unread build is still the rung, just its floor. The gate's entire payload is the number in `Verified to rung <N>`, so an ambiguity about what 3 means is an ambiguity in every declaration the gate will ever collect — and the ambiguity resolves in the weaker direction, because a script that reads nothing is the thing named as delivering the floor. The doc's own split paragraph draws the line the other way ("whether the output was actually inspected ... cannot be script-verified, so they are require-declaration"), which is the reading that makes the declaration worth requiring. Two of the three sentences should say the same thing and do not.
- **Fix risk:** none mechanical — this is wording. Saying "an unread green build is rung 2 plus a build; rung 3 begins when the output is read" would make `verify-ladder`'s header claim (`rung-3 floor`) wrong and it would need renaming again, which is the F1 vocabulary sweep for a fourth time. Cheaper to fix the one sentence inside rung 3 than the six files that now cite the ladder by number.

**Checked and clean (security, 2026-09-07, second pass on child 3).**
Re-derived F3 and F4 rather than trusting their FIXED stamps, by running
the shipped `plan_rung_problem` over a 55-case matrix. **F3 is closed:**
a declaration hard-wrapped mid-phrase (`Verified to` / `rung 3`), one
wrapped after the phrase, `**bold**`, `_underscore_`, `> blockquoted`,
`- `/`* `/`1. ` bulleted, indented, double-spaced, tab-separated,
uppercase, emphasis *inside* the phrase (`Verified to **rung** 3`,
`Verified to rung **3**`), and second-sentence-of-a-paragraph forms all
pass; the two live `in-progress/` plans that carry real declarations
both still pass. **F4 is partly closed:** `Not verified to rung 4`,
`This was not verified to rung 4`, the same negation split across a wrap
boundary, `not_verified`, `Nothing is verified`, `Never verified`,
`Nowhere near verified`, `Rung 3 verified`, `Verified at rung 3`,
`Verified to rungs 3 and 4`, `rung 0`, `rung 6`, `rung 12`, a
double-quoted declaration and the refusal message pasted verbatim into
`## State` are all refused — but see F8 and F9 for the two shapes that
are not. The `tr -d`/`tr -s` normalization introduces no fail-open from
the cases probed for it: `not_verified`, `**not** verified`,
`>Verified` mid-word and a word ending in `-` with no following space
all still refuse; `-` only reopens the hole when a space follows it
(F9). CRLF fails **closed** — `grep -q '^## State$'` misses the
`\r`-terminated heading, so `plan_state_problem` refuses first with a
misleading "no `## State` heading found"; pre-existing, untouched here,
and in the safe direction. Direction that matters, both ways: a `##
State` with no declaration is refused by `plan-move ... done` and by
`plan-freeze` independently, and every accept form "Declaring the rung"
actually teaches is accepted (the one gap is a `+ `-bulleted
declaration, a markdown bullet marker this repo never uses). No new
close-out path: `plan-new`'s template seeds no declaration, so no plan
auto-passes at birth; `plan-carry` appends the carried `D` section to
the end of the file, never into `## State`; `plan-reject` remains
deliberately ungated. Confirmed the only behavior change outside
`plan_rung_problem` is comment and doc text: `git diff HEAD` over
`*.sh`, `.githooks/` and both skills' `scripts/` directories touches
only `lib.sh` (the two new functions plus the `plan_state_body`
refactor, byte-identical awk), the two four-line gate calls in
`plan-move`/`plan-freeze`, and `verify-ladder`'s header comment;
`modules/flake/checks.nix` changes one word inside a `#` comment and no
Nix evaluation semantics with it. No host, service, systemd unit,
firewall rule, capability, user or group was touched anywhere in this
diff, and nothing under `secrets/` or `.sops.yaml` was read or
referenced.

_security finished 2026-09-07T19:12:28Z -- see Findings above._

**FIXED 2026-09-07:** rung 3 now has one definition: running it is the cheaper half and does not reach the rung, which is earned by reading the output. The three floor phrasings were rewritten to say so -- verify-ladder's header and testing-changes.md now call it rung 3's mechanical half and state that passing it is not what gets declared

### F11 — F10's "three floor phrasings" fix landed on one of three; two newly-written `rung 3's floor` claims survived in testing-changes.md

- **File:** `docs/procedures/testing-changes.md:125` (the checked-vs-declared paragraph), `docs/procedures/testing-changes.md:207` ("When to reach for which rung", first bullet)
- **Axis:** docs accuracy (docs-updater)
- **Finding:** F10's `FIXED` stamp says all three "floor" phrasings were rewritten to "rung 3's mechanical half". Only `verify-ladder`'s header and testing-changes.md's automation bullet were. Two other lines, both *added* by this same diff, still carried the retired framing: "`verify-ladder` enforces the rung-3 *floor* mechanically" and "let the `pre-push` hook catch anything real — rung 3's floor". Both contradict rung 3's new single definition three sections above them ("running it is the cheaper half and does not reach this rung on its own"; "the rung is earned by **reading the output**"), and both are exactly the F10 failure mode: a green script with its output unread presented as landing the reader at rung 3. Fixed in place — 125 now says `verify-ladder` runs rung 3's mechanical half "which is not the same as reaching rung 3", and 207 says reading what the hook printed is what makes it rung 3.
- **Also fixed:** `docs/skills/plan/scripts/lib.sh:236-238` said the block normalizer strips "One marker" when it applies three anchored `sub()`s in sequence (numbered, bullet/quote, emphasis) and can strip more than one from a single block (`- **Verified to rung 3**`). Reworded to "one anchored sub per marker kind"; awk behavior unchanged.
- **Verified:** re-derived the shipped `plan_rung_problem` over the 22 accept/refuse cases "Declaring the rung" itself states — bold, bullet, numbered, blockquote, underscore-emphasis, hard-wrapped and second-paragraph declarations all pass; `We have not (yet) verified to rung 3.`, ``the phrase `Verified to rung 3` ``, a bare backticked phrase, `Blocked: verified to rung 3 is not yet true.`, a mid-sentence mention, `Verified to rungs 3 and 4`, `Verified at rung 3`, `Rung 3 verified`, `-- verified to rung 3 was never true.`, `### Verified to rung 3 is the goal`, and rungs 0/6/12 are all refused. Every claim in that section is true of the shipped matcher, and the refusal message's example phrase matches the doc's verbatim.

_docs-updater finished 2026-09-07T19:30:47Z -- see Findings above._

**FIXED 2026-09-07:** both surviving floor claims rewritten in the docs-updater pass that found them -- one of them added by the F10 fix itself, which is why F10's marker overstated its own reach. lib.sh's marker comment now describes the three anchored subs rather than 'one marker'

### F12 — the rung gate reads every `## State`-shaped line in the file, fences included, so a plan can satisfy both State gates without owning a real State section

- **File:** `docs/skills/plan/scripts/lib.sh:197-199` (`plan_state_body`), `:206-211` (`plan_state_problem`), `:229-250` (`plan_rung_problem`), `docs/skills/plan/scripts/plan-lint:30`; interacts with G4
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening (gate correctness) + needed-used
- **Reachability:** no network adversary — the principal is the agent running `plan-move <file> done` / `plan-freeze`, and the path is ordinary prose, not evasion. Specifically: any plan whose subject is this tooling and whose body therefore quotes an example State section. `docs/skills/plan/reference.md:168-196` already carries a full worked plan example with a column-0 State heading, and "Declaring the rung" is the section such a plan would paste. Measured against the shipped functions: a fixture whose real State reads `Still in progress; nothing verified yet.` and which shows the required form in a fenced `markdown` block under `## Progress` **passes** `plan_rung_problem`. A fixture with **no** State section at all, only that fenced example, passes `plan_state_problem` *and* `plan_rung_problem` — every State-quality gate in the repo, satisfied entirely by quoted text.
- **Rule:** n/a — new-rule candidate.
- **Finding:** `plan_state_body` is `awk '/^## State$/{f=1;next} /^## /{f=0} f'`, and three of its properties are unbounded. It does not track code fences. `f` is re-armed by *every* matching line, so the body is the union of all State headings in the file rather than the first section. And the two older readers are blind the same way — `plan_state_problem`'s `grep -q` and `plan-lint`'s required-section check both accept a fenced heading. The extractor is pre-existing; what is new is that a gate whose entire value is "the closing agent wrote a claim, in their own State, on purpose" now rests on it. Separately, G4 records the indented-code-block residue and argues that "a fenced block is already refused (the paragraph then opens with a backtick, not the phrase)". That reasoning holds only for a fence containing no blank line: give the fence a blank line before the declaration — which is exactly what quoting a State section looks like, heading, blank, declaration — and the declaration opens its own block and is accepted. Same family as G4, but by a mechanism G4 states is closed, so it is not covered by that acceptance.
- **Fix risk:** bounding the extractor (track fences; stop at the first `## ` after the first State heading) changes what `plan_state_problem` and `plan-lint` see too, so a plan whose real State is empty while quoting a filled one would newly be refused by three gates at once instead of passing all three. Re-exercise every live plan: exactly two pass today (`2026-09-05-route-every-fact-...:149` and this plan's own `:83`), both via real declarations, and both must still pass. If G4's acceptance is to be kept, its stated reason needs correcting either way — it is not true as written.


**FIXED 2026-09-07:** plan_state_body now tracks code fences and arms on the first State heading only, and returns non-zero when the file has none; plan_state_problem reads presence from that same call instead of its own grep, so the two cannot disagree. Both reproductions verified: the fenced example no longer satisfies the rung check, and a plan whose only State is fenced now reports no heading found. A real declaration whose State contains a fenced command block still passes

### F13 — the block anchor's stated premise is false in the subject position: a mention that *is* the paragraph's subject passes, including in the bold and bullet forms the doc teaches

- **File:** `docs/skills/plan/scripts/lib.sh:220-225` (the rationale comment), `:239-242` (the marker strips and the match), `docs/procedures/testing-changes.md:98-109`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening (gate correctness)
- **Reachability:** the closing agent again, on any plan whose State discusses the gate — the same thirteen `docs/plans/todo/` tooling plans F8 enumerated. Exercised against the shipped `plan_rung_problem`; every one of these **passes** with no declaration anywhere in the section:
  - `Verified to rung 3 is the phrase the gate demands; we have not reached it.`
  - `**Verified to rung 3** is the line this gate wants; nothing here has been run.` — the `^[*_]+` strip removes the opening `**`, and the closing `**` is absorbed by the `([^0-9].*)?` tail
  - `*Verified to rung 5* was never claimed -- we stopped at rung 2.`
  - `_Verified to rung 4_ is what a VM run would let us say.`
  - `- Verified to rung 3 would be a lie here.`
  - `> Verified to rung 3 is what the doc tells you to write.`
  - a multi-line HTML comment — `<!--`, blank, the declaration, blank, `-->` — which renders as nothing and satisfies the gate; the single-line form F9 reported is now correctly refused, so this is that case surviving in block shape
- **Rule:** n/a — new-rule candidate; the same "names the phrase rather than claiming it" shape as F8, whose FIXED marker says the rewrite closed it because "a code-formatted mention is refused because it does not open its paragraph".
- **Finding:** the comment justifies the whole design with "a mention lives inside a sentence by definition, so it never opens the paragraph it sits in". That is true of a mention in object position (`the phrase X`, `we have not yet X`) and false of one in subject position (`X is what the gate wants`), which is the natural English for writing *about* a required string — and writing about this required string is the subject matter of a dozen live plans. Two of the matcher's own components make it worse rather than better. The `^[*_]+` emphasis strip is what renders `**Verified to rung 3** is the line...` byte-identical to the doc's taught `**Verified to rung 3 (...)**` by the time the regex runs. And the open-ended `([^0-9].*)?` tail means everything after the number is unexamined, so the clause that turns the claim into a denial is precisely the part not looked at. On the needed-used axis the tail buys only the parenthetical the doc teaches, and it costs the entire remainder of the sentence.
- **Fix risk:** a copula guard (refusing a following ` is `/` was `/` means `/` would `) costs no accept-case "Declaring the rung" teaches, but it is a fourth round of the character-class patching the block anchor was adopted to end, and it will not catch `Verified to rung 3 -- that is what this gate wants`. Constraining the tail instead (a parenthetical, a `--` clause, or end-of-block) is more structure but is checkable against the doc's own examples. Either direction can newly refuse States already written: this plan's `:83` and the map's `:149` must both still pass, and any tightening has to land in "Declaring the rung" and in the refusal message before it lands in the matcher, or it teaches string-fighting (map F1).


**FIXED 2026-09-07:** the phrase must now end the claim: what follows the rung number is punctuation or nothing, never another word, which is what a subject-position mention always has. Emphasis is deleted throughout rather than stripped from the front, so a bolded mention cannot hide behind its markers while backticks stay undeleted and keep F8 closed. All five reported forms, including the multi-line HTML comment, verified refused

### F14 — two rows added by this diff tell the writer the gate is sentence-anchored; the shipped gate is block-anchored, so a declaration written to their spec is refused

- **File:** `docs/skills/plan/SKILL.md:25`, `docs/skills/workflow/SKILL.md:62` (both lines added by this diff); shipped behavior at `docs/skills/plan/scripts/lib.sh:229-250`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** needed-used (documentation that no longer matches the code) + hardening (an un-passable gate teaches the bypass)
- **Reachability:** the closing agent at `workflow/SKILL.md` step 8 — the one step in the sequence that says what the gate wants, in the file the skill loads into context. Both rows say the State section must carry "a sentence starting with the fixed phrase `Verified to rung <N>`". Measured against the shipped function, a sentence starting with the phrase is refused unless it also opens the block: `The restructure is done and the docs are updated. Verified to rung 3 (ran it locally, output inspected).` is **refused**, and so is `Everything landed.` on one line followed by `Verified to rung 3 (ran it locally).` on the next with no blank line between — the second is what hard-wrapped prose produces on its own.
- **Rule:** n/a — this is F6's class (the gate-describing docs kept a pre-tightening description) reintroduced by the F8/F9 fix, which changed the anchor from sentence to block without re-sweeping the two rows F6 had just rewritten.
- **Finding:** three of the five gate-describing places are right and two are wrong, and the two wrong ones are the ones an agent actually reads. `docs/procedures/testing-changes.md:98` states the rule correctly ("It opens its own paragraph or list item"), and `plan/reference.md:126-127` and `workflow/reference.md:29-30` are correct by being unspecific ("declares no verification rung"). The two `SKILL.md` rows assert a unit — the sentence — that the matcher stopped using. The failure is in the expensive direction: it does not let a mention through, it refuses a truthful declaration, and an agent's recovery from an unexplained refusal is to reshape the string until the gate stops complaining, which is the behavior the map's F1 says a gate must not train.
- **Fix risk:** none mechanical — replace "sentence" with "paragraph or list item" in both rows and point at "Declaring the rung", which already carries the accept/refuse examples. Worth pairing with something that keeps them honest, since this is the second time these two rows have gone stale inside one plan.

**Checked and clean (security, 2026-09-07, third pass on child 3).**
Re-derived the shipped `plan_rung_problem` against the doc's own
examples rather than trusting the F8/F9/F10 markers. **The three fixes
hold for what they claimed:** every accept form "Declaring the rung"
teaches passes — plain, `**bold**`, `- ` and `* ` bulleted, `1. `
numbered, `> ` blockquoted, two-space-indented, hard-wrapped mid-phrase,
a declaration in the second paragraph, and the declare-then-skip form —
and every refusal that section states is refused: `We have not (yet)
verified to rung 3.`, ``the phrase `Verified to rung 3` ``, `Blocked:
verified to rung 3 is not yet true.`, `-- verified to rung 3 is the
phrase.`, `### Verified to rung 3`, `Verified to rungs 3 and 4`,
`Verified at rung 3`, `Rung 3 verified`, and rungs 0/12/35. The marker
strips are tight in the direction claimed: `>> `, `>Verified`, a table
row, a footnote definition, a `- [ ] ` task item and a fence with no
blank line in it are all refused. Two markdown forms are refused that
arguably should not be, both harmless and neither taught by the doc: a
`+ `-bulleted declaration (noted last pass) and a bulleted blockquote
(`> - `), since only one marker is stripped. Where the fixes do not hold
is F12/F13 above.
**Callers and ordering:** both `plan-move`'s `done` branch (`:45`) and
`plan-freeze` (`:37`) call it, each *after* `plan_state_problem`, which
is the right order — a missing or empty section reports as itself rather
than as a missing declaration — and `plan-move ... done` `exec`s
`plan-freeze`, so the gate applies twice on that path and once on a
direct freeze. `plan-reject` remains deliberately ungated and its header
comment still says why. No other caller exists: `plan-lint`, `plan-new`,
`plan-tick`, `plan-carry`, `plan-decide`, `plan-resolve`,
`.githooks/*` and `.github/workflows/*` reference none of the three
functions, and `plan-new`'s template seeds no declaration, so no plan
auto-passes at birth. **Fail-closed direction:** awk's `found` is unset
when no block matches, so `exit found ? 0 : 1` refuses; a missing file
yields empty output and refuses; CRLF still fails closed and now fails
closed twice, since a `\r`-only line is not `/^[ \t]*$/` and the whole
section collapses into a single block (`plan_state_problem` refuses
first regardless).
**Rest of the diff:** `git diff HEAD -- docs/skills/*/scripts .githooks
'*.nix'` touches only `lib.sh` (the `plan_state_body` extraction,
byte-identical to the awk it replaced, plus the new `plan_rung_problem`),
the two four-line gate calls in `plan-move`/`plan-freeze`,
`verify-ladder`'s header comment, and one word inside a `#` comment in
`modules/flake/checks.nix` — no Nix evaluation semantics change, and
`.githooks/` is untouched. No host, service, systemd unit, firewall
rule, port, capability, user or group appears anywhere in this diff;
nothing under `secrets/` or `.sops.yaml` was read, referenced or
decrypted.

_security finished 2026-09-07T19:41:07Z -- see Findings above._

**FIXED 2026-09-07:** both SKILL.md lines now say the declaration opens a paragraph rather than starts a sentence, matching the block anchor; testing-changes.md's rule gained the same 'and the sentence ends there' wording so all three describe one rule

### F15 — "Declaring the rung" describes a scanner that reads the whole State, so a fenced example still reads as an accepted declaration

- **File:** `docs/procedures/testing-changes.md:98-111`, shipped behavior at `docs/skills/plan/scripts/lib.sh:263` (`plan_state_body "$1" skip-fences`)
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the second bullet spells out the matcher's mechanism -- "joins each blank-line-separated block, drops emphasis and leading markers, then requires the phrase at the front" -- and never mentions fences, so read literally it says a fenced example whose declaration sits after a blank line is a declaration. That is exactly the F12 reproduction, and it stopped being true when `plan_rung_problem` started reading the section through `plan_state_body ... skip-fences`. The refusal list next to it teaches the inline-code case (``the phrase `Verified to rung 3` ``) but not the fenced one, which is the shape a plan documenting this schema actually writes. Rewritten this pass: the mechanism sentence now leads with "drops fenced code blocks", and the refusal list ends with the fenced declaration and why it is refused. Re-derived against the shipped functions: all four accept-examples the section teaches pass, all seven refusals it names refuse, a fenced example inside a real State is refused, and a real declaration whose State also carries a fenced command block passes.


**FIXED 2026-09-07:** the rule now names the fence step first -- the gate drops fenced blocks, then joins blank-line-separated blocks -- and the refusal list ends with the fenced declaration, so quoting the required form in an example cannot read as declaring it

### F16 — the marker-strip comment names `###`, which no strip in the function touches

- **File:** `docs/skills/plan/scripts/lib.sh:274-276`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the comment above the marker strips said the trailing-space requirement is what keeps `--` and `###` from being mistaken for a list marker. The strips are `^[0-9]+[.)] ` and `^[->] `; `#` is in neither class, so the trailing space is load-bearing for `--` only and a `###`-opened block is refused regardless. Comment tightened to name `--` alone.


_docs-updater finished 2026-09-07T20:01:03Z -- see Findings above._

**FIXED 2026-09-07:** the comment names '--' alone, which is what the trailing-space requirement in the [-<] strip actually excludes; '###' is refused because '#' is in neither strip class, not by that rule

### F17 — the fence dropper is anchored at column 0, so a declaration quoted inside an *indented* fence is accepted as the plan's own

- **File:** `docs/skills/plan/scripts/lib.sh:214` (the fence match), `:263` (`plan_state_body "$1" skip-fences`), `:266-269` (the whitespace collapse that undoes the indentation); `docs/procedures/testing-changes.md:110-112`; `docs/skills/plan/scripts/lib.sh:196-198` (the comment asserting the property)
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening (gate correctness) + needed-used (two places assert a property the code does not have)
- **Reachability:** no network adversary — the principal is the closing agent running `plan-move <file> done` / `plan-freeze`, and the path is ordinary house style, not evasion. Nesting a code example under a bullet or a numbered step *requires* indenting the fence, and this repo does it 62 times under `docs/` — `docs/skills/plan/reference.md:15-22` (the plan-file schema itself), `docs/procedures/vm-testing.md:139-154`, `docs/architecture.md:229-241`. Reproduced against the shipped functions: a fixture whose real State reads `Nothing verified yet.` and then, under a `- Example:` bullet, carries a **two-space-indented** backtick fence containing `## State`, a blank line, and `Verified to rung 3 (ran it locally).` **passes** `plan_rung_problem` and `plan_state_problem` both. One space of indentation is enough; so is a three-space fence under `1. `. No plan file uses an indented fence today, so this is reachable-but-unexercised.
- **Rule:** n/a — new-rule candidate; the F12 class, reopened by F12's own fix.
- **Finding:** CommonMark allows a fence marker up to three spaces of indentation, and a fence nested inside a list item must be indented. The `^` in the fence match sees none of those, so `fence` never sets and `skip-fences` drops nothing — while the block normaliser two functions later collapses `[ \t]+` to a single space and strips one leading space, erasing the very indentation that hid the fence. The two halves conspire: the dropper is indentation-sensitive, the matcher indentation-blind, so the more markdown-correct the example, the more likely it is to read as a claim. This is **not** G4 residue: G4 is a four-space indented code block with no fence, and its stated reason — "a fenced block is already refused" — is precisely the claim that fails here. Two places now assert the property outright: the new comment at `:196-198` ("fenced blocks inside the section are dropped") and `testing-changes.md:110-112` ("as is a declaration inside a fenced code block, so a plan that quotes the required form in an example never declares it by accident"). Both are true only at column 0.
- **Fix risk:** allowing up to three leading spaces before the marker means the opener indentation has to be remembered and the closer allowed its own, independently, per CommonMark; over-widening to *any* indentation would start swallowing four-space indented code blocks, flipping G4 from an accepted residue into a silent behavior change nobody asked for. Re-exercise every accept form "Declaring the rung" teaches plus the two live plans that pass today. Whichever way it lands, the "never declares it by accident" sentence in `testing-changes.md` has to become true of indented fences or be narrowed to say column-0 only.


**FIXED 2026-09-07:** the fence matcher allows leading whitespace, so an indented fence -- three spaces, or the deeper indent a list-nested fence requires -- is tracked like any other. scripts/gate-tests asserts all six reported shapes refuse, and the quoting property sweeps four fence forms including an indented one

### F18 — the trailing-punctuation guard inspects one character, so a punctuation-led mention or an outright denial is accepted

- **File:** `docs/skills/plan/scripts/lib.sh:284` (the rung regex), `:280-283` (the comment stating the premise), `docs/procedures/testing-changes.md:104-109`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening (gate correctness) + needed-used (the refusal list teaches a rule the matcher does not implement)
- **Reachability:** the closing agent again, on any plan whose State discusses this gate — the same thirteen `docs/plans/todo/` tooling plans F8 enumerated. Exercised against the shipped `plan_rung_problem` as its own State; every one of these **passes** with no declaration anywhere in the section:
  - `Verified to rung 3 (the required phrase) is not yet true.`
  - `Verified to rung 3 -- we have not reached this.`
  - `Verified to rung 3 -- that is the phrase the gate wants -- is not something we can claim yet.`
  - `Verified to rung 3, which is the line this wants, has not been written.`
  - `Verified to rung 3: this is the phrase, not a claim.`
  - `Verified to rung 3? Not yet.`
- **Rule:** n/a — new-rule candidate; the F4/F8/F9/F13 family, fifth occurrence, again created by the previous fix.
- **Finding:** the comment and the F13 FIXED marker both say "what follows the rung is punctuation or nothing, never another word ... which is what a subject-position mention always has". The second clause is false. Only the *first* character after the number is examined; the `.*` that follows swallows the rest unread, so a subject-position mention needs exactly one punctuation mark before its copula to pass. This is F9 in mirror image — F9 was "the negation guard only inspects one character, so any of `.:;!)-` between the negation and the phrase reopens F4", and the same single-character horizon has now been rebuilt on the trailing side. F13 own Fix-risk text predicted it (`it will not catch "Verified to rung 3 -- that is what this gate wants"`), the shipped matcher confirms it, and nothing in G4 or the FIXED marker records it as accepted. The doc names `Verified to rung 3 is the line this wants` as refused — it is — while a one-character variant of that exact sentence is accepted, so the refusal list overstates what the gate does. Note the direction: the accepted forms are not evasions, they are *denials* — a State that says the rung was not reached satisfies a gate whose only job is to make the claim explicit.
- **Fix risk:** constraining the tail to a shape the doc already teaches — a parenthetical, a `;`-introduced skip clause, or end-of-block — is checkable against the four accept examples in "Declaring the rung", but it is a fifth round of the character-class patching the block anchor was adopted to end, and each round so far has opened the next hole. Any tightening can newly refuse States already written: this plan `:83` and the map `:149` must both still pass. The alternative worth considering is to stop patching and accept this residue in G4 explicitly, with the reason stated correctly this time — but then `testing-changes.md:104-109` must stop listing `Verified to rung 3 is the line this wants` as the boundary case, because the boundary is one character to the left of where the doc puts it.


**ACCEPTED 2026-09-07:** accepted by the user (LilijoySkyseeker) 2026-09-07: a declaration whose later clause denies it is a false declaration, which G4 already puts outside a require-declaration gate's reach -- separating it from the legitimate trailing-clause form needs meaning, not form, and this plan's own State uses that form. Asserted in scripts/gate-tests as a recorded residue, so a later tightening shows up as a change rather than a surprise

### F19 — fence state is file-global, so one unbalanced fence relocates the State section for both gates at once

- **File:** `docs/skills/plan/scripts/lib.sh:214-220` (the fence state), `:221-222` (arm/disarm, both guarded by `!fence`), `:238`, `:263`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** hardening (gate correctness, both directions)
- **Reachability:** the closing agent on a plan whose prose opens a column-0 fence it never closes. The natural way to acquire one is a plan *about* fences, which is this branch subject matter. Measured today: no file under `docs/plans/`, `docs/procedures/`, `docs/skills/` or `AGENTS.md` is unbalanced under the function own rule, so this is latent rather than live.
- **Rule:** n/a — new-rule candidate.
- **Finding:** two reproduced consequences, one in each direction. (1) **A declaration in another section satisfies the gate.** A fence opened at column 0 inside `## State` and closed inside a later section makes both readers treat everything up to the next heading *after the closer* as State: a fixture whose State says `Nothing verified yet.` and opens a bare fence, whose `## Progress` closes it and then reads `Verified to rung 5 (deployed to vps).`, **passes** `plan_rung_problem`. The `!fence` guard on the disarm rule is what does it — a `## ` line inside a fence cannot end the section, which is correct for a real fence and wrong for an unbalanced one. (2) **A real State with a real declaration is refused with the wrong reason.** A fence opened before `## State` and never closed hides the heading from both readers, and `plan_state_problem` then reports the missing-heading message for a file that plainly has one — an un-passable gate whose message points at the wrong thing, which is the class the map F1 says must not be taught. Separately confirmed and fine: the two callers *cannot* disagree with each other about the boundary, because `skip` controls only whether a line is printed, never the `fence` or `f` transitions — verified by diffing both modes over the same fixtures. They can, however, both be wrong together.
- **Fix risk:** the obvious repairs are not free. Resetting fence state at each `^## ` would close (2) but break the legitimate case the F12 fix exists for — a fenced example plan containing `## State` lines. The cheap half is diagnostic rather than semantic: when `fence` is still set at `END`, say "unbalanced code fence" instead of "no heading found", which costs no accept case and turns a dead end into an actionable message. Anything more should wait for the fixture harness `2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md#G1` is going to hold, since this is the fourth consecutive pass in which a fix to this function opened the next hole.

**Checked and clean (security, 2026-09-07, fourth pass on child 3).**
Re-derived the shipped `plan_state_body` / `plan_state_problem` /
`plan_rung_problem` from the file rather than from the FIXED markers, over
a fixture set built in a scratch directory outside the repo. **F12 and F13
hold for the column-0, single-word cases they claimed:** a plan whose only
`## State` sits in a column-0 fence now reports no heading found; a fenced
example under `## Progress` no longer satisfies the rung check; a
column-0 tilde fence behaves the same as a backtick one; a four-backtick
opener is not closed by a three-backtick line and a backtick fence is not
closed by a tilde line, so the nested-fence desync the comment describes
is genuinely closed at column 0.
**Accept forms:** all nine forms "Declaring the rung" teaches pass —
plain, `**bold**`, `_italic_`, `- ` bulleted, `1. ` numbered, `> `
blockquoted, bare with no trailing punctuation, hard-wrapped mid-phrase,
and the declare-then-skip sentence — as does a real declaration whose
State also carries a fenced command block, indented or not, before or
after it. All ten refusals that section names are refused. No truthful
declaration in the documented form was found to be refused. Two narrow
refusals that are not taught and stay harmless: a `+ `-bulleted
declaration (only `-` and `>` are stripped, noted in the third pass too),
and a declaration written with no blank line on *either* side of an
adjacent fence, where `skip-fences` glues it to the preceding prose into
one block — a blank line before the fence or after it is enough to make
it pass, and repo style always has one.
**Boundary agreement (asked explicitly):** `plan_state_problem` and
`plan_rung_problem` cannot disagree about where State starts or ends.
Both go through `plan_state_body`, and `skip` gates only the `next`s that
suppress output — every `fence`, `seen` and `f` transition is identical
in both modes, so the presence answer and the content answer come from
one traversal. F19 is the residual: they agree with each other and can
still both be wrong. **G4 family:** the four-space indented-code-block
residue is still present and is not re-raised. F17 is a different
mechanism (a fence the tracker does not see, not a block with no fence)
and contradicts G4 stated reason, so it is reported. `plan-lint` fence-
blind `grep -qF "## State"` is unchanged and also not re-raised.
**Rest of the diff:** `git diff HEAD` over the scripts and Nix shows no
behavior change outside the three functions — the two three-line gate
calls in `plan-move`/`plan-freeze` (both scripts `set -u` only, so the
`[ -n ... ] && plan_die` form cannot exit early on a false test),
`verify-ladder` header comment, and one word inside a `#` comment in
`modules/flake/checks.nix`. `.githooks/` untouched. `plan-gate` and the
GitHub workflow call none of the three functions, so the new interval
expressions in the fence regex never meet a non-gawk `awk`; locally
`awk` is gawk 5.4.1. No host, service, systemd unit, firewall rule,
port, capability, user or group appears anywhere in this diff; nothing
under `secrets/` or `.sops.yaml` was read, referenced or decrypted.

_security finished 2026-09-07T20:14:31Z -- see Findings above._

**ACCEPTED 2026-09-07:** accepted by the user (LilijoySkyseeker) 2026-09-07: an unbalanced fence is a malformed document, no file in the repo has one, and the dominant direction is fail-closed -- the State reads as missing. The alternative, disarming on a fenced heading, trades it for the worse failure of truncating a real State and refusing an honest declaration
