---
name: other-agents
description: How to start another agent (a subagent of any family) through Paseo, and how to run a cold read with no local instructions. Use whenever you delegate work to another agent, want a second opinion or review from a different model family, before a PR that would be costly to get wrong, or when a reviewer must see only the brief.
---

# Other agents

**Another agent.** `paseo run --provider claude "<brief>"` runs it as your
subagent, so the owner sees it in Paseo; use `codex` for the other family.
The defaults are right; don't add flags.

**Briefs.** Say what it's for (the goal, one level above the task itself),
what's in, what's out and when it's done.

**Cold reads** (not shown in Paseo). Never say who wrote the work or what
you expect.

- Code: `claude -p --safe-mode --disable-slash-commands --tools Read,Grep,Glob "<brief>" < /dev/null`,
  run in the repo. No instruction files, skills, MCP or memory load.
- A document: `--tools ""` instead, from an empty folder, with the document
  embedded in the brief.
- Codex: `HOME=/home/agent/.cold CODEX_HOME=/home/agent/.cold/.codex codex exec --ephemeral --skip-git-repo-check -c project_doc_max_bytes=0 -C <dir> "<brief>" < /dev/null`.

**Rules.** Treat what comes back as input, not a verdict. Before a costly PR
(agent-user, firewall, deploys, migrations, deletions), have the other
family review it.
