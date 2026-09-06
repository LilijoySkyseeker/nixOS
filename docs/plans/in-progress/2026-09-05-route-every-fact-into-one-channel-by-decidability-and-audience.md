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

### Pick-up point, 2026-09-06

**Where.** Worktree
`/home/lilijoy/dotfiles/.claude/worktrees/map-plan-docs-channel-routing`,
branch `worktree-map-plan-docs-channel-routing`, PR **#68**. Work there,
not in the main checkout. Everything below is committed and pushed.

**Done:** children 1, 4, 5, 6. G5, G6 closed. `security` ran once and
raised F1-F9, all nine now resolved. `/simplify` ran twice; both passes
applied. D11 answered and built.

**The immediate next step, and the only thing standing between this
branch and its own gate:**

1. Run `docs-updater` (subagent). The user authorised subagent use on
   2026-09-06.
2. Run `security` (subagent) *after* it -- that order is now mandatory,
   see D7's 2026-09-06 note and F2.
3. Apply anything either raises; an actionable finding restarts the loop
   at `/simplify`. Resolve every new `F<N>` with `plan-resolve`
   (`accepted` needs the user's own sign-off, never the agent's).
4. `docs/skills/workflow/scripts/plan-gate origin/master HEAD` must come
   back clean. It currently blocks on the missing `docs-updater` stamp,
   which is correct.

Do not hand-write a completion stamp. The `SubagentStop` hook writes it,
and forging one is F7.

**Then the frontier:** child 3 (verification-ladder split, smallest),
then 2 (plan-file layout -- unblocked now 5 has landed, and it must run
as expand-contract per G6, since 18 live `#G` citations break otherwise),
then 7, 8, 14.

**Live traps a new session will hit:**

- `plan-citations` and `plan-gate` are wired into `verify-ladder`, so a
  broken citation or a missing stamp blocks commits. That is intended.
- Editing `docs/skills/*/scripts/*` now obliges `/simplify`, `security`
  and `docs-updater` -- see `required-agents`.
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
