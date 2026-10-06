---
slug: manage-a-user-level-claude-md-declaratively-with-cross-project
created: 2026-10-06
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# Manage a user-level CLAUDE.md declaratively with cross-project working lessons

## State

Todo, nothing built. The content is decided in principle: **only the two
lessons**, the five steps and the doghouse check (user, 2026-10-06). See
"Draft content, revised". D1–D3 are proposals, not yet answered.
`~/.claude/CLAUDE.md` currently exists on torrent as an empty, unmanaged file
(G1).

## Original plan

**Owner:** the user, 2026-10-06 ("save the lessons learned … somewhere more
permanent, maybe a plan to add this as a declarative config memory for Claude
under NixOS home manager").

**Why:** the working lessons from the agent-sandbox design discussion
(2026-10-05/06, `~/Projects/agenticsandbox/`) apply to every project, not just
dotfiles. Today they live only in this repo's Claude auto-memory, which is
scoped per project (G2). A session in any other repo, or in the planned agent
user's place, never sees them. `~/.claude/CLAUDE.md` is the user-level
instructions file Claude Code loads in every project.

**What:** home-manager manages `~/.claude/CLAUDE.md` from a markdown file in
`modules/home-manager/claude-code/`, next to the existing `home.file` entries
(statusline, tcr skill). The content is short: the lessons below, each a few
lines.

**Out of scope:**
- migrating every dotfiles memory (most are repo-specific and belong in
  AGENTS.md/docs/);
- managing the memory directories themselves;
- the agent user's own config (stage 1 of the sandbox, G3).

### Draft content

> **The real goal is the work.** The goal is learning and research, a fleet that
> quietly serves me, and finished projects. Tools, sandboxes, workflow systems
> and orchestrators are means (the doghouse, not the dog owner). Before adding a
> part, ask whether it serves the work or only the thing being built. Where the
> work needs nothing built, build nothing.
>
> **Five steps, in order:**
> 1. Every requirement names its owner, Claude's included. Question it.
> 2. Delete parts and process; if nothing is ever added back, too little was
>    deleted.
> 3. Simplify what's left.
> 4. Speed up the cycle.
> 5. Automate last.
>
> **Problem before solution.** State the goal and what I actually do. Rate the
> real threats or problems by likelihood × impact for me. Then propose the
> fewest controls that cover them.
>
> **Friction is a cost.** Prefer hard boundaries over procedural gates and
> rules. Process I built to make agents safe once stopped me more than it
> stopped them.
>
> **Agents are untrustworthy, and the agent is never me.** Non-sensitive work
> (undoable or public-tolerant): agents work alone, without prompts. Sensitive
> work (secrets, private data, root, deploys, irreversible actions, acting as
> me): only with me present. Work crosses the line only when I pull it.

~~The five-lesson draft above.~~ 2026-10-06: the user named the SpaceX
engineering rules and the doghouse as **the two most important lessons**.
Applying step 2 to the draft deleted the other three: "problem before
solution" is step 1 plus the doghouse check, "friction is a cost" is step 2,
and "the agent is never me" is a design decision for the sandbox project, not
a working lesson (it lives in `~/Projects/agenticsandbox`).

### Draft content, revised

> **The real goal is the work (the doghouse check).**
> - The real goal is learning and research, a fleet that quietly serves me,
>   and finished projects.
> - Projects go doghouse → moonbase when the real goal isn't solid and the means
>   becomes the goal. The builder forgot that the point was to be a good dog
>   owner.
> - Before adding any part, check one level above the thing being built: does
>   this serve the work, or only the doghouse?
> - Where the work needs nothing built, build nothing.
>
> **Five steps, in order (SpaceX's engineering rules):**
> 1. **Make the requirements less dumb.** Every requirement names the person
>    who made it, never a department or "best practice". Question it however
>    smart the source is, Claude's own requirements included.
> 2. **Delete the part or process.** If nothing is ever added back (~10%), too
>    little was deleted. Give each deletion an add-back trigger.
> 3. **Simplify and optimize** only what survived. Don't optimize what shouldn't
>    exist.
> 4. **Speed up the cycle.**
> 5. **Automate last.** Automating a process that shouldn't exist is the most
>    common mistake.

~~"Draft content, revised" above.~~ 2026-10-06: superseded after two
cold-read tests. A fresh agent was given only the two lessons and five
scenarios (an explicit small edit, a process-heavy request, an annoying
existing repo rule, a design task, reviewing someone else's design).
- **Round 1:** "mostly". It might delete or skip repo rules unprompted,
  second-guess explicit requests, and read "automate last" as "make backups
  manual".
- **Round 2,** after scope and limits were added (deleting means proposing;
  repo rules and explicit requests still bind; automating process vs. the
  deliverable): every scenario was handled correctly. The last one-line gaps
  were then fixed ("once per task"; untraced requirements are still followed;
  "hard boundary" isn't a reason to add a control; others' projects use their
  own goal).

**The content is now the bodies of the two memory files**
(`feedback_five_step_algorithm.md`, `feedback_doghouse_dog_owner.md`), without
frontmatter and `[[links]]`. Copy them at implementation time; don't maintain a
second draft here. Re-run the cold-read check if they change.

Source of the reasoning: `~/Projects/agenticsandbox/` (`README.md`,
`ENGINEERING-RULES.md`, `DECISIONS.md` D16–D21).

## Progress

- [ ] D1 -- where the content lives
- [ ] D2 -- read-only symlink, not a writable copy
- [ ] D3 -- what happens to the duplicate memories
- [ ] G1 -- an empty unmanaged `~/.claude/CLAUDE.md` already exists
- [ ] build torrent and thinkpad
- [ ] user switches; a session in a non-dotfiles project shows the lessons in context

## Decisions (D)

### D1 -- where the content lives

Proposal: a plain `user-claude.md` in `modules/home-manager/claude-code/`,
wired with `home.file.".claude/CLAUDE.md".source`. import-tree only loads
`.nix` files, and that directory already holds non-Nix content
(`tcr-skill/reference.md`). Alternative: an inline `text = ''…''`, which is
harder to read and edit.

### D2 -- read-only symlink, not a writable copy

Proposal: a plain `home.file` store symlink, read-only. Edits go through the
repo, which is the point of declaring it. Cost: Claude Code's in-session
shortcuts for editing user memory (`#` / `/memory` on the user file) would fail
on a read-only file. Alternative: an activation-time copy like the
`settings.json` merge in the same module, which is writable but drifts.

### D3 -- what happens to the duplicate memories

Proposal: once the file lands and is confirmed loaded, delete the dotfiles
memories it duplicates (`feedback_doghouse_dog_owner.md`,
`feedback_five_step_algorithm.md`, `feedback_problem_before_solution.md`,
`feedback_friction_kills_work.md`), keeping one pointer. This follows "docs
over memory": a fact lives in one place.

2026-10-06 (user: "apply the two most important rules to everything in the
memories … repo specific stuff should live in the repo"): done ahead of the
file landing. Memory went from 25 files to 11.
- **Deleted as repo-specific and already codified:** build-before-commit
  (`docs/GIT_WORKFLOW.md`), test-don't-switch (`AGENTS.md`), pull-before-branching
  (the `fresh-branch-guard` hook), secrets, debug-tools, plan tracking, verifying
  against pinned nixpkgs (`docs/architecture.md`, `docs/procedures/testing-changes.md`),
  ZFS snapshot recovery (`docs/procedures/workflow.md`).
- **Moved into the repo:** statix organization → `docs/style-guide.md`; landing
  stale branches → `docs/GIT_WORKFLOW.md` (marked to die with the frozen-plan
  hook); findings blocked on agent separation stay open → `docs/accepted-risks.md`.
- **Folded into the two core lessons:** "friction kills work" and "problem
  before solution".

The 11 remaining memories are cross-project. They are this plan's content
once it lands.

## Gotchas (G)

### G1 -- an empty unmanaged `~/.claude/CLAUDE.md` already exists

0 bytes, dated 2026-10-04, on torrent. home-manager refuses to replace an
unmanaged file unless it's removed or a backup extension is configured. Remove
it right before the switch (it's empty, so nothing is lost). Check thinkpad too.

### G2 -- Claude auto-memory is per project

The memory directory is `~/.claude/projects/-home-lilijoy-dotfiles/memory/`,
keyed by working directory. Lessons saved there are invisible to sessions in
other repos. This is the actual reason for this plan, not tidiness.

### G3 -- the planned agent user won't see this file

Stage 1 of the agentic sandbox (`~/Projects/agenticsandbox/notes/stage-1-agents-place.md`)
adds a separate Unix user with its own `~/.claude`. If that user's home is
managed by home-manager, it can import the same file; otherwise its sessions
won't get the lessons. Decide there, not here.

## Findings (F)
*(populated by security/docs-updater when invoked)*
