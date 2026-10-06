---
slug: make-the-agent-s-place-reproducible-with-an-agent-setup-check-and-fix
created: 2026-10-06
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# Make the agent's place reproducible with an agent-setup check and fix script

## State

Built on branch `agent-setup`.
- The VM test passes, including the `agent-setup --check` and git-identity
  subtests, which failed first.
- shellcheck passes, via `writeShellApplication`.

Waiting on the user to run `run0 agent-setup --check` on torrent after
switching.

## Original plan

**Owner:** the user, 2026-10-06: "it needs to be reproductible in the future or
it is not a real solution". Follows
`2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md`.

**Goal:** after a reinstall, or when something drifts, one command brings the
agent's place back to verified-good, or says exactly what's missing.

**What:**
- **Declare what can be declared.** The agent's git identity, as the bot,
  goes into `~agent/.config/git/config` through a store symlink. `~/.gitconfig`
  stays writable, because `gh auth setup-git` writes its credential helper
  there.
- **`agent-setup`**, packaged by the `agent-user` module. You run it as root
  (`run0 agent-setup`): one polkit prompt, then `runuser` for each identity.
  - **Plain run:** checks each piece of state in dependency order, and asks
    before fixing anything that's missing.
  - **`--check`:** only reports, and exits 1 if anything is wrong.
- **What it covers:** the module is deployed, the research folder exists, the
  mount works, the settings merge took, egress is blocked, the git identity,
  `gh` logged in as the bot, the Claude login and workspace trust, the Remote
  Control consent, the service is running, and GitHub (the bot is a
  collaborator, `master` is protected). Trusted Devices is printed as a
  reminder, because nothing local can check it.

**Out of scope:** pre-seeding `~agent/.claude.json` keys. They're
undocumented, and they sit inside the login flow, which is interactive anyway
(stage-1 notes, `~/Projects/agenticsandbox/notes/stage-1-agents-place.md`).

## Progress

- [x] D1 -- the wizard template isn't used
- [x] declared git identity + `agent-setup`, with a VM subtest for `--check`
- [x] build torrent and thinkpad
- [ ] the user runs `run0 agent-setup --check` on torrent and sees everything ✓

## Decisions (D)

### D1 -- the wizard template isn't used

The `wizard` skill's `template.sh` is built around `.env` and GitHub-secret
capture, and it clears the screen at every stage. That fights a health-check
report, and none of its helpers apply here. Kept: its idea (ordered stages,
confirm before each change, a closing summary). Dropped: the template itself.


**ANSWERED 2026-10-06:** user: 'lets do 1' (the agent-setup script); template judged not to fit, idea kept

## Gotchas (G)

## Findings (F)
*(populated by security/docs-updater when invoked)*
