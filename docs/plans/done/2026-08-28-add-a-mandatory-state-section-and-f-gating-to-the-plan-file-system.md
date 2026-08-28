---
slug: add-a-mandatory-state-section-and-f-gating-to-the-plan-file-system
created: 2026-08-28
status: done
frozen: true
---

# Add a mandatory State section and F-gating to the plan-file system

## State
Done -- State section and F-gating shipped in plan-new/lib.sh/plan-freeze/
plan-move/plan-resolve, all four gating scripts live-tested end-to-end
against a scratch plan (State-missing refusal, F-unresolved refusal,
successful plan-resolve + plan-move to done/, in that order). Docs
(SKILL.md, reference.md, security-audit/SKILL.md) updated and confirmed
accurate by docs-updater (clean, no findings). F-scheme collision (G29)
resolved via provenance-citation convention, no renaming of existing
F-P<n>-NN citations. verify-ladder passes (nix flake check needed one
retry after an unrelated stale-store-path hiccup, unconnected to this
change -- no .nix files touched). All four decisions ANSWERED, Findings
(F) section empty (docs-updater raised nothing). Ready to move to done/.

## Original plan

Rework the plan-file system (docs/skills/plan/) so a plan shows its
current state, not just an append-only history a cold reader has to
reconstruct, and so security/doc findings block closing a plan the same
way unresolved decisions already do. Full design context: a user design
conversation that reviewed the current plan-skill contract, all existing
plan files, the security-audit branch's hand-rolled `RESUME.md` (the
precedent for a rewritten "current state" block), and the repo's own
`docs/plans/todo/2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md`
catalog (specifically G29, the F-scheme collision this also resolves).

## Progress

- [x] `## State` section added to plan-new's template, and gated on by
      plan-freeze/plan-move (D1)
- [x] F-gating added: plan-resolve script, FIXED/ACCEPTED/MOOT states,
      gated on by plan-freeze/plan-move (D2)
- [x] F-scheme collision (task-local F<N> vs fleet F-P<n>-NN) resolved via
      documented provenance-citation convention, not a rename (D3)
- [x] SKILL.md and reference.md updated to document all of the above
- [x] docs/skills/security-audit/SKILL.md Phase 4 updated with the
      provenance-citation convention
- [x] verify-ladder passes
- [x] docs-updater invoked and clean (or findings resolved)

## Decisions (D)

### D1 -- should the `## State` section be mandatory on every plan, or opt-in for plans that outgrow a single session?

**ANSWERED 2026-08-28:** Mandatory on every plan. A single consistent shape is worth the small amount of boilerplate on trivial plans (one line is enough there); opt-in would have meant deciding case-by-case which plans 'count', which is exactly the kind of judgment call this system prefers to hardcode instead.

### D2 -- should Findings (F) block a plan reaching done/ the same way unresolved Decisions (D) do?

**ANSWERED 2026-08-28:** Yes, gated on F the same way D is gated -- FIXED, ACCEPTED, or MOOT (new third state, not just fixed/accepted) so a finding whose target code was simply removed doesn't need a contrived 'accepted' framing.

### D3 -- should the task-local `F<N>` and fleet-wide `F-P<n>-NN` finding-id schemes be reconciled now, before F-gating ships, or left for later?

**ANSWERED 2026-08-28:** Resolved now. Existing F-P<n>-NN citations are not renamed (load-bearing elsewhere); going forward, an audit finding graduating into a plan gets a fresh plan-local F<N> that cites its fleet origin instead.

### D4 -- should the 18 pre-existing unfrozen plans be retrofitted with a State section now, or lazily on next substantive touch?


**ANSWERED 2026-08-28:** Lazily. Nothing retroactively edits the 18 existing unfrozen plans in this pass -- plan-freeze/plan-move enforce the State section only going forward, so each plan picks it up naturally the next time it's actually closed out.

## Gotchas (G)

### G1 -- a background-job session with a pinned cwd can't call EnterWorktree directly
The session driving this design conversation was itself a background job
with a cwd override, so its own `EnterWorktree` call failed
("cannot create a worktree from a subagent with a cwd override"). It also
briefly ran `plan-new`/`plan-move` in the shared checkout before
discovering this -- a live hit of the exact class of problem
`2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md`'s G37
already named (an untracked plan file stranded outside worktree
isolation). Recovered by discarding that copy and delegating the actual
implementation to a fresh subagent spawned with `isolation: "worktree"`,
which creates and enters its own worktree internally. Worth remembering:
`EnterWorktree` failing with a cwd-override error doesn't mean "continue
unsafely in place" is the only option -- spawning an isolated subagent is
often the correct next move instead.

## Findings (F)
*(populated by security/docs-updater when invoked)*

~~_docs-updater finished 2026-08-28T22:14:10Z -- see Findings above._~~
**2026-08-28:** the referenced "Findings above" don't exist -- struck
through as a stray, inaccurate auto-note. `docs-updater` was invoked
against `docs/skills/plan/SKILL.md`, `reference.md`, and the
`security-audit/SKILL.md` Phase 4 edit; verdict was clean, no
inaccuracies or staleness found against the actual script behavior. No
`### F<N>` findings were raised, so there is nothing for `plan-resolve` to
resolve -- the empty placeholder above stands.
