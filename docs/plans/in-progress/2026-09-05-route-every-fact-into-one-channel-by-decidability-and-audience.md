---
slug: route-every-fact-into-one-channel-by-decidability-and-audience
created: 2026-09-05
status: in-progress
frozen: false
---

# route every fact into one channel by decidability and audience

**Plan kind: map.** The first plan of the `map` kind proposed in D4 — a
destination plus child plans with blocking edges, worked one child at a
time, rather than a single task plan. Until D4's `blocked_by` frontmatter
exists the edges live in Progress below (see G1).

## Original plan

### Destination

Every fact in this repo lives in **one** channel, chosen by whether a
machine can decide it and who needs to read it — and the mechanism that
keeps it there runs without anyone remembering to run it.

Reaching it means: no channel carries a fact another channel already
carries, every obligation fires on a mechanical trigger rather than on
judgment, and an outside reader can learn something here without reading
anything written for an agent.

### Why

Three failures, one cause:

1. Agents do not read `docs/` prose.
2. Agents do not update it — **78 of 86** plan files still carry the
   untouched `*(populated by security/docs-updater when invoked)*`
   placeholder.
3. There is no concise human-facing layer, though the repo is public
   under the Unlicense specifically so others can learn from and lift
   out of it.

The cause is visible in one file. `docs/skills/workflow/SKILL.md` step 6
mandates `/simplify` for every non-trivial change — done — and
`security`/`docs-updater` "where relevant" — done ~9% of the time. Same
skill, same agent, one sentence apart. **Judgment-gated obligations get
skipped; mechanically-triggered ones do not.** `scripts/doc-host.sh` is
the control: it fires on "did the diff touch host config", and its
generated inventory blocks are current.

Volume is a symptom, not the disease. Markdown outruns Nix roughly 4:1,
but prose nobody reads would be a problem at any size.

### The routing rule (D1)

Ask decidability first, then audience and scope:

| Ask | Channel |
|---|---|
| Can a machine decide it? | **Mechanism** |
| Does an agent need it on *every* task? | **`AGENTS.md`** — auto-loaded, hard budget (~1,290 words) |
| Does an agent need it *during a specific activity*? | **That activity's skill reference** — loaded on invoke |
| Otherwise, a person needs to understand it | **Human prose** — `README.md`, explainers, `docs/` |

Decidability leads because it is the only objective question; audience is
a judgment call, and leading with it makes every routing decision inherit
that judgment. `AGENTS.md` is both index and rules channel, and its budget
is exactly what forces the third row to exist.

**No fact is rendered twice, and the unit is the fact, not the topic.**
ZFS policy tiers spans all four channels without duplication: "tier is
path segment 2, a dataset declared without one is an eval error" is
mechanism (`modules/nixos/datasets.nix`); "never point a root service at
a user-writable path" is an `AGENTS.md`-class standing rule; "how to add
a dataset to a live host" is a skill reference, because disko will not and
`zfs create` stays manual; "why exclusion means a separate dataset" is
human prose, already in
`docs/adr/0001-zfs-policy-tiers-and-the-mydatasets-registry.md`.

Plans and ADRs are orthogonal to all four — they are the why-record, not
a delivery channel.

### Notes

Consult on every session working this map: `docs/skills/plan/SKILL.md`,
`docs/skills/workflow/SKILL.md` and its `reference.md` (trust hierarchy),
`docs/style-guide.md`, `docs/procedures/testing-changes.md`.

Standing preference for this effort: prefer deleting prose over rewriting
it, and prefer a generated block over prose describing what could be
generated.

### Out of scope

Ruled outside this destination; these do not graduate.

- **Adopting the Matt Pocock engineering skill set.** Evaluated and
  declined: its pipeline assumes a live issue tracker (this repo has 0
  issues and 86 plan files) and a sub-second test loop (this repo has 8
  VM tests that boot real machines), and its enforcement is prose where
  this repo's is hooks. Four ideas were taken and appear as children
  below — the map shape, expand-contract, two-axis review separation,
  and the diagnosis goal met by making the trust hierarchy binding.
  Nothing else from it is in scope.
- **Rewriting the plan-file schema.** See D4 — a rewrite breaks 86 files
  and 31 live `# plan:` code citations to buy what a targeted revision
  already delivers.
- **Rolling back `docs/adr/`.** See D3.
- **Deleting any plan, audit, or superseded document.** See D5.

## State

**2026-09-05: child 5 done, child 1 all but one item, G5 and G6 closed.**
D1-D10 are settled from a full grilling session with the user on
2026-09-05.

Landed so far:

- **G5** — `tests/zrepl-replication.nix` imports nixpkgs' test SSH keys by
  path concatenation rather than string interpolation. `verify-ladder`
  had been un-passable on master for any change.
- **G6** — child 2 re-blocked behind child 5; 18 live `#G` citations
  would have broken silently otherwise.
- **Child 5** — `docs/skills/plan/scripts/plan-citations` exists and is
  wired into `verify-ladder`. 167 citations resolve, zero broken.
- **Child 1** — seven of eight corrections applied across `AGENTS.md`,
  `docs/adr/README.md`, `docs/procedures/testing-changes.md`,
  `docs/skills/plan/reference.md` and `docs/skills/workflow/SKILL.md`.
  The eighth, the GitHub description and homepage URL, needs the user's
  own wording.

**2026-09-06: child 4 landed**, so 6, 7, 8 and 14 are unblocked.
`docs/skills/workflow/scripts/required-agents` computes the obliged set
from the diff; `workflow/reference.md`'s "Subagent selection" and step 6
of `workflow/SKILL.md` no longer contain a judgment escape. Child 1 is
complete — GitHub description and homepage set 2026-09-06.

**2026-09-06: child 6 landed, and D11 with it.** `plan-gate` now refuses
a merge unless every obliged, stampable agent left a completion stamp in
the cited plan, and the stamp carries a fingerprint of the code it read
so a stale stamp is caught rather than accepted. `/simplify` ran and its
ten findings were applied; `security` and `docs-updater` follow.

Also this session: skill scripts and git hooks were added to the trigger
set. They are code *and* they are the enforcement machinery — a change to
`plan-gate` or `verify-ladder` can weaken every other gate — so keying
only off `.nix` had left them reviewed by nothing.

Four children done (1, 4, 5, 6). Next takeable: child 3 (smallest),
child 2 (now that 5 has landed), child 7, or child 8.

**Verified to rung 4 (VM).** `verify-ladder` passes, and
`nix build .#checks.x86_64-linux.zrepl-replication` booted both VMs and
produced `vm-test-run-zrepl-replication`. Not deployed to any host, and
nothing here needs a switch.

---

### Pick-up point, 2026-09-07 (unreviewed tail closed)

**Where.** Worktree
`/home/lilijoy/dotfiles/.claude/worktrees/map-plan-docs-channel-routing`,
branch `worktree-map-plan-docs-channel-routing`, PR **#68**. Work there,
not in the main checkout.

**Children done:** 1, 4, 5, 6. G5, G6 closed; G11 added. D11 answered
and built.

**The unreviewed tail of `854156c` is closed.** The 2026-09-07 session
ran the full loop twice over `git diff origin/master...HEAD` plus the
working tree, in D7's order. Pass one: `/simplify` (four angles) applied
six cleanups -- `plan_in_list` replacing three membership idioms,
`plan_active_plan` tightened to `plan_locate`'s guard shape per F59's
own prescription, `plan_has_heading` reuse, dead awk guard dropped, and
the build-trigger set now spelled once per file in `pre-push` and
`verify-ladder` (equivalence tested case by case); `docs-updater` fixed
five comment/doc drifts (F61-F63); `security`'s seventh pass
re-reproduced the F52/F56/F57 fixes as real, proved the new build-set
selection never under-builds, and found F64 (the coordinated both-arrays
tamper still green-passed) and F65 (latent glob expansion in the new
`plan_in_list` call sites). Pass two, after the F64 floor and the array
conversions landed: all three agents clean, zero findings. F61-F65 all
resolved fixed.

**The full review record.** Eight `security` passes, seven
`docs-updater` passes and six `/simplify` rounds have produced **65
findings**: 58 fixed, 7 accepted by the user with a follow-up plan each.
The loop's own shape was settled with the user along the way -- see D7's
three dated notes for the order, the named fix stage, why the read-only
reviewers stay serialized, and the narrowed restart rule.

**What the review actually found, and it is worth reading before
touching any gate script.** Almost every defect was a gate that *failed
in a way that reported the wrong answer*, not a gate that was missing.
Eight instances reported success without checking; four blocked in a way
nothing could clear. Six were the same index-versus-worktree confusion,
five of those in `.githooks/pre-commit`, and four were live secret-scan
or frozen-plan bypasses reproduced end to end. Fifteen were documentation
describing code that had since changed. The classification is
`2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md`,
and its first item -- a failure-mode harness for the gate scripts --
would have caught eight of them mechanically.

**Thirteen follow-up plans are filed** under `docs/plans/todo/`, all
dated 2026-09-06. The ones that block or shape later work here: inverting the
code set from an allowlist to a denylist; making `plan-gate` survive a
PR that changes the fingerprint's inputs; making CI hash the tree it was
told to gate.

**Then the frontier:** child 3 (verification-ladder split, smallest),
then 2 (plan-file layout -- unblocked now 5 has landed, and it must run
as expand-contract per G6, since 18 live `#G` citations break otherwise),
then 7, 8, 14.

**Live traps a new session will hit:**

- `plan-citations`, `plan-lint` and `plan-gate` are wired into
  `verify-ladder`, so a broken citation, a malformed active plan or a
  missing stamp blocks commits. That is intended.
- Editing any of `PLAN_CODE_GLOBS` -- now including `.claude/`,
  `.github/workflows/`, `.sops.yaml`, `secrets/`, `flake.lock`,
  `.gitignore` and `.gitattributes` -- obliges `/simplify`, `security`
  and `docs-updater`. See `required-agents`.
- Every stamp on this branch reads `legacy`, because a worktree session
  runs hooks from the main checkout (F12). Pull the main checkout after
  this merges before trusting new hook behaviour.
- PR #67 will conflict with child 4's rewrite of `reference.md`'s
  "Subagent selection". Resolve by taking this branch's version, which
  already subsumes #67's serialization rule (G8).
- `git stash` is shared across worktrees here; use a WIP commit instead.

## Progress

Frontier (no blockers, takeable now):

- [x] 1. free-fix batch — all eight done, seven in-repo 2026-09-05 and
      the GitHub description plus homepage URL 2026-09-06. See G3
- [x] 5. G31 citation-integrity checker — done 2026-09-05,
      `docs/skills/plan/scripts/plan-citations`, wired into
      `verify-ladder`. See G7
- [x] 4. agent trigger table — done 2026-09-06,
      `docs/skills/workflow/scripts/required-agents` plus the rewritten
      "Subagent selection" in `workflow/reference.md` and step 6 of
      `workflow/SKILL.md`. See D7 and G8
- [x] 6. `plan-gate` requires a completion stamp — done 2026-09-06.
      Stamps carry a code fingerprint, so the gate distinguishes "ran"
      from "ran against this code". See D11
- [ ] 3. verification ladder split — evidence ladder vs deploy sequence
      — see D6

Blocked:

- [ ] 2. plan-file layout revision — `## State` first, three frontmatter
      fields, defect G-to-F reclassification — blocked by 5, see D4
      and G6
- [ ] 7. `docs-updater` split: mechanical checks into `verify-ladder`
      — blocked by 3, 4
- [ ] 8. `spec-check` subagent — blocked by 4
- [ ] 9. `plan-supersede` + `docs/plans/superseded/` — blocked by 2
- [ ] 10. generated plan index — blocked by 2, carries fog (below)
- [ ] 11. `docs/procedures/` folds into skills — blocked by 7, carries
      fog (below)
- [ ] 12. `docs/audits/` declared a frozen report, one paragraph — see D8
- [ ] 13. `security-audit` output contract: emit plans + doc updates +
      a small frozen report — blocked by 12
- [ ] 14. standing-rules mechanization, 7-8 rules from `docs/hardening.md`
      — blocked by 4
- [ ] 15. `README.md` gains a "goodies" register beside "Interesting
      stuff" — secondary track, see D9
- [ ] 16. three explainers: push-deploy topology, sops-nix key model,
      ZFS policy tiers — blocked by 15; the ZFS one additionally gated
      on PR #67 landing

## Not yet specified

In scope, not yet sharp enough to make a child. Graduates as the frontier
advances.

- **Index fallback for the 44 plans with no `## State`.** Child 10
  generates the index from `## State`, but only 42 of 86 plans have that
  section — it arrived with
  `2026-08-28-plan-file-rework-mutable-state-section-f-item-resolution-gating-and-a.md`
  and was not retrofitted. Whether the fallback is a generated stub, a
  first-paragraph excerpt, or a backfill pass is undecided.
- **Whether `docs/procedures/` folds into existing skills or needs new
  ones.** `new-host.md` and `new-service.md` read as skills already;
  `backup-restore.md` and `remote-access.md` may map onto none.
- **How much of `docs/architecture.md` survives as human prose** once
  child 7's generated host-composition block exists. Cannot be sized
  before that block is real.

## Decisions (D)

### D1 - what is the routing rule?

Four channels, asked in order: decidability, then whether an agent needs
it always, then whether an agent needs it during a specific activity,
then human prose. Rejected: a two-outcome test (checkable vs prose),
which has no entry rule for skill references and would have wrongly
routed `docs/procedures/` — 1,041 lines of agent-facing runbook — to the
human layer. Also rejected: asking audience first, which makes routing
inherit a judgment call.


**ANSWERED 2026-09-05:** four channels, decidability asked before audience

### D2 - what forms does mechanism take?

Three: **check** (evaluate the claim, refuse if false), **generate**
(write the fact so it cannot drift), **require-declaration** (refuse
without a recorded judgment, when the claim itself cannot be evaluated).
The third makes expensive-but-decidable obligations enforceable — a hook
cannot verify a VM test was meaningful, but it can refuse to close a plan
that does not say whether one ran.


**ANSWERED 2026-09-05:** check / generate / require-declaration

### D3 - do ADRs survive?

Yes; `docs/adr/` is not rolled back. It is the conclusion of
`2026-09-05-adopt-zfs-policy-tiers-and-a-mydatasets-registry.md#D8`,
which considered and rejected both a section in `docs/architecture.md`
and the plan file alone. ADR-0001 is cited by that ANSWERED marker and by
`2026-08-28-restructure-zfs-so-ordinary-temp-and-cache-data-is.md`, and
the work sits inside commit `0dd1b1b` alongside the ZFS and
log-monitoring plans. `docs/architecture.md` is **not** superseded by
ADRs: an append-only decision log cannot answer "what is true now", which
is the lesson `## State` already encodes one level down.


**ANSWERED 2026-09-05:** ADRs survive; docs/adr is not rolled back

### D4 - revise or rewrite the plan-file schema?

Revise. `## State` moves first and `## Original plan` is demoted beneath
it, because the latter is stale by construction and currently sits above
the only section that is true. Frontmatter gains `priority`,
`blocked_by`, `superseded_by`, and `kind`. Defects reclassify G to F.
Two plan kinds: task and map. Expand-contract becomes a named map
pattern, not a skill, since it is a blocking-edge graph and `blocked_by`
already expresses it. Rejected: a rewrite, which breaks 86 files and 31
live `# plan:` citations for no gain the revision does not deliver.

Rationale for G to F: D has `plan-decide`, F has `plan-resolve`, G has
neither — correct for G's design meaning, a lesson, but wrong for how it
is used. `2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md`
holds 40 G items of which 33 are open defects, arriving ~5/day and
draining ~0.9/day, because nothing can resolve them. G returns to meaning
lesson and needs no drain.


**ANSWERED 2026-09-05:** revise the plan-file schema, do not rewrite it

### D5 - is anything ever deleted?

No. A superseded plan holds the highest-value knowledge in the corpus:
the newer plan records *that* something was removed, the older one
records *why it was built that way*. Deleting the older leaves the next
agent with the removal and not the reasoning, and it re-proposes the
original design — the exact re-derivation the plan system exists to
prevent. Contamination is a labeling problem, so `plan-supersede` writes
a frontmatter marker and moves the file to `docs/plans/superseded/`, out
of the default grep path but still citeable, because bare-filename
citations survive folder moves by design.


**ANSWERED 2026-09-05:** nothing is deleted; plan-supersede plus a superseded/ folder

### D6 - one verification list or two?

Two. The six-layer list in `docs/procedures/testing-changes.md` mixes
evidential depth with deploy chronology, which is why `nvd diff` sits at
position 5 despite costing seconds where layer 4 costs minutes. Split
into an **evidence ladder** mapping 1:1 onto the trust hierarchy
(documentation, source, local build with output inspected, VM, switch)
and a separate **deploy sequence** (build, `nvd diff`, switch, observe).
Old layers 2, 3 and `nvd` collapse into one rung, because the hierarchy
always described rung 3 as a single thing; splitting it across three
non-adjacent positions is why nothing could stamp it. **Lint is not a
rung** — by the ladder's own words it catches style and dead code, not
correctness. It gates; it warrants nothing.

`verify-ladder` stamps the rung-3 floor mechanically. Rung 3 full, rung 4
and rung 5 are declared, and `plan-move ... done` requires the
declaration. VM testing stays manual — minutes inside a pre-commit gate
teaches bypassing — but the skip becomes visible instead of silent.
`docs/audits/2026-08-26/RESUME.md` already declares rungs by hand
("build-verified only, not deployed to any host yet"), which is proof the
practice works and that it is currently manual.


**ANSWERED 2026-09-05:** split into an evidence ladder and a deploy sequence; lint is not a rung

### D7 - how are the review agents invoked and ordered?

A convergence loop, not a pipeline:

```
loop { /simplify -> security -> spec-check }  until clean or signed off
                                              then docs-updater, once
```

Any actionable finding from `security` or `spec-check` restarts the loop
at `/simplify`, because their fixes are code changes the earlier agents
have not seen. `docs-updater` runs last and outside the loop, because its
job is describing the settled state. Serialization is required, not
preferred: a real session had `/simplify` land a refactor later reverted
for eval-time infinite recursion while `docs-updater` ran concurrently and
wrote the reverted design into a plan's Findings as settled fact.

Termination needs no new machinery. Every finding resolves `fixed`,
`accepted`, or `moot`, and `plan-freeze` already refuses while any is
unresolved — the loop's exit condition is the gate that already exists.
If the same finding recurs across passes, seek sign-off rather than loop
again.

