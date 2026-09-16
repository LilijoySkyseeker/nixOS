---
slug: codify-that-subagents-and-the-full-toolset-are-allowed-in-this-repo
created: 2026-09-16
status: in-progress
frozen: false
kind: task
priority: normal
blocked_by:
---

# codify that subagents and the full toolset are allowed in this repo

## State

Docs-only. Both sections written, `verify-ladder` green, review subagents
run (F-section). Nothing deployable here.

## Original plan

While fixing the printer (`2026-09-16-ensure-printers-fails-every-boot-on-torrent-undeployed-fix-plus-no.md`)
the session's harness carried a default of *"don't call subagents unless
the user requested it."* The repo's own `workflow` gate mandates four
review subagents at step 6, so that default silently cost a change its
review gate. The user asked for the permission to be written down so it
stops recurring.

Work:

- `AGENTS.md`: a standing grant, shaped like the existing "You have real
  SSH access" section, scoped so it can't be read as permission to *act*
  (D2).
- `docs/agents.md`: why a repo file can grant this at all without
  pretending to override a system prompt (D1).

## Progress

- [x] `AGENTS.md` — "You may use subagents and every tool you have"
- [x] `docs/agents.md` — how the grant actually works
- [x] `verify-ladder`
- [x] Review subagents (the first change in this repo to actually get them)

## Decisions (D)

### D1 -- framed as satisfying a condition, not as an override

The user's words were "add an override to AGENTS.md." Written literally
that would be a file instructing agents to disregard their system prompt,
which is both ineffective (harness instructions outrank project files)
and bad shape — an agent that honored it would be broken more generally
than the problem being solved.

The defaults in question are not prohibitions. They read "don't use
subagents **unless the user requested it**" — default-off with a
user-supplied override already built in. `AGENTS.md` is authored by the
user and loaded at session start, so a standing request there is a real
instance of the condition being met. Same practical effect, no fiction.

Told the user this before writing. They had also already unblocked the
current session just by asking.

### D2 -- grants tools, explicitly not actions

The request said "all tools available to the agent are allowed," which a
future agent could read as blanket license — including `nixos-rebuild
switch` on torrent, which is precisely the hard-confirm action left
pending on the printer plan at the moment this was written.

So both sections state the split outright: the grant covers which tools
an agent may pick up, never which actions it may take, and the
hard-confirm rules bind a subagent exactly as they bind its caller.
Delegation is not laundering. This is narrower than the literal ask;
flagged to the user rather than done silently.

## Gotchas (G)

### G1 -- the grant can't reach unconditional rules, only conditional ones

Falls out of D1 and worth stating so the grant isn't stretched later. It
works on defaults whose stated condition is user consent. It has no
purchase on anything unconditional — a harness safety rule, or this
repo's hard-confirm actions, which are *stricter* than the harness
default and are the user's own standing instruction not to act. Writing
"and also switch freely" into `AGENTS.md` would not work the way this
does.


## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 -- `AGENTS.md` trimmed to the grant plus its scope; the rationale moved to `docs/agents.md`

User ruling during the docs review: the "why" does not belong in
`AGENTS.md`. The paragraph beginning *"That matters because the `workflow`
skill's step 6 requires review subagents..."* (AGENTS.md:77-81 as written)
was rationale, and `docs/agents.md`'s last paragraph already covered the
same ground, so it was folded in there rather than duplicated. What stays
in `AGENTS.md` is the grant itself and the scope limit, which is a rule,
not rationale. The section is now two short paragraphs, sized like the
neighbouring "You have real SSH access", and the bar in
`docs/procedures/updating-documentation.md` for that file ("if a change
needs more than a couple of sentences to explain, that detail belongs in
`docs/` with a link") is met rather than stretched.

Also dropped from `AGENTS.md`: the framing clause *"Scope, so this isn't
read wider than it is:"*, which narrated the author's intent instead of
stating the rule. The rule now leads: "The grant is tool use, not
permission to act."

### F2 -- "requires"/"mandates" review subagents contradicted ADR-0002's advisory model

`AGENTS.md` said step 6 *requires* review subagents and `docs/agents.md`
said the `workflow` gate *mandates* them. Neither matches the current
system: `docs/skills/workflow/reference.md`'s "Subagent selection" states
"All of it is advisory (ADR-0002) ... nothing refuses a merge over whether
or when they ran," and `plan-gate` obliges no stamp. Step 6 tells the
agent to run them; nothing enforces it. Left as-is, the new sections would
have been the only place in the repo asserting a blocking review gate that
ADR-0002 deliberately dismantled.

Reworded in `docs/agents.md` to say step 6 has the agent run whatever
`required-agents` names, and that the failure is quiet *because* nothing
blocks on whether they ran -- which is the sharper point anyway, and the
reason the printer session's substitution went unnoticed.

### F3 -- "four independent reviews" was not a count the repo can deliver

`docs/agents.md` said a hand review got recorded "where four independent
reviews should have been." `PLAN_AGENT_ORDER` has four entries, but
`docs/skills/workflow/reference.md`'s table marks `spec-check` "Built?
not yet", and `.claude/agents/` contains only `docs-updater` and
`security`. At most three reviews were actually available on 2026-09-16.
Replaced the count with "the review agents", which stays true as the set
changes.

### F4 -- added the missing cross-reference at the point of failure

The grant lives in `AGENTS.md`, but the moment an agent hits the harness
default is step 6 of the `workflow` skill. Added one sentence to
`docs/skills/workflow/reference.md`'s "Subagent selection" (the section
step 6 points at) noting that a harness default against spawning
subagents is not a reason to skip them here, and naming the `AGENTS.md`
section. Nothing else in `docs/skills/workflow/`,
`docs/procedures/workflow.md`, or
`docs/procedures/updating-documentation.md` contradicts the new sections.

### F5 -- checked and deliberately left alone

- `AGENTS.md`'s "Where things live" row for `docs/agents.md` ("the
  reasoning *behind* the rules in this file and in
  `docs/procedures/workflow.md`") already covers the new section; no
  table edit needed, since no doc was added, moved, or removed.
- `plan-citations` reports the
  `2026-09-16-ensure-printers-fails-every-boot-on-torrent-undeployed-fix-plus-no.md`
  citation as broken from both `docs/agents.md` and this plan. Expected:
  that plan file exists on `worktree-printer-ensure-printers-retry`, where
  `### F1` is present and is the right anchor. The warning clears when
  that branch merges; the citation is correct and was not removed.

### F6 -- pre-existing, not fixed: `updating-documentation.md` points at a section that doesn't exist

`docs/procedures/updating-documentation.md:61-62` says `AGENTS.md` is
"a docs table plus the handful of rules that matter most (see
`docs/agents.md` for why it's kept this lean)". `docs/agents.md` has no
section explaining why `AGENTS.md` is kept lean. Predates this change and
is outside its scope, but it is adjacent enough to be worth naming: the
next edit to either file should either write that section or drop the
pointer.

_docs-updater finished 2026-09-16T21:04:18Z (code 0ac5a71fd5ba61fc) -- see Findings above._
