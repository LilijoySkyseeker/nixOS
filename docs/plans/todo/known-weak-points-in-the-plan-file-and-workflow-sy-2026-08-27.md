---
slug: known-weak-points-in-the-plan-file-and-workflow-sy
created: 2026-08-27
status: todo
frozen: false
---

# Known weak points in the plan-file and workflow system

## Original plan

User's explicit request after this session built and landed the plan-file/
workflow system (`establish-the-workflow-and-plan-file-system-2026-08-27.md`)
and then rebased it against 57 commits of drift
(`hardcode-pull-before-branching-as-a-hook-2026-08-27.md`): a single
running catalog of every weak point, gap, or improvement opportunity
noticed in the system itself so far — deliberately over-inclusive ("list
more than you think, I can always veto them later"), not a queue to work
through now. Nothing here is prioritized or scheduled; each item is just
recorded so it isn't lost. Cross-references three already-tracked plans
(`design-the-vm-testing-subagent-s-2026-08-27.md`,
`design-a-diff-scoped-linting-skill-or-subagent-2026-08-27.md`,
`resolve-whether-samba-s-var-lib-samba-persistence--2026-08-27.md`)
rather than duplicating them.

## Progress

Nothing here is scheduled. This section exists only so a future pass can
tick items off as they're picked up or explicitly rejected by the user —
every line below is currently unstarted.

- [ ] G1 — no `plan-find`/citation-resolver helper
- [ ] G2 — no index/dashboard view across all plans
- [ ] G3 — `plan-tick`'s ID matching is line-bound and fragile
- [ ] G4 — heading-regex mismatches fail silently with no linter
- [ ] G5 — no structural validator ("plan-lint") for a plan file
- [ ] G6 — near-duplicate plan detection is judgment-only, not hardcoded
- [ ] G7 — `subagent-stamp`'s `agent_type` allowlist is a hardcoded, easy-to-forget list
- [ ] G8 — host-build detection logic is duplicated between `pre-push` and `verify-ladder`
- [ ] G9 — no reverse index from a plan file to the commit(s) that landed it
- [ ] G10 — `docs/plans/.checksums` is a single shared file with no locking
- [ ] G11 — `plan-carry`/`plan-reject` default titles can collide after 50-char slug truncation
- [ ] G12 — no automated test suite for the plan/workflow scripts
- [ ] G13 — `plan-touch-guard` can't verify the *right* plan was touched, only *a* plan
- [ ] G14 — `footer-guard`'s pattern list isn't exhaustive
- [ ] G15 — `verify-ladder`'s diff-scoped lint precision silently degrades without `jq`
- [ ] G16 — diff-scoped line-range logic untested against renamed files
- [ ] G17 — `plan-new`'s 50-character slug truncation produces awkward, sometimes-ambiguous filenames
- [ ] G18 — `plan-reject`'s mandatory reason has no substance check
- [ ] G19 — no retention/archival story for `done/`/`rejected/` at scale
- [ ] G20 — `workflow`'s auto-invocation is inherently unreliable, and nothing gates *mid-task* drift before a commit is attempted
- [ ] G21 — every hook in this system is bypassable (`--no-verify`, direct payload crafting) by design, not just in theory
- [ ] G22 — `security`/`docs-updater` both hold `Bash`, which can fully defeat a "read-only" intent at the tool-restriction level
- [ ] G23 — no verification that a subagent actually stayed in its intended scope
- [ ] G24 — `mark-trivial` has no usage audit trail; nothing stops it being used as a blanket bypass
- [ ] G25 — `.claude/.active-plan`/`.trivial-ack` are single-slot markers; concurrent plans/subagents in one session can cross-contaminate
- [ ] G26 — no recovery ("plan-doctor") for a plan left mid-operation by an interrupted `plan-freeze`/`plan-move`
- [ ] G27 — the whole system exists on one unpushed/unmerged branch; multi-machine drift risk until it lands
- [ ] G28 — no CI validation independent of local hooks
- [ ] G29 — `security` subagent vs. the landed `docs/skills/security-audit/` skill: overlapping domain, unreconciled, incompatible ID schemes
- [ ] G30 — `docs/agents/security/reference.md` is a copied/adapted rubric, not single-sourced from the audit's own reference material
- [ ] G31 — no repo-wide citation-integrity checker confirming every bare-filename citation actually resolves
- [ ] G32 — no chain-of-custody view for multi-hop `plan-carry`/supersession chains
- [ ] G33 — `hook-lib.sh`'s no-`jq` awk fallback path has never actually been exercised
- [ ] G34 — see `design-the-vm-testing-subagent-s-2026-08-27.md` (tabled separately)
- [ ] G35 — see `design-a-diff-scoped-linting-skill-or-subagent-2026-08-27.md` (tabled separately)
- [ ] G36 — see `resolve-whether-samba-s-var-lib-samba-persistence--2026-08-27.md` (tabled separately)
- [ ] G37 — `workflow`'s step sequence has no guidance for validating an unmerged branch on a live target host without building on that host

## Decisions (D)

## Gotchas (G)

### G1 — no `plan-find`/citation-resolver helper
Resolving a bare-filename citation today means `git grep -rl '<name>.md'`
or an editor's quick-open — both work, but there's no dedicated script a
subagent or a human could call. A `plan-find <slug-or-partial>` that
prints the current full path (and errors clearly on zero/multiple matches,
reusing `plan_locate`'s existing logic from `lib.sh`) would make citation
resolution a first-class, scriptable operation instead of "grep it
yourself."

### G2 — no index/dashboard view across all plans
Explicitly considered and dropped early in this session's design
(physical folders were judged to solve "browse by status" well enough).
With real volume now (12 `todo/`, 6 `in-progress/`, 24+ `done/` after one
session), a generated `docs/plans/INDEX.md` or a `plan-list [--status X]`
script might earn its place — worth revisiting once the count grows
further, not because the original call was wrong at the time.

### G3 — `plan-tick`'s ID matching is line-bound and fragile
`plan-tick` greps for the ID token on the *same line* as the `- [ ]`
marker. A wrapped multi-line bullet whose ID citation lands on a
continuation line fails to match with no clear hint why, until the wording
is manually reflowed — hit twice for real in this session's own meta plan
(`G7`/`D14` references). No `--line <N>` fallback exists despite being
considered during design.

### G4 — heading-regex mismatches fail silently with no linter
`plan-decide`/`plan-carry`/`plan-tick` all match `### D<N>`/`### G<N>`
headings via a fairly strict regex. A typo (inconsistent dash style, "###
Decision 1" instead of "### D1", a missing space) makes the script die
with "no heading found" — correct behavior, but there's no proactive way
to catch a malformed heading *before* that point except hitting the error.

### G5 — no structural validator ("plan-lint") for a plan file
Nothing checks that a plan file's frontmatter is well-formed, that D/G/F
IDs are sequential without gaps or duplicates, that every ID referenced
from a Progress checkbox actually exists as a heading, or that the four
required `##` sections are all present. Every plan file produced so far is
correct by construction (via the scripts) or careful hand-authorship, not
by any automated check.

### G6 — near-duplicate plan detection is judgment-only, not hardcoded
`plan-new` refuses an *exact* slug collision only. A near-duplicate title
(different wording, different slugification) silently creates a second,
redundant plan. `workflow/reference.md` tells the agent to grep first, but
that's pure convention — the exact category of rule this session's own
"hardcode with scripts" tenet says shouldn't be left to memory.

### G7 — `subagent-stamp`'s `agent_type` allowlist is a hardcoded, easy-to-forget list
`subagent-stamp` only stamps when `agent_type` is exactly `security` or
`docs-updater` (a `case` statement). Adding a third reviewing subagent
later requires remembering to update this hook; there's no dynamic
discovery from `.claude/agents/*.md`'s actual frontmatter names.

### G8 — host-build detection logic is duplicated between `pre-push` and `verify-ladder`
Both `.githooks/pre-push` and `docs/skills/workflow/scripts/verify-ladder`
independently re-implement "which hosts does this change affect" (diff
changed paths against `hosts/<name>/`, `modules/`, `flake.nix`/`flake.lock`,
loop over `hosts/*`). A future change to this logic (e.g. adding a new
shared path prefix) has to be made in both places or they drift apart
silently.

### G9 — no reverse index from a plan file to the commit(s) that landed it
The `Plan: <file>.md` commit trailer (decision 9 in the meta plan) lets a
commit point *at* a plan, but nothing records the reverse — which
commit(s) actually closed a given plan. Answering "what commit fixed this"
today means `git log --grep` against the plan's filename by hand.

### G10 — `docs/plans/.checksums` is a single shared file with no locking
`plan_do_freeze` does a read-modify-write on one shared manifest file with
no locking. Two sessions freezing different plans at the exact same
moment could race (lost update). Low likelihood for a single-user repo,
but a real latent bug, not a hypothetical one.

### G11 — `plan-carry`/`plan-reject` default titles can collide after 50-char slug truncation
`plan-new`'s slugify caps at 50 characters. A long default title (e.g.
`plan-carry`'s auto-generated "follow-up: <original-slug> D<N>") can
truncate into an unexpected or colliding slug for a sufficiently long
original name — untested against this edge case.

### G12 — no automated test suite for the plan/workflow scripts
Every script (`plan-*`, the four hooks, `verify-ladder`) was verified this
session via extensive, careful, but entirely manual/ad hoc Bash testing —
thorough in the moment, not regression-proof. `tcr-skill` has
`tests/run-fixture-tests.sh`; nothing equivalent exists yet for `plan`/
`workflow`, so a future edit to `lib.sh` could silently break `plan-decide`
with no automated signal.

### G13 — `plan-touch-guard` can't verify the *right* plan was touched, only *a* plan
Documented as a known, accepted limit already (`workflow/reference.md`,
"Why a hook at all"), restated here for the consolidated list: the hook
only checks that *some* `docs/plans/` file was touched this session. It
cannot detect "this commit's actual content has nothing to do with the
plan file that satisfied the gate."

### G14 — `footer-guard`'s pattern list isn't exhaustive
Matches specific known phrasings (`Co-Authored-By: Claude`,
`Claude-Session:`, `Generated with Claude Code`, a robot emoji). A
differently-worded AI-attribution line ("Written with AI assistance", a
different tool's footer format) would not be caught.

### G15 — `verify-ladder`'s diff-scoped lint precision silently degrades without `jq`
If `jq` isn't on `PATH` (e.g. outside the nix devshell), the script falls
back to whole-file, non-blocking, informational-only statix/deadnix output
— strictly weaker than the normal diff-scoped hard gate — with only a
printed note, easy to miss in a wall of build output.

### G16 — diff-scoped line-range logic untested against renamed files
`verify-ladder`'s `changed_lines` helper parses `git diff -U0 HEAD`
hunk headers. Never exercised this session against a renamed `.nix` file
(`git mv` + edits) — `git diff`'s hunk output for a rename-with-changes
case wasn't specifically verified to behave as expected.

### G17 — `plan-new`'s 50-character slug truncation produces awkward, sometimes-ambiguous filenames
Visible in this session's own output: `resolve-whether-samba-s-var-lib-
samba-persistence--2026-08-27.md` is visibly cut off mid-word. Not
currently a collision risk (the date suffix still disambiguates in
practice), but the truncation point is arbitrary and can make a filename
citation less self-descriptive than intended.

### G18 — `plan-reject`'s mandatory reason has no substance check
The gate is "non-empty string." A one-word reason ("no", "abandoned")
satisfies it exactly as well as a real explanation. No minimum-length or
content heuristic exists, nor was one considered necessary at design time
— flagging as a possible future tightening, not a confirmed problem.

### G19 — no retention/archival story for `done/`/`rejected/` at scale
Both folders grow unboundedly with no compaction, indexing, or search
tooling beyond `grep`/`ls`. Fine at current volume (24 `done/` after one
session); unclear how this ages over years of use.

### G20 — `workflow`'s auto-invocation is inherently unreliable, and nothing gates *mid-task* drift before a commit is attempted
Confirmed via this session's own research: skill auto-invocation is
documented as missing roughly half the time when it overlaps a trained
behavior. The *only* hard backstop is the commit-time hook, which fires
at commit time — it does nothing to catch a session doing a large amount
of non-trivial, ungated work *before* ever attempting a commit (e.g. a
long exploratory session that's abandoned without committing never
touches the gate at all).

### G21 — every hook in this system is bypassable by design, not just in theory
`git commit --no-verify` skips the git-level hooks; a sufficiently
sophisticated or careless agent session could in principle craft tool
calls that don't trigger `PreToolUse` matching, or a differently-configured
harness might not load `.claude/settings.json` hooks at all. This mirrors
`tcr-guard-hook`'s own documented "best-effort deterministic guard, not a
sandbox" caveat — worth stating explicitly for this system too rather than
leaving it implicit.

### G22 — `security`/`docs-updater` both hold `Bash`, which can fully defeat a "read-only" intent at the tool-restriction level
This is the sharpest one on this list. `security`'s frontmatter omits
`Edit`/`Write` specifically to enforce read-only behavior, but its `tools:`
list includes `Bash` — and Bash can trivially write files (`cat > file`,
`sed -i`, redirection) with no tool-level distinction between "read-only"
and "destructive" shell commands. The read-only guarantee for `security`
today rests entirely on the system prompt's instructions ("never edit
anything"), the same prompt-level trust the audit's own subagent brief
already relied on — not on any tool-level enforcement, despite `tools:`
being confirmed as real, tool-*name*-level enforcement. A determined or
confused subagent (or a successful prompt injection targeting it) could
write files via Bash and the harness would not stop it.

### G23 — no verification that a subagent actually stayed in its intended scope
Nothing checks after the fact that `security`'s live test run, for
example, only read the files it was told to scope to. Reliance is entirely
on the prompt's stated scope plus the subagent's own good-faith behavior
(confirmed reasonable in this session's live tests, but not mechanically
verified).

### G24 — `mark-trivial` has no usage audit trail; nothing stops it being used as a blanket bypass
The marker file is overwritten each time, not appended/logged. There's no
way to look back later and ask "how often was the triviality exemption
actually used, and were those calls actually trivial" — the one
deliberately judgment-based step in the system has zero retrospective
visibility.

### G25 — `.claude/.active-plan`/`.trivial-ack` are single-slot markers; concurrent plans/subagents in one session can cross-contaminate
If a session is genuinely working across two plans at once (plausible —
this session itself ran two subagents in parallel against one shared
active plan deliberately), the single global marker means a `SubagentStop`
stamp could land on whichever plan happened to be "active" at that moment,
not necessarily the one the finishing subagent was actually working
against.

### G26 — no recovery ("plan-doctor") for a plan left mid-operation by an interrupted `plan-freeze`/`plan-move`
If a session crashes between the `git mv` and the frontmatter/checksum
update inside `plan-move`/`plan-freeze`, a plan file could be left in an
inconsistent state (wrong folder vs. wrong `status:` field, or missing a
checksum entry) with no dedicated repair tool — `scripts/claude-links-check
--fix` has an analog for symlinks; nothing equivalent exists for plan-file
state.

### G27 — the whole system exists on one unpushed/unmerged branch; multi-machine drift risk until it lands
This repo is edited from multiple machines. Until this branch is merged,
any other machine/session still uses old TODO.md-based conventions (which
no longer exist once this branch lands) or, worse, could independently
reintroduce TODO.md-shaped content that needs yet another reconciliation
pass — exactly the shape of problem this session's own rebase just went
through once already.

### G28 — no CI validation independent of local hooks
This repo has no CI configured. All of this session's new mechanical
guarantees (`claude-links-check`, `verify-ladder`, the frozen-file check)
run only as local git hooks, which depend on the dev shell being entered
and hooks being installed (`core.hooksPath`) — a clone that skips that
setup step gets none of these guarantees enforced.

### G29 — `security` subagent vs. the landed `docs/skills/security-audit/` skill: overlapping domain, unreconciled, incompatible ID schemes
Discovered only during the rebase: `docs/skills/security-audit/` is now a
real, landed skill (fleet-wide multi-agent audit, `F-P<n>-NN` finding IDs),
coexisting with this session's own `security` subagent (per-task,
`F<N>` finding IDs local to one plan file). No doc explains when to reach
for which, and the two ID schemes don't cross-reference each other at all.

### G30 — `docs/agents/security/reference.md` is a copied/adapted rubric, not single-sourced from the audit's own reference material
Harvested deliberately (per the user's own instruction) from
`docs/skills/security-audit/reference/{finding-schema,subagent-brief}.md`,
but as a narrowed copy, not a shared include. If the audit's own
methodology improves later, this copy won't inherit the update
automatically — a duplication-drift risk, not yet a real divergence.

### G31 — no repo-wide citation-integrity checker confirming every bare-filename citation actually resolves
Proposed early in this session's design (a "citation integrity" skill),
never built. Nothing currently scans the whole repo for citation-shaped
strings (`<slug>-<date>.md`) and confirms each one resolves to a real file
under `docs/plans/` — a citation could go stale (its target renamed or
deleted outside the normal scripts) with nothing catching it.

### G32 — no chain-of-custody view for multi-hop `plan-carry`/supersession chains
A deferred decision can be carried into a new plan, which can itself later
defer-and-carry again. Nothing visualizes or validates that such a chain
terminates rather than looping, or makes it easy to walk the full history
of "this idea started here and is now tracked over there."

### G33 — `hook-lib.sh`'s no-`jq` awk fallback path has never actually been exercised
Copied from `tcr-guard-hook`'s proven pattern, but this session's actual
environment always had `jq` present — the awk-only JSON extraction
fallback (`hook_extract_top`/`hook_extract_obj`) has never been run for
real here, only inherited on faith from the tcr precedent.

### G37 — `workflow`'s step sequence has no guidance for validating an unmerged branch on a live target host without building on that host
Surfaced 2026-08-28 while deploying a fix for
`homelab-zdata-pool-usb-uas-checksum-errors-2026-08-28.md`: the user
wanted PR #26 (a `hosts/homelab/configuration.nix` change) actually
verified live on `homelab` *before* merging, rather than trusting
`nixos-rebuild build` alone. The obvious-looking move — fetch the branch
into the target host's own `/etc/nixos` checkout and run `nixos-rebuild
build --flake .#<host>` there over SSH — was corrected by the user:
don't build on the target host itself, since it's a live
storage/service host and a full Nix evaluation+build burns its own
CPU/IO for no benefit when a separate build machine exists. The `workflow`
skill's step sequence (`docs/skills/workflow/SKILL.md`) covers triviality
check → plan → work → `verify-ladder` → commit, but says nothing about
*this* shape of task — validate an unmerged change on a specific host
before merging — and there's no equivalent of
`modules/nixos/push-deploy.nix`'s pattern (which only fits the opposite
direction: homelab, the more capable build host, building *for* vps) for
"build here, deploy/activate on `<host>`, don't build there." The correct
manual incantation is
`nixos-rebuild switch --flake .#<host> --target-host root@<host>` alone --
~~`--build-host localhost` required since `--target-host` alone builds
remotely by default~~ **CORRECTED 2026-08-28:** verified via
`nixos-rebuild --help`: "If `--build-host` is not explicitly specified or
empty, building will take place locally" -- i.e. `--target-host` alone
already builds locally and only activates remotely; the opposite of what
was first assumed here. Still had to be re-derived/verified in the moment
rather than looked up. Worth a named convention or helper script in
`docs/procedures/` — and/or a `workflow` step — for "validate a branch on
a real host pre-merge," so this doesn't need re-deriving next time.

**2026-08-28 addendum:** user's suggested shape for the fix — deploying
(build-here/activate-there, per-host target selection, the
`--build-host`/`--target-host` incantation, pre-merge validation vs. real
merge-and-adopt) should be its own dedicated skill, the same way `plan`
and `workflow` are, rather than logic re-derived ad hoc each time or
buried inside `workflow`'s existing step sequence. Would give this a
proper home instead of a footnote on `workflow`.

### G34, G35, G36 — already tracked as their own separate plans
Listed here only as an index pointer, not duplicated: VM-testing's
subagent shape (`design-the-vm-testing-subagent-s-2026-08-27.md`), a
generalized diff-scoped-linting skill
(`design-a-diff-scoped-linting-skill-or-subagent-2026-08-27.md`), and the
unresolved samba persistence conflict
(`resolve-whether-samba-s-var-lib-samba-persistence--2026-08-27.md`).

## Findings (F)
*(populated by security/docs-updater when invoked)*