Invocation is **mechanically triggered, never judgment-gated**:
`/simplify` and `security` fire when `.nix` changed, `docs-updater` when
a doc, comment, or documented config surface changed, `spec-check` when
the plan carries `## Decisions`. This replaces the escape hatch in
`docs/skills/workflow/reference.md` ("use judgment, and if genuinely
unsure, invoke the one in question"), which is the ~9% channel. It also
dissolves G41 of the weak-points plan for free — `/simplify` does not
fire on a docs-only diff — and removes any need for a no-op path in a
mandatory agent, since an irrelevant agent never starts.

**2026-09-06: the order above is superseded.** It read
`/simplify -> security -> spec-check`, then `docs-updater` once at the
end. `security` F2 showed that and the D11 staleness rule are mutually
unsatisfiable: `docs-updater` rewrites inline comments in `.nix` files and
skill scripts, all inside `PLAN_CODE_GLOBS`, so running it after
`security` leaves `security`'s stamp stale *by construction* and
`plan-gate` blocks on a task where nothing is wrong. A gate that goes red
on the first honest attempt every time is the one people learn to route
around.

New order: **`/simplify` -> `docs-updater` -> `security` -> `spec-check`**,
one loop, restarting at `/simplify` on any actionable finding. The rule
behind it is *every agent that writes runs before every agent whose stamp
must stay valid*. PR #67's incident constrained `docs-updater` to follow
`/simplify`; it never required it to follow the read-only reviewers, so
moving them last keeps what that incident actually established.

**2026-09-06, restart rule narrowed (user).** The loop repeats to
`/simplify` only when code -- or anything functionally load-bearing,
agent definitions included, `.md` or not -- changed after it last ran: a
fix following a `security` or `spec-check` finding, or any other manual
change by the main agent. Each pass still runs all the way through to
the read-only reviewers, so their verdict always lands on that pass's
settled state.

**2026-09-06, fix stage named and reviewers kept serialized (user).**
The fix stage is the pass's explicit last step: findings are applied
after both read-only reviewers report, and a non-empty fix stage is what
triggers the next pass. The reviewers stay serialized even though both
are read-only toward code, because both append `### F<N>` findings to
the same plan file numbering from the next unused id -- concurrent runs
collide on the number and plan-lint rejects the duplicate. Parallel tail
reviewers would need child 8 to design `spec-check`'s finding-append
contract collision-free first. `docs-updater`'s own doc and comment fixes never restart the
loop by themselves: they change no behavior, so there is nothing new for
the earlier agents to judge. Its comment edits still move the code
fingerprint, which is why `security` runs after it within each pass (G9's
third gap resolves as "accept that ordering", not as an extra loop).

`spec-check` is new. It reads the plan's `## Decisions` and `## Progress`
as the spec, which are already written and already anchored. Every
existing gate checks that the *record* is complete — `plan-gate` asks
"is the security review this range depended on actually closed out" —
and none checks that the *code matches the record*. It is kept separate
from `security` and from `docs-updater` on the no-rerank principle: a
change can pass one axis and fail the other, and merging them lets one
mask the other. It sits before `docs-updater` so it judges an unmutated
plan.


**ANSWERED 2026-09-05:** convergence loop, restart at /simplify, mechanical triggers

### D8 - what happens to `docs/audits/`?

Declared a frozen report now, in one paragraph, with remaining findings
ported on-touch rather than swept. It is not an archive — it is the last
body of work still running on the pre-plan system, doing three jobs at
once: point-in-time evidence (keep), a live work queue duplicating
`docs/plans/todo/` (port), and a session log duplicating `## State`
(retire). Its 19,479 lines carry ~170 findings and almost no per-finding
state; status lives in `RESUME.md`'s narrative instead.

Rejected: a one-pass sweep, which floods `todo/` with ~150 plans most of
which will never be worked. Rejected: pruning to unresolved findings,
which destroys the evidence half — the part an outside reader finds
credible.


**ANSWERED 2026-09-05:** audits become a frozen report; findings port on-touch

### D9 - what is the human layer?

`README.md` gains a **"goodies — easy to take for your own"** section
beside the existing **"Interesting stuff"**: lift-this register and
resume register, two jobs, two voices. Three explainers, each
self-contained enough to lift without adopting the repo: the push-deploy
topology (homelab builds and pushes `vps`'s closure over the tailnet),
the sops-nix per-host age key model, and ZFS policy tiers once PR #67
lands. Secondary track, sequenced behind the agent-facing children.


**ANSWERED 2026-09-05:** README gains a goodies register; three explainers, secondary track

### D10 - how is this work itself structured?

As this map plan. The effort spans the `workflow` skill, `docs-updater`,
a `docs/` restructure, the plan-file schema, three explainers,
`AGENTS.md`, and mechanism for 7-8 standing rules — too large for one
session, and its back half is not specifiable until the front half lands.
Rejected: a single task plan, which would freeze with half its decisions
unresolved. Rejected: incremental with no plan, which loses the thread
across sessions.


**ANSWERED 2026-09-05:** structured as this map plan

### D11 - should a completion stamp prove *what* was reviewed?

**Open.** Child 6 proves an obliged agent ran **at least once**, not that
it ran against the code being merged. A fix applied after `docs-updater`
stamped leaves a stale stamp and `plan-gate` still passes. The convergence
loop in D7 is therefore discipline, not mechanism -- the exact conversion
this effort exists to make.

The obvious designs all break the same way. An agent reviews
*uncommitted* work at T and stamps; that work is committed at T+1. So
"stamp must be newer than the last commit touching reviewable files" and
"stamp must name the current HEAD" both read as stale immediately, for a
review that did happen. An un-passable gate is worse than a weak one
(G5).

Options:

1. **Content fingerprint.** The stamp records a hash over the reviewable
   file set as it stood when the agent ran; `plan-gate` recomputes it for
   the range head. Immune to the commit-boundary false positive, since it
   compares content rather than history. Costs a hash over ~220 tracked
   files and needs the reviewed work staged before the agent runs, so
   the index reflects what was read.
2. **Stamp the merge-base diff hash.** Cheaper, but the hook does not
   know the base branch, so it would have to be passed in or guessed.
3. **Leave it.** Keep the stamp as proof-of-invocation and rely on
   unresolved findings to catch the substantive case: a review that ran
   and found something still blocks until resolved.

Leaning (1), but it is a real change to both the stamp format and the
workflow's ordering, so it wants its own child rather than riding along
with child 6.

**Built 2026-09-06 as option 1**, inside child 6 after all, because the
design turned out smaller than feared once the fingerprint was scoped to
code.

`plan_code_fingerprint` hashes the tracked *and untracked* content of
`PLAN_CODE_GLOBS` -- `*.nix`, `docs/skills/*/scripts/*`, `.githooks/*`.
`.md` is deliberately excluded: every stamp appends to a plan file and
`docs-updater` edits docs, so folding prose in would make each stamp
invalidate itself and every stamp before it. Excluding it also sharpens
the question the stamp answers to exactly the right one -- *did the code
change since this agent read it?*

`subagent-stamp` records the fingerprint in the stamp line;
`plan-gate` recomputes it and blocks on a mismatch. A stamp written
before fingerprints existed reads as `legacy` and downgrades to a
warning, so an older plan cited by a live range cannot become an
unfixable block.

Verified by direct test: fingerprint stable across calls; absent stamp
returns non-zero; write/read round-trips; a legacy stamp reports
`legacy`; **a code edit moves the fingerprint and a prose edit does
not** -- the last being the property that makes the scheme
self-consistent.


**ANSWERED 2026-09-06:** option 1: stamps record a code-only content fingerprint

## Gotchas (G)

### G1 - this map bootstraps on a field it is proposing

Blocking edges belong in `blocked_by` frontmatter, which D4 introduces
and which does not exist yet. Until child 2 lands, the edges live in
Progress as prose. Migrate them into frontmatter as part of child 2, not
as a separate pass, or the two will disagree.

### G2 - child plans are created at the frontier, not all at once

Creating all 16 children now would take `docs/plans/todo/` from 29 to 45
in one commit, most of them unworkable for weeks. This is the same
objection that ruled out a one-pass audit sweep in D8, and it applies to
this map's own children. Create a child plan when its blockers clear, and
cite it back here by bare filename.

### G3 - the free-fix batch is documentation drift found while charting

Eight corrections, all evidence for the destination rather than
incidental:

- `docs/skills/plan/reference.md:125` names `docs/plans/done/.checksums`;
  the manifest is `docs/plans/.checksums`.
- `docs/skills/workflow/SKILL.md:19` greps only `{todo,in-progress}/`, so
  `done/` sits outside the documented search path — which is why 31 of 50
  done plans are cited from nowhere outside `docs/plans/`.
- `AGENTS.md:22` says older ADR decisions are "being backfilled",
  implying a sweep rather than the on-touch trigger.
- `AGENTS.md:33` renders the verification ladder omitting VM testing.
- `docs/procedures/testing-changes.md` layer 4 says the VM checks are
  "currently `zrepl-replication` and `zfs-space-guard`"; there are eight.
- `docs/adr/README.md`'s Format section says most ADRs will not need
  Status, Considered alternatives or Consequences, while the only ADR
  uses all three plus two more; its closing line also casts
  `docs/architecture.md` as a temporary home pending migration.
- No document names `nix flake check` without `--no-build` as the
  run-all-VM-tests form.
- The GitHub repo description is "my nixOS config", with no homepage URL.

### G4 - two remote branches are merged and deletable

`origin/worktree-docs-verify-ladder-trust-hierarchy` and
`origin/workflow-plan-done-before-merge` have zero diff against master.

### G5 - `verify-ladder` is currently un-passable on master

`nix flake check --no-build` fails while evaluating
`checks.zrepl-replication`, on `nodes.puller.environment.etc."zrepl/snakeoil"`:

```
error: path 'm8319qq7008kira1p5m725xk6s5d4fa3-sr2lpwrcdjfpkk8gpvr98gp4nrgsijns-source' is not valid
```

Reproduced against clean `origin/master` (commit `0bc0265`) with no local
changes, so it is not caused by any work in flight. `snakeOilEd25519PrivateKey`
resolves through a store path that no longer exists —
`/nix/store/sr2lpwrcdjfpkk8gpvr98gp4nrgsijns-source` is present but the
derived `m8319qq...` path is not, ~~which reads as a garbage-collected
input rather than a repo defect~~.

The consequence is the interesting part: `verify-ladder` hard-blocks on
`nix flake check`, so while this holds **every** non-trivial change is
either blocked or committed past a failing gate. A gate that cannot pass
for environmental reasons trains exactly the bypass habit D7 is trying to
design out, which makes this worth fixing before children 3, 4 or 6 land.

**2026-09-05: fixed, and the "not a repo defect" reading above was
wrong.** It was both — a garbage-collected path *and* a repo defect that
made a collectable path load-bearing.

`tests/zrepl-replication.nix:48` read
`import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs`. Coercing a path to
a string copies the referenced directory into the store, so that
interpolation silently added a **203 MiB copy of the entire nixpkgs
source**, named after the original — hence the `<hash>-<original
basename>` shape. That copy is a *source* path with no deriver, so
`nix build` can never recreate it: once `nix-collect-garbage` takes it,
`nix flake check` breaks with an error that looks unrecoverable. It would
have recurred after every GC.

Two-part fix:

1. Immediate — `nix-store --add /nix/store/sr2lpw...-source` reproduced
   the exact missing hash, confirming the diagnosis and unblocking the
   gate.
2. Durable — the import now uses path concatenation,
   `import (pkgs.path + "/nixos/tests/ssh-keys.nix") pkgs`, which never
   coerces the path to a string and so never makes the copy.

Verified by deleting the re-added copy (203.4 MiB freed) and re-running
`verify-ladder` with the fix in place: all checks passed without it, so
the dependency is gone rather than merely re-satisfied. The interpolation
was the only occurrence in `tests/`, `modules/` and `hosts/`.

Lesson worth keeping: **a deriver-less source path is unrecoverable by
`nix build`.** Any `"${somePath}/..."` interpolation over a large tree is
a latent GC-triggered breakage, and the reason it looks like corruption is
that nix reports the symptom (invalid path) rather than the cause (a copy
nothing can rebuild).

**2026-09-06: a near-identical error that is *not* this bug.** Fixing the
above let `nix flake check` get further and hit
`error: path 'ihrfigy8...-base16-schemes-...drv' is not valid`, reached
through `modules/profiles/PC.nix:237`'s
`"${pkgs-stable.base16-schemes}/share/themes/..."`. That looks like the
same defect and is not: interpolating a *derivation* puts its `.drv` in
the string's context, and a `.drv` is **re-instantiable** — one
`nix build --dry-run` of a host toplevel recreated it and the error
vanished on its own. No repo change was needed, and PC.nix:237 is
idiomatic.

The distinction is the whole lesson, because the error text is identical:
interpolating a **path** copies a tree in with no deriver and is
permanent breakage; interpolating a **derivation** is normal and
self-heals. Check whether the invalid path ends in `.drv` before
suspecting the code. Note also that `nix flake check` stops at the first
failure, so one such fault can mask the next — the base16 one was only
visible once the zrepl one was fixed.

### G6 - the G-to-F reclassification breaks live citations, so child 5 gates child 2

Charted with child 2 unblocked; that was wrong, corrected 2026-09-05.

Renaming a defect from `G<N>` to `F<N>` changes its **anchor**, and
anchors are cited. Eighteen live citations point at `#G` anchors today —
sixteen from `.nix` (`#G1` x3, `#G8` x2, `#G6` x2, `#G4` x2, `#G2` x2,
plus `#G3`, `#G5`, `#G12`, `#G13`) and two more from `docs/`. Every
cited G that turns out to be a defect breaks its citation, and G31 means
nothing would report it.

This is the `8ae2a4a` failure mode exactly: 74 plan files renamed in one
commit, every inbound bare-filename citation broken, nothing to catch it.
So child 2 is blocked by child 5, and child 2 runs as **expand-contract**
per D4 rather than one mass edit — the first real use of that pattern.
Ordering within child 2: add the new `F<N>` beside the old `G<N>`,
migrate citations in batches, delete the old anchors only once the
checker reports zero unresolved references.

### G7 - `plan-tick` cannot tick a map child, and the checker needed an opt-out

Two things child 5 turned up.

**`plan-tick` only addresses `D`/`G`/`F` ids.** A map's children are
numbered items, not typed ids, so their checkboxes have to be ticked by
hand — which collides with the skill's "never hand-edit these mechanics"
rule even though a Progress checkbox is free-text content. Either
`plan-tick` grows a map-child form, or the map kind reuses typed ids for
its children. Decide this inside child 2, since that is where the schema
changes; until then, map children are ticked by hand.

**Docs that teach citation syntax must contain citations that resolve to
nothing.** `docs/skills/plan/reference.md` explains the convention with a
placeholder filename, and its worked example is an entire fictional plan
file. (Writing this entry tripped the checker on its own quoted example,
which is the shortest possible demonstration that the category is real.) That is a permanent category, not a one-off, so `plan-citations`
skips regions between `<!-- plan-citations: ignore-start -->` and
`<!-- plan-citations: ignore-end -->` rather than excluding whole files —
real citations in the same file still get checked. This is the same
false-positive class that made a naive doc-path checker too noisy to
wire up, and it is why that one stayed deferred while this one did not.

Baseline at the time of writing: **167 citations resolve, zero broken.**
That is the number child 2 must not regress, and it is what made wiring
the checker into `verify-ladder` safe — the opposite of G5, where a gate
that could not pass would have taught bypassing.

### G8 - `verify-ladder` does not see untracked files, and child 4 will conflict with PR #67

**Untracked files are invisible to `git diff`.** `required-agents` counts
them (`git ls-files --others --exclude-standard`) because a brand-new
module is the change most in need of review and appears in no diff view
until it is staged. `verify-ladder` does **not**: its `changed_nix` is
`git diff --name-only HEAD` plus `--cached` only, so a new, unstaged
`.nix` file skips `nixfmt`, `statix` and `deadnix` entirely. Found while
testing `required-agents`, which reported nothing for a tree whose only
change was a new file. Worth folding into child 7, which is already
touching `verify-ladder`.

**Child 4 collides with PR #67.** That PR adds the `/simplify` ->
`security` -> `docs-updater` serialization paragraph to the same region
of `workflow/reference.md` that child 4 rewrote. The rewrite already
carries that rule *and* the incident behind it, extended with the
convergence loop and the trigger table, so resolve the conflict by taking
this branch's version rather than merging both. If #67 lands first, redo
the section rather than hand-merging two overlapping prose blocks.

### G9 - the fingerprint enforces the loop, but `docs-updater` can force an extra pass

D11's fingerprint makes the convergence loop mechanical for stampable
agents: fix code after `security` stamped, the fingerprint moves, and
`plan-gate` demands a re-run. It terminates exactly when a pass stops
changing code, which is the right condition.

Three gaps remain, and the third is self-inflicted:

1. **`/simplify` is never stamped** -- a slash command fires no
   `SubagentStop`. D7 makes it the loop's *restart point*, so the one
   step the loop pivots on is the one with no mechanical proof.
2. **`spec-check` does not exist** (child 8), so its leg is unenforced by
   construction.
3. **`docs-updater` edits inline comments in `.nix` files by contract.**
   That moves the fingerprint, which makes the earlier `security` stamp
   stale, which forces another `security` pass -- every time it touches
   code. It converges, because a second `docs-updater` pass over
   already-tightened comments is a no-op, but it costs a guaranteed extra
   round.

Do not "fix" (3) by dropping code comments from the fingerprint: a
comment edit and a logic edit are indistinguishable at the file level
without parsing Nix, and a fingerprint that ignores some code changes
stops answering the question it exists for. The honest options are to
accept the extra pass, or to run `docs-updater` inside the loop rather
than after it -- which contradicts the ordering rationale in D7, so it
needs a decision rather than a quiet change.

### G10 - a content fingerprint is only as stable as its `sort`

`plan_code_fingerprint`'s first form hashed a file list sorted under the
ambient locale. Measured over an identical 87-file set:

```
C / C.UTF-8 / POSIX   4fe06a04e030d9d7
en_US.UTF-8 / en_GB   d6ceceb07eea0414
```

`sort` honours `LC_COLLATE`, and the writer and reader of a stamp are in
different environments by construction: `subagent-stamp` runs in the
author's shell, typically a UTF-8 locale, while `plan-gate` also runs on
`ubuntu-latest`, which sets no `LANG`. Every correctly stamped plan would
therefore have reported `stamp is stale` in CI with no code change --
turning the gate meant to stop bypasses into the best possible argument
for one. `LC_ALL=C` on both sorts fixes it.

Two neighbouring traps found with it, both now closed:

- `git ls-files --cached --others` must include **both**, or a file's
  presence in the hash changes when it goes from untracked to tracked at
  commit time, giving the same false staleness from the other direction.
  A scratch code file that is never committed still skews the local hash;
  remove it before the review, not after the gate complains.
- `2>/dev/null` plus an unchecked `xargs` turned any failure into
  `e3b0c442...`, the sha256 of nothing, returned successfully.

General lesson: a fingerprint used across two machines has to pin every
input to its own value -- locale, file order, and the tracked/untracked
distinction are all part of the hash whether or not you meant them to be.

### G11 - the code set missed the files that decide whether the gates run at all

`PLAN_CODE_GLOBS` began as `*.nix`, `docs/skills/*/scripts/*`,
`.githooks/*`, justified as "the enforcement machinery earns review at
least as much as a module does". By that argument the set was
incomplete, and the omissions were the worst possible ones: deleting the
`SubagentStop` block from `.claude/settings.json` stops every stamp from
being written, and gutting `.github/workflows/plan-gate.yml` stops CI
gating anything. Neither obliged a single review agent, neither moved
the fingerprint, and both passed `plan-gate` green. The most
gate-weakening edit available in the repo was the one the mechanism
could not see.

Widened 2026-09-06 to add `.github/workflows/*`, `.claude/settings.json`,
`scripts/*`, `*/scripts/*` (skill scripts outside `docs/skills/`, e.g.
`tcr-skill`), and `docs/agents/*.md`. That last one is the mechanical
half of the restart rule the user set the same day: an agent definition
is behavior, not prose, so "load-bearing changes restart the loop" now
has something enforcing it rather than relying on the agent to judge it.

Two consequences worth knowing. Widening the globs changes the emitted
fingerprint for an unchanged tree, which is precisely the trap
`2026-09-06-make-plan-gate-survive-a-pr-that-changes-the-fingerprint-algorithm-or.md`
is filed against -- harmless here only because the base branch has no
stamp check yet and every stamp on this branch is legacy. And the set is
still an allowlist, so the next file that matters will be missed the
same way; inverting it to a `PLAN_NONCODE_GLOBS` denylist is the
structural fix, not attempted here.

## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 — a frozen plan plus a stale fingerprint is an unfixable block, and the only escape is the G42 no-trailer bypass

- **File:** `docs/skills/workflow/scripts/plan-gate:95-101`, `docs/skills/workflow/scripts/subagent-stamp:34`, `docs/skills/plan/scripts/plan-move:48-52`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any contributor following `workflow/SKILL.md` steps 6 to 8 to 9 in order. Step 8 mandates `plan-move <file> done` in the same branch, before committing; `plan-move done` execs `plan-freeze`, which sets `frozen: true`. `subagent-stamp:34` refuses to stamp a frozen plan, and `plan_require_not_frozen` refuses every other `plan-*` edit. So the moment step 8 runs, the stamp set is immutable. Any later fingerprint drift — a rebase onto an advanced master, a follow-up fix commit, or F2/F3 below — makes `plan-gate` print `BLOCKED: ... stamp is stale` with no in-system remedy: re-running the agent cannot re-stamp, `plan-resolve` cannot touch the file, and hand-editing it breaks `docs/plans/.checksums`.
- **Rule:** new-rule candidate (a gate whose only recovery path is outside the system is a gate that gets routed around); compare `docs/hardening.md` rule 11.
- **Finding:** The three escapes available to a blocked author are (a) hand-edit a frozen plan, (b) unfreeze it, (c) drop the `Plan:` trailer, at which point `plan-gate` prints "nothing to gate" and exits 0 — the documented `2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md#G42` bypass. (c) is the cheapest and leaves no trace, so the fingerprint's net effect is to teach the bypass that disables the whole gate, including the unresolved-findings check that predates this change. This is exactly the dynamic G5 in this plan identified ("an un-passable gate is worse than a weak one") and D11 tried to design around; the fingerprint dodges the commit-boundary false positive D11 names but not the freeze-boundary one. A second instance of the same class: the pinned base-branch `lib.sh` supplies `PLAN_CODE_GLOBS` for `current_fp` while the PR's own `lib.sh` supplied it for `stamped_fp`, so any PR that edits `PLAN_CODE_GLOBS` compares two different file sets and is unconditionally blocked.
- **Fix risk:** Making `subagent-stamp` exempt stamps from the freeze re-opens frozen plans to writes and invalidates `.checksums`; scoping the fingerprint to the range's own changed files instead of the whole repo weakens what it proves. Either way, test the full step 6-8-9 sequence end to end with master advanced underneath, not just `plan-gate` in isolation.


**FIXED 2026-09-06:** a stale stamp on a frozen plan degrades to NOTE; blocking was unsatisfiable

### F2 — the mandated agent order guarantees a stale `security` stamp whenever `docs-updater` edits code

- **File:** `docs/skills/plan/scripts/lib.sh:238` (`PLAN_CODE_GLOBS`), `docs/skills/workflow/SKILL.md:41-52` (step 6 order), `docs/agents/docs-updater.md` (frontmatter `tools: ... Edit`; "for every doc or comment touched by the diff")
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** every non-trivial change that touches a `.nix` file or a skill script — i.e. every change `security` is obliged on. Step 6 fixes the order as `/simplify`, `security`, `spec-check`, then `docs-updater` once at the end. `docs-updater` holds `Edit` and its brief tells it to rewrite inline comments in the code the diff touched. `PLAN_CODE_GLOBS` is `*.nix`, `docs/skills/*/scripts/*`, `.githooks/*` — all of which `docs-updater` edits. Its edits therefore land after `security` stamped, `subagent-stamp` fingerprints at `SubagentStop` (so `docs-updater`'s own stamp is current and `security`'s is not), and `plan-gate` blocks on `security` being stale.
- **Rule:** n/a — internal control correctness.
- **Finding:** The ordering `SKILL.md` mandates and the staleness rule `plan-gate` enforces are mutually unsatisfiable in one pass. Recovery requires re-running `security` after `docs-updater`, which contradicts step 6 and, if step 8 already ran, is impossible (F1). This will fire on this very PR: `docs/skills/*/scripts/*` was added to both the trigger set and `PLAN_CODE_GLOBS` in the same change, and those scripts carry the longest comment blocks in the repo — prime `docs-updater` concision targets. The practical outcome is a first-run red gate on essentially every task, which is the strongest possible training signal toward F1's bypass (c).
- **Fix risk:** Re-ordering `docs-updater` before `security` means security reviews comments the docs agent has not yet corrected. Excluding comment-only changes from the fingerprint requires parsing Nix and shell, which is not cheap. Whatever is chosen, verify by running the actual step-6 sequence, not by reasoning about it.


**FIXED 2026-09-06:** reordered to editors-then-reviewers: /simplify, docs-updater, security, spec-check

### F3 — `required-agents` turns a failed `git diff` into "no agents obliged", so `plan-gate`'s mandatory-dependency guard cannot fire

- **File:** `docs/skills/workflow/scripts/required-agents:14,25,36`, `docs/skills/workflow/scripts/plan-gate:56-59`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any PR whose head branch has no merge base with `master` (an orphan branch, a re-imported history, or a clone shallow enough that the merge base is beyond the graft). Verified in a scratch repo: `git log master..HEAD` succeeds and prints the commits while `git diff --name-only master...HEAD` exits 128 with `fatal: no merge base`. `plan-gate` therefore gets a non-empty `plans` list, proceeds past its early exit, and reaches the stamp check with an empty obligation set. Narrow but not hypothetical; every other trigger for a failing `git diff` (bad ref, missing object) is caught earlier by the `git log` step.
- **Rule:** n/a — internal control correctness.
- **Finding:** `required-agents` runs under `set -uo pipefail` with no `set -e`, so the failing `git diff` on line 25 leaves `changed` empty and line 36's `[ -n "$changed" ] || exit 0` returns exit 0 with no output. Verified against this repo: `required-agents <bogus-ref> HEAD` prints `fatal: Invalid symmetric difference expression ...` to stderr and exits 0. `plan-gate`'s `obliged="$("$ra" ...)" || { BLOCKED; exit 1; }` only tests exit status, so the guard whose own comment says "a missing or failing required-agents would otherwise yield an empty obligation set and quietly turn the stamp check into a pass" cannot detect the one failure mode it names. `required-agents` also cannot distinguish "empty diff" from "diff failed" — both are exit 0 with no output — so no caller can.
- **Fix risk:** Making `required-agents` exit non-zero on a git failure will make `plan-gate` hard-block on any range it cannot diff; confirm that does not break the legitimate empty-diff case (a range whose files match no glob still exits 0 with no output today, and that must stay a pass).


**FIXED 2026-09-06:** required-agents now checks git diff's exit status and dies rather than reporting an empty set

### F4 — `plan-gate` reports success for a base or head ref it cannot resolve

- **File:** `docs/skills/workflow/scripts/plan-gate:34-39`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** anyone invoking `plan-gate` by hand (its own header advertises a pre-merge and pre-deploy path) with a mistyped or absent ref, and in CI if `github.event.pull_request.head.sha` is ever absent from the fetched objects. Verified in this worktree: `plan-gate origin/main HEAD` and `plan-gate deadbeef... HEAD` both print `no 'Plan:' trailers found ... nothing to gate.` and exit 0.
- **Rule:** `docs/hardening.md` rule 11 ("a guard that declines to act must be watched by something that measures the outcome, not the attempt") — a skip and a pass are indistinguishable here.
- **Finding:** `git log ... 2>/dev/null` swallows `fatal: bad revision`, so an unresolvable ref is indistinguishable from a range with no `Plan:` trailers. Pre-existing, but this change makes `plan-gate` the sole enforcement point for review-completion too, so the blast radius of a silently-skipped run grew. Nothing in the repo invokes `plan-gate` locally today (grep over `docs/`, `.githooks/`, `modules/`, `hosts/` finds no caller), so the header's "used both pre-merge and pre-deploy" is currently aspirational — the only real caller is `.github/workflows/plan-gate.yml`, which does pass a good ref.
- **Fix risk:** Validating refs with `git rev-parse --verify` before use is cheap; the only risk is a caller that deliberately passes a ref that may not exist yet (the workflow's "base branch doesn't have the script yet" path already handles that separately).


**FIXED 2026-09-06:** plan-gate resolves both refs up front and blocks on an unresolvable one

### F5 — `plan-citations` fails open: one unreadable file silently truncates the scan and it still prints `OK`

- **File:** `docs/skills/plan/scripts/plan-citations:41,124`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any contributor whose working tree has a tracked-but-deleted file when `verify-ladder` runs — mid-rename, an interrupted `git mv`, or a sparse checkout. `git ls-files` still lists the path, `awk` aborts with `fatal: cannot open file` and exit 2, and because the whole pipeline sits in a process substitution (`done < <(awk "$awk_prog" "${scan[@]}" | sort -u)`) that status is discarded — `set -o pipefail` does not reach inside `<( )`. Verified: `awk '{print}' nosuchfile.md </dev/null` exits 2 and processes nothing further.
- **Rule:** `docs/hardening.md` rule 11 — the gate measures the attempt, not the outcome.
- **Finding:** Every file after the unreadable one goes unscanned, and `plan-citations` then prints `plan-citations: OK (N citations resolve)` and exits 0, so `verify-ladder` goes green. The success line reports a count with nothing to compare it against, so a scan that covered 12 of 87 files looks identical to a full one. Second, smaller instance of the same class: `awk` treats an operand of the form `<identifier>=<value>` as a variable assignment, not a filename — verified, `awk '{print FILENAME": "$0}' 'foo=bar.md' </dev/null` produces no output and no error. Any tracked repo-root file named e.g. `notes=1.md` is therefore silently excluded from the scan (paths containing `/` are unaffected, which is why this only reaches top-level files).
- **Fix risk:** Checking `awk`'s exit status means capturing it out of the process substitution (a temp file, or restructuring to a pipeline with `PIPESTATUS`); prefixing operands with `./` fixes the assignment case but changes `FILENAME` in every report line, so the report strings need adjusting together.


**FIXED 2026-09-06:** awk output goes through a file so its status is observed; absent files filtered; ./ prefix stops = being read as an assignment

### F6 — the `plan-citations` ignore markers are an unrestricted, unreported off switch

- **File:** `docs/skills/plan/scripts/plan-citations:62-77`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** any contributor blocked by `verify-ladder`'s new hard `plan-citations` gate. Wrapping a whole file between a balanced ignore-start / ignore-end HTML-comment pair mutes it entirely, and a balanced pair produces no diagnostic at all — only the unbalanced case is reported. There is no allowlist of files permitted to use the markers, no cap on region size, and no "N regions skipped" line in the success output.
- **Rule:** n/a.
- **Finding:** The design correctly hardened against the unbalanced marker as "an undetectable off switch", but the balanced form is equally undetectable and strictly easier to write. The markers also fire on any line containing the text, including prose inside backticks — this plan file's own lines 623-624 open and close a region purely by describing the feature, which happens to be harmless only because the two mentions are adjacent. A doc that mentions the start marker without a nearby end marker would mute the rest of itself.
- **Fix risk:** Reporting skipped-region counts is free. An allowlist would need `docs/skills/plan/reference.md`'s two legitimate regions enumerated, and would have to be kept current.


**FIXED 2026-09-06:** markers must start a line, and ignored regions are now reported on success

### F7 — a completion stamp is self-issued plaintext, and the fingerprint is a public helper

- **File:** `docs/skills/plan/scripts/lib.sh:249-273`, `docs/skills/workflow/scripts/subagent-stamp:37-41`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** the authoring agent or human itself — the only principal in scope. `plan_stamp_fingerprint` greps a plain line out of a file the PR fully controls, and `plan_code_fingerprint` is a shell function in the same sourced library, so a stamp that satisfies the gate with zero review is one `printf` with `$(plan_code_fingerprint)` substituted in.
- **Rule:** n/a.
- **Finding:** `subagent-stamp`'s header calls the stamp "mechanical proof the step actually ran", and `lib.sh` calls the agent set the ones "whose completion can be mechanically proven". Neither is true of a forged line, and the stamp does not even prove a review happened when it is genuine: `SubagentStop` fires for any subagent of that `agent_type` regardless of what it did, so dispatching a `security` subagent with a no-op prompt produces an identical, valid stamp. This is acceptable against the stated adversary ("an agent simply forgetting"), but it should be written down as such rather than described as proof — and F1/F2 matter here precisely because a gate that blocks spuriously makes forging the cheapest correct-looking resolution.
- **Fix risk:** Any real attestation (a signed note, a `git notes` ref written by a trusted runner) is a much larger change and cannot be produced by a local hook the same principal controls; the realistic fix is to soften the claim in the comments, not to strengthen the mechanism.


**FIXED 2026-09-06:** claims softened: a stamp is a record that defeats forgetting, not proof

### F8 — `plan-gate.yml`'s new comment states the opposite of what `plan-gate` does when `required-agents` is missing

- **File:** `.github/workflows/plan-gate.yml:48-55`, `docs/skills/workflow/scripts/plan-gate:51-55`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** the next person reasoning about the gate's fail mode from the workflow file.
- **Finding:** The comment says "Absent on the base branch (the PR introducing it), plan-gate skips the stamp check rather than failing." `plan-gate:51-55` does the opposite — `[ -x "$ra" ] || { echo "BLOCKED: required-agents is missing or not executable ..."; exit 1; }`. Fail-closed is the right behaviour; the comment describing it as fail-open is the defect, and it is the single comment a reader would consult to decide whether a missing `required-agents` is dangerous. Separately, `git show "origin/$BASE_REF:.../lib.sh"` on line 46 has no `git cat-file -e` guard where its two siblings do — harmless today (the step's implicit `bash -e` fails the job), but the asymmetry reads as intentional and is not.
- **Fix risk:** none, comment-only.


**FIXED 2026-09-06:** plan-gate.yml comment now states the actual fail-closed behaviour

### F9 — `plan-gate`'s failure summary always blames unresolved findings

- **File:** `docs/skills/workflow/scripts/plan-gate:123-125`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** anyone reading CI output. Verified in this worktree: a run that failed only on two missing stamps still ended with `plan-gate: one or more cited plans have unresolved findings. See above.`
- **Finding:** `fail=1` is now set by four distinct causes (unlocatable plan, unresolved findings, missing stamp, stale stamp) but the summary names only one. The per-cause `BLOCKED:` lines above it are correct, so this is cosmetic — but it is the line that will be quoted when someone reports the gate misbehaving, and it points at the wrong subsystem.
- **Fix risk:** none.

**Checked and clean (security, 2026-09-06).** `tests/zrepl-replication.nix`: verified that `import (pkgs.path + "/nixos/tests/ssh-keys.nix")` selects the same keys as the `"${pkgs.path}/..."` form it replaces. nixpkgs is a locked `github` flake input (`nix flake metadata --json`), so `pkgs.path` is already a store path and both forms read byte-identical content; `snakeOilEd25519PrivateKey`/`PublicKey` in `/nix/store/sr2lpwrcdjfpkk8gpvr98gp4nrgsijns-source/nixos/tests/ssh-keys.nix` are a `writeText` of a literal string and a literal `concatStrings`, both content-addressed, so the derivation and the key bytes are identical either way. These are nixpkgs' published RFC 9500 / OpenSSH-fuzz test keys, ephemeral to the VMs, and no private key enters this repo. `nix flake check --no-build` now passes end to end, so G5 is genuinely closed.

No NixOS module, systemd unit, firewall rule, user, group, capability, container, or `sops.secrets` reference is touched by this change, so `docs/hardening.md`'s standing rules 1-10 have no surface here; no secret was decrypted or read at any point. `plan_locate`'s `..` rejection was re-read against its new attacker-influenced input (commit-trailer text) and holds — a `/`-rooted, glob-bearing, or multi-match trailer all fail closed. `plan_has_heading` and `plan_stamp_fingerprint` take only regex-safe inputs (`[DGF][0-9]+` from the citation matcher, names from `PLAN_STAMPABLE_AGENTS`), so no shell or regex injection is reachable from `git ls-files` output or from trailer text. The CI pinning is sound as far as it goes: pinned `plan-gate`, `lib.sh` and `required-agents` all resolve through `SCRIPT_DIR`, never `$root`, so a PR editing its own gate scripts is judged by the base branch's logic, and a PR tampering with `PLAN_CODE_GLOBS` fails closed rather than open. `plan_code_fingerprint` cannot return empty (worst case it is `sha256sum` of nothing), and `xargs` batch-splitting does not perturb it since paths are sorted and included in the hash. `plan-citations` runs clean over 171 citations in ~0.4s and its memoisation and `checked` accounting are correct. `verify-ladder` dropping its `[ -x ]` guard around `plan-citations` is a real improvement — a missing script now yields exit 127 and `fail=1` rather than a printed skip.

_security finished 2026-09-06T18:32:51Z -- see Findings above._

**FIXED 2026-09-06:** summary line no longer names a cause; points at the BLOCKED lines

### F10 — `testing-changes.md`'s `verify-ladder` bullet omitted the new `plan-citations` gate

- **File:** `docs/procedures/testing-changes.md:99-104`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** this branch wired `plan-citations` into `verify-ladder` as an unconditional hard gate, but the doc's "What's automated" bullet for `verify-ladder` still described it as automating layers 1-3 only (`nixfmt --check`, `nix flake check --no-build`, targeted host builds, `statix`/`deadnix`). A reader deciding what the gate covers would conclude citation integrity is unchecked. The bullet now names `docs/skills/plan/scripts/plan-citations` and why it runs on every pass (a citation breaks from the target side).


**FIXED 2026-09-06:** testing-changes.md verify-ladder bullet now names the plan-citations gate

### F11 — `workflow` docs kept pre-D7-note language: "stamps proof", judgment-trigger agent bullets

- **File:** `docs/skills/workflow/SKILL.md:48-49`, `docs/skills/workflow/reference.md:128-145`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** two leftovers from before the D7 2026-09-06 note and F7's claim-softening. (1) SKILL.md step 6 still said the `SubagentStop` hook "stamps proof it actually finished" — F7 established a stamp is a record that defeats forgetting, not proof, and every script comment was softened accordingly; the skill doc was not. Now reads "stamps a record ... (a record, not proof)". (2) reference.md's "The agents themselves" bullets were left as the old judgment-gated invocation list: `security` phrased as a trigger condition ("anything touching firewall rules ..."), `docs-updater` as "once the code-level work is otherwise done" (it now runs second in the loop, before the read-only reviewers), and `/simplify` as "fires on any `.nix` change" (narrower than the trigger table, which includes skill scripts and git hooks). Rewritten to describe what each agent reviews, deferring firing conditions to the mechanical table and order to the loop section.

**FIXED 2026-09-06:** SKILL.md proof wording softened; reference.md agent bullets rewritten to match table/loop

_docs-updater finished 2026-09-06T19:08:14Z -- see Findings above._

_docs-updater finished 2026-09-06T19:26:39Z -- see Findings above._

### F12 — every completion stamp on this branch was written by master's pre-fingerprint `subagent-stamp`, so D11's staleness check is inert on the PR introducing it

- **File:** `.claude/settings.json` (SubagentStop hook, `${CLAUDE_PROJECT_DIR}` path), `docs/skills/workflow/scripts/subagent-stamp:41-47`, this plan's stamp lines (918, 939, 941)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the effect (stamps and gate behavior verified live); PLAUSIBLE for the mechanism (that `${CLAUDE_PROJECT_DIR}` resolves to the main checkout for worktree sessions is inferred, not observed directly)
- **Axis:** hardening
- **Reachability:** the system's own stated adversary — a stale review passing as current. All three stamps in this plan (`security` 18:32:51Z, `docs-updater` 19:08:14Z and 19:26:39Z) lack the `(code <fp>)` field this branch's `plan_stamp_line` emits, and byte-match the output format of the main checkout's master copy of `subagent-stamp`, which has no fingerprint support. The two docs-updater stamps postdate commit `23c2955` (18:58:20Z), which added fingerprinting to this worktree's script, so the hook that executed was not this branch's copy. Verified live: `plan-gate origin/master HEAD` exits 0, downgrading both stamps to `legacy` NOTEs — even though the code changed substantially after the security stamp (the F1-F9 fix commit, two docs-updater comment passes, the /simplify refactor), which is exactly the drift D11 exists to block.
- **Rule:** analog of `docs/hardening.md` rule 9 — "verify that config actually takes effect; rendering is not applying." The hook wiring renders correctly; the code that runs is a different version.
- **Finding:** worktree sessions execute hooks from the main checkout's tree, so a PR that changes hook behavior is never exercised by the sessions developing it, and its stamps carry whatever format master's scripts produce. For this PR the mechanism D11 built is unverified end to end: the gate passes on legacy stamps, and the stamp this very review produces will also be fingerprint-less. It self-heals for later PRs once master carries the new script and the main checkout is pulled — but the same gap recurs on every future hook-script PR developed in a worktree, and D11's "verified by direct test" tested the scripts standalone, never the live hook path.
- **Fix risk:** pointing the hook at the worktree's copy would let a PR neuter its own local stamp writer (CI pins the gate, not the writer). The realistic fix is written-down procedure: after merging a hook-script PR, pull the main checkout before trusting new hook behavior, and expect the introducing PR's own stamps to read as legacy — by design, not by surprise.


**FIXED 2026-09-06:** the worktree-hook gap is now written-down procedure in workflow/reference.md's stamp section: an introducing PR's stamps read legacy by design; pull the main checkout after merging a hook-script PR

### F13 — a fingerprint-less stamp on a non-frozen plan passes the gate forever, and is cheaper to produce than an honest one

- **File:** `docs/skills/workflow/scripts/plan-gate:128-131`, `docs/skills/plan/scripts/lib.sh:352-368`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** the authoring agent (deliberately, or via F12 occurring naturally). `plan_stamp_fingerprint` returns `legacy` for any stamp lacking `(code ...)` and `malformed` for an empty capture, and plan-gate treats both as non-blocking NOTEs regardless of frozenness — while a *missing* stamp on a non-frozen plan is BLOCKED. So the old-format line `_security finished <ts> -- see Findings above._` — one printf, no fingerprint computation — satisfies the gate on a live plan indefinitely, strictly more cheaply than the honest path, which risks staleness blocks.
- **Rule:** compare `docs/hardening.md` rule 11 — a NOTE nothing consumes measures the attempt, not the outcome.
- **Finding:** the legacy downgrade exists so pre-fingerprint *frozen* plans cannot become unfixable blocks (F1), but on a non-frozen plan re-running the agent is always satisfiable: `plan_stamp_fingerprint` reads the newest stamp (`tail -n 1`), so a fresh run supersedes a legacy line. Routing `legacy`/`malformed` through `stamp_problem` (NOTE when frozen, BLOCKED otherwise) closes the loophole without recreating F1. As it stands, F12's stamps sail through, and would keep doing so even after the fingerprint era fully arrives.
- **Fix risk:** an in-progress plan spanning the fingerprint transition blocks until its agents re-run once — one extra, satisfiable pass. Verify against this plan's own three legacy stamps before enabling.


**ACCEPTED 2026-09-06:** accepted by the user (LilijoySkyseeker) 2026-09-06: blocking legacy stamps on non-frozen plans would brick this very PR, whose stamps are all unavoidably legacy per F12 -- no session can produce a fingerprinted stamp until this branch merges and the main checkout is pulled. Safe only after the transition; follow-up filed as 2026-09-06-enable-fingerprint-less-stamp-blocking-once-the-fingerprint-era-has.md

### F14 — F1's second instance is still open: a PR that changes the fingerprint's inputs or algorithm cannot pass CI honestly

- **File:** `docs/skills/workflow/scripts/plan-gate:81`, `docs/skills/plan/scripts/lib.sh:243,258-290`, `.github/workflows/plan-gate.yml:46`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED by reading both sides; not reproducible without a second stacked PR
- **Axis:** hardening
- **Reachability:** the next PR that edits `PLAN_CODE_GLOBS` or `plan_code_fingerprint` while citing a non-frozen plan — and such a PR always obliges `security`/`docs-updater`, since `lib.sh` is itself inside the code globs. CI computes `current_fp` with the *pinned base-branch* `lib.sh`; the stamp's fingerprint was computed locally by the *PR's* `lib.sh`. When the two disagree on the file set or the hash pipeline, they disagree on the value for the same tree: the stamp reads stale, re-running the agent re-stamps with the PR's algorithm, and the block is unfixable in-system on a non-frozen plan. F1 named this instance explicitly; its FIXED resolution (frozen degrades to NOTE) addressed only the freeze-boundary case.
- **Rule:** same class as F1 — a gate whose only recovery is outside the system (drop the `Plan:` trailer, the G42 bypass) teaches the bypass.
- **Finding:** frequency is not hypothetical. This very working tree changed the algorithm again (dropping the post-hash `sort` changes the emitted value for an identical tree), and the D7 restart-rule note ("agent definitions included, `.md` or not") is a standing invitation to widen `PLAN_CODE_GLOBS` soon. Both are masked on *this* PR only because the base branch has no stamp check yet and this branch's stamps are all legacy (F12) — the next such PR hits the block for real.
- **Fix risk:** plan-gate could detect that base and head disagree on `lib.sh` (or on the glob array) and degrade staleness to a named NOTE for that range — but that hands any PR touching `lib.sh` a staleness pass, so the missing-stamp arm must stay blocking, and the fact that `lib.sh` edits themselves oblige security review is what bounds the exposure. Whichever way, test with an actual stacked PR, not by reasoning.


**ACCEPTED 2026-09-06:** accepted by the user (LilijoySkyseeker) 2026-09-06: structural gate-design work (base-pinned lib.sh vs the PR's own compute two different fingerprints for one tree), and the finding itself says it must be tested with a real stacked PR rather than reasoned about. Masked on this PR because the base branch has no stamp check yet. Follow-up filed as 2026-09-06-make-plan-gate-survive-a-pr-that-changes-the-fingerprint-algorithm-or.md

### F15 — `plan-touch-guard`'s new `lib.sh` dependency fails open

- **File:** `docs/skills/workflow/scripts/plan-touch-guard:13-14,32`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** a checkout where `docs/skills/plan/scripts/lib.sh` is missing or moved (a future restructure of the plan scripts, a broken/sparse worktree). The `.` fails but the script continues under `set -u` (no `-e`) until `$PLAN_ACTIVE_MARKER_RELPATH` — unbound, bash exits 1. A PreToolUse hook blocks via the JSON deny (exit 0) or exit 2; a plain exit 1 is a non-blocking error, so the bare `git commit` proceeds unguarded. Before this refactor the guard was self-contained; the shared-constant cleanup traded one duplicated literal for a fail-open dependency. `subagent-stamp` shares the dependency but fails closed (no stamp means the gate blocks), so only the touch-guard direction matters.
- **Rule:** `docs/hardening.md` rule 11.
- **Fix risk:** source with `|| exit 2` (or restore the one literal) — but confirm exit 2 is what Claude Code treats as a PreToolUse block, and note it would then block *every* Bash call in a checkout that broken, which is loud on purpose.


**FIXED 2026-09-06:** the lib.sh dependency is removed, not guarded. A guard was written first (source on the commit path only, `|| hook_deny`), and the next `/simplify` pass showed it was worse than the disease: it still failed open if the *symbol* were renamed rather than the file removed, and a lib.sh that merely ended on a nonzero command would have made the hook deny every commit in the repo. plan-touch-guard hardcodes both marker paths again, with the reason recorded at lib.sh's PLAN_ACTIVE_MARKER_RELPATH so the next agent does not re-centralize it

### F16 — `plan-citations` never scans untracked files, unlike every sibling this branch aligned on `plan_worktree_files`

- **File:** `docs/skills/plan/scripts/plan-citations:49`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** an author adds a brand-new, never-staged `.md` or skill script containing a citation; `git ls-files` (index only) omits it, verify-ladder's citation gate passes, and the broken citation lands unless something re-runs after `git add`. The branch's own rationale for `plan_worktree_files` — "a brand-new module is the change most in need of review" — applies verbatim: the fingerprint and required-agents both count untracked files, the citation checker does not.
- **Rule:** n/a.
- **Fix risk:** add `--others --exclude-standard` to the `ls-files` call; the cost is scanning scratch files never meant to be committed — the same documented trade `plan_code_fingerprint` already makes.

**Checked and clean (security, 2026-09-06, second pass).** Reviewed the full branch diff plus the uncommitted working tree: `lib.sh`, `plan-citations`, `plan-lint`, `plan-gate`, `required-agents`, `verify-ladder`, `subagent-stamp`, `plan-touch-guard`, `plan-gate.yml`, and the doc changes (SKILL.md step 6, reference.md loop/agent sections, testing-changes.md). All nine first-pass fixes hold and none was regressed by the refactors: F3 and F4 re-verified live (bogus refs die with exit 1 on both scripts), F5's awk-status observation survives (`awk | sort -u > file` under `set -o pipefail`, absent files filtered, `./` prefix intact), F6's line-anchored markers and region reporting survive the /simplify pass (the per-file count was dropped, the count itself stays), F1's NOTE-vs-BLOCKED split is preserved exactly by the new `stamp_problem` helper (`fail=1` persists — the plan loop is a here-string, not a pipeline subshell), F2's editor-then-reviewer order is consistently stated in SKILL.md, reference.md and the D7 note, and F7/F8/F9's wording fixes are all still in place. `plan_code_fingerprint` post-refactor: verified deterministic and locale-stable by direct run (identical value under `en_US.UTF-8` and `C`); dropping the post-hash sort is sound because `LC_ALL=C sort -zu` fixes path order and sequential `xargs` batches preserve it, and duplicate index stages (merge conflicts) dedupe in the same sort. `plan_worktree_files` pins `LC_ALL=C`, reproduces the previous inline unions exactly, and genuinely closes G8's first half (untracked files now reach the targeted-build set, not just linting). The duplicate-basename map agrees with `plan_locate`'s ambiguity refusal, the fail-closed dispatch arm makes scanner/reader drift loud, and `plan-citations` runs clean (181 citations, 2 ignored regions). The CI pin tree satisfies every `SCRIPT_DIR` resolution (pinned plan-gate sources pinned lib.sh; pinned required-agents likewise); nothing in CI executes the PR's own copies. `subagent-stamp`'s frozen test is now frontmatter-scoped and agrees with plan-gate, closing the raw-grep divergence. The narrowed restart rule is a user-signed decision recorded consistently in D7, SKILL.md and reference.md, and it keeps `security` after every editing agent within a pass, so no review gap opens. Two non-findings for the record: the unpinned `sort -u` in plan-citations only dedupes (its reader is order-independent), and `nixfmt --check` false-blocking on a tracked-but-deleted `.nix` file predates this branch (master's `changed_nix` had the same legs minus untracked). No NixOS module, systemd unit, firewall rule, user, group, capability, container, or `sops.secrets` reference is touched anywhere in this range; no secret was decrypted or read.

_security finished 2026-09-06T19:41:43Z -- see Findings above._

**FIXED 2026-09-06:** plan-citations ls-files now includes --others --exclude-standard, matching the fingerprint's tracked+untracked union

### F17 — `plan-touch-guard`'s hardcoded-path comment carried F15's whole argument inline, and stated the failure direction backwards

- **File:** `docs/skills/workflow/scripts/plan-touch-guard:30-35`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the six-line comment justifying the hardcoded `.claude/.active-plan` path reproduced, in prose, the rationale already recorded verbatim in F15's FIXED note — exactly the "why belongs in the plan, not the comment" split `docs/style-guide.md` sets out, and the citation form it prescribes was unused. It was also inaccurate twice. (1) It called this "the pre-commit path"; `plan-touch-guard` is a `PreToolUse` hook that matches `git commit` in a Bash tool call, not a git `pre-commit` hook — the repo has a real `.githooks/pre-commit`, so the mislabel points a reader at a different file. (2) "a lib.sh that is missing ... would deny every commit in the repo" holds only for the *withdrawn* guarded design (`source ... || hook_deny`). Unguarded sourcing, which is what every hook in `docs/skills/workflow/scripts/` actually does with `hook-lib.sh`, fails the other way: the `.` returns 1, execution continues under `set -u` with no `set -e`, `hook_json_str` is command-not-found, `tool_name` comes back empty, the Bash guard exits 0 — a silent allow, as `2026-09-06-make-the-workflow-hooks-fail-closed-when-hook-lib-sh-is-missing.md` records. A reader taking the comment at face value would conclude the missing-library case is loud, when the open follow-up says it is silent. Replaced with a two-line mechanics note plus `plan: ...#F15`; `lib.sh`'s counterpart cross-reference now cites F15 directly instead of chaining through "see the comment there".

**FIXED 2026-09-06:** plan-touch-guard comment reduced to keep-in-sync + F15 citation; lib.sh cross-reference cites F15 directly

### F18 — `verify-ladder`'s `plan-citations` comment still described the pre-F16 tracked-only scan

- **File:** `docs/skills/workflow/scripts/verify-ladder:26`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the comment justifying why the citation gate runs on every pass described its cost as "one awk pass over tracked code and docs". F16's fix added `--others --exclude-standard`, so the scan now covers untracked files too — the same class of stale-after-revert comment this branch has already hit twice. Left as-is it also understates the gate: a reader would not expect a never-staged scratch file to be reported. Now reads "over the working tree's code and docs, tracked and untracked", matching `plan-citations`' own header.

**FIXED 2026-09-06:** verify-ladder's plan-citations comment names the tracked+untracked scope

### F19 — `SKILL.md` step 4 omitted `plan-citations` from `verify-ladder`'s hard-block list

- **File:** `docs/skills/workflow/SKILL.md:31-37`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** F10 fixed this omission in `docs/procedures/testing-changes.md` but not in the skill doc an agent actually reads at step 4, which still listed only `nixfmt --check`, `nix flake check --no-build`, the targeted build and statix/deadnix. `verify-ladder` runs `plan-citations` first and unconditionally, and blocks on it; an agent working from the skill would not know a broken citation stops the ladder, and would read the block as unrelated. Step 4 now names it.

**FIXED 2026-09-06:** SKILL.md step 4 lists plan-citations among verify-ladder's hard blocks

### F20 — `reference.md` stated F12's inferred hook-resolution mechanism as settled fact, and pointed at "child 8" with nothing to resolve it against

- **File:** `docs/skills/workflow/reference.md:91-97,151-158`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** two things in the newly added paragraphs. (1) "Hooks resolve through the session's original project directory" is asserted flatly, but F12 marks exactly that mechanism `PLAUSIBLE` — "inferred, not observed directly" — while marking only the effect `CONFIRMED`. This is the same claim-strength drift F7 and F11 corrected for "stamps proof": a doc that hardens the plan's own hedge is how an inference becomes repo fact. Softened to name which half is confirmed. (2) The serialized-reviewers paragraph ended "(child 8)", the only use of the map plan's Progress numbering anywhere in the `workflow` skill and unresolvable without opening that plan and counting. Replaced with a bare-filename+anchor citation to D7, which is where the constraint is actually recorded.

**FIXED 2026-09-06:** worktree-stamping claim hedged to match F12's confidence; "child 8" replaced with a D7 citation

_docs-updater finished 2026-09-06T20:09:37Z -- see Findings above._

### F21 — `reference.md`'s stamp section still spelled out the pre-G11 `PLAN_CODE_GLOBS`, contradicting the same file's own trigger table

- **File:** `docs/skills/workflow/reference.md:142`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the `/simplify` pass widened `PLAN_CODE_GLOBS` (G11) and rewrote the trigger-table section to say the array in `lib.sh` is the authority, listing CI workflows, `.claude/settings.json` and the agent definitions alongside Nix, skill scripts and git hooks. "What a completion stamp proves", ninety lines down the same file, was left re-listing the old three globs verbatim: "a content hash over `*.nix`, `docs/skills/*/scripts/*` and `.githooks/*`". So one document gave two different answers to "what does the fingerprint cover", and the wrong one was the one a reader lands on when asking why their stamp went stale — they would conclude a `.github/workflows/` edit could not have moved it, when it is exactly what did. This is the branch's recurring defect (a comment describing a version later changed) in a doc rather than a comment, and it is the second rendering of a fact D1 says must live in one place: rewritten to point at `PLAN_CODE_GLOBS` rather than restate it.


**FIXED 2026-09-06:** reference.md's stamp section now points at PLAN_CODE_GLOBS instead of re-listing the pre-widening three globs

### F22 — `verify-ladder` gained a hard `plan-lint` gate that none of the three places enumerating its hard blocks mentioned

- **File:** `docs/skills/workflow/scripts/verify-ladder:5-6`, `docs/skills/workflow/SKILL.md:32-37`, `docs/procedures/testing-changes.md:99-105`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the `/simplify` pass added a `plan-lint` run over the active plan to `verify-ladder`, setting `fail=1` on a malformed plan — a fourth hard block. All three enumerations of what the ladder blocks on were left at the previous set: the script's own header ("Hard-blocks on plan-citations, nixfmt --check, nix flake check, a targeted nixos-rebuild build, and statix/deadnix"), SKILL.md step 4, and `testing-changes.md`'s `verify-ladder` bullet. Exactly the omission F19 fixed one pass earlier for `plan-citations`, recurring for the gate added in its place: an agent blocked by "the active plan is malformed" would find nothing in the skill it reads explaining that the ladder checks plan structure at all, and would read the block as unrelated to the ladder. All three now name it and what it catches.


**FIXED 2026-09-06:** verify-ladder's header, SKILL.md step 4 and testing-changes.md all name the plan-lint hard block now

### F23 — `plan-gate` and its workflow both advertised a local pre-merge/pre-deploy caller that does not exist

- **File:** `docs/skills/workflow/scripts/plan-gate:6-8`, `.github/workflows/plan-gate.yml:8-11`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** F4 observed in passing that nothing in the repo invokes `plan-gate` locally — "the header's 'used both pre-merge and pre-deploy' is currently aspirational — the only real caller is `.github/workflows/plan-gate.yml`" — but F4's FIXED resolution covered only the ref-resolution half, leaving the claim in place. Re-verified this pass: a grep over `docs/`, `.githooks/`, `modules/`, `hosts/` and `.claude/` still finds no caller, and `verify-ladder` runs `plan-citations` and `plan-lint` but not `plan-gate`. The `/simplify` pass then rewrote both headers around the false claim rather than dropping it, so `plan-gate.yml` now asserts it "runs the same script the local pre-merge/pre-deploy path uses", naming a path with nothing in it. The cost is misdirection about where the gate actually fires: a reader planning a deploy would expect to be gated and is not. Both headers now say what is true — CI over the PR range is the only automated caller, any other range is a hand-run.


**FIXED 2026-09-06:** both headers name CI over the PR range as the only automated caller; the local pre-merge/pre-deploy claim is gone

### F24 — `PLAN_CODE_GLOBS`' comment reproduced G11's argument inline

- **File:** `docs/skills/plan/scripts/lib.sh:255-262`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the widening added a nine-line why-block to the array — the enforcement machinery is not all Nix, settings.json decides whether hooks run, the workflow decides whether CI gates anything, a set missing them would let the most gate-weakening change oblige no review — which is G11 restated, in G11's own words, one channel over. `docs/style-guide.md` routes exactly this to the plan file with a citation pointer inline, and the block is the shape most likely to go stale next: the array is an allowlist G11 itself says will need widening again, and the prose enumerating today's members would not be updated with it. Reduced to a one-line labelling fragment plus `#G11`. Not re-recorded here in full, since duplicating it into a second plan section is the same defect D1 rules out.

**FIXED 2026-09-06:** PLAN_CODE_GLOBS comment cut to a labelling fragment plus a #G11 citation

### F25 — `.github/workflows/*` in `PLAN_CODE_GLOBS` buys no enforcement, because the workflow is its own enforcer

- **File:** `docs/skills/plan/scripts/lib.sh:258-266`, `.github/workflows/plan-gate.yml:25-33,62-67`, `docs/skills/workflow/reference.md:53-58`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any agent or contributor with push access to a branch in this repo — the same principal the base-branch pinning at `plan-gate.yml:25-33` exists to constrain. Edit `.github/workflows/plan-gate.yml` in the PR itself: add `continue-on-error: true` to the "Check cited plans" step, or flip its `if:`, or repoint `BASE_REF`. GitHub resolves a `pull_request` workflow from the PR's own merge ref, not from the base branch, so the neutered file is the one that runs and the pinned `/tmp/plan-gate-trusted/...` script is never invoked. The repository ruleset (verified live via `gh api repos/LilijoySkyseeker/nixOS/rules/branches/master`) requires exactly one status context, `plan-gate`, and that context is satisfied by whatever job in the PR's own workflow carries `name: plan-gate`. The check reports green.
- **Rule:** new-rule candidate — a gate whose only enforcer is the artefact it gates cannot gate that artefact; compare `docs/hardening.md` rule 11 (a guard that declines to act must be watched by something that measures the outcome).
- **Finding:** G11 names two omissions and calls them "the worst possible ones": gutting `.claude/settings.json` and gutting `.github/workflows/plan-gate.yml`. The widening genuinely closes the first — a `settings.json` edit sets `code=1` in `required-agents:51-52`, and the stamps that go missing when hooks stop firing are checked *server-side* by a script the PR does not control, so the evasion is caught. It does not close the second. Adding `.github/workflows/*` makes a workflow edit oblige `/simplify`+`security` and move the fingerprint, but both obligations are enforced only by `plan-gate`, which the edited workflow decides whether to run. `required-agents` has exactly one enforcing caller (`plan-gate:72`); nothing under `.githooks/` invokes it, so there is no second, independent observer. The net effect against a deliberate adversary is zero; against forgetting it is real, which is worth having, but `reference.md:53-58` and G11 both present it as covering the deliberate case. What would actually close it is outside the repo: a second required status context supplied by a workflow the PR cannot edit (a reusable workflow pinned by SHA, an `on: pull_request_target` job, or a GitHub App check), or a ruleset requiring review for `.github/**` paths. This also means the repo's only server-side gate is defeatable by a single-file edit that the same edit obliges nobody to notice.
- **Fix risk:** `pull_request_target` runs with a writable token against the base ref and must never check out PR code — a naive conversion is a known repo-takeover primitive, so any fix there needs the untrusted-checkout rule applied strictly. A path-scoped ruleset requiring review on `.github/**` blocks the solo maintainer from self-merging workflow changes, which for a one-contributor repo means an approval that has to come from a second account. Test that the existing `plan-gate` context still reports on a PR touching no workflow at all before relying on a second context.


**ACCEPTED 2026-09-06:** accepted by the user (LilijoySkyseeker) 2026-09-06: listing the CI workflow in PLAN_CODE_GLOBS buys review and a stamp, not prevention, because GitHub resolves a pull_request workflow from the PR's own ref. Prevention needs repository settings rather than code, and the finding itself requires a real stacked PR to test. reference.md no longer claims the settings.json and workflow halves are equivalent. Follow-up filed as 2026-09-06-stop-a-pr-from-weakening-the-ci-gate-it-is-judged-by.md

### F26 — `.sops.yaml` and `secrets/*` change without obliging any review agent and without moving the fingerprint

- **File:** `docs/skills/plan/scripts/lib.sh:258-271`, `docs/skills/workflow/scripts/required-agents:43-59`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** any agent working in this repo, on the one edit `docs/procedures/secrets.md:48-50` explicitly authorises it to make unsupervised — "Adding/removing recipients is fine for an agent to do directly". Verified by evaluating the predicates against the pinned working tree: `plan_is_code_path .sops.yaml` and `plan_is_doc_path .sops.yaml` both return false, likewise for `secrets/secrets.yaml`, `flake.lock`, `.gitignore` and the `.claude/agents/*.md` / `.claude/skills/*` symlinks. With `code=0` and `docs=0`, `required-agents` emits nothing, `plan-gate`'s `for agent in $obliged` loop body never executes, and the run prints "all cited plans have their findings resolved and their obliged reviews stamped" over a diff nobody reviewed. The file's content is also outside the fingerprint, so no pre-existing stamp goes stale either.
- **Rule:** violates the spirit of `docs/hardening.md` "Secrets" rules 1 and 2 — a blanket `creation_rules` rewrite (rule 2's named mistake, "makes every host a full-fleet decryption oracle") and a recipient removal without value rotation (rule 1, "removing an age recipient protects nothing already committed") are both single-file `.sops.yaml` edits. `git log -- .sops.yaml` shows this is not hypothetical: `e42683c security(vps): rotate sops recipient ahead of reinstall`, plus `a6f4fb0` and `c2a6549`, are all real recipient changes that under today's set would oblige nobody.
- **Finding:** G11 concedes generically that "the set is still an allowlist, so the next file that matters will be missed the same way", but names no instance. The instances are the point: the most security-sensitive non-Nix file in the repo obliges zero review, while `.github/workflows/plan-gate.yml` — which F25 shows the mechanism cannot enforce anyway — was added. Three further instances share the gap and the fix. `flake.lock`: a lock bump moves every package version on the fleet and obliges nothing, which is also internally inconsistent, since `verify-ladder:163` counts `flake.lock` as build-relevant enough to trigger a `nixos-rebuild build` while `required-agents` counts it as not review-relevant at all. `.gitignore`: it is an input to `--exclude-standard` and therefore to both the fingerprint and `plan-citations`' scan set. `.claude/agents/*.md` and `.claude/skills/*`: these are the tracked symlinks Claude Code actually discovers agents and skills through, and repointing `.claude/agents/security.md` swaps this agent's definition wholesale — matched only by `PLAN_DOC_GLOBS`, so it obliges `docs-updater` and not `security`, while `docs/agents/security.md` (its target) is code. That last pair is exactly the class the widening claims to have closed. Related but separate: `docs/agents.md`, which `reference.md:18` calls the home of the general agent-invocation policy, is not matched by `docs/agents/*.md` (no trailing `/`), so the top-level policy file is prose while the per-agent files under it are code.
- **Fix risk:** adding `.sops.yaml` and `secrets/*` to `PLAN_CODE_GLOBS` puts the ciphertext blob into the fingerprint, so every `sops updatekeys` (which rewrites the whole file even when no value changed) stales every stamp and obliges a full review round — acceptable for `.sops.yaml`, arguably not for `secrets/secrets.yaml`. Adding `flake.lock` means every routine `nix flake update` obliges `/simplify`+`security`+`docs-updater`; that may be correct but it changes the cost of a weekly chore. Any glob change is itself the F14 / `2026-09-06-make-plan-gate-survive-a-pr-that-changes-the-fingerprint-algorithm-or.md` trap, so it has to land on a PR whose own stamps are expected to mismatch. Test by running `required-agents <base> <head>` over a synthetic `.sops.yaml`-only range before and after.


**FIXED 2026-09-06:** PLAN_CODE_GLOBS now covers .sops.yaml, secrets/*, flake.lock, .gitignore and all of .claude/ (the agent and skill symlinks, not just settings.json). .gitignore matters most subtly: --exclude-standard means it decides the fingerprint's own inputs

### F27 — the code set now contains `.md`, so `reference.md`'s "the fingerprint covers code only, never `.md`" and its no-restart rule for `docs-updater` are both false

- **File:** `docs/skills/workflow/reference.md:148-150`, `docs/skills/workflow/reference.md:119-129`, `docs/skills/plan/scripts/lib.sh:251-253`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any contributor following `reference.md`'s own loop rules. `docs/agents/*.md` is in `PLAN_CODE_GLOBS`, and `git ls-files --cached --others --exclude-standard -- "${PLAN_CODE_GLOBS[@]}"` returns `docs/agents/docs-updater.md`, `docs/agents/security.md` and `docs/agents/security/reference.md` (the glob's `*` crosses `/` under both git's default pathspec matching and bash `[[ ]]`, so it reaches the nested file too). All three are `.md`, and all three are inside `docs-updater`'s remit — its definition at `docs/agents/docs-updater.md:40-78` scopes it to "every doc or comment touched by the diff", with no carve-out. So the sequence `reference.md:126-129` explicitly blesses — "`docs-updater`'s *own* doc and comment fixes never restart the loop by themselves: they change no behavior" — moves the fingerprint whenever that pass touches a `docs/agents/*.md` file *or* an inline comment in any `.nix`/skill script, and leaves the already-written `security` stamp stale. `plan-gate:133` then prints BLOCKED on a task the doc said was finished. This branch is the live instance: two `docs-updater` passes ran after the last `security` pass, and the only reason the gate is green is that every stamp here is `legacy` (F12), which the same run downgrades to a NOTE.
- **Rule:** n/a — but it is the failure mode F1 and G5 named ("an un-passable gate teaches the bypass"); the cheapest escape from a BLOCK the docs say should not happen is dropping the `Plan:` trailer, which disables the unresolved-findings check too.
- **Finding:** three statements now disagree. `reference.md:148` says flatly "The fingerprint covers code only, never `.md`", and gives the reason — "including prose would make each stamp invalidate itself". `lib.sh:251-253` repeats it: "Code only: prose is excluded so a stamp cannot invalidate itself". `lib.sh:255-256` and `reference.md:53-58`, two and ninety lines away respectively, say the set covers "the agent definitions", which are `.md`. F21 fixed one half of this contradiction last pass by making `reference.md:142` point at `PLAN_CODE_GLOBS` instead of restating it; the categorical "never `.md`" three lines further down survived, and it is the sentence a reader lands on when asking why a stamp went stale. The mechanism is defensible — an agent definition is behavior, as G11 argues — but then the invariant is not "no `.md`", it is "nothing an already-stamped agent writes", and `reference.md:119-129`'s no-restart carve-out for `docs-updater` has to be narrowed to match, because `docs-updater` writes to both `.nix` comments and `docs/agents/*.md`.
- **Fix risk:** narrowing the carve-out to "doc fixes outside `PLAN_CODE_GLOBS`" makes the rule correct but requires the reader to evaluate a glob set mid-loop, which is the kind of judgment call D7 says gets skipped; stating "any `docs-updater` pass restages `security`" is simpler and costs one extra review round per pass. Dropping `docs/agents/*.md` from the code set instead re-opens the hole G11 added it for. Either way `reference.md:148`, `reference.md:119-129` and `lib.sh:251-253` have to move together — they are three renderings of one fact, which D1 says should be one.

**Checked and clean (security, 2026-09-06, final pass).** Re-reviewed `git diff origin/master...HEAD` plus the full uncommitted working tree, reading current file contents rather than diff hunks. Verified and found fine: `plan_code_fingerprint` is still deterministic and locale-stable after the widening — measured identical output (`dc72e0c4ef0c8658`) under the ambient locale, `LC_ALL=en_US.UTF-8`, and `LANG=C.UTF-8 LC_COLLATE=en_GB.UTF-8`, so G10's fix survives; it cannot silently return the sha256-of-nothing on failure (`set -o pipefail` inside the substitution plus `|| return 1`, confirmed by running it outside a repo: rc=1, no output), though an empty *match* set does still return `e3b0c44298fc1c14` successfully — unreachable with today's globs, and fail-closed either way, since a writer computing a subset and a reader computing the full set produce a mismatch, not a match. The 16-char output is always non-empty when rc=0, so `subagent-stamp:48`'s `|| exit 0` genuinely closes the `(code )` fail-open: `plan_stamp_fingerprint` returns `malformed` for an empty capture, `legacy` only for a stamp with no `(code ` at all, and non-zero for no stamp — all three verified against synthetic files. `plan-gate`'s hoisted `stamp_problem` propagates `fail=1` correctly; reproduced the exact construct (a function called from a `while` loop fed by a here-string, not a pipeline) and confirmed the assignment survives to the caller, and confirmed the live run over `origin/master..HEAD` still exits 0 with only the expected F12/F13 legacy NOTEs. `required-agents` emits in `PLAN_AGENT_ORDER` in both modes (`/simplify`, `docs-updater`, `security`, `spec-check` in the working tree; the first three in range mode), so the order `reference.md` calls unsatisfiable is no longer produced. `plan_heading_re` introduces no regex or quoting regression: the string it emits is byte-identical to the four inlined copies it replaced, it reaches `grep -E` quoted and `awk -v` in a value containing no backslash (so awk's escape processing has nothing to act on), and every id reaching it is either a literal (`required-agents:67`), regex-free `[DGF][0-9]+` text from `plan-citations`' own scanner and `plan-lint`'s `grep -oE`, or a CLI argument already screened by `case "$id" in D[0-9]*)`. That screen does admit ids like `D1.*` that would match a sibling heading, but it is unchanged from before the refactor and has no adversary beyond a malfunctioning caller. `plan_path_matches` agrees with git's pathspec matching on every path tested, including the `*`-crosses-`/` cases, so `required-agents`, `plan-citations` and the fingerprint cannot disagree about what counts as code. `verify-ladder`'s split sets are right: deleted-but-uncommitted paths are dropped from the lint set (the linters take filenames) and kept in `changed_all` for host detection (a deleted module still has to rebuild). The widened globs over-match nothing harmful in the current tree — `.claude/worktrees/` is gitignored, so a worktree checkout cannot double-count every script into the fingerprint, and no code-glob-matched path is a symlink to a directory. `plan-lint` and `plan-citations` both pass on the active plan (206 citations resolve, 2 ignored regions). No secret was read or decrypted at any point; `.sops.yaml` was inspected only for the presence of `creation_rules`/`path_regex` keys and its commit subjects. F12, F13 and F14 were not re-raised; the glob widening does not change F12's or F13's severity, and makes F14 certain rather than merely possible for this PR, which G11 already records.

_security finished 2026-09-06T21:16:37Z -- see Findings above._

**FIXED 2026-09-06:** the set is documented as behavior-not-extension: plan files and explanatory prose stay out so a stamp cannot invalidate itself, agent definitions are in despite being .md. The docs-updater-never-restarts rule now states its mechanical exception -- an edit inside the code set moves the fingerprint, which is the same rule rather than a second one

### F28 — the `.claude/*` narrowing's rationale was written into two channels at once, and supersedes F26's resolution text

- **File:** `docs/skills/plan/scripts/lib.sh:287-291`, `.gitignore:10-13`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the same why lives in two comments. `lib.sh:288-291` reads "Named individually, not `.claude/*`: the harness writes its own files into this directory, and an untracked one that exists locally but never in CI puts a phantom into the fingerprint that no re-run can clear." `.gitignore:10-13` reads "written by Claude Code on a 'don't ask again' grant, so it exists locally and never in CI. Untracked files count toward the stamp fingerprint, so leaving this visible would make every stamp read stale in CI with no way to fix it from inside the system." Two renderings of one fact is the defect D1 rules out and F24 already corrected once at the `PLAN_CODE_GLOBS` definition site. Separately, this narrowing invalidates the wording of F26's resolution above, which records that the set "now covers ... all of .claude/ (the agent and skill symlinks, not just settings.json)". The set now covers `.claude/settings.json`, `.claude/agents/*` and `.claude/skills/*` only; `.claude/*` as a whole-directory glob was reverted because it swept in `.claude/settings.local.json`. F26's resolution line is not edited (Findings are append-only) — this entry is the correction of record.

**FIXED 2026-09-06:** both comments cut to one-line fragments plus an `#F28` pointer; `.claude/settings.local.json` also added to `.gitignore` so it never reaches the fingerprint

### F29 — two comments still claimed `plan-citations` shares `PLAN_CODE_GLOBS` after the `PLAN_TEXT_GLOBS` split

- **File:** `docs/skills/workflow/scripts/required-agents:40-42`, `docs/skills/plan/scripts/lib.sh:359-363`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the same pass that introduced `PLAN_TEXT_GLOBS` left both descriptions of the old three-way sharing in place. `required-agents:41-42` said the code set "has to agree with what plan-citations scans and what the fingerprint covers", and `lib.sh:360-363` called `plan_is_code_path` "the single test for 'is this reviewable code', so required-agents, plan-citations and the fingerprint cannot drift into three different answers". Neither is true now: `plan-citations:55` scans `PLAN_TEXT_GLOBS` + `PLAN_DOC_GLOBS`, and `plan_is_code_path` has exactly one caller repo-wide (`required-agents:46`) — the fingerprint reads `PLAN_CODE_GLOBS` directly at `lib.sh:348`. The invariant that survives is narrower and worth stating precisely: what obliges review must equal what the stamp fingerprint hashes. This is the eighth instance on this branch of a comment describing a version of the code that was later changed, and the first where the stale comment asserted an agreement between two sets that had just been deliberately separated — a reader auditing the split would have taken it as evidence the split was incomplete.

**FIXED 2026-09-06:** both comments rewritten to the surviving invariant (obliges-review == fingerprinted), with no claim about `plan-citations`

### F30 — `PLAN_TEXT_GLOBS`' rationale was rendered at both its definition site and its only consumer

- **File:** `docs/skills/plan/scripts/lib.sh:307-311`, `docs/skills/plan/scripts/plan-citations:47-49`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** `lib.sh:307-311` reads "Where a plan citation can live. Deliberately not PLAN_CODE_GLOBS: that set answers 'what does a review agent read', and reusing it made plan-citations scan a sops blob, a lockfile and .gitignore -- files that cannot hold a citation, and one of which nobody can hand-edit if a base64 run ever happened to spell <date>-<slug>.md." `plan-citations:47-49` restates the same argument in its own words: "PLAN_TEXT_GLOBS + PLAN_DOC_GLOBS, not the code set: 'where can a citation live' is a different question from 'what does a review agent read', and answering both from one array silently rescoped this scan." F24's precedent applies unchanged — the definition site keeps a labelling fragment, the consumer names which arrays it reads, and the argument lives here once.

**FIXED 2026-09-06:** both comments reduced to fragments plus an `#F30` pointer

### F31 — `plan_code_fingerprint`'s `[ -f ]` filter silently excludes symlinks-to-directories, which is a real coverage gap, not just a note

- **File:** `docs/skills/plan/scripts/lib.sh:341-344`
- **Axis:** docs accuracy (docs-updater), with an open behavioral question
- **Finding:** the comment moved here verbatim: "Note the -f test below also drops symlinks-to-directories, so .claude/skills/* obliges review without moving the hash. Covering those means hashing `git ls-files -s` mode+oid rather than content." Both halves verified against the current tree: `.claude/skills/{human-style-writing,plan,security-audit,workflow}` are tracked mode-120000 symlinks to directories, so `[ -f "$f" ]` drops all four from the hash while `plan_is_code_path` still matches them and sets `code=1`. `.claude/agents/*.md` behave differently and are covered — they are symlinks to *files*, so `-f` follows them and their target's content (already in the set via `docs/agents/*`) is hashed; repointing one does move the fingerprint. So the gap is exactly the four skill symlinks: repointing `.claude/skills/plan` at a different tree obliges `/simplify`+`security` but leaves every existing stamp valid. Whether to close it by hashing `git ls-files -s` mode+oid is a design decision with a cost (the mode+oid form also changes the value for every file, so it is the `2026-09-06-make-plan-gate-survive-a-pr-that-changes-the-fingerprint-algorithm-or.md` trap) and is left to the user rather than decided here.

**FIXED 2026-09-06 (docs half only):** comment cut to a one-line statement of the exclusion plus an `#F31` pointer; the behavioral question is recorded above, not resolved

_docs-updater finished 2026-09-06T21:51:54Z -- see Findings above._

### F32 — `plan_code_fingerprint` returns non-zero and prints nothing whenever the sort-last reviewable path is not a regular file; the comment three lines above asserts the opposite

- **File:** `docs/skills/plan/scripts/lib.sh:319-354` (the `while IFS= read -r -d '' f; do [ -f "$f" ] && printf '%s\0' "$f"; done` loop at 346-348, under `set -o pipefail` at 323)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any contributor or agent mid-task, with no adversary required. A `while` loop's exit status in bash is the status of the last command executed in its *body*, and the body here is `[ -f "$f" ] && printf ...`, so if the **last** path `git ls-files -z` emits fails `[ -f ]` the loop exits 1. `set -o pipefail` is on inside the command substitution, so a non-zero component fails the whole pipeline, `out="$(...)" || return 1` fires, and the function returns 1 having printed nothing. Reproduced two ways in this tree: (a) directly, feeding the real pipeline a single absent path — rc=1, no output; (b) through the real function with `PLAN_CODE_GLOBS=(".claude/settings.json" ".claude/skills/*")`, whose sort-last member `.claude/skills/workflow` is a symlink to a directory — rc=1, no output. Today the LC_ALL=C-sort-last member of the real set is `tests/zrepl-replication.nix`, a regular file, so the fingerprint computes (`884af04a691757b0`); the branch is one deleted-but-uncommitted file away from not computing. `git ls-files --cached` keeps a tracked file listed after `rm`, verified in a scratch repo, and `tests/zrepl-replication.nix` is a file this very branch edits.
- **Rule:** new-rule candidate — a guard's failure path has to be exercised, not asserted; compare `docs/hardening.md` rule 11, "a guard that declines to act must be watched by something that measures the outcome, not the attempt".
- **Finding:** the comment at `lib.sh:342-344` states the invariant this loop is supposed to hold: "Absent-but-tracked files are skipped rather than failing the hash: a deletion that is not yet committed is a normal mid-work state, and CI, where the deletion *is* committed, also omits the file." That is true for every position except the last, where the same test that skips the file also becomes the loop's exit status. F31's accepted resolution leans on the same `[ -f ]` filter to drop the four `.claude/skills/*` symlinks; those happen to sort before `docs/`, `flake.lock`, `hosts/`, `modules/` and `tests/`, so the filter's side effect is invisible today and would surface as an unrelated-looking failure the first time a reviewable path sorts last and is absent. The consequence is not a fail-open — `subagent-stamp:45` takes `|| exit 0` and writes no stamp, `plan-gate` then blocks on a missing stamp — it is an **unfixable** gate: re-running the agent re-runs the same failing fingerprint, so the block cannot be cleared from inside the system. `plan-gate:117` names exactly this as the thing to avoid ("An unfixable gate teaches the bypass"), and its cheapest escape, dropping the `Plan:` trailer, also disables the unresolved-findings check that predates the stamp check. This is the same class of bug as F28 (a state that reads stale with no in-system fix), reached by a different route.
- **Fix risk:** the obvious repair — ending the loop body with `:` or `true`, or replacing `&&` with an `if` — must not swallow a *real* failure of `git ls-files` upstream, which `pipefail` currently does catch and which should stay fatal. Whatever form is chosen has to be tested against three cases explicitly: sort-last file absent, sort-last file a symlink-to-directory, and `git ls-files` itself failing (run outside a repo). Note that any change here alters no fingerprint *value*, so it does not trip the `2026-09-06-make-plan-gate-survive-a-pr-that-changes-the-fingerprint-algorithm-or.md` trap.


**FIXED 2026-09-06:** the loop body is now 'if [ -f ]; then printf; fi' rather than '[ -f ] && printf', so the loop no longer inherits a false test as its exit status. Verified against all three reproductions: a symlink-to-directory glob set, a deleted sort-last .nix, and the normal call all return rc=0 with a real fingerprint

### F33 — `plan-gate` does not check `plan_code_fingerprint`'s exit status, so an uncomputable fingerprint is reported as ordinary staleness against no code

- **File:** `docs/skills/workflow/scripts/plan-gate:76-77`, `docs/skills/workflow/scripts/plan-gate:133-134`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** whoever reads a blocked CI run. `current_fp="$(plan_code_fingerprint)"` is the only unguarded call to that function on this branch — `subagent-stamp:45` guards it with `|| exit 0` and nothing else calls it. When the function returns 1 per F32, `current_fp` is empty, and every stamped agent falls through to the `[ "$stamped_fp" != "$current_fp" ]` arm, printing `BLOCKED: ... it reviewed code 884af04a691757b0, but the code is now .` The direction is fail-closed, so this is not a bypass; it is a diagnostic that sends the reader to re-run the agent, which is the one action that cannot help.
- **Rule:** n/a — but it is the mirror of the reasoning already applied at `plan-gate:63-66` (required-agents missing) and `plan-gate:72-75` (required-agents failing), where a dependency that cannot answer is turned into an explicit `BLOCKED: ... cannot tell` rather than a silently-degraded answer. The fingerprint is the third such dependency and is the only one not treated that way.
- **Finding:** the script is careful about exactly this failure mode twice within ten lines and then drops it for the third dependency. A one-line guard makes the state legible and, more importantly, distinguishable from real staleness — which matters because the two have opposite remedies. Worth landing with F32 rather than instead of it: fixing F32 alone leaves the unguarded call as a latent trap for the next failure mode of that function, and fixing F33 alone leaves the gate unfixable, just honestly labelled.
- **Fix risk:** none identified beyond wording — the change only converts an already-blocking path into a differently-worded blocking path. The guard must stay *before* the plan loop, where the call already sits, and exit directly rather than route through `stamp_problem`, which reads `$frozen`/`$agent` from a loop that has not started yet; the frozen-plan case must keep degrading to a NOTE.


**FIXED 2026-09-06:** plan-gate now checks plan_code_fingerprint's status and blocks with a message naming the real cause, matching how it already treats required-agents

### F34 — `git diff --name-only` quotes non-ASCII paths, so a reviewable file with a non-ASCII name obliges no review agent, skips every linter, and skips the targeted build — while the fingerprint hashes it

- **File:** `docs/skills/plan/scripts/lib.sh:387-393` (`plan_worktree_files`), `docs/skills/workflow/scripts/required-agents:30,36,45-49`, `docs/skills/workflow/scripts/verify-ladder:29,158-166`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any contributor or agent who names a reviewable file with a non-ASCII, control, `"` or `\` character — an accented word, a smart quote, an em-dash. `core.quotePath` defaults to true, and `git diff --name-only` / `git ls-files` *without* `-z` emit such paths in C-quoted form: verified in a scratch repo that `café.nix` comes back as the literal 18-character string `"caf\303\251.nix"`, quotes included. `plan_is_code_path` and `plan_is_doc_path` then both return false on it (verified against this tree's real `PLAN_CODE_GLOBS`/`PLAN_DOC_GLOBS`; the same path unquoted returns true), so with that file as the only change `required-agents` sets `code=0 docs=0`, prints nothing, and exits 0. `plan-gate`'s `for agent in $obliged` loop body never runs, no stamp is required, and the gate reports "all cited plans have their findings resolved and their obliged reviews stamped" over a Nix module nobody reviewed. Two further legs in the same file set: `verify-ladder:29`'s `plan_worktree_files '*.nix' | plan_existing_files` drops the quoted path at the `[ -f ]` test, so `nixfmt --check`, `statix` and `deadnix` never see it; and `verify-ladder:163`'s `grep -qE "^(hosts/${host}/|modules/|flake\.nix|flake\.lock)"` cannot match a string whose first character is `"`, so no targeted `nixos-rebuild build` is triggered for it either.
- **Rule:** violates the mechanical-trigger principle this branch's D7 establishes — "a trigger an agent has to *judge* is a trigger that gets skipped, so the obligation is computed from the diff instead". A trigger that silently declines to fire on a legal filename is worse than a judged one, because nothing reports the skip.
- **Finding:** the round that produced this state added `-z`/`mapfile -d ''` to `plan-citations:55` for precisely this reason, and `plan_code_fingerprint:345` has used `-z` from the start with the comment "a path may contain a newline" — so the repo already knows the rule and applies it in two of four places. `plan_worktree_files` is the consolidation of three previously-inline unions and is documented as "one definition, because three call sites each spelling this union is how the untracked leg went missing from one of them"; consolidating them without `-z` makes one shared bug out of three identical ones, which is an improvement in maintainability and no change in exposure. The asymmetry is what makes it worth fixing rather than accepting: the fingerprint *does* hash the file (it uses `-z`), so the two halves of the system disagree about whether that file exists — the exact drift `lib.sh:356-361`'s comment says `plan_is_code_path` exists to prevent. Reachability is not adversarial in practice (nobody is smuggling a backdoor through an accented filename to dodge a review that is itself advisory), but it is a mechanical gate that silently answers "nothing obliged" over a real code change, and the repo's own threat model for this machinery is forgetting, not lying — forgetting is exactly what an invisible skip causes.
- **Fix risk:** switching `plan_worktree_files` to `-z` throughout means its callers must consume NUL-separated output (`mapfile -d ''` or `while read -d ''`), and three call sites currently pipe it through `sed`/`sort`/`while read -r` line-wise; `verify-ladder:64`'s `xargs -r nixfmt --check` would need `xargs -0`. A cheaper partial fix is `git -c core.quotePath=false`, which handles non-ASCII but still mangles a path containing a literal newline — acceptable only if stated as such at the call site rather than left implicit. Either way, test with a file whose name contains a non-ASCII character and confirm `required-agents` names `/simplify`, `security` and `docs-updater` for it, that `verify-ladder` lints it, and that a `modules/`-resident one triggers the targeted build.


**FIXED 2026-09-06:** plan_worktree_files and required-agents' range diff now pass -c core.quotePath=false, so a non-ASCII path arrives unquoted and matches the globs. Verified: modules/cafe-scratch.nix with an accented e was reported as "modules/café-scratch.nix" and failed plan_is_code_path; with quotePath=false it matches

### F35 — gitignoring `.claude/settings.local.json` is redundant against the glob narrowing that lands with it, and its only net effect is to hide a local permission/hook-override file from `git status`

- **File:** `.gitignore:10-13`, `docs/skills/plan/scripts/lib.sh:287-293`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** the user, or an agent that induces a "don't ask again" grant. Claude Code's settings precedence puts `.claude/settings.local.json` above `.claude/settings.json`, and both carry `permissions` and `hooks` keys — so the local file can widen tool permissions or override the `SubagentStop` wiring that `reference.md` calls out as the reason `.claude/settings.json` is reviewable code at all. With this `.gitignore` entry in place the file never appears in `git status`, never appears in `git ls-files --others --exclude-standard`, and is read by no gate in this repo.
- **Rule:** n/a — but it cuts against `docs/hardening.md` rule 6's shape ("put privilege on the unit, not the user": a grant that outlives the thing that needed it is the failure), applied to tool permissions rather than Unix groups.
- **Finding:** the two halves of the F28 fix are not equally load-bearing, and the resolution text treats them as one remedy. Verified against this tree: with the narrowed globs, `plan_path_matches ".claude/settings.local.json" "${PLAN_CODE_GLOBS[@]}"` is false and the same test against `PLAN_TEXT_GLOBS`+`PLAN_DOC_GLOBS` is false — so the file cannot enter the fingerprint or the citation scan **regardless of `.gitignore`**, and the same is true of `.claude/.credentials.json` and `.claude/statsig/*`, neither of which is gitignored. The narrowing alone therefore fully closes the CI-staleness bug F28 describes; the `.gitignore` entry adds nothing to it and costs the one signal that would otherwise show a permission change happened. This is not a gate bypass: locally disabling the stamp hook makes `plan-gate` block server-side on a missing stamp, exactly as F25/G11 reason for `settings.json`. The loss is visibility, not enforcement. If the entry is kept — a reasonable choice, since `git status` noise every session is its own failure mode — the reason to keep it is "this is per-machine local state", not "otherwise it reaches the fingerprint", and F28's resolution line currently records the latter.
- **Fix risk:** removing the `.gitignore` entry makes `.claude/settings.local.json` show as untracked, which invites someone to commit it — and a committed local-grants file is worse than a hidden one. If it is removed, the `git status` noise needs somewhere to go; `.git/info/exclude` is the closest correct answer, being per-clone and therefore invisible to CI by construction. Nothing here changes any fingerprint value, so no stamp is affected either way.


**FIXED 2026-09-06:** the .gitignore entry is kept but its comment no longer claims to be what excludes the file from the fingerprint -- the glob narrowing does that. Its actual job is stopping an 'add -A' from committing local permission grants

### F36 — the `PLAN_TEXT_GLOBS` split dropped `.gitignore`, which is the one file outside the new set that carries a citation — added by this same round

- **File:** `docs/skills/plan/scripts/lib.sh:306-309`, `.gitignore:12`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** anyone who renames this plan file or renumbers a finding. `PLAN_TEXT_GLOBS=("*.nix" "*/scripts/*" "scripts/*" ".githooks/*" "docs/agents/*")` plus `PLAN_DOC_GLOBS=("*.md")` produces a 258-path scan set in this tree that contains no `.gitignore`, no `.github/workflows/*`, no `.sops.yaml`, no `secrets/*` and no `flake.lock` — verified by evaluating the same `git ls-files` invocation `plan-citations:55` uses. A repo-wide grep for the citation pattern across exactly those excluded paths returns one hit: `.gitignore:12`, `# plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F28`, written by the same pass that performed the split. `plan-citations` reports 227 resolving citations and does not count or check that one.
- **Rule:** n/a
- **Finding:** the split's stated goal is met — scanning `secrets/secrets.yaml`, `flake.lock` and `.gitignore` was the concern, and the first two are genuinely out (confirmed: no path under `secrets/` reaches the scan set, so the encrypted blob is never opened by this tooling). The overshoot is `.gitignore`: it was excluded on the reasoning that it "cannot hold a citation" (F30's text), and within the same working tree it now holds one. `.github/workflows/*` is in the same position prospectively — it is a comment-carrying file in a repo whose convention is `# plan: <file>#<id>` comments, and `plan-gate.yml`'s header is written in exactly that register. The right shape is probably "any file this repo writes prose comments into", which is the code set minus `secrets/*`, `.sops.yaml` and `flake.lock`, rather than an enumeration that excludes four things for one reason and one thing for another. Left as INFO because the failure mode is a stale pointer in a comment, not a gate that opens; but it is the second time on this branch that a set was narrowed past what its own rationale justified.
- **Fix risk:** adding `*.gitignore` and `.github/workflows/*` back to `PLAN_TEXT_GLOBS` costs two more files in a scan that already covers 258 in one awk pass; the only real risk is re-admitting a binary or encrypted file by accident, so any re-widening should be checked by confirming `secrets/` and `flake.lock` still return zero paths from the scan-set query above.

**Checked and clean (security, 2026-09-06, closing pass).** Fourth review of this branch, over `git diff origin/master...HEAD` plus the full uncommitted working tree, reading current file contents rather than diff hunks. **F28 is genuinely closed from both directions, and the glob half is the one doing the work**: `git check-ignore -v` confirms `.gitignore:13` excludes `.claude/settings.local.json` from `--exclude-standard`, and independently `plan_path_matches` returns false for it against `PLAN_CODE_GLOBS`, `PLAN_TEXT_GLOBS` and `PLAN_DOC_GLOBS`, so neither the fingerprint nor the citation scan can reach it even with the ignore rule removed (recorded as F35, which is about the visibility cost of the redundant half, not about the fix being incomplete). Swept the other globbed directories for the same class of harness- or tool-written local file and found none: `.claude/.active-plan` and `.claude/.trivial-ack` are both gitignored *and* outside the narrowed globs, `.claude/.credentials.json` and `.claude/statsig/*` match no glob, `.claude/worktrees/` is gitignored, `scripts/claude-links-check --fix` writes only the `.claude/{agents,skills}` symlinks that `.githooks/pre-commit:45-51` then requires to be committed, and no plan or workflow script writes into `scripts/`, `*/scripts/`, `.githooks/`, `.github/workflows/` or `secrets/`. The remaining F28-shaped residue is benign and already documented: an untracked-but-intended file in a globbed directory (a new `.claude/agents/*.md`, a scratch `.nix`) skews the local hash until committed, which `lib.sh:329-330` states outright. `*.gitignore` verified to match the root `.gitignore` under git's pathspec matching (`*` crosses `/` for a non-`:(glob)` pathspec) and under bash `[[ ]]`, so nested ignore files would be covered identically.

`plan_code_fingerprint` is deterministic and locale-stable — measured `884af04a691757b0` identically under the ambient locale, `LC_ALL=C`, `LC_ALL=en_US.UTF-8`, and `LANG=C.UTF-8 LC_COLLATE=en_GB.UTF-8` over 112 paths — and dropping the post-`sha256sum` `LC_ALL=C sort` is sound: `LC_ALL=C sort -zu` already fixes path order, sequential `xargs` batches preserve it, and GNU `sha256sum`'s backslash-escaping of odd filenames changes a line's content but not its position. It cannot silently return the sha256-of-nothing (`pipefail` plus `|| return 1`), and an empty match set would return `e3b0c44298fc1c14` fail-closed rather than empty. It *can* fail to compute at all — see F32, the one thing this pass found that the round's own comments deny. `secrets/` is no longer scanned by `plan-citations`, confirmed directly: the `PLAN_TEXT_GLOBS`+`PLAN_DOC_GLOBS` scan set contains zero paths under `secrets/`, zero `.sops.yaml`, zero `flake.lock`, so the stated concern about awk-ing an encrypted blob is closed. `secrets/*` and `.sops.yaml` remaining in `PLAN_CODE_GLOBS` exposes nothing — `sha256sum` over ciphertext, truncated to 16 hex, is not a disclosure — and no secret was decrypted or read at any point in this review; `.sops.yaml` was not opened.

The helper consolidation weakens no caller. `plan_active_plan` reproduces `subagent-stamp`'s previous three-part test byte-for-byte (`-f` marker, non-empty content, `-f` target) and is the strictest of the three it replaced, so the `-r`-succeeds-on-a-directory divergence closed in the safe direction; its refusal path still short-circuits `subagent-stamp` before any write. `plan_is_frozen` replacing `subagent-stamp`'s raw `grep -q '^frozen: true'` narrows the test to frontmatter, which is stricter in the right way — it now agrees exactly with the `plan-gate` reading whose NOTE-vs-BLOCKED reasoning assumes this script refuses frozen plans — and the only behavior lost is refusing on a body line that happens to read `frozen: true`. `plan_existing_files` matches the filter it replaced in `plan-citations` and is correctly *not* applied to `verify-ladder`'s host-detection set. `plan_heading_re` emits a string identical to the four inlined copies; every id reaching it is a literal or regex-free `[DGF][0-9]+` text, so no injection. `plan-citations`' `mapfile -d ''` handles the empty-array case safely under `set -u` (bash 5), `-t` strips the NUL delimiter, and the new fail-closed `*)` dispatch arm reaches `plan_die` from a `while` fed by a file redirect rather than a pipe, so its `exit 1` is not lost in a subshell. Live runs: `plan-citations` OK (227 citations, 2 ignored regions), `required-agents` emits `PLAN_AGENT_ORDER` in both modes, `plan-gate origin/master HEAD` exits 0 with only the expected F12/F13 legacy NOTEs and the still-open NOTE.

Nothing in this range touches a NixOS module, systemd unit, firewall rule, user, group, capability, container image or `sops.secrets` reference, so `docs/hardening.md`'s ten standing rules have no surface here beyond the secrets rules considered above. F12, F13, F14, F25, F31, the CI-merge-ref issue, the allowlist-vs-denylist question and the unguarded `hook-lib.sh` sourcing were deliberately not re-raised; none of this round's changes alters their severity.

_security finished 2026-09-06T22:06:28Z -- see Findings above._

**FIXED 2026-09-06:** *.gitignore and .github/workflows/* added to PLAN_TEXT_GLOBS -- both can and now do carry citations. Verified secrets/, .sops.yaml and flake.lock remain outside the scan set

### F37 — `plan_worktree_files` reported success with empty output when a git call failed, re-opening F3's fail-open for every consumer

- **File:** `docs/skills/plan/scripts/lib.sh` (`plan_worktree_files`), `docs/skills/workflow/scripts/required-agents`, `docs/skills/workflow/scripts/verify-ladder`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any transient git failure in working-tree mode -- an unborn HEAD, a locked index, a corrupt object. The helper joined its three legs in a `{ ...; ...; ...; }` group, whose exit status is only the *last* command's, so a failing `diff` leg produced no output and returned 0. Verified directly: `{ false; true; }` exits 0, and the helper under a broken `GIT_DIR` returned rc=0 with empty output.
- **Rule:** n/a -- internal control correctness.
- **Finding:** every consumer inherited it, and each turned it into a pass. `required-agents` printed an empty obligation set and exited 0, so `plan-gate` would have found no agents obliged and waved the range through -- exactly what F3 closed for range mode, whose own comment says "That is the fail-open this whole check exists to close, so it must not reappear here". It reappeared in the sibling branch, introduced by the helper extracted to stop three call sites spelling the union differently. `verify-ladder` was affected twice over: an empty `changed_nix` prints "(no changed .nix files)" and skips nixfmt/statix/deadnix, and an empty `changed_all` skips the targeted build -- both reporting success. Found by `/simplify` (reuse/simplification) on the closing pass.
- **Fix risk:** making the helper fail-closed means every caller must check it, or a git failure becomes an unhandled empty set one level up instead. All three call sites were converted together.

**FIXED 2026-09-06:** each leg's status is checked separately and the helper returns 1 on any failure; required-agents plan_die's and both verify-ladder sites block. Verified: the broken-GIT_DIR case now returns rc=1

**FIXED 2026-09-06:** also made plan_code_fingerprint self-locating -- pathspecs are cwd-relative, so from a subdirectory it returned a different hash with rc=0, and a wrong-but-successful answer is worse than a failure. Verified identical from root and from docs/skills, rc=1 outside a repo

### F38 — the `malformed` half of the fingerprint-less-stamp fix landed this round, and the todo plan filed for it still describes it as unbuilt

- **File:** `docs/plans/todo/2026-09-06-enable-fingerprint-less-stamp-blocking-once-the-fingerprint-era-has.md:11-14,44-48,89`, `docs/skills/workflow/scripts/plan-gate:135-139`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the todo plan was written against a `plan-gate` that downgraded both `legacy` and `malformed` to a non-blocking NOTE — "treats a stamp with no `(code <fp>)` field as `legacy` and a stamp with an empty one as `malformed`, and downgrades **both** to a non-blocking NOTE regardless of whether the cited plan is frozen" — and proposes, as its change and its third Progress item, routing both through `stamp_problem`. The same round that filed it already routed `malformed` through `stamp_problem`, so an empty-fingerprint stamp now BLOCKS on a non-frozen plan. Half the plan's stated work is done and its premise sentence is false. The cost is not cosmetic: this plan's whole reason for existing is an entry condition that must hold before the change is safe, and a reader picking it up would either re-do the `malformed` half or, worse, conclude from the premise that a hand-written fingerprint-less stamp still passes the gate — which is the loophole the plan exists to close and which is now closed for the `malformed` form. This is the branch's recurring defect (text describing a version the same pass changed) reaching a plan file rather than a comment; the plan file is where an agent goes for the *state* of a deferred fix, so a stale premise there is more durable than a stale comment. Fixed in `## State`, the only section append-only rules let a later pass rewrite — "Original plan" and "The change" are left as written, per `plan/SKILL.md`'s append-only rule, with `## State` now carrying which arm landed and which remains.

**FIXED 2026-09-06:** the todo plan's State records that `malformed` already blocks and that only the `legacy` arm is still gated on the entry condition

### F39 — two comment rewrites this round left their pre-rewrite text spliced into the new text mid-sentence

- **File:** `docs/skills/plan/scripts/lib.sh:308-309` (`PLAN_NONTEXT_GLOBS`), `.github/workflows/plan-gate.yml:28-30`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** both are editing artifacts, not wrong claims, but both render as broken prose in the file a reader actually opens. `lib.sh` carried the orphaned head of the pre-derivation comment immediately above its replacement — "`# where a plan citation can live -- a different question from what a`" followed by "`# Where a plan citation can live: the code set minus the members that`" — a dangling half-sentence ending in "what a", with the sentence it belonged to deleted. `plan-gate.yml` had the F25 citation inserted into the middle of a sentence, leaving the line "`# plan: <file>#F25 This still reads the PR's own`" — the citation and the resumed prose on one line, which breaks both the citation's one-line form and the paragraph. The `lib.sh` one is the twelfth instance on this branch of comment text surviving the change it described; it is worth separating that the *mechanism* here is a partial replacement rather than a missed update, because the two need different guards — a missed update needs a re-read of the code, a partial replacement is visible in the diff itself.

**FIXED 2026-09-06:** the orphaned `lib.sh` fragment is deleted; the F25 citation moved to its own line at the end of the `plan-gate.yml` pin comment

### F40 — `reference.md`'s enumeration of what `PLAN_CODE_GLOBS` covers lost skill scripts and git hooks when the paragraph naming them was deleted

- **File:** `docs/skills/workflow/reference.md:53-62`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the trigger-table rewrite replaced the old "'Skill script or git hook' means `docs/skills/*/scripts/*` and `.githooks/*`" paragraph with a prose enumeration of the widened set — `.claude/settings.json`, the `.claude/` entries, the agent definitions, `.sops.yaml`, `secrets/`, the CI workflows, `flake.lock`, `.gitignore`. The enumeration lists everything the widening *added* and silently drops the two members that were there first and that the deleted paragraph existed to justify: `*/scripts/*`/`scripts/*` and `.githooks/*`. Since the sentence reads "deliberately wider than Nix: <list>", the list is the reader's answer to "what is in besides `.nix`", and the answer omitted this repo's entire enforcement machinery. A reader asking why a `verify-ladder` edit obliged `security` would find nothing in the list accounting for it. F21 fixed the reverse failure in the same file ninety lines down — a stale enumeration that named only the old three globs — so both renderings of this one fact have now been wrong in opposite directions within two passes, which is the case D1 makes for the array being the single home and the doc pointing at it. Left as an enumeration rather than cut, because the table's "any code change (see below)" needs *some* concrete answer inline; the `lib.sh` authority pointer immediately above it is what a reader is meant to fall back to.

**FIXED 2026-09-06:** the enumeration names `*/scripts/*`, `scripts/*` and `.githooks/*` alongside the widened members

_docs-updater finished 2026-09-06T22:30:26Z -- see Findings above._

### F41 — the pre-commit secret scan still silently skips a staged file whenever the *working-tree* path is not a regular file, so `git add key.pem && rm key.pem && git commit` commits a private key with the hook reporting success

- **File:** `.githooks/pre-commit:53-57` (the `core.quotePath=false` comment and `staged_files`), `.githooks/pre-commit:62-63` (`while IFS= read -r file; do [[ -f "$file" ]] || continue`), `.githooks/pre-commit:66-92` (the four scans that never run)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** the committer -- any human or agent working in this checkout, no second party needed. The loop's only gate is `[[ -f "$file" ]]` against the *working tree*, while every scan below it reads the *index* (`git show ":$file"`). The two disagree in two reachable ways, both verified in a scratch repo against this exact hook file:
  - **staged-then-removed:** stage a file holding an OpenSSH private-key header line, delete it from the working tree, run the hook -> **rc=0, no output**. Restore the working-tree copy and the same index content -> `BLOCKED: leak.pem contains a private key block.`, rc=1. Same blob either way; the only variable is whether the worktree file exists. A rename after staging, or replacing the path with a directory, does the same thing.
  - **names git always C-quotes:** `core.quotePath=false` demotes only bytes >= 0x80. `"`, `\` and control characters are escaped *regardless* of the setting -- verified: with `quotePath=false`, `naïve.txt` comes back bare but `quo"te.txt` and `tab<TAB>name.txt` still come back as `"quo\"te.txt"` and `"tab\tname.txt"`. Staging a private key as `lea"k2.pem` gives **rc=0, no output** from the current hook.
- **Rule:** new-rule candidate, adjacent to `docs/hardening.md` "Recipient rotation is not value rotation" -- this repo is public, so anything the backstop misses is permanently downloadable, and `docs/procedures/secrets.md` names this hook as the last-resort catch for exactly private-key blocks, age secret keys and live API tokens.
- **Finding:** the round's own comment at `pre-commit:53-56` states the failure class correctly -- "git otherwise C-quotes a non-ASCII path, the quoted name fails the `[[ -f ]]` test below, and the secret scan silently skips that file" -- and then fixes one input to it rather than the test. The `[[ -f ]]` guard exists to avoid feeding a deleted path to `git show`, but nothing below actually needs the worktree: `git show ":$file"` reads the index, and `basename` is pure string work. The scan is therefore gated on a condition none of its consumers require, and it fails **open** -- no diagnostic, exit 0, hook satisfied. That is the same shape as F3/F5/F33/F37 on this branch (a failed or skipped step reported as a pass), reappearing in the one place where the cost is a permanent public disclosure rather than an unreviewed diff. The hook is a backstop and not the primary control -- the primary control is the sops discipline in `docs/procedures/secrets.md`, which is unaffected -- but a backstop that reports success while doing nothing is worse than an absent one, because the green exit is what the committer reads.
- **Fix risk:** dropping the `[[ -f ]]` guard entirely means the loop runs `git show ":$file"` for staged deletions too; with `--diff-filter=ACM` a pure deletion is already excluded, but a path staged as a type change would newly reach `git show`, which succeeds for a blob and fails loudly for a gitlink/submodule -- so the replacement test wants to be "does this path have a blob in the index" (`git cat-file -e ":$file"`), not "does it exist on disk". The C-quoted-name half needs `-z` on the `diff --cached` and a NUL-delimited read, which also changes the `<<<"$staged_files"` feed. Test both directions: the positive control (key present, still BLOCKED) and each of the two bypasses above, plus a normal commit touching only ordinary paths, to confirm no new false block.


**FIXED 2026-09-06:** the working-tree existence test is gone from the secret-scan loop; every scan reads the index and --diff-filter=ACM already excludes deletions. Verified in a scratch repo: 'git add leak.pem && rm leak.pem' now blocks (rc=1) where it previously passed silently (rc=0) with the key still staged

### F42 — `-c core.quotePath=false` is a partial fix presented as complete at all five new call sites, and F34's own stated acceptance condition ("acceptable only if stated as such at the call site") is met at none of them

- **File:** `docs/skills/plan/scripts/lib.sh:423-427,436-438` (`plan_worktree_files`), `docs/skills/workflow/scripts/required-agents:30-32`, `.githooks/pre-commit:53-56`, `.githooks/pre-push:23-26`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any contributor or agent who names a reviewable file with `"`, `\`, a tab or a newline -- a smart-quote paste, a shell-mangled name, a copied filename with a stray backslash. Verified against git's documented behavior and in a scratch repo: `core.quotePath` governs only bytes >= 0x80; `"`, `\` and control characters are C-quoted no matter what it is set to. So the F34 chain reproduces unchanged for those names -- `plan_is_code_path` and `plan_is_doc_path` both return false on a leading-`"` string, `required-agents` prints nothing and exits 0, `plan-gate`'s obligation loop never runs, `verify-ladder:168`'s `grep -qE "^(hosts/${host}/|modules/|...)"` cannot match, and `.githooks/pre-push:40`'s identical anchor cannot match, so no targeted build fires either.
- **Rule:** n/a -- but it is the F34 finding's own fix-risk clause, quoted verbatim from this file: "A cheaper partial fix is `git -c core.quotePath=false`, which handles non-ASCII but still mangles a path containing a literal newline -- **acceptable only if stated as such at the call site rather than left implicit**."
- **Finding:** the partial fix was taken, which is the right trade (NUL-delimiting five call sites and their `sed`/`sort`/`grep`/`xargs` consumers is a large change for a rare name class). What did not happen is the condition attached to it. Read in order, the five comments say "git otherwise C-quotes a non-ASCII path ... so a `.nix` file with an accented name obliged no review at all" (`lib.sh`), "for the same reason as `plan_worktree_files`" (`required-agents`), "git otherwise C-quotes a non-ASCII path, the quoted name fails the `[[ -f ]]` test below, and the secret scan silently skips that file" (`pre-commit`), and "so a non-ASCII path is not C-quoted, which would defeat the `^(hosts/...)` anchor below and skip the build" (`pre-push`). Every one of them describes the residue as closed. A reader auditing "can a filename still dodge this gate" gets "no" from all five, and the answer is "yes, for three other character classes". This is the branch's recurring defect -- text describing a stronger version of the code than exists -- landing on the exact class of claim the next reviewer will trust instead of re-deriving. The `pre-commit` instance is the sharp one and is carried separately as F41 because there the residue is a secret-scan bypass, not a skipped review.
- **Fix risk:** none from documenting it -- a clause per call site, or one clause in `plan_worktree_files` that the other four point at. Actually closing it means `-z` end to end at all five sites and NUL-aware consumers (`xargs -0`, `read -d ''`, no `sed '/^$/d'`, no `grep -qE '^...'` over a newline-joined blob); if that is attempted, test with a file named with an embedded newline and confirm `required-agents`, `verify-ladder`'s lint set, the targeted build and the pre-commit scan all see it.


**FIXED 2026-09-06:** all four call sites now state that core.quotePath=false demotes bytes >= 0x80 only, and that quotes, tabs and newlines remain quoted -- the detail written once at plan_worktree_files, cited from the others. Verified: naive.txt with a diaeresis comes back bare, quo"te.txt and tab-name.txt do not

### F43 — the `PLAN_TEXT_GLOBS` derivation inverts the failure direction: a `PLAN_NONTEXT_GLOBS` entry that is not string-identical to a `PLAN_CODE_GLOBS` entry silently no-ops, and the thing it fails to exclude is `secrets/*`

- **File:** `docs/skills/plan/scripts/lib.sh:308-334`, `docs/skills/plan/scripts/plan-citations:55`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** a future editor of `lib.sh` -- human or agent -- who renames or re-spells a `PLAN_CODE_GLOBS` member without touching `PLAN_NONTEXT_GLOBS`. `secrets/*` -> `secrets/**`, or splitting it into `secrets/*.yaml`, or a typo in either array, all leave the inner loop's `[ "$_g" = "$_n" ]` false, the entry stays in `PLAN_TEXT_GLOBS`, and `plan-citations:55`'s `git ls-files` re-admits `secrets/secrets.yaml` to the awk scan. Nothing errors, nothing warns, and `plan-citations` still prints `OK`.
- **Rule:** n/a
- **Finding:** the derivation is correct as it stands -- verified in this tree: 13 code globs, 6 non-text globs, 7 text globs, every non-text entry matching a code entry exactly, and the resulting 263-path scan set containing zero paths under `secrets/`, zero `.sops.yaml` and zero `flake.lock`. The `set -u` question is also clean: both source arrays are non-empty, bash 5 tolerates `"${empty[@]}"` anyway, `_g`/`_n`/`_skip` are assigned before use and unset after, and the loop's trailing `[ "$_skip" = 0 ] && ...` cannot abort a `set -e` caller (verified: bash's `&&`-list exemption covers it, and `unset` follows it as the file's last statement, so `source` returns 0). What changed is the *direction* of the remaining hand-maintenance. The old hand-kept `PLAN_TEXT_GLOBS` failed by omitting a text glob -- F30 and F36, whose worst outcome was a citation going unchecked. The new `PLAN_NONTEXT_GLOBS` fails by omitting an *exclusion* -- whose outcome is opening the encrypted blob, which is the precise thing the split was introduced to stop. The comment ("Derived rather than restated, because a hand-kept second list is a copy -- this one silently missed two entries within a day of being written") reads as though the hand-kept list is gone; it is not, it is a hand-kept exclusion list with a stricter coupling than the one it replaced, because it must match the other array *character for character* rather than merely cover the same paths. Left INFO because the impact when it fires is bounded -- awk reads the ciphertext but only ever emits regex-matched `YYYY-MM-DD-slug.md` tokens, so no ciphertext or plaintext reaches stdout, and no secret is disclosed -- but the guarantee "this tooling never opens `secrets/`" would be silently gone, and that guarantee is what the last two passes signed off on.
- **Fix risk:** the cheap guard is an assertion at source time that every `PLAN_NONTEXT_GLOBS` entry matched something, which turns a silent no-op into a loud one; the risk is that `lib.sh` is sourced by hooks and a `plan_die` at source time takes a hook down, so it wants to be a `plan_note` or a `plan-lint`-side check rather than a fatal. The other shape is to stop deriving by glob string and derive by resolved path set, which is more robust and costs a `git ls-files` at source time in every script that sources this file -- measurably worse for a hook that runs before every commit.


**FIXED 2026-09-06:** lib.sh now warns at source time when a PLAN_NONTEXT_GLOBS entry matches no PLAN_CODE_GLOBS entry. Verified by renaming only the exclusion-list copy of secrets/*: the warning fires, and the test also demonstrates the consequence it guards -- secrets/* re-entering the citation scan set

### F44 — `subagent-stamp`'s declined-stamp `plan_note` writes to stderr and exits 0, which is the one hook channel Claude Code does not surface; the comment beside it asserts the opposite

- **File:** `docs/skills/workflow/scripts/subagent-stamp:46-51`, `docs/skills/workflow/scripts/hook-lib.sh:85-90` (`hook_deny`, the repo's working example)
- **Severity:** INFO
- **Confidence:** PLAUSIBLE
- **Axis:** needed-used
- **Reachability:** the main agent running the review loop. If `plan_code_fingerprint` fails, no stamp is written; `plan-gate` then blocks on a missing stamp; the agent re-runs the reviewer; it declines again for the same reason. The comment at :47-48 says the `plan_note` exists so that loop is not "with the reason visible nowhere" -- but `plan_note` (`lib.sh:32`) prints to **stderr**, and the script then `exit 0`s. Claude Code surfaces hook stderr on exit 2 (back to the model) and on other non-zero exits (to the user); on exit 0 it does not. The repo's own counter-example is one file over: `plan-touch-guard` needs its message seen, and gets it by emitting structured JSON on **stdout** via `hook_deny`, not by writing stderr.
- **Rule:** n/a
- **Finding:** marked PLAUSIBLE, not CONFIRMED, because the claim rests on Claude Code's hook output semantics, which I cannot verify against a pinned source the way an option default can be checked -- and this repo documents those semantics nowhere (`reference.md`'s "Why a hook at all" covers *whether* the hook fires, never what its output does). Two things are certain regardless: the arm is close to unreachable in practice -- `subagent-stamp:27-28` has already proved `$root` is a git top level, so `plan_code_fingerprint`'s own `git rev-parse` cannot be what fails, leaving only a transient `ls-files`/`xargs`/`sha256sum` error -- and the decision it implements (write no stamp rather than a fingerprint-less one) is right, since `plan-gate` now BLOCKs on `malformed`. So the cost is not a gate hole, it is that the *one* thing the round added here may be a no-op with a comment claiming it is not. Confirming it needs one run of a `SubagentStop` hook that writes stderr and exits 0, checking whether the text appears in the transcript.
- **Fix risk:** switching to `hook_deny` is wrong -- this is not a denial and the agent did finish. The correct channel is stdout (shown in transcript mode) or a non-zero exit, and a non-zero exit from `SubagentStop` has its own semantics worth checking before adopting. If the note is left on stderr, the comment should say it is best-effort.

**Checked and clean (security, 2026-09-06, final pass).** Fifth review of this branch, over `git diff origin/master...HEAD` plus the full uncommitted working tree, reading current file contents rather than diff hunks.

**`plan_code_fingerprint`'s self-location is correct and closes the cwd-dependence outright.** Measured `3c27f906890da9d7` identically from the repo root, from `docs/skills/`, and from a path reached through a symlink to the worktree, where `git rev-parse --show-toplevel` resolves to the real worktree and the pathspecs, the `[ -f ]` filter and `sha256sum`'s printed names are all top-level-relative -- so neither a symlinked nor a bind-mounted route can change the value. Locale-stable across `C`, `en_US.UTF-8`, `C.UTF-8` and `en_GB.UTF-8`, identical every time. It returns non-zero, not a wrong hash, everywhere it cannot compute: outside a repo (`rc=1`), inside a bare repo (`git rev-parse --show-toplevel` itself exits 128, "this operation must be run in a work tree"), and under a broken `GIT_DIR` (`rc=1`). The `cd "$r"` cannot be reached with an empty `$r` because the `|| return 1` fires first, and bash's `cd ""` returns 1 anyway ("null directory"), so even that path is fail-closed. It cannot return rc=0-with-empty: the F32 `if`/`fi` rewrite is in place at `lib.sh:381-383` and `lib.sh:262-266`, the subshell sets its own `pipefail` (which matters -- `subagent-stamp` runs under bare `set -u`), and an empty match set yields `e3b0c44298fc1c14` rather than nothing. Swept every remaining `while`/`for` loop in the changed scripts for the `[ -f ] && ...`-as-last-body-command shape and found none in a position that matters; `required-agents:50-54` and `plan_existing_files` both carry the `if` form with the reason cited.

**`plan_worktree_files`' fail-closed conversion genuinely propagates, at all three call sites.** Verified under a broken `GIT_DIR`: the helper returns rc=1, and `verify-ladder:28`'s `plan_worktree_files '*.nix' | plan_existing_files` also returns rc=1 -- which depends on `verify-ladder:14`'s `set -uo pipefail`, since a pipeline otherwise reports only its last stage; that is present, so the guard is real and not decorative. `required-agents:38` and `verify-ladder:160` are direct assignments and need no such help. There is no fourth caller: `plan_worktree_files` appears exactly three times outside its own definition across `docs/`, `.githooks/`, `.github/` and `scripts/`. `plan-gate`'s two new status checks are correct too -- `required-agents` and `plan_code_fingerprint` are both two-step, so no `exit` is stranded in a command substitution's subshell.

**The `PLAN_TEXT_GLOBS` derivation is correct today and keeps the encrypted material out.** 13 code globs minus 6 non-text globs gives exactly 7; every non-text entry matches a code entry byte-for-byte, so no exclusion is silently no-oping right now; the resulting scan set is 263 paths containing zero under `secrets/`, zero `.sops.yaml` and zero `flake.lock`. No surviving text glob reaches those paths by another route -- `*.nix`, `*/scripts/*` and `*.gitignore` all miss everything under `secrets/`. The source-time loop is safe under `set -u` and cannot abort a `set -e` caller. Its one structural weakness is the string-identity coupling, recorded as F43. Live runs: `plan-citations` OK (243 citations resolve, 2 ignored regions); `plan-lint` on the active plan OK; `required-agents` prints the full four-agent set in working-tree mode and three in range mode, both in `PLAN_AGENT_ORDER`; `plan-gate origin/master HEAD` exits 0 with only the two expected F12 legacy NOTEs and the still-open NOTE.

**Nothing in this branch touches a NixOS module, host, systemd unit, firewall rule, user, group, capability, container or `sops.secrets` reference** -- `git diff origin/master...HEAD --name-only` returns nothing under `hosts/`, `modules/`, `profiles/`, `services/`, `secrets/` or `.sops.yaml`, so `docs/hardening.md`'s eleven standing rules have no surface here beyond the secrets rules considered above and in F41. The one `.nix` change in range, `tests/zrepl-replication.nix`, moves `"${pkgs.path}/nixos/tests/ssh-keys.nix"` to `pkgs.path + "/nixos/tests/ssh-keys.nix"`, which is the safer idiom and imports nixpkgs' own snake-oil test keys -- no key material enters the repo. (Its comment's stated mechanism, "coercing a path to a string copies the whole nixpkgs source into the store", is the general Nix pitfall but is inert in a flake, where `pkgs.path` is already the locked input's store path; `nix eval` was unavailable in this sandbox, so that is an unverified nuance on an already-committed change, not a finding.) The `.github/workflows/plan-gate.yml` step's unguarded `git show origin/$BASE_REF:.../lib.sh` was checked and is fail-closed: GitHub's default `run:` shell is `bash -e`, so a missing base-branch `lib.sh` reds the job rather than pinning an empty file. `.claude/worktrees/` is gitignored, so a linked worktree's copies of every script and `.nix` file cannot leak into the main checkout's fingerprint through `*/scripts/*`. `plan-citations`' citation regex is `[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9][a-z0-9-]*\.md(#[DGF][0-9]+)?`, so the new `dup`/`plan_path` associative-array subscripts can never carry a shell metacharacter. No secret was decrypted or read at any point in this review, and `.sops.yaml` and `secrets/*` were not opened; both remain in `PLAN_CODE_GLOBS`, where a truncated sha256 over ciphertext discloses nothing.

F12, F13, F14, F25, F31, the CI merge-ref question, allowlist-vs-denylist, the unguarded `hook-lib.sh` sourcing, the plan-citations anchor cost and the set-quoting-once-globally proposal were deliberately not re-raised. This round changes the severity of none of them -- though F43 sharpens the case for the allowlist-inversion plan, since the inversion would delete `PLAN_NONTEXT_GLOBS`' string-identity coupling rather than document it, and F42 strengthens the set-quoting-once proposal by showing that one setting applied in five places is still not the same as one setting.

_security finished 2026-09-06T23:47:12Z -- see Findings above._

_security finished 2026-09-06T22:46:21Z -- see Findings above._

**FIXED 2026-09-06:** the comment no longer claims the note is user-visible; it records that stderr on a SubagentStop reaches a hook log rather than the session, so this is a log breadcrumb and not a signal to the operator

### F45 — `.githooks/pre-commit` had four more fail-opens of the same index-vs-worktree class as F41, including two that disable the frozen-plan guard outright

- **File:** `.githooks/pre-commit` (frozen-plan guard; the staged-file filter; the binary detector; the content read)
- **Severity:** HIGH
- **Confidence:** CONFIRMED — all four reproduced in scratch repos against the real hook, before and after
- **Axis:** hardening
- **Reachability:** any committer, none of these needing `--no-verify`.
- **Rule:** `docs/hardening.md` rule 11 — a guard that declines to act must be watched by something measuring the outcome, not the attempt.
- **Finding:** F41 fixed one instance of "decide from the working tree, read from the index". Four more were in the same file.
  1. **The frozen-plan guard keyed on `[[ -f "$checksums" ]]` on disk** while comparing against `git show ":$f"`. `rm docs/plans/.checksums` without staging it skipped the entire freeze check, with the committed manifest still intact and only an unstaged deletion of a file nobody inspects to show for it.
  2. **The expected hash was read from the working-tree manifest.** Rewriting that file to the tampered hash, unstaged, made `recorded` match `actual`. The commit then carried a frozen plan contradicting its own committed manifest.
  3. **`--diff-filter=ACM` on the secret scan excluded `R` and `T`, not only `D`.** Rename detection is on by default, so `git mv app.conf app.conf.bak` plus an injected private key was reported `R096` and never entered the loop. The comment added with F41 said the filter "already excludes deletions", which is half of what it excludes -- the omission is what made this easy to miss on re-read.
  4. **The binary detector failed open**, and the content read aborted the hook. `git diff --numstat | awk … || continue` turned any git failure into "binary, skip", and after F41 removed the working-tree guard an unreadable index entry (a staged gitlink) reached `git show` and killed the hook under `set -e` with a raw `fatal:` and no `BLOCKED:` line -- the case the removed guard had been handling by accident, which F41's own fix-risk clause named and the fix did not address.
- **Fix risk:** widening the filter to `ACMRT` scans more files; the binary detector becoming fatal means a genuinely broken index blocks rather than skips, which is the intended direction. Verified the control case still blocks and a clean commit still passes.

**FIXED 2026-09-06:** manifest read from the index, filter widened to ACMRT, detector and content read both fail closed. All four reproductions now block; the positive control still blocks and a clean tree still passes

### F46 — `.gitattributes` can switch off the secret scan and was outside the reviewable-code set

- **File:** `docs/skills/plan/scripts/lib.sh` (`PLAN_CODE_GLOBS`), `.githooks/pre-commit` (binary detection)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** anyone adding a `.gitattributes`. `git diff --numstat` prints `-` for any path whose `diff` attribute is unset, and the hook reads `-` as "binary, skip", so `*.pem -diff` disables the private-key scan for every `.pem` in the repo.
- **Finding:** `.gitignore` was added to `PLAN_CODE_GLOBS` this session on the reasoning that `--exclude-standard` lets it decide the fingerprint's own inputs. `.gitattributes` decides the *secret scanner's* inputs by exactly the same argument and was missed -- so adding one obliged no review, obliged no `/simplify`, and moved no stamp fingerprint. `docs/hardening.md:71` already names `.gitattributes` among the things that make a git repository executable configuration, so the repo's threat model had this and the glob set did not. Third instance of G11's prediction that an allowlist keeps missing things that meet its own rule.
- **Fix risk:** none; one glob.

**FIXED 2026-09-06:** `*.gitattributes` added to PLAN_CODE_GLOBS, so it obliges review and moves the fingerprint like every other piece of enforcement config

### F47 — an agent name present in `required-agents` but absent from `PLAN_AGENT_ORDER` was silently dropped, degrading the whole gate to a no-op

- **File:** `docs/skills/workflow/scripts/required-agents` (the emission loop), `docs/skills/plan/scripts/lib.sh` (`PLAN_AGENT_ORDER`)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any edit to `PLAN_AGENT_ORDER` that does not also touch `required-agents`' hardcoded literals. Verified by renaming `"security"` to `"sekurity"` in the order array alone: `required-agents` emitted `/simplify`, `docs-updater`, `spec-check` and **exit 0**, with `security` gone and no diagnostic.
- **Rule:** n/a -- internal control correctness.
- **Finding:** `required-agents` builds `obliged` from string literals, then prints the intersection with `PLAN_AGENT_ORDER` to fix the run order. The intersection silently discards anything not in the order array, so one renamed entry means `plan-gate` obliges no `security` stamp and the merge passes with a green check. This is the failure `lib.sh`'s own comment claims the shared list prevents -- "a stamper with no checker silently degrades the gate to a no-op" -- and the shared list only prevents the writer/reader split, not this. The neighbouring invariant, `PLAN_STAMPABLE_AGENTS` being a subset of `PLAN_AGENT_ORDER`, has the same shape and is still unchecked; it holds today. Found by `/simplify` (altitude), which argued correctly that the source-time warning added for F43 cannot express this one, since the literals live in a different file.
- **Fix risk:** making the mismatch fatal means a half-finished rename blocks `required-agents` outright rather than degrading, which is the intended direction but will surface as a hard failure mid-edit.

**FIXED 2026-09-06:** the emission loop records what it printed and `plan_die`s on any obliged agent it could not place. Verified: the tampered order now exits 1 with a named cause, and the untampered path is unchanged

### F48 — the pre-push/verify-ladder pathspec alignment was documented by narrating the bug it had just fixed

- **File:** `.githooks/pre-push:40-43`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the round that dropped the dead top-level `profiles/` and `services/` from the pathspec and the anchor recorded its reasoning inline, verbatim: "Same set as verify-ladder's targeted build, literally: top-level profiles/ and services/ used to appear here and match nothing (both live under modules/), which made 'same pattern' false and hid any real divergence between the two build gates." That is four lines of history at a call site whose reader needs one fact — that this anchor is deliberately identical to `verify-ladder`'s and must stay so. Style guide, "Why context: the plan file, not comments": a workaround's history belongs in the plan with a citation pointer inline. Verified that the claim the comment makes is now true: `.githooks/pre-push:26` and `verify-ladder:160` both pass `hosts/ modules/ flake.nix flake.lock`, and `.githooks/pre-push:42` and `verify-ladder:168` both anchor `^(hosts/${host}/|modules/|flake\.nix|flake\.lock)` — byte-identical in both halves, so the "same host-detection pattern as .githooks/pre-push" claim at `verify-ladder:155` holds for the first time.

**FIXED 2026-09-06:** comment reduced to the invariant plus an `#F48` pointer; the history is the paragraph above

### F49 — `.githooks/pre-commit` still named `--diff-filter=ACM` in the comment F45 had just widened to `ACMRT`

- **File:** `.githooks/pre-commit:74-79` (the F41 comment inside the scan loop)
- **Axis:** docs accuracy (docs-updater)
- **Finding:** F45 widened the secret scan's filter to `ACMRT` precisely because F45's own item 3 records that "the comment added with F41 said the filter 'already excludes deletions', which is half of what it excludes -- the omission is what made this easy to miss on re-read". The filter was widened; that comment was not touched, so after the fix it read "`--diff-filter=ACM` already excludes deletions, so the index always has content here" three lines below a `--diff-filter=ACMRT` invocation. The safety argument the comment makes — dropping the `[ -f ]` guard is safe because deletions never reach `git show` — is still sound under `ACMRT`, so this is a wrong name, not a wrong conclusion. It is the fourteenth instance on this branch of a comment describing a version of the code that was later changed, and the second time in two rounds that the *same six lines* have been the stale ones.

**FIXED 2026-09-06:** comment names `ACMRT` and is cut to the fragment plus its `#F41` pointer

### F50 — `reference.md`'s `PLAN_CODE_GLOBS` enumeration omitted `.gitattributes` and undercounted the allowlist's own misses

- **File:** `docs/skills/workflow/reference.md:53-64`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** two stale claims in one paragraph, both from the same round. (1) The prose enumeration of what "code" covers ends at "`flake.lock`, and `.gitignore`" — `*.gitattributes` was added to `PLAN_CODE_GLOBS` in this same round (F46) and never reached the list. This is F40's failure repeating in the same paragraph one round later: the enumeration exists because the trigger table says "any code change (see below)", so the list *is* the reader's answer, and the member missing from it is the one that can switch the `pre-commit` secret scan off. (2) The sentence "it has twice been found to be missing something that met its own rule" was written when that count was two; F46's own text calls itself the "third instance of G11's prediction". A reader weighing the standing denylist-inversion proposal gets a materially weaker case from "twice" than the record supports.

**FIXED 2026-09-06:** `.gitattributes` added to the enumeration with what it controls; the count corrected to three

### F51 — the lib.sh-split plan tells its implementer to move "the four arrays"; there are six

- **File:** `docs/plans/todo/2026-09-06-shrink-the-ci-trusted-set-by-splitting-lib-sh.md:33`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** `constants.sh`'s contents are specified as "the four arrays, the relpaths, `plan_path_matches`, `plan_is_code_path` / `plan_is_doc_path`, and the derived-set logic". `lib.sh` defines six `PLAN_*` arrays — `STAMPABLE_AGENTS`, `AGENT_ORDER`, `CODE_GLOBS`, `DOC_GLOBS`, `NONTEXT_GLOBS` and the derived `TEXT_GLOBS` (`lib.sh:21,30,285,308,316,333`). The count reads as pre-`PLAN_AGENT_ORDER`, which landed in the same round the plan was filed. It matters because the plan's failure mode is a partial move: `plan-gate` reads `PLAN_STAMPABLE_AGENTS` and `required-agents` reads `PLAN_AGENT_ORDER`, so an implementer who moves four arrays and leaves the two agent lists behind gets a `constants.sh` the CI-pinned entry points cannot run on. Named rather than counted, so the list cannot go stale again the next time an array is added.

**FIXED 2026-09-06:** the six arrays are named individually instead of counted

_docs-updater finished 2026-09-06T23:19:30Z -- see Findings above._

### F52 — the secret scan's binary skip is driven by `git diff --numstat`, so a `.gitattributes` entry or a filename containing pathspec glob magic silently switches it off

- **File:** `.githooks/pre-commit:83-88`; `docs/skills/plan/scripts/lib.sh:302`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED — both routes reproduced end to end against the real hook in scratch repos
- **Axis:** hardening
- **Reachability:** any committer (human or agent) in this **public** repo, no `--no-verify` needed, no diagnostic printed. Route 1: stage `.gitattributes` containing `*.pem -diff` together with `leak.pem` holding an OpenSSH private-key header block; `git diff --cached --numstat` prints `-` in the first field, the hook reads that as "binary, skip", and exits 0. Route 2: the `-- "$file"` argument is a *pathspec*, not a literal path, so a file whose own name contains `*`/`?`/`[` matches its siblings too — staging `k*.txt` (an age secret key) alongside `k!.txt` (binary) makes `numstat`'s **first line** the binary one, so `${numstat%%$'\t'*}` is `-` and `k*.txt` is never scanned. Hook exited 0 in both cases.
- **Rule:** `docs/hardening.md` rule 7 already names "`.gitattributes` filters" among the things that make a git repository executable configuration; `docs/procedures/secrets.md` names this hook as the backstop for a repo whose every revision is permanently public (rule 1).
- **Finding:** `2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F46` identified the `-diff` mechanism exactly and correctly, but the fix it records — adding `*.gitattributes` to `PLAN_CODE_GLOBS` — only makes such a change oblige a review and move the stamp fingerprint. The hook is unchanged and still blind, and F46 is marked FIXED, so the live bypass now reads as closed. Route 2 is the same root cause with no `.gitattributes` involved at all: `--numstat` is an *attribute- and pathspec-sensitive oracle*, being used to answer a question ("is this blob binary?") about content the loop already holds three lines later. The fix is either one `git diff --cached --numstat -z` pass up front keyed by path, or dropping the skip entirely — command substitution already strips NULs, so grepping a binary blob's `$content` is harmless, just slower. `:(literal)` pathspec magic closes route 2 alone but leaves route 1 open.
- **Fix risk:** removing the skip costs a grep over every staged binary; on a repo that ever commits large blobs that is a real pre-commit latency cost, so measure before choosing. Any replacement must not start blocking on ordinary binaries (`files/gruvbox-dark-rainbow.png` is the live case) — verify a clean commit touching that file still passes.


**FIXED 2026-09-06:** binary detection now reads the blob's own bytes (grep -qaP for a NUL) instead of git diff --numstat, whose answer comes from the diff gitattribute. Verified: staging .gitattributes with '*.pem -diff' beside a key-bearing .pem passed before and blocks now, while numstat still reports -

### F53 — the frozen-plan guard is keyed on the destination path, so `git mv` plus an edit rewrites a frozen plan with no output and exit 0

- **File:** `.githooks/pre-commit:24-38`
- **Severity:** LOW
- **Confidence:** CONFIRMED — reproduced: `git mv` a frozen plan to a new name under the same folder, append a line, `git add -A`, hook exits 0 silently. The in-place control still blocks.
- **Axis:** hardening
- **Reachability:** any committer. `--name-only` reports only a rename's *destination*, and the manifest is keyed on the *source* path, so `recorded` is empty and the `[[ -z "$recorded" ]] && continue` arm skips the file as "not frozen". The `ACMRT` widening from `2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F45` buys nothing here — it genuinely fixed the secret scan (verified: `git mv` plus an injected age key now blocks), but for this guard the entry it lets through is one the lookup then discards. Nothing legitimate produces this shape: `plan-move` calls `plan_require_not_frozen` and refuses to move a frozen plan at all.
- **Rule:** n/a — internal control correctness. The guard's header says deletions are deliberately allowed "since this only guards against silent content drift, not against removing the file outright"; a rename is content drift wearing a deletion's clothes, which is exactly the case that reasoning does not cover.
- **Finding:** the immutability the whole citation scheme rests on (`docs/skills/plan/reference.md:129`) is enforced in one place, and that place can be walked around with a rename. Secondary effect: the manifest keeps an entry for a path no longer in the index and nothing notices, so the guard's coverage silently shrinks by one file per rename.
- **Fix risk:** feeding a rename's source path through the lookup needs `--name-status` (or `--raw -z`) rather than `--name-only`, i.e. a different parse for the rename record shape; get it wrong and the guard reports the wrong filename. Cheaper and stronger: after the loop, assert every manifest entry still names a path present in the index, and block if one vanished.


**ACCEPTED 2026-09-06:** accepted by the user (LilijoySkyseeker) 2026-09-06: the guard keys on a rename's destination while the manifest keys on the source, so git mv plus an edit passes. Fixing it needs --name-status -z parsing of a rename's three NUL-separated fields, and must not break plan-move, which is itself a rename. Follow-up filed as 2026-09-06-make-the-frozen-plan-guard-survive-renames-and-stop-self-certifying.md

### F54 — the manifest the frozen guard trusts is supplied by the same commit it is gating

- **File:** `.githooks/pre-commit:24,29`
- **Severity:** LOW
- **Confidence:** CONFIRMED — both reproduced against the real hook
- **Axis:** hardening
- **Reachability:** any committer. (a) Stage a tampered frozen plan **and** a `docs/plans/.checksums` rewritten to its new hash: `recorded` matches `actual`, exit 0. (b) `git rm --cached docs/plans/.checksums` in the same commit: `git show ':docs/plans/.checksums'` fails, the `if` is false, and the *entire* frozen-plan guard is skipped with no output at all. Nothing else in the repo validates this manifest — CI's `plan-gate` reads `frozen:` frontmatter, never the checksums.
- **Rule:** `docs/hardening.md` rule 11 — a guard that declines to act must be watched by something measuring the outcome. Route (b) is a guard declining to act, silently, on evidence supplied by the thing it guards.
- **Finding:** not a regression — strictly better than the pre-`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F45` state, where both bypasses worked from the *working tree* and left nothing in the commit. Reading the index means the tampering is now inside the diff a reviewer sees. But the guard is still self-certifying: the expected hash and the file it is compared against come from the same commit, and the "no manifest" case is a silent skip rather than a block. A local hook cannot fully fix this — it has no trusted prior state — which is why the durable answer is server-side: a CI step that recomputes every entry in the *merge base's* manifest against the PR's tree and blocks on any frozen plan whose content moved. Same "the PR supplies its own gate" shape as `2026-09-06-stop-a-pr-from-weakening-the-ci-gate-it-is-judged-by.md`, one layer down.
- **Fix risk:** the "no manifest" arm cannot simply be made fatal — the repo had no manifest before `plan-freeze` existed, and a clone of an older base would block every commit. It needs a "manifest exists on the base ref" condition, which is a CI-shaped question, not a pre-commit-shaped one.


**ACCEPTED 2026-09-06:** accepted by the user (LilijoySkyseeker) 2026-09-06: the manifest is supplied by the commit being gated, so the guard certifies itself. F45 already moved the read to the index, which puts any tampering inside the diff where review and CI can see it; closing it properly means validating the manifest server-side, where the committer does not control the comparison. Follow-up filed with F53

### F55 — `plan-gate` never asserts that it checked any stamp at all, so a typo in `PLAN_STAMPABLE_AGENTS` turns two BLOCKs into a green pass

- **File:** `docs/skills/workflow/scripts/plan-gate:130-131`; `docs/skills/plan/scripts/lib.sh:21`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED — reproduced end to end in a scratch repo carrying a stale fingerprinted stamp. Unmodified: two `BLOCKED: ... stamp is stale` lines, exit 1. With `PLAN_STAMPABLE_AGENTS=("sekurity" "docs-updatr")` as the *only* change: `plan-gate: all cited plans (1) have their findings resolved and their obliged reviews stamped.`, exit 0, no diagnostic anywhere. `required-agents` exits 0 throughout, because the names it emits are still in `PLAN_AGENT_ORDER` and `2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F47`'s guard therefore never fires.
- **Rule:** n/a — internal control correctness. Same class as `docs/hardening.md` rule 11: the gate measures the attempt (it ran, it printed a success line) and not the outcome (how many stamps it actually examined).
- **Finding:** F47 closed one side of this — an obliged agent missing from `PLAN_AGENT_ORDER` — by making the mismatch fatal in the *emitter*. The *checker* has no equivalent floor. `for agent in $obliged; do plan_is_stampable "$agent" || continue` is a filter with no lower bound: if `PLAN_STAMPABLE_AGENTS` and `required-agents`' hardcoded literals ever disagree, every stamp arm is skipped and the gate reports success over zero checks. F47's own text records the neighbouring `PLAN_STAMPABLE_AGENTS` ⊆ `PLAN_AGENT_ORDER` invariant as unchecked; this is the sharper form, because the set that actually matters is `PLAN_STAMPABLE_AGENTS` ⊆ {names `required-agents` can emit}, which lives in two files with no shared definition and no assertion. Both invariants verified to hold today. Two cheap floors: assert at source time that `PLAN_STAMPABLE_AGENTS` is a subset of `PLAN_AGENT_ORDER` (beside the `2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F43` warning, and fatal like F47 rather than a warning), and in `plan-gate` count the obliged agents that were stampable and `plan_die` when `obliged` is non-empty but that count is zero.
- **Fix risk:** the "non-empty obliged, zero stampable" floor would fire legitimately on a range obliging only `/simplify` — possible in principle, impossible today, since every path that sets `code=1` also emits `security`. Encode it only after confirming that stays true, or the gate becomes unpassable for a class of ranges.


**FIXED 2026-09-06:** plan-gate asserts every PLAN_STAMPABLE_AGENTS entry appears in PLAN_AGENT_ORDER before using it as a filter. Verified: pointing it at nonexistent names turned two BLOCKs into a green pass before, and now exits 1 naming the cause

### F56 — `.githooks/pre-push` still swallows a failed range diff, the fail-open this branch closed at every other diff call site

- **File:** `.githooks/pre-push:26`
- **Severity:** LOW
- **Confidence:** CONFIRMED — `git diff <unknown-sha>..HEAD` exits 128; `2>/dev/null || true` makes `files` empty, `changed_files` empty, and the hook `exit 0`s at line 33 having built nothing
- **Axis:** hardening
- **Reachability:** anyone pushing when `remote_sha` names an object the local clone does not have — a `git push --force` after the remote branch was rewritten, a push to a second remote carrying commits never fetched, or a range broken by a local `gc`. The hook then reports "no host config changed" for a push that changes every host, silently, and the first anyone learns of a broken build is on the target machine.
- **Rule:** n/a — but this is the exact `2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F3` / `#F37` pattern ("a failed diff inside a command substitution reads as 'nothing changed'"), which this branch fixed in `required-agents`, `plan_worktree_files`, `verify-ladder` and `.githooks/pre-commit`. This file was edited in the same round, on the very line above the `|| true`, and left as it was.
- **Finding:** the round's stated goal for this file was pathspec alignment, and that part is correct — top-level `profiles/` and `services/` were removed by the dendritic migration (commit `9c0a601`) and match nothing in any current tree, so no host can escape the targeted build that previously would not have; verified byte-identical against `verify-ladder:160,168`. But `verify-ladder`'s counterpart *does* check its status (`plan_worktree_files ... || { BLOCKED; exit 1; }`), so the two gates the round set out to make identical are still not identical in the way that matters most.
- **Fix risk:** failing closed means a push aborts on an unresolvable range rather than proceeding unbuilt; the escape is `--no-verify`, already this hook's documented one. Check the new-branch arm first — it deliberately tolerates a missing `origin/master`.


**FIXED 2026-09-06:** pre-push checks the range diff's status instead of swallowing it; an unresolvable range now blocks rather than reading as 'no host config changed'

### F57 — a staged gitlink is now an unfixable block whose only offered remedy is `--no-verify`, which disables every other check in the hook

- **File:** `.githooks/pre-commit:93-97`
- **Severity:** INFO
- **Confidence:** CONFIRMED — a real `git submodule add` produces `BLOCKED: cannot read the staged content of sub2; refusing to scan it.` and exit 1, with the only advice being `git commit --no-verify`
- **Axis:** hardening
- **Reachability:** not an adversary — anyone adding or updating a submodule. Latent today: the repo has no `.gitmodules`.
- **Rule:** n/a. `plan-gate:125` states the principle this trips: "An unfixable gate teaches the bypass."
- **Finding:** the F45 fix's comment says a staged gitlink "has no blob in this object store". True for a real submodule (the commit object lives under `.git/modules/<name>/`), but not for every gitlink — one pointed at a commit the superproject happens to have makes `git show ":$path"` *succeed* and print a commit log plus diff, which is then grepped for private keys. So the arm is both over-broad and non-deterministic. A gitlink is not an unreadable entry; it is a known entry type with no content to scan, and mode `160000` is available from `git diff --cached --raw`. Escaping via `--no-verify` is worse than skipping it, because that one flag also turns off the frozen-plan guard, `claude-links-check`, and the secret scan for every other file in the commit.
- **Fix risk:** none of consequence; the classification has to come from the mode, not from `git show`'s exit status, so genuinely unreadable entries keep failing closed.


**FIXED 2026-09-06:** a staged gitlink is skipped deliberately (mode 160000 has no blob and cannot carry a secret) rather than blocking, so git submodule add no longer needs --no-verify, which would have disabled every other check in the hook

### F58 — `files/` is imported by a module but sits outside both targeted-build pathspecs

- **File:** `.githooks/pre-push:26,42`; `docs/skills/workflow/scripts/verify-ladder:160,168`; `modules/profiles/PC.nix:238`
- **Severity:** INFO
- **Confidence:** CONFIRMED — `modules/profiles/PC.nix:238` reads `image = ../../files/gruvbox-dark-rainbow.png;`, and neither gate's pathspec (`hosts/ modules/ flake.nix flake.lock`) includes `files/`
- **Axis:** needed-used
- **Reachability:** no adversary — a commit that changes only `files/` changes the PC hosts' derivation and triggers no targeted build in either gate, so a broken or missing asset reaches a host unbuilt.
- **Rule:** n/a
- **Finding:** pre-existing, not introduced by this round. Raised because this round is the one that rewrote both pathspecs and verified them byte-identical: the two were made to agree with each other while both continue to omit a directory a module actually imports. "Same set in both places" is a weaker property than "the right set", and confirming the first is what makes it easy to stop asking the second.
- **Fix risk:** adding `files/` widens what triggers a full `nixos-rebuild build` — check nothing large and frequently-touched lives there first, or the pre-push hook gets materially slower for unrelated work.


**FIXED 2026-09-06:** files/ added to both targeted-build pathspecs and both anchors, since modules/profiles/PC.nix imports from it

### F59 — `plan_active_plan` puts no constraint on the marker's path, and `subagent-stamp` appends to whatever it names

- **File:** `docs/skills/plan/scripts/lib.sh:248-255`; `docs/skills/workflow/scripts/subagent-stamp:30,55`
- **Severity:** INFO
- **Confidence:** CONFIRMED — `plan_active_plan` returns `../target.txt` with rc=0 for a marker containing that string; `subagent-stamp` then does `printf ... >> "$root/$rel"`
- **Axis:** hardening
- **Reachability:** anything that can write `.claude/.active-plan` — any process running as the desktop user, and notably any agent tool call, since the marker is gitignored, unremarkable, and written as a matter of course by `plan_mark_touched`. Point it at a traversal path, finish any `security` or `docs-updater` subagent, and the `SubagentStop` hook appends one line to that file. The following `git -C "$root" add "$rel"` fails harmlessly and is `|| true`'d.
- **Rule:** n/a. Not a privilege gain — the writer already has the user's file access — but it is an append primitive that does not go through the permission system, driven by a file no permission rule guards.
- **Finding:** the appended text is fixed (`plan_stamp_line` with an `agent_type` that must already have passed `plan_is_stampable`), so this is a nuisance-write, not injection. What makes it worth recording is the asymmetry: `plan_locate` rejects any `..` segment with a comment explicitly about attacker-influenced input, and `plan_active_plan` — which feeds the only *writer* in the system — has no such check. Whatever justified guarding the reader applies at least as strongly here. A one-line `case "$rel" in docs/plans/*/*.md) ;; *) return 1 ;; esac` closes it and also catches the ordinary corruption case of a truncated marker.
- **Fix risk:** the pattern must match every folder a plan can live in (`todo/`, `in-progress/`, `done/`, `rejected/`); anything narrower silently stops stamping for one status class, which is `2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F47`'s failure again.


**FIXED 2026-09-06:** plan_active_plan rejects '..', absolute paths, and anything outside docs/plans/, matching what plan_locate already enforced on the same class of input

### F60 — `subagent-stamp`'s comment says a fingerprint-less stamp reads as `malformed`, which is the opposite of what a stamp with no `(code ...)` field actually does

- **File:** `docs/skills/workflow/scripts/subagent-stamp:42-45`
- **Severity:** INFO
- **Confidence:** CONFIRMED — `plan_stamp_fingerprint` (`docs/skills/plan/scripts/lib.sh:483-494`) returns `malformed` only for a literal `(code )` with an empty value, and `legacy` for any stamp line with no `(code ` substring at all; `plan-gate` blocks on the former and NOTEs on the latter
- **Axis:** docs accuracy
- **Reachability:** a reader deciding whether the `legacy` loophole is real
- **Rule:** n/a
- **Finding:** the comment reads "No stamp at all, rather than one naming no code. Both block -- a fingerprint-less stamp reads as `malformed` to plan-gate, not `legacy`." Under the intended reading ("one naming no code" = `plan_stamp_line` called with an empty `fp`, giving `(code )`) it is correct. But "fingerprint-less stamp" is also the exact phrase `2026-09-06-enable-fingerprint-less-stamp-blocking-once-the-fingerprint-era-has.md` uses for the *other* shape — a stamp with no `(code ...)` field — which reads as `legacy`, does **not** block, and is a live user-accepted loophole. Observed on this very branch: `plan-gate origin/master HEAD` currently emits `legacy` NOTEs for both stamps and passes, so the stamp check is doing nothing on the PR that introduces it (expected per `2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F12`, which is exactly what makes this phrasing the actively misleading one). A reader taking the comment at face value concludes the legacy loophole is closed.
- **Fix risk:** none; naming the shape (`an empty (code ) field`) instead of "fingerprint-less" resolves it.

**Checked and clean (security, 2026-09-06, sixth pass).** Reviewed `git diff origin/master...HEAD` plus the full uncommitted working tree, reading current file content rather than diff hunks. Verified fine, by reproduction where possible: all four `2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F45` fixes are real and none regressed — the manifest now genuinely comes from the index (an unstaged `rm` or rewrite no longer disables the guard), `ACMRT` genuinely closes the rename leg of the *secret scan* (`git mv` plus an injected age key now blocks, where `ACM` skipped it), the captured-status binary detector fails closed on a git error, and the content read fails closed on an unreadable entry. `${numstat%%$'\t'*}` is a correct first-field extraction for every single-path `--numstat` shape: a rename restricted by a single-path pathspec is reported as an ordinary add (`5  0  new.txt`), never the `old => new` two-path form, and binary is `-  -  path`; the only shapes it mishandles are the multi-line ones F52 covers. Paths that `core.quotePath=false` still C-quotes (embedded quote, backslash, tab, newline) fail closed at `git show`, not open. A rename's *source* path cannot matter to the secret scan (the source blob is gone; only the destination is scanned) but does matter to the frozen guard — F53. Confirmed `.githooks/pre-push`'s dropped `profiles/`/`services/` are dead in every current tree and byte-identical to `verify-ladder`'s pathspec and anchor, so no host escapes a build it previously got. Confirmed the `lib.sh` single-pass merge derives the right set (14 code globs − 6 non-text = 8 text globs, `secrets/*` and `.sops.yaml` correctly outside the citation scan) and that the `_hit` drift check still fires per exclusion; it warns rather than dying, which is a deliberate asymmetry with F47 and defensible since a sourced library dying would take every plan script with it. Confirmed `plan_code_fingerprint` is deterministic, cwd-independent (identical from repo root and from `docs/`), locale-stable (identical under `LC_ALL=C`, `en_US.UTF-8`, and unset), and cannot return empty — a repo with no matching files yields `e3b0c44298fc1c14`, the empty-input hash, and every failure path (`git rev-parse`, `ls-files`, `xargs`) returns 1 under `pipefail` rather than an empty string. Removing the second `LC_ALL=C sort` is safe: the path list is already `sort -zu`'d under `LC_ALL=C`, so `sha256sum`'s output order is fixed. Confirmed the CI pinning story is unaffected by moving the `source` above `root=`: `SCRIPT_DIR` is still computed with `pwd -P` before anything is sourced, `lib.sh` and `required-agents` both resolve through it, and `$root` is used only for repo *data* (`plan_locate`, the plan file paths) — a PR editing `plan-gate`, `lib.sh` or `required-agents` still gets the base branch's copies, and a PR that widens or narrows `PLAN_CODE_GLOBS` produces a fingerprint mismatch in CI, i.e. fails closed. Confirmed `required-agents`' new F47 guard cannot itself fail open: it runs under `set -uo pipefail` with `plan_die`'s `exit 1`, its output is consumed by `plan-gate` through a status-checked command substitution, and the guard's own loop is a plain string membership test with no external command that could fail silently. Also checked and judged not worth a finding: `plan_repo_root`'s `plan_die` is inert inside `root="$(plan_repo_root)"` (the `exit` runs in the subshell), but every call site follows with `cd "$root" || plan_die`, and bash's `cd ""` fails, so all four callers still fail closed; `plan-citations` observes `awk`'s status through a real file rather than a process substitution and fails closed on an unknown record kind; `tests/zrepl-replication.nix` still imports only nixpkgs' own snake-oil test keys, now by path concatenation, and grants nothing outside the ephemeral VM. No secret was decrypted or read at any point, and no file outside this plan was modified.

_security finished 2026-09-06T23:37:19Z -- see Findings above._

**FIXED 2026-09-06:** the comment now distinguishes the two cases: a stamp this script writes always carries (code ...), so an empty fingerprint reads as malformed and blocks, while legacy is the separate accepted loophole for pre-fingerprint stamps

### F61 — the /simplify rewrite of the build-set selection left two comments describing the regex it deleted

- **File:** `.githooks/pre-push:23-25`; `docs/skills/workflow/scripts/verify-ladder:26`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the working-tree /simplify pass replaced the per-host alternation `^(hosts/${host}/|modules/|files/|flake\.nix|flake\.lock)` in both build gates with a two-step selection (any changed line outside `hosts/` builds every host; otherwise `^hosts/<host>/` picks the one). Two comments still described the old shape. (1) `pre-push`'s F34 comment said a C-quoted non-ASCII path "would defeat the ^(hosts/...) anchor below and skip the build" — the anchor it names no longer exists, and the stated consequence inverted: a C-quoted `hosts/` path starts with `"`, so it now trips the any-non-`hosts/` test and builds *every* host rather than skipping the affected one. `core.quotePath=false` is still wanted, but to keep the build set precise, not to close a fail-open. (2) `verify-ladder`'s deleted-paths comment still said "The host-detection set further down keeps them" after the same pass renamed the concept to "build-set selection" in the header comment four lines up. Same stale-comment class as F48/F49/F60 — a comment describing the version of the code that was just changed out from under it. Both rewritten in this pass to match shipped behavior.


**FIXED 2026-09-06:** both comments rewritten in the same docs-updater pass that found them: pre-push's F34 comment now states the current consequence (a C-quoted hosts/ path over-builds instead of skipping) and verify-ladder's deleted-paths comment names the targeted-build set

### F62 — pre-push's rewritten trigger-set comment re-inlined a sentence of bug history

- **File:** `.githooks/pre-push:48-49` (the F48 comment above the build-set selection, as the /simplify pass left it)
- **Axis:** channel routing (docs-updater)
- **Finding:** moved here verbatim, per the style guide's "Why context: the plan file, not comments": "Re-spelling the set as a regex here is how a watched directory got added to one copy and not the other." The comment keeps only the invariant (the diff's pathspec is the trigger set's one spelling; the two build gates must not diverge) plus citations to F48 and this entry. F48 is the fuller record of the same incident class — the deleted alternation was a second spelling of the set, and the pre-dendritic `profiles/`/`services/` drift it hid is quoted there; F58 records the `files/` omission both copies shared.


**FIXED 2026-09-06:** the history sentence lives in this entry verbatim; the pre-push comment carries only the invariant plus the F48 and F62 citations

### F63 — `testing-changes.md`'s hook descriptions drifted from both hooks in the same commit that edited the file

- **File:** `docs/procedures/testing-changes.md:80,94-95`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** two stale claims left by `854156c`. (1) The pre-push bullet listed the watched paths as "`hosts/`, `modules/`, `flake.nix`, `flake.lock`" — F58's fix added `files/` to the hook's pathspec in that same commit and the enumeration never got the new member. Same shape as F50: the list *is* the reader's answer, and the member missing from it is the one that just changed. (2) The pre-commit bullet opened "two guards", but the hook runs three: the secret scan, the frozen-plan check, and `scripts/claude-links-check` — the symlink-drift check `workflow/reference.md` already names as a pre-commit extension, present in the hook since before this branch. Both corrected in this pass: `files/` added to the enumeration, and the third guard named with a pointer to reference.md.

_docs-updater finished 2026-09-07T04:15:30Z -- see Findings above._

**FIXED 2026-09-06:** testing-changes.md fixed in the same docs-updater pass: files/ added to the pre-push watched-path enumeration and the pre-commit bullet names all three guards including claude-links-check

### F64 — F55's fix encodes only the subset floor, so the coordinated form of the same typo still green-passes over zero stamp checks

- **File:** `docs/skills/workflow/scripts/plan-gate:86-89`; `docs/skills/plan/scripts/lib.sh:21,30`
- **Severity:** LOW
- **Confidence:** CONFIRMED — both directions reproduced in a scratch repo against the current scripts
- **Axis:** hardening
- **Reachability:** a post-merge editor of `lib.sh` (human or agent) whose agent rename or typo lands in *both* `PLAN_STAMPABLE_AGENTS` and `PLAN_AGENT_ORDER` while `required-agents`' hardcoded literals keep the real names. CI pins `lib.sh` from the base branch, so the PR making the edit is still gated correctly; every PR *after* it merges is gated by a stamp check that examines zero stamps.
- **Rule:** n/a — same `docs/hardening.md` rule-11 class F55 named: the gate measures the attempt, not how many stamps it examined.
- **Finding:** F55's FIXED note is accurate about what it claims — `PLAN_STAMPABLE_AGENTS=("sekurity" "docs-updatr")` alone now dies at the new assertion (`BLOCKED: stampable agent 'sekurity' is not in PLAN_AGENT_ORDER`, exit 1, reproduced), where before it green-passed. But F55's own text named two floors, and only the subset assertion shipped. Reproduced the residual: with the same bogus names *also appended to* `PLAN_AGENT_ORDER`, the assertion passes, `required-agents` emits the real names unbothered (its F47 check compares its own literals against `PLAN_AGENT_ORDER`, which still contains them), `plan_is_stampable` filters every obliged agent out, and the gate prints `plan-gate: all cited plans (1) have their findings resolved and their obliged reviews stamped.` with exit 0 over a plan carrying no stamp at all. Every single-array typo is now covered (order-side drift dies in `required-agents`' F47 check, stampable-side drift dies in the new assertion); only this two-array form survives, and nothing asserts the invariant that actually matters — `PLAN_STAMPABLE_AGENTS` ⊆ {names `required-agents` can emit} — which still spans two files with no shared definition.
- **Fix risk:** exactly what F55 recorded for its second floor: "non-empty obliged but zero stampable checked → die" fires legitimately on a range obliging only `/simplify` — impossible today, since every path that sets `code=1` also emits `security`, but encode the floor only with that invariant checked, or the gate becomes unpassable for such ranges.


**FIXED 2026-09-06:** plan-gate now counts the obliged agents the stampable filter keeps and blocks when the range obliged agents but none was stampable. Reproduced: the coordinated both-arrays tamper that green-passed over zero stamp checks now exits 1 naming the drift, and the untampered missing-stamp path still blocks

### F65 — plan_in_list's unquoted call sites add a pathname-expansion behavior the case-pattern idiom they replaced never had

- **File:** `docs/skills/workflow/scripts/required-agents:86,97`
- **Severity:** INFO
- **Confidence:** CONFIRMED — the expansion demonstrated directly; the non-reachability checked against every current member
- **Axis:** hardening
- **Reachability:** none today — every word reaching the two unquoted `$obliged`/`$emitted` expansions is one of the hardcoded literals `/simplify`, `docs-updater`, `security`, `spec-check`, none containing a glob or IFS character, and `$obliged` is built only from those literals, never from input. Latent only.
- **Rule:** n/a — recorded for the same "inert here but one refactor from mattering" reason as F32.
- **Finding:** the /simplify pass replaced `case " $obliged " in *" $a "*` with `plan_in_list "$a" $obliged`, and the comment documents the deliberate word-split. Unquoted expansion also performs *pathname* expansion, which a `case` word never does — demonstrated: with files `secA`/`secB` in the cwd, `lst='sec*'; plan_in_list 'sec*' $lst` returns 1, because the member expanded to `secA secB` and no longer matches itself. `required-agents` runs from the repo root, so a future agent name containing a glob character would be compared against the repo's top-level filenames instead of literally, in both the emit filter and the F47 completeness loop — and the failure direction there is an agent silently not emitted, i.e. the fail-open F47 exists to close. `plan_in_list`'s own comment sells it as the non-subtle replacement for the padded-string idiom; at these two call sites it traded the space caveat for a glob caveat.
- **Fix risk:** none of consequence — making `obliged`/`emitted` bash arrays removes both unquoted expansions with no behavior change; a `set -f` toggle would also work but leaks into everything else the script runs.

**Checked and clean (security, 2026-09-07, seventh pass).** Reviewed `git diff origin/master...HEAD` plus the full uncommitted working tree, reading current file content rather than diff hunks, with every re-reproduction run in scratch repos under /tmp. **The F52/F56/F57 fixes are real**: staging `.gitattributes` with `*.pem -diff` beside a private-key `.pem` now blocks (`numstat` still answers `-  -  leak.pem`, and the hook no longer asks it); the `k*.txt`-age-key-beside-binary-`k!.txt` pathspec route also blocks (the `:$file` index read resolves the literal name, so the glob sibling cannot shadow it); a synthetic staged gitlink (`update-index --cacheinfo 160000`) commits cleanly while a plaintext age key still blocks; and pre-push fed an unresolvable remote sha prints `BLOCKED: cannot diff ... refusing to decide the build set from a failed diff` and exits 1. The second `git show` in the binary probe is necessary, not redundant — bash's "ignored null byte" warning fired in the repro, confirming `$content` can never carry a NUL. One inherent property, unchanged from the numstat era and from any binary skip: a secret file with a deliberately embedded NUL byte commits silently (reproduced) — same before this branch, and a committer wanting to dodge the backstop already has `--no-verify`. **The new build-set selection cannot under-build relative to the deleted regex**: for every line the pathspec-restricted diff can emit, the new selection's set is a superset of the old alternation's — reproduced host-scoped (`alpha` only), `modules/` (all), `files/`-only (all, F58's fix live), C-quoted `hosts/` path (all — the old regex *skipped* the affected host here, so the inversion is fail-safe), depth-1 `hosts/README.md` (nothing built, byte-for-byte the old behavior; no depth-1 file exists under `hosts/` in the real tree), and an empty range (exit 0). Host names (`homelab isoimage thinkpad torrent vps`) contain no regex metacharacters, and the one case where a pathological host directory name could error the per-host grep is one the old interpolated ERE handled worse. verify-ladder's copy is the same logic over `plan_worktree_files` with a checked exit status; its deleted-paths split (dropped from the lint set, kept in the build set) is right. The new-branch arm's swallowed `merge-base` is unchanged from master and was already flagged as deliberate in F56's fix-risk; its "empty tree" comment predates this branch. **`plan_active_plan`'s tightened guard is strictly stricter**: its accept set (`docs/plans/*/*.md`, no `..`) is a subset of the old one (`docs/plans/*`, no `..`, not absolute — an absolute path cannot match the new allowlist), so nothing the old guard rejected is now accepted; tested accept on all four status folders, reject on depth-1 `docs/plans/p.md` (even when the file exists), `../target.txt`, `/etc/passwd`, embedded `..`, `docs/plansX/`, and a non-`.md` suffix. Residue: `docs/plans/./p.md` and `docs/plans//p.md` still pass the pattern — both resolve inside `docs/plans/`, both were accepted by the old guard too, and the only depth-1 non-`.md` file there (`.checksums`) stays unreachable, so F59's "never outside docs/plans/" claim holds. **F55's primary repro now blocks** (see F64 for the coordinated residual, reproduced both directions). `plan_in_list` itself is correct (empty-list call returns 1 without tripping `set -u`, members with spaces impossible for callers passing `"${array[@]}"`), and its two quoted-array call sites (plan-gate's assertion, `plan_is_stampable`) are hazard-free; the unquoted required-agents sites are F65, latent only. `required-agents` emits `/simplify docs-updater security spec-check` in order in working-tree mode and the first three in range mode; `plan_has_heading` is byte-equivalent to the inline grep it replaced. `plan-citations`' dropped `prev != ""` guard was dead (skip is 0 before the first record, so the FNR==1 and END arms can only fire with a real filename in `prev`), and the live run passes (271 citations, 2 ignored regions). `subagent-stamp`'s corrected comment now matches `plan_stamp_fingerprint`'s actual three-way split (F60), and `testing-changes.md`'s three-guard/`files/` corrections match both hooks as shipped (F63); the "hosts/<name>/README.md still triggers a real build" example survives the selection rewrite. plan-gate over `origin/master..HEAD` still exits 0 with the two expected `legacy` NOTEs, and plan-lint passes on this plan. The range's only `.nix` change remains `tests/zrepl-replication.nix`'s path-concatenation import of nixpkgs' snake-oil test keys — no NixOS module, firewall rule, systemd unit, user, group, capability, or `sops.secrets` reference is touched anywhere in the range or the working tree. No secret was decrypted or read at any point, and no file outside this plan was modified.

_security finished 2026-09-07T05:52:00Z -- see Findings above._

_security finished 2026-09-07T04:30:08Z -- see Findings above._

**FIXED 2026-09-06:** required-agents builds obliged and emitted as arrays and every plan_in_list call quotes the expansion, so no word-splitting or pathname expansion happens at all; both modes verified emitting the correct ordered set

_docs-updater finished 2026-09-07T04:38:20Z -- see Findings above._

**Checked and clean (security, 2026-09-07, eighth pass).** Reviewed only the delta since the seventh-pass stamp — the F64 fix in `plan-gate`, the F65 fix in `required-agents`, and the F61–F65 plan appends — after confirming the rest of the working-tree diff (`pre-commit`, `pre-push`, `verify-ladder`, `plan-citations`, `lib.sh`, `testing-changes.md`) is byte-for-byte the material the seventh pass already examined. All reproductions ran in a scratch repo under the session job dir, against verbatim copies of the current scripts. **The F64 floor genuinely closes the coordinated both-arrays tamper, and every neighboring drift shape fails closed**: bogus names in both `PLAN_STAMPABLE_AGENTS` and `PLAN_AGENT_ORDER` (real names kept so `required-agents`' F47 check passes) now exits 1 at the new outcome floor for both a code-obliging and a docs-only plan-citing range, where before it green-passed over zero stamp checks; `PLAN_STAMPABLE_AGENTS` emptied outright — which sails through the F55 subset loop by iterating zero times — is also caught by the floor; the single-array shapes still die where they always did (stampable-side rename at the F55 assertion, order-side rename at `required-agents`' F47 `plan_die`, which plan-gate surfaces through its status-checked capture). Every legitimate direction still behaves: missing stamps block (both BLOCKED lines, exit 1), stale stamps block (working-tree edit after stamping, exit 1), correctly stamped code and docs ranges pass (exit 0), and an empty obligation set (non-code, non-doc range) passes through both the untampered and the tampered gate without tripping the floor — the `[ ${#obliged_agents[@]} -gt 0 ]` guard is what keeps the tamper detector from false-blocking a range that obliged nothing. **No dodge through the conversions was found**: empty `required-agents` output produces an empty array (the `[ -n "$a" ]` filter drops the herestring's phantom empty line — demonstrated, count 0, no `set -u` trip on bash 5.3, and `"${arr[@]}"` on an empty array is safe on every bash ≥ 4.4, so CI's runner is fine too); a trailing newline is normalized by command substitution before the herestring re-adds exactly one; and hostile member shapes (a glob `sec*` beside matching files, a name with spaces, an embedded blank line) come through the new loop exactly as emitted where the old unquoted `for agent in $obliged` demonstrably expanded the glob against the cwd and split the spaced name into three. **The array forms change no behavior for any real input**: old (HEAD) and new `required-agents` produce byte-identical output and exit status across a no-trigger range, docs-only, code-only, code+docs, and working-tree mode with a D-heading active plan (`/simplify docs-updater security spec-check`, in order); the only divergences are for glob/space member names that cannot currently exist, and each diverges in the strengthening direction F65 named. The F64 comment's fatality argument was checked against the actual trigger sets: in range mode (the only mode plan-gate uses) the possible obliged sets are {}, {docs-updater}, and {/simplify, security, docs-updater}, so every non-empty set contains a stampable agent and the floor cannot false-block today; the /simplify-only caveat is correctly recorded as fix risk in F64's entry. The F61–F65 resolution markers were verified against the shipped diffs and none misstates behavior — F64's marker says "counts" where the code short-circuits a boolean, but the claim that matters (blocks when the range obliged agents and none was stampable; tamper repro exits 1; missing-stamp control still blocks) is exact and was re-reproduced here. Two non-findings for the record: the "no Plan: trailers — nothing to gate" early exit means the drift floor does not run on a non-citing range, which is the gate's documented pre-existing scope (the drift is caught on the next citing range); and all four stamps written during the F61–F65 resolution work carry no `(code ...)` field because the live SubagentStop hook is still merged master's pre-fingerprint copy — the expected state for an unmerged hook, and the resulting legacy-NOTE behavior is exactly what F12 already records. The live worktree runs stay green: `required-agents` emits the correct ordered set in both modes and `plan-gate origin/master HEAD` exits 0 with the two expected legacy NOTEs. Nothing in the delta adds anything but exit-1 paths to plan-gate; no NixOS module, firewall rule, systemd unit, user, capability, or `sops.secrets` reference is touched. No secret was decrypted or read, and no file outside this plan was modified.

_security finished 2026-09-07T04:45:45Z -- see Findings above._
