---
name: other-agents
description: How to start another agent (a subagent of any family) through Paseo, and how to run a cold read with no local instructions. Use whenever you delegate work to another agent, want a second opinion or review from a different model family, before a PR for complicated or sensitive work, or when a reviewer must see only the brief.
---

# Other agents

**Another agent.** `paseo run --provider claude "<brief>"` runs it as your
subagent, so the owner sees it in Paseo; use `codex` for the other family.
The defaults are right; don't add flags. Subagents report back by themselves: when a child's turn ends, errors or needs permission, its last reply reaches you as a message, so never poll; only add `--no-wait`, to carry on meanwhile.

**Briefs.** Say what it's for (the goal, one level above the task itself),
what's in, what's out and when it's done.

**Cold reads** (not shown in Paseo). Never say who wrote the work or what
you expect.

- Code: `claude -p --safe-mode --disable-slash-commands --model claude-fable-5-2 --effort high --tools Read,Grep,Glob "<brief>" < /dev/null`,
  run in the repo. No instruction files, skills, MCP or memory load.
- A document: `--tools ""` instead, from an empty folder, with the document
  embedded in the brief.
- Codex: from an empty folder, naming in the brief any paths to read (it
  can read anywhere, write nowhere; started in a repo, it loads the repo's
  skills): `HOME=/home/agent/.cold CODEX_HOME=/home/agent/.cold/.codex codex exec --ephemeral --skip-git-repo-check -m gpt-6-astra -c model_reasoning_effort=high -C "$(mktemp -d)" "<brief>" < /dev/null`.

**Reviews.** When one is due: your global instructions. The model and
effort in these commands are each family's strongest at high, pinned
because the defaults are weaker (the cold Codex home has no config, so it
ran GPT-6.1 Sol at effort none); move a pin when a stronger model ships.
Treat what comes back as input, not a verdict.
