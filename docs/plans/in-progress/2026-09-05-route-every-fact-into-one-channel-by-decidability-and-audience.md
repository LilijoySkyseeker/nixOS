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

Next takeable: child 3, child 6, child 2, or child 8. Child 3 is the
smallest; child 6 turns child 4's table into an actual gate and is the
natural follow-on.

Caveat on this branch's own compliance: `required-agents` names
`docs-updater` and `spec-check` for this diff, and neither was run —
`spec-check` does not exist yet (child 8), and subagents were out of
scope for the session that wrote this. Child 6 is what makes that
omission impossible rather than merely recorded.

**Verified to rung 4 (VM).** `verify-ladder` passes, and
`nix build .#checks.x86_64-linux.zrepl-replication` booted both VMs and
produced `vm-test-run-zrepl-replication`. Not deployed to any host, and
nothing here needs a switch.

Blocked on nothing. The frontier is children 1-5 in Progress.

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
- [ ] 3. verification ladder split — evidence ladder vs deploy sequence
      — see D6

Blocked:

- [ ] 2. plan-file layout revision — `## State` first, three frontmatter
      fields, defect G-to-F reclassification — blocked by 5, see D4
      and G6
- [ ] 6. `plan-gate` requires the `docs-updater` stamp — blocked by 4
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

## Findings (F)
*(populated by security/docs-updater when invoked)*
