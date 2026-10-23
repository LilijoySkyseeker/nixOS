# Where you are

You are one of several equal agents (Claude Code, Codex, a local model in
either harness, and any added later) that run as the Unix user `agent` on
torrent, the owner's NixOS desktop. Your system prompt says which model you
are. Every agent reads this same file and the same skills, and any of you
may take any task. The owner reaches you through Paseo and the vendors'
remote-control apps. This is not a cloud container: anything you write is
on the owner's machine.

## Boundaries

- No permission prompts: the Unix user, its systemd units and the egress
  firewall are the boundary, not the agents' own sandboxes.
- By design you have no root, no secrets, no access to the owner's home,
  and no route to their LAN or tailnet. If a task needs root, a secret or
  a LAN host, say exactly what to run and why; the owner does it.
- Use the machine's full resources without asking; the limits are hard
  ones. Details and quirks: the `torrent-machine` skill.
- The GPU is the owner's desktop card, and their desktop and games come
  first: check VRAM before a big job and free the GPU when you're done.

## Places

- `~/work` is shared with the owner, who sees it as `~/Agent`. Sessions
  start here. Keep nothing else at the top:
  - `repos/`: every clone goes in `~/work/repos`. The owner's repos and
    yours at the top; anyone else's in `repos/external/`, treated as
    someone else's project.
  - `projects/`: work that isn't a repo, one folder per project.
  - `scratch/`: downloads, one-off scripts, source material. Deletable.
  - `inbox/`: files the owner drops for you; move each into a project.
  - `TODO.md`: deferred work. Read it when you start; add what you put
    off, dated, with enough context to pick up cold; delete what's done.
  - `ENVIRONMENT.md`: the log of environment failures (below).
- `~/research` is the owner's Obsidian `Vault/Research` folder. Finished
  research goes there as markdown; it appears on the owner's phone.
- When you can't send the owner a file, give its path under `~/Agent`.

## Starting work

- Read the repo's or project's `AGENTS.md` and `AGENTS.local.md` yourself
  when you start there: not every harness loads them from `~/work`.
- Keep notes in that `AGENTS.local.md` (git ignores it everywhere), never in
  a tool's built-in memory. Cross-project memory only when the owner asks.
- Use the tool-neutral names: `AGENTS.md`, `AGENTS.local.md`. Never create
  a `CLAUDE.md` or run `/init`. Conventions for instructions, skills and
  settings: the `agent-config` skill.

## Git and publishing

- Your changes reach the owner as pull requests from your GitHub account.
  You can't push to `master` of the `nixOS` repo; the owner reviews and
  merges.
- Work in your own git worktree or branch, never in a checkout another
  agent may be using.
- **Never stack branches or PRs**, in any repo: every branch starts from
  the up-to-date default branch, and every PR targets it. Stacked PRs that
  merge out of order land in their parent branch, silently (nixOS #142 and
  #144, 2026-10-21). If work needs an unmerged PR, wait for it, or put both
  in one PR.
- Once your PR merges, remove its worktree and delete its branch, locally
  and on the remote.
- No AI attribution anywhere: no `Co-authored-by` trailers, "Generated
  with" lines, session links or agent signatures in commits, PR or issue
  bodies, review comments or code. Not every harness has a setting for
  this, so this line is the control.
- **Nothing is published under your GitHub account**: no repos, forks or
  gists. Public work in anyone else's project goes out under the owner's
  account, since it's their responsibility: you prepare the text and the
  branch (in `repos/external/`, or a fork the owner made and gave you push
  access to), and tell the owner exactly what to post and where.

## Tools

- `web-research` skill: `web-fetch` for bot walls and feeds, paper routes.
  The owner authorizes getting past bot walls when you read for their
  work; the line is access control (no paywall or login bypass).
- `other-agents` skill: calling the other agents for a second opinion,
  review or handoff; review by another model family before a costly PR.
- `local-ai` skill: the local model server and the local tools on the GPU.
- `torrent-machine` skill: hardware, caps, VMs, network, shell quirks.
- Scheduled jobs (flake update, maintenance, security watch) run
  unattended from the nixOS repo's `modules/nixos/agent-jobs/` and report
  in `~/research/Fleet/`. A new job is a PR there.

## Working with the owner

- When you put a decision to the owner, restate it in full every time: the
  problem, a concrete example, each option with its trade-offs, and your
  recommendation. Don't point back to "3a above".
- A temporary workaround (a patch, an override, a stopgap waiting on an
  upstream fix) gets a `# TODO: drop when <condition>` comment with a link,
  so the weekly jobs remove it when the condition is met.
- When the environment gets in your way (a missing tool, a sandbox or
  permission denial, a blocked network call, a hook or CLI misbehaving,
  this file being wrong or missing a fact), say so in one line in your
  reply and append an entry to `~/work/ENVIRONMENT.md`: the date, which
  agent you are, what failed (command and error), what you did instead,
  and the fix you'd suggest. Log it even when the workaround was easy;
  quiet workarounds are how these stayed invisible. Mistakes in your own
  work don't go there. Anything you need but can't get (an account, a
  tool) goes there too; the weekly maintenance job brings it to the owner.
