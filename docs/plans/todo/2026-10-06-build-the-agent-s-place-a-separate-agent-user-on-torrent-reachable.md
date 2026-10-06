---
slug: build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable
created: 2026-10-06
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# Build the agent's place: a separate agent user on torrent reachable via Remote Control

## State

Todo. Spec approved 2026-10-06. Nothing built. Branch `agent-place`.

## Original plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** non-sensitive agent work (research, side projects, dotfiles edits)
runs as a separate `agent` user on torrent.
- You reach it from the Claude app through Remote Control.
- It runs with zero prompts.
- It can't read your home or reach your LAN/tailnet. It sees only
  `Vault/Research/`.

**Architecture:** one plain NixOS module (no options surface), `agent-user`,
imported by torrent only. It covers:
- the user and its group;
- Nix access;
- a bindfs mount of `Vault/Research/`;
- an iptables uid-owner egress chain;
- a `claude remote-control` system service.

One `runNixOSTest` covers the whole module. One-time account steps (the bot,
logins, the first interactive run, Trusted Devices) stay manual.

**Tech stack:** NixOS (unstable, as torrent), bindfs 1.18.1, iptables
(torrent's firewall backend; nftables is off), Claude Code 2.1.280,
`pkgs.testers.runNixOSTest`.

**Spec:** `~/Projects/agenticsandbox/SPEC-stage-1.md` (outside the repo; the
design record lives in `~/Projects/agenticsandbox/`, decisions D1–D23).

### Global constraints

- **Torrent only.** Imported from torrent's module list in
  `modules/flake/hosts.nix`, never from `profile-pc`.
- **The `agent` user:**
  - its own group `agent`; **no** `users`, `wheel` or any other extra group;
  - home `/home/agent`, mode `700`.
- **Nix:** `nix.settings.allowed-users` gains `"agent"`. **Never**
  `trusted-users`.
- **The service** runs `claude remote-control --spawn same-dir --name
  torrent-agent --permission-mode bypassPermissions`, with
  `WorkingDirectory=/home/agent/work` (never `~`: trust isn't saved for a home
  directory).
- **Its environment:** `ENABLE_CLAUDEAI_MCP_SERVERS=false`.
- **Its unit:**
  - `ConditionPathExists=/home/agent/.claude/.credentials.json`;
  - `Restart=always`, `RestartSec=30`;
  - after and wanting `network-online.target`.
- **The vault:** only `/home/lilijoy/Documents/Vault/Research` is exposed,
  mounted at `/home/agent/research`, with bindfs `force-user=agent`,
  `force-group=agent`, `create-for-user=lilijoy` and `create-for-group=users`.
- **Egress:** the agent uid is rejected to `10.0.0.0/8`, `172.16.0.0/12`,
  `192.168.0.0/16`, `100.64.0.0/10` and `169.254.0.0/16`, plus `fc00::/7` and
  `fe80::/10` on IPv6. Loopback stays allowed.
- **No home-manager, settings files or `CLAUDE.md`** for the agent.
- **Repo rules:**
  - dendritic registration (`flake.modules.nixos."agent-user"`);
  - `nixfmt`, `statix` and `deadnix` clean;
  - inline comments for mechanics only, with `# plan:` citations for the why;
  - build torrent and thinkpad before every commit;
  - **never switch.** The user switches.

### Review focus

1. **Boot with the source folder missing, or `/home` (ZFS) mounting late.** The
   bindfs mount must not block boot (`nofail`) and must order after
   `zfs-mount.service`. The agent then sees an empty folder, and Obsidian is
   unaffected because the real files never move. Pinned in Task 2's eval check,
   and verified on the real host in Task 6.
2. **Firewall restart or stop duplicates or loses the egress jump.** Restarting
   the firewall should leave exactly one `OUTPUT → agent-egress` jump. Pinned in
   Task 3's restart subtest.
3. **Group-readable files exposed through group membership.** `id -nG agent`
   must be exactly `agent`. Pinned in Task 1.
4. **The service flapping before the one-time login.** No credentials file
   means the unit is skipped by its condition, not failing in a loop. Pinned in
   Task 4.
5. **DNS for the agent while the LAN is blocked.** Lookups go to `127.0.0.53`
   (allowed), and resolved itself talks to the router. Verified on the real host
   in Task 6 (`run0 -u agent getent hosts github.com`). The VM has no internet.

---

### Task 1: The `agent` user, its Nix access and its directories

**Files:**
- Create: `modules/nixos/agent-user.nix`
- Create: `tests/agent-user.nix`
- Modify: `modules/flake/checks.nix` (add `agent-user` beside `docker-publish-guard`)

**Interfaces:**
- Produces: module `config.flake.modules.nixos."agent-user"`; check
  `checks.x86_64-linux.agent-user`. The test takes
  `{ pkgs, agentUserModule }`, the same shape as `tests/docker-publish-guard.nix`.
- Test node `machine` imports the module and defines `users.users.lilijoy`
  (`isNormalUser`, `homeMode = "700"`) plus a file `/home/lilijoy/secret`.

- [ ] **Step 1: Write the failing test.** In `tests/agent-user.nix`, subtest
  `"user boundary"`:
  - `machine.fail("su agent -s /bin/sh -c 'ls /home/lilijoy'")`
  - `machine.succeed("id -nG agent").strip() == "agent"`
  - `stat -c '%a %U' /home/agent` == `700 agent`
  - `/home/agent/work` and `/home/agent/repos` exist, `700 agent`
  - `su agent -s /bin/sh -c 'nix-store --query --hash /run/current-system'`
    succeeds (the daemon allows `agent`)
- [ ] **Step 2: Run it and see it fail.** Run
  `nix build .#checks.x86_64-linux.agent-user -L`. Expected: an evaluation
  error (the module doesn't exist yet).
- [ ] **Step 3: Implement.** `users.users.agent` (`isNormalUser`, `group =
  "agent"`, `homeMode = "700"`, `packages = [ git gh ]`), `users.groups.agent`,
  `nix.settings.allowed-users = [ "agent" ]`, and `systemd.tmpfiles` rules for
  `work`/`repos` (`d … 0700 agent agent`).
- [ ] **Step 4: Run it and see it pass**, using the same command.
- [ ] **Step 5: Lint and commit.** Run `nixfmt`, `statix check .` and
  `deadnix .`, then commit with
  `feat(agent-user): separate agent user with its own group and nix access`.

### Task 2: The `Vault/Research` mount

**Files:** modify `modules/nixos/agent-user.nix` and `tests/agent-user.nix`.

**Interfaces:**
- Consumes: Task 1's user and test node.
- Produces: the mount at `/home/agent/research`.

- [ ] **Step 1: Write the failing test.** Subtest `"research mount"`:
  - `su agent -c 'echo x > /home/agent/research/note.md'` succeeds;
  - `stat -c %U:%G /home/lilijoy/Documents/Vault/Research/note.md` ==
    `lilijoy:users`;
  - a file lilijoy creates in the source is writable by agent through the mount;
  - `ls /home/agent/research/..` doesn't show the source's sibling folders
    (create `/home/lilijoy/Documents/Vault/Library/x.md` in the test and assert
    agent can't read it by any path).
- [ ] **Step 2: Run it and see it fail** (no mount).
- [ ] **Step 3: Implement.**
  - `fileSystems."/home/agent/research"`: `device` is the source,
    `fsType = "fuse.bindfs"`, options are the four bindfs ones from Global
    constraints plus `nofail` and `x-systemd.after=zfs-mount.service`.
  - `system.fsPackages = [ pkgs.bindfs ]`.
  - A tmpfiles `d` for the source dir (`0755 lilijoy users`) so it exists.
  - If the agent gets "permission denied" on the mount (FUSE `allow_other`),
    add `allow_other`. Record it as a gotcha.
- [ ] **Step 4: Run it and see it pass.** Also check with
  `nix eval .#nixosConfigurations.torrent.config.fileSystems."/home/agent/research".options`
  that `nofail` is present (after Task 5 wires torrent; until then, use the
  test node's config).
- [ ] **Step 5: Lint and commit**, as
  `feat(agent-user): expose only Vault/Research to the agent via bindfs`.

### Task 3: Egress chain, no LAN or tailnet for the agent

**Files:** modify `modules/nixos/agent-user.nix` and `tests/agent-user.nix`
(add a second node `lan` serving HTTP on port 8000).

**Interfaces:**
- Consumes: Task 1's user.
- Produces: the iptables chain `agent-egress`, jumped from `OUTPUT` for
  `--uid-owner agent`.

- [ ] **Step 1: Write the failing test.** Subtest `"egress"`:
  - `curl --max-time 5 http://lan:8000` fails as agent and succeeds as root (the
    test net is 192.168.1.x);
  - `iptables -S agent-egress` contains `-d 100.64.0.0/10 … REJECT`;
  - `ip6tables -S agent-egress` contains `fc00::/7`.

  Then a restart subtest: `systemctl restart firewall`, and
  `iptables -S OUTPUT | grep -c agent-egress` == `1`.
- [ ] **Step 2: Run it and see it fail.**
- [ ] **Step 3: Implement.**
  - `networking.firewall.extraCommands` creates or flushes `agent-egress` for
    both `iptables` and `ip6tables`, appends the REJECT rules from Global
    constraints, and adds the `OUTPUT -m owner --uid-owner agent -j agent-egress`
    jump only if `-C` says it's missing.
  - `extraStopCommands` deletes the jump and the chain, tolerating absence.
- [ ] **Step 4: Run it and see it pass.**
- [ ] **Step 5: Lint and commit**, as
  `feat(agent-user): block LAN and tailnet egress for the agent uid`.

### Task 4: The Remote Control service

**Files:** modify `modules/nixos/agent-user.nix` and `tests/agent-user.nix`.

**Interfaces:**
- Consumes: Task 1's user and directories.
- Produces: `systemd.services.claude-remote-control`, used by the manual steps
  in Task 6.

- [ ] **Step 1: Write the failing test.** Subtest `"service"`:
  - with no credentials file,
    `systemctl show claude-remote-control -p ConditionResult --value` == `no`
    and `ActiveState` != `failed`;
  - `systemctl show -p User --value` == `agent`;
  - `-p WorkingDirectory` == `/home/agent/work`;
  - `systemctl cat` contains `--spawn same-dir`, `--name torrent-agent` and
    `--permission-mode bypassPermissions`;
  - `-p Environment` contains `ENABLE_CLAUDEAI_MCP_SERVERS=false`.
- [ ] **Step 2: Run it and see it fail.**
- [ ] **Step 3: Implement** the unit with the Global constraints values.
  - `ExecStart` uses the same `claude-code` package attribute `profile-pc`
    installs (`modules/profiles/PC.nix:74`).
  - `PATH` includes `/run/wrappers/bin`, `/etc/profiles/per-user/agent/bin` and
    `/run/current-system/sw/bin`.
  - The unit sets `HOME=/home/agent`.
- [ ] **Step 4: Run it and see it pass.**
- [ ] **Step 5: Lint and commit**, as
  `feat(agent-user): run claude remote-control as the agent user`.

### Task 5: Wire into torrent, build, docs, PR

**Files:**
- Modify: `modules/flake/hosts.nix` (torrent's list, after `"nfs-homelab-mounts"`)
- Modify: `hosts/torrent/README.md` (inventory, via `scripts/doc-host.sh torrent`)
- Modify: `docs/accepted-risks.md`: under AR-5's "Not covered", note that
  stage 1 sets `master` branch protection (D3)

- [ ] **Step 1: Build both hosts.** Run `nixos-rebuild build --flake .#torrent`
  and `.#thinkpad`; both must print `Done.`.
- [ ] **Step 2: Diff and check.** Run `nvd diff /run/current-system result` for
  torrent. Expect only the agent user, the unit, the mount, bindfs and the
  firewall lines. Then run `nix flake check --no-build` and
  `nix build .#checks.x86_64-linux.agent-user`, both passing.
- [ ] **Step 3: Docs pass.** Run the `docs-updater` agent on the branch.
- [ ] **Step 4: Security review.** Run the `security` agent. This touches
  firewall rules and a new principal, so it's required by the workflow.
- [ ] **Step 5: Commit and open the PR.** Don't merge. The user merges and
  switches.

### Task 6: The user switches and does the one-time steps (manual, not an agent)

All of these are from the spec, section 2, and run on torrent by you:
1. `systemctl status home-agent-research.mount` shows it active after a
   reboot, and `run0 -u agent getent hosts github.com` resolves (Review focus
   items 1 and 5).
2. **The bot account:** create it, add it to `nixOS` and `project-elysian` with
   write access, and protect `master` (PR + 1 review, admin bypass on).
3. `run0 -u agent gh auth login` (as the bot), then
   `run0 -u agent git config --global user.name/user.email` (bot noreply).
4. `run0 -u agent claude auth login` (with your account).
5. **The first interactive run:**
   - `run0 -u agent --chdir=/home/agent/work claude remote-control --spawn same-dir`;
   - answer **y** and **y**, then press Ctrl+C;
   - `systemctl start claude-remote-control`.
6. **Trusted Devices on.**
7. **The done-check from your phone:**
   - a note lands in `Vault/Research/`;
   - a bot PR on `nixOS`;
   - a push to `project-elysian`;
   - zero prompts;
   - `/mcp` shows no connectors.

## Progress

- [ ] Task 1 -- the `agent` user, its Nix access and its directories
- [ ] Task 2 -- the `Vault/Research` mount
- [ ] Task 3 -- egress chain
- [ ] Task 4 -- the Remote Control service
- [ ] Task 5 -- wire into torrent, build, docs, security, PR
- [ ] Task 6 -- the user switches and does the one-time steps

## Decisions (D)

### D1 -- the design lives outside the repo

The reasoning (D1–D23, the spikes, the threat ratings) is in
`~/Projects/agenticsandbox/`. This plan carries only what implementation needs.
The spec's decisions S1–S5 are settled there. Don't re-litigate them here.

## Gotchas (G)

### G1 -- bindfs `create-for-*` only applies when root mounts

That's true for a `fileSystems` entry. Checked with `bindfs --help` from the
pinned nixpkgs, 2026-10-06.

### G2 -- `isNormalUser` defaults to group `users`

That's your group too, so it would expose anything of yours that's
group-readable. Hence the explicit `group = "agent"`.

## Findings (F)
*(populated by security/docs-updater when invoked)*
