---
name: agent-config
description: Conventions for agent instructions and tooling on torrent. Use before creating or changing an AGENTS.md, AGENTS.local.md, skill, rule, hook or agent setting, in any repo or project, or when you find a CLAUDE.md.
---

# Agent configuration on torrent

Several agents (Claude Code, Codex, the local model in the Codex harness, and
any future one) share this environment, so every piece of guidance exists
once, under a tool-neutral name, where all of them find it.

## Names

- `AGENTS.md`: a repo's or project's instructions. Claude Code loads it
  itself where there is no `CLAUDE.md`; Codex loads it from the git root
  down to its working directory.
- `AGENTS.local.md`: untracked notes for a repo or project. Git ignores it
  everywhere (the user-wide ignore file). Neither tool loads it on its own,
  so read it when you start work there, and update it as you go.
- **Don't create a `CLAUDE.md`**, not even an `@AGENTS.md` import, and
  don't run `/init`, which writes one. A `CLAUDE.md` hides `AGENTS.md` from
  Claude Code.
- Keep a Claude-only name only where Claude requires it (`~/.claude/`,
  `.claude/settings.json`).
- In a repo of the owner's or yours that still has a `CLAUDE.md` or
  `CLAUDE.local.md`, propose moving it to the `AGENTS` name. Someone else's
  repo keeps its own convention.

## One copy of each tool

- Skills follow Agent Skills (`<name>/SKILL.md`, frontmatter `name` and a
  `description` saying what it does and when to use it, under 1,024
  characters).
  - A repo's skills go in `.agents/skills/`, which Codex reads, with
    `.claude/skills` a symlink to it for Claude.
  - User-level skills live in the nixOS repo, and a new one is a PR there.
    `modules/home-manager/claude-code/skills/` holds the ones the owner's
    own sessions get too; `modules/nixos/agent-skills/` holds the ones only
    about this sandbox. `modules/nixos/agent-user.nix` links both into
    every agent's skill directory from one harness list.
- Where only one tool has a feature (Claude's path-scoped `.claude/rules/`,
  plugins, settings), keep one copy and point the other tool at it from
  `AGENTS.md`. Never keep two copies to sync.
- Don't rely on any tool's built-in memory (Claude's auto memory is off).
  Notes go in the project's `AGENTS.local.md`. Save cross-project memory
  only when the owner asks; facts about the machine belong in the shared
  instructions or the `torrent-machine` skill.

## Writing guidance

Anthropic's and OpenAI's guidance agree: keep the always-loaded file short
(under about 200 lines), give the reason for each rule, and move multi-step
procedures into skills that load only when needed. A rule that must hold
every time is better as a hook, a setting or a permission than as prose.
For each line, ask whether an agent would make a mistake without it.

The shared instructions every agent loads are built from
`modules/nixos/agent-user-AGENTS.md` and the owner's
`modules/home-manager/claude-code/user-claude.md` ("How to work with me",
which is the owner's text: don't edit it without being asked).
