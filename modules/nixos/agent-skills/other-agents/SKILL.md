---
name: other-agents
description: The other agents installed on torrent and how to call them non-interactively. Use for a second opinion or review from a different model family, before a PR that would be costly to get wrong, to hand off a task that suits another agent better, or when you're stuck between two designs.
---

# The other agents

Every agent on torrent is an equal: Claude Code, Codex and the local model
run as the same Unix user, read the same instructions and skills, and can
take any task. The others are on your `PATH`, logged in. Your own system
prompt says which one you are; call the others, not yourself.

Treat what another agent returns as input, not a verdict: check it against
the code.

## How to call each one

Run each from the directory to work in, with `< /dev/null` so it never
waits on a terminal.

| Agent | Non-interactive command |
|---|---|
| Claude (Anthropic) | `claude -p --permission-mode bypassPermissions "<task>" < /dev/null` |
| Codex (OpenAI) | `codex exec --skip-git-repo-check -C <dir> "<task>" < /dev/null` (add `--search` for web search) |
| Local model, Claude Code harness | `claude-local -p --permission-mode bypassPermissions "<task>" < /dev/null` |
| Local model, Codex harness | `codex exec --skip-git-repo-check -C <dir> -c model_provider=local -c 'model_providers.local.name="llama-server"' -c 'model_providers.local.base_url="http://127.0.0.1:8080/v1"' -c 'model_providers.local.wire_api="responses"' -m <model> "<task>" < /dev/null` |

- Codex refuses a directory that isn't a git repo unless you pass
  `--skip-git-repo-check`. It loads AGENTS.md only from the git root down
  to `-C`, so point `-C` at the repo.
- The local model's name and whether its server is up are in the
  `local-ai` skill. `claude-local` is Claude Code with
  `ANTHROPIC_BASE_URL` set to the local server, a placeholder API key, no
  Anthropic login, and an appended system prompt saying which model it
  really is. Without that prompt the local model believes Claude Code's own
  "you are Claude". If `claude-local` isn't on `PATH`, set the variables
  yourself:
  `ANTHROPIC_BASE_URL=http://127.0.0.1:8080 ANTHROPIC_API_KEY=local ANTHROPIC_MODEL=<model> ANTHROPIC_SMALL_FAST_MODEL=<model> CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude --append-system-prompt "You are <model> running locally, not Claude." -p ...`
- The local model is free and uncapped but slower and weaker than the
  cloud models. It's the one to use for private material, for work the
  cloud models refuse, and as a third opinion.

## Rules

- **One hop.** A delegated task doesn't delegate back to its caller, so two
  agents can't loop on each other's usage.
- **Separate checkouts.** You share one home and one `~/work`. Work in your
  own git worktree or branch, never in a checkout another agent may be
  using.
- **Review before a costly PR.** Before a PR that would be costly to get
  wrong (agent-user, firewall, deploys, migrations, deletions), have an
  agent of another model family review the branch against the base:
  - From Claude: `node ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs adversarial-review --wait --base master`
    (the `codex:codex-rescue` subagent also works). Its Codex runs in a
    read-only sandbox, so it can't evaluate or build: do the builds and
    runtime checks yourself.
  - From Codex: `claude -p --permission-mode bypassPermissions "Review the branch <branch> against master for bugs and risks" < /dev/null`
    in the repo.
  - `/codex:review` and `/codex:adversarial-review` are the owner's to type.
- **Several opinions on one question:** the `important-question` skill.
