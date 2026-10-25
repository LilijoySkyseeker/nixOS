---
name: other-agents
description: The other agents installed on torrent and how to call them non-interactively. Use for a second opinion or review from a different model family, before a PR that would be costly to get wrong, to hand off a task that suits another agent better, or when you're stuck between two designs.
---

# The other agents

Claude Code, Codex, OpenCode, Antigravity and the local model run as the
same Unix user, read the same instructions and skills, and can do work.
The others are on your `PATH`, logged in. Your own system prompt says which one you are; call the
others, not yourself.

The local Qwen3.8-27B agent keeps the same access, tools and ability to
do work, but is not a capability peer of the cloud agents. Do not call it
for reviews, alternative opinions or independent checks.

Treat what another agent returns as input, not a verdict: check it against
the code.

## How to call each one

Run each from the directory to work in, with `< /dev/null` so it never
waits on a terminal.

| Agent | Non-interactive command |
|---|---|
| Claude (Anthropic) | `claude -p --permission-mode bypassPermissions "<task>" < /dev/null` |
| Codex (OpenAI) | `codex exec --skip-git-repo-check -C <dir> "<task>" < /dev/null` (add `--search` for web search) |
| OpenCode, any OpenRouter model | `opencode run --standalone -m openrouter/<vendor>/<model> "<task>" < /dev/null` |
| Antigravity (Google Gemini) | `agy -p --dangerously-skip-permissions "<task>" < /dev/null` |
| Local model, Claude Code harness | `claude-local -p --permission-mode bypassPermissions "<task>" < /dev/null` |
| Local model, Codex harness | `codex exec --skip-git-repo-check -C <dir> -c model_provider=local -c 'model_providers.local.name="llama-server"' -c 'model_providers.local.base_url="http://127.0.0.1:8080/v1"' -c 'model_providers.local.wire_api="responses"' -m <model> "<task>" < /dev/null` |

- OpenCode reaches most open-weight and frontier models through the
  owner's OpenRouter key, paid per token, so pick the model for the task:
  `opencode models --standalone | grep '^openrouter/'` lists them. Without
  `-m` it picks one itself. The `opencode/*` models are free, but some
  may train on what you send. `--standalone` uses a private server
  instead of OpenCode's background service.
- Antigravity runs Gemini on a free Google account set aside for the
  agents, which has weekly limits; `agy models` lists what it gets.
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
  cloud models. It's the one to use for private material and for work the
  cloud models refuse, with its output checked. It hallucinated review
  results in an earlier session (owner, 2026-10-23); keep it out of
  review and opinion workflows.

## Rules

- **One hop.** A delegated task doesn't delegate back to its caller, so two
  agents can't loop on each other's usage.
- **Separate checkouts.** You share one home and one `~/work`. Work in your
  own git worktree or branch, never in a checkout another agent may be
  using.
- **Review before a costly PR.** Before a PR that would be costly to get
  wrong (agent-user, firewall, deploys, migrations, deletions), have an
  agent of another model family review the branch against the base:
  - Codex reviewing: `codex review --base master < /dev/null` in the repo.
    It runs Codex's built-in review with its full sandbox, so it can build
    and evaluate too. The output is long; the verdict is at the end
    (`| tail -40`). `--base` takes no custom instructions: for a focused
    pass (security, an adversarial read), use `codex exec -C <repo>
    "Review the diff master...HEAD for <focus>; report findings with
    file:line" < /dev/null`.
  - Claude reviewing: `claude -p --permission-mode bypassPermissions
    "Review the branch <branch> against master for bugs and risks" <
    /dev/null` in the repo.
  - A change that touches security (firewall, ports, secrets,
    authentication, an exposed service) gets both a security review and
    the other family's review, in parallel, before the PR opens.
- **Several opinions on one question:** the `important-question` skill.
