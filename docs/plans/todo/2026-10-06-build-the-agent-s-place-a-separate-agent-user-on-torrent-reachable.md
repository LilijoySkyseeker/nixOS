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

Tasks 1–5 are built on branch `agent-place`, and everything passes: one VM
test with 6 subtests, a build of both hosts, and `nix flake check`.
- **Review fix pass done.** The security review found F1–F8; the whole-branch
  review confirmed F1 and F2 in a VM and added F9 and F10.
  - **Fixed**, each with a test that failed first: F1, F2, F3, F4, F5, F8, F9
    and F10.
  - **Open, low:** F6 (bindfs symlinks and modes) and F7 (snapdirs, routed to
    the existing snapdir plan).
- **Docs pass done.** Comment rationale moved here (F11). The new principal
  is now in `docs/hardening.md`, `docs/architecture.md`,
  `docs/threat-model.md` and `hosts/torrent/README.md` (F12).
- **Not built yet:** Task 6, the user's part. Switch, then the one-time steps,
  starting with creating `Vault/Research`.
- **Not verified:** whether the sandboxed service runs the real `claude` on
  torrent. The VM can't log in. If the unit fails after the first-run step,
  check `journalctl -u claude-remote-control` for an `EROFS` caused by
  `ProtectSystem=strict`.

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
  `192.168.0.0/16`, `100.64.0.0/10` and `169.254.0.0/16`, ~~plus `fc00::/7` and
  `fe80::/10` on IPv6~~. Loopback stays allowed. 2026-10-06: what shipped
  adds multicast and broadcast on IPv4, refuses **all** IPv6 except loopback,
  and also jumps gid `nixbld` through the chain (F1, F2).
- **No home-manager, settings files or `CLAUDE.md`** for the agent.
- **Repo rules:**
  - dendritic registration (`flake.modules.nixos."agent-user"`);
  - `nixfmt`, `statix` and `deadnix` clean;
  - inline comments for mechanics only, with `# plan:` citations for the why;
  - build torrent and thinkpad before every commit;
  - **never switch.** The user switches.

### Review focus

1. **The source folder is missing, or `/home` mounts late.** ~~nofail /
   zfs-mount ordering / "agent sees an empty folder"~~ (superseded by the
   rulings). It's an automount, so it never blocks boot, and on torrent
   `/home` is an ordinary `home.mount`. A missing source gives the agent a
   visible error on access and must never wedge the automount: F10, pinned in
   the research-mount subtest.
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

All of these are from the spec, section 2, and run on torrent by you. Do
them in this order:
1. **Create the research folder before switching:**
   `mkdir -p ~/Documents/Vault/Research`. The module never writes inside your
   home.
2. **Switch.** Then check, *by access*, because the mount is an automount and
   looks inactive until something touches it:
   - `run0 -u agent touch /home/agent/research/.probe` succeeds;
   - `.probe` shows up in your `Vault/Research`, owned by you;
   - `run0 -u agent getent hosts github.com` resolves (Review focus 5).
3. **The bot account:** create it, add it to `nixOS` and `project-elysian` with
   write access, and protect `master` (PR + 1 review, admin bypass on).
4. `run0 -u agent gh auth login` (as the bot), then
   `run0 -u agent git config --global user.name/user.email` (bot noreply).
5. `run0 -u agent claude auth login` (with your account).
6. **The first interactive run:**
   - `run0 -u agent --chdir=/home/agent/work claude remote-control --spawn same-dir`;
   - answer **y** and **y**, then press Ctrl+C;
   - `systemctl start claude-remote-control`.

   If it fails, check `journalctl -u claude-remote-control` (see State: the
   sandbox isn't verified against the real `claude`).
7. **Trusted Devices on.**
8. **The done-check from your phone:**
   - a note lands in `Vault/Research/`;
   - a bot PR on `nixOS`;
   - a push to `project-elysian`;
   - zero prompts;
   - `/mcp` shows no connectors.

## Progress

- [x] Task 1 -- the `agent` user, its Nix access and its directories
- [x] Task 2 -- the `Vault/Research` mount
- [x] Task 3 -- egress chain
- [x] Task 4 -- the Remote Control service
- [x] Task 5 -- wire into torrent, build, docs, security, PR
- [ ] Task 6 -- the user switches and does the one-time steps
- [x] D2 -- add back a minimal agent `CLAUDE.md`, and drop the unused `~/repos`

## Decisions (D)

### D1 -- the design lives outside the repo

The reasoning (D1–D23, the spikes, the threat ratings) is in
`~/Projects/agenticsandbox/`. This plan carries only what implementation needs.
The spec's decisions S1–S5 are settled there. Don't re-litigate them here.

### D2 -- add back a minimal agent `CLAUDE.md`, and drop the unused `~/repos`

This part was deleted in the five-step pass (design D21), and its add-back
trigger was "the agent doesn't know something it needs". It fired twice in
the first real sessions (2026-10-06):
- the agent believed it ran "in a cloud container, not on your machine";
- it cloned repos into `~/work/repos`, not the planned `~/repos`.

So the module now declares `~agent/.claude/CLAUDE.md` as a store symlink
(edits go through the repo). It holds orientation facts only: where the agent
runs, `~/research`, `~/work/repos`, its limits, and the bot-PR crossing. The
`~/repos` tmpfiles dir is dropped, and the agent's own choice of
`~/work/repos` is kept. The two core working lessons are deliberately not in
it; they arrive through the user-level `CLAUDE.md` plan (its G3).


**ANSWERED 2026-10-06:** user 2026-10-06: do it now as a small PR

## Gotchas (G)

### G1 -- bindfs `create-for-*` only applies when root mounts

That's true for a `fileSystems` entry. Checked with `bindfs --help` from the
pinned nixpkgs, 2026-10-06.

### G2 -- `isNormalUser` defaults to group `users`

That's your group too, so it would expose anything of yours that's
group-readable. Hence the explicit `group = "agent"`.

### G3 -- NixOS VM tests replace `fileSystems` wholesale

`qemu-vm.nix` sets `fileSystems = mkVMOverride cfg.fileSystems`, so a
module's `fileSystems` mount silently disappears inside `runNixOSTest`, and
the test would pass without ever exercising it. The mount is therefore
`systemd.mounts` plus `systemd.automounts`, which behave the same on the host
and in the test. ~~It's an automount because `/home` is a late ZFS mount.~~
The source folder is your data: you create it once, and the module never
writes inside your home (root creating paths in a user-owned tree is an
unsafe path transition). A missing source shows up as an error on access.

**2026-10-06 (docs pass):** the struck reason is wrong. On torrent `/home`
is `zroot/local/home` mounted by an ordinary `home.mount` (`fileSystems`,
`zfsutil`), not late by `zfs-mount.service`; Review focus 1 already says so.
It's an automount because the source is user data that may not exist yet:
a plain mount would fail at boot, while the automount retries on each
access and never blocks boot (F10 keeps a missing source from wedging it).
The same wrong reason was in the comment at `modules/nixos/agent-user.nix:90`
and is gone; the mount's comment cites this entry.

## Findings (F)
*(populated by security/docs-updater when invoked)*

Security review, 2026-10-06, against `bba23ef..6eaa865`. All checks are
read-only: torrent's live permissions plus `nix eval` of
`nixosConfigurations.torrent`. Nothing was deployed, and no secret was read.

### F1 — IPv6 egress misses the LAN's own global /64, and multicast/broadcast are unfiltered

- **File:** `modules/nixos/agent-user.nix:20-26`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (rule gap and torrent's addressing); PLAUSIBLE (which LAN devices listen on their global address)
- **Axis:** hardening
- **Reachability:** a prompt-injected agent process (uid `agent`) can reach any LAN device that has a SLAAC global address. On torrent, `enp8s0` carries a global address in the RA-delegated `2600:1010:a023:9663::/64`, and that prefix is an on-link route (`ip -6 route`). So `agent-egress`, which rejects only `fc00::/7` and `fe80::/10`, passes traffic straight to LAN neighbours on that /64. Examples are the router (seen in `ip -6 neigh` with several global addresses), the printer, and any IoT device. The IPv4 chain also leaves `224.0.0.0/4` and `255.255.255.255` open, so mDNS, SSDP and broadcast to the LAN still work.
- **Rule:** violates `docs/hardening.md` rule 5 in spirit: it trusts a belief that the LAN is RFC1918-only. The same rule records that this LAN hands out globally routable IPv6.
- **Finding:** "No LAN" holds for IPv4 unicast only. homelab's LAN NIC opens nothing (host-wide `allowedTCPPorts = []`), so I can't name a vulnerable service. The design goal is still unmet for every other device on the segment.
- **Fix risk:** the prefix is ISP-delegated and dynamic, so a hard-coded /64 will go stale silently. Options: a dispatcher hook that keeps an ipset of on-link prefixes up to date; a policy-routing table for the agent uid that has only the default route; or REJECT on `-o enp8s0` for anything except the gateway. Also add `ff00::/8`, `224.0.0.0/4` and `255.255.255.255/32`. Test IPv6 in the VM: the current test is IPv4-only (`lan` on 192.168.1.0/24), so this gap passed CI.


**FIXED 2026-10-06:** fixed in the review fix pass; pinned by tests/agent-user.nix (test failed first, then passed)

**2026-10-06 (docs pass):** the fix chosen was none of the options above:
IPv6 is rejected outright for the chain except on loopback (`-o lo -j
RETURN`, then `-j REJECT`), plus `224.0.0.0/4` and `255.255.255.255/32` on
IPv4. Reason, moved verbatim from the comment at
`modules/nixos/agent-user.nix:9-11`: "IPv6 refuses everything but loopback:
the LAN's v6 is a dynamic ISP global prefix that can't be listed, and the
internet still works over IPv4".

### F2 — Builds through the nix daemon run as `nixbld*`, so `--uid-owner agent` doesn't cover them

- **File:** `modules/nixos/agent-user.nix:43-44` (`allowed-users = [ "agent" ]`), `:48-61`
- **Severity:** MEDIUM
- **Confidence:** PLAUSIBLE. I didn't test it, and deliberately didn't build a proof. What is confirmed: `agent` is in the effective `allowed-users`; `sandbox = true`; and `agent-egress` matches only the agent uid. The untested part is the documented Nix behaviour that fixed-output derivations get host network access inside the sandbox.
- **Axis:** hardening
- **Reachability:** a prompt-injected agent can use the nix daemon, an allowed user, to build a fixed-output derivation. The fetch runs as a `nixbld` uid with host networking. The OUTPUT match never sees it, so the LAN and the flat tailnet are reachable, including homelab's `tailscale0` ports 22/445/2049/2283/3000/3100/8096 (Loki and Grafana among them). The build log goes back to the agent, so responses can be read as well as requests sent.
- **Rule:** new-rule candidate: "a uid-owner egress rule does not cover work the principal delegates to a daemon."
- **Finding:** this is the main gap the chain was meant to close. The VM test only checks `nix-store --query` and never runs an egress check from a build.
- **Fix risk:** adding `-m owner --gid-owner nixbld` to the jump would apply to *every* user's builds, including lilijoy's. That's fine unless something fetches from a LAN or tailnet cache, so check before applying. The other option is to remove the agent from `allowed-users`, which loses `nix build`/`nix develop` for the agent. Either way, add a VM subtest that runs a fixed-output fetch against `lan:8000` as the agent.


**FIXED 2026-10-06:** fixed in the review fix pass; pinned by tests/agent-user.nix (test failed first, then passed)

**2026-10-06 (docs pass):** the fix chosen is the `--gid-owner nixbld`
jump, so it applies to every user's sandboxed builds, lilijoy's included,
and (with F1's fix) those builds also lose IPv6. The "check before
applying" from Fix risk: torrent's only substituter is
`https://cache.nixos.org/` (`nix eval` of `nix.settings.substituters`), and
substitution is done by the daemon, not a `nixbld` uid; no `fetch*` in the
repo points at a LAN or tailnet address. Now documented in
`docs/hardening.md` ("The `agent` user") and `hosts/torrent/README.md`.

### F3 — The unit that runs untrusted code with no prompts has no systemd sandboxing at all

- **File:** `modules/nixos/agent-user.nix:85-106`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (the effective `serviceConfig` is only ExecStart/User/Group/Restart/RestartSec/WorkingDirectory)
- **Axis:** hardening
- **Reachability:** every session spawned by `claude remote-control` inherits this unit, and an injected agent runs arbitrary code in it. Today that code sees the whole filesystem (all world-readable paths and `/tmp`), keeps every setuid wrapper on PATH (`/run/wrappers/bin` is listed explicitly), has `/dev/kvm` and `/dev/net/tun` (both 0666), and has no memory or task ceiling on the desktop host.
- **Rule:** violates `docs/hardening.md` "Custom `systemd.services` sandboxing" (`NoNewPrivileges` plus the full stack when the job allows). This job allows it: no activation, no root.
- **Finding:** the boundary is meant to be "this user", but the unit gives up the cheap second layer. `NoNewPrivileges=true` alone would neutralise the setuid path in F4. Useful settings here: `ProtectHome=tmpfs` with `BindPaths=/home/agent` (lilijoy's home and the snapdirs simply don't exist for the agent), `PrivateTmp`, `PrivateDevices`, `ProtectSystem=strict` + `ReadWritePaths=/home/agent`, `ProtectKernel*`, `ProtectControlGroups`, `MemoryMax`/`TasksMax`, and `IPAddressDeny=` for the LAN ranges. The last one is a cgroup-level second egress layer that doesn't depend on the iptables chain surviving a firewall reload. Note that interactive `run0 -u agent` sessions (Task 6) don't get any of this.
- **Fix risk:** `ProtectHome`/`BindPaths` must keep the bindfs automount at `/home/agent/research` working inside the namespace. Test the mount from inside the unit, not with `su`. `RestrictNamespaces` would break rootless podman and nix's own sandbox if the agent uses them. `PrivateDevices` removes `/dev/kvm`. Confirm the result with `systemd-analyze security claude-remote-control`.


**FIXED 2026-10-06:** fixed in the review fix pass; pinned by tests/agent-user.nix (test failed first, then passed)

### F4 — The setuid `qemu-bridge-helper` lets the agent put a VM on `virbr0`, outside the uid match

- **File:** not in this diff. It comes from `modules/nixos/virtual-machines.nix` (libvirtd on, `allowedBridges = [ "virbr0" ]`, `/etc/qemu/bridge.conf: allow virbr0`) and becomes reachable because of this diff's new principal.
- **Severity:** MEDIUM
- **Confidence:** PLAUSIBLE. Confirmed: the helper is setuid and runnable by any user (`/run/wrappers/bin/qemu-bridge-helper`, `-r-s--x--x`), `/dev/kvm` and `/dev/net/tun` are 0666, and qemu is on the system PATH. Conditional: `virbr0` isn't up right now (no bridges on torrent). It exists whenever lilijoy's libvirt default network is started.
- **Axis:** hardening
- **Reachability:** while `virbr0` is up, a prompt-injected agent can start an unprivileged qemu VM attached to it. The VM's traffic is forwarded and NATed by the host, not generated by a local socket owned by `agent`, so `OUTPUT --uid-owner` never matches and LAN/tailnet reach is restored.
- **Rule:** new-rule candidate (same class as F2: the boundary is a uid match, and this path doesn't run as that uid).
- **Finding:** F3's `NoNewPrivileges=true` closes this for the service. It doesn't close it for interactive `run0 -u agent` sessions.
- **Fix risk:** restricting the helper (e.g. a group-gated wrapper) affects lilijoy's own unprivileged qemu or gnome-boxes networking. Test with quickemu and gnome-boxes.


**FIXED 2026-10-06:** fixed in the review fix pass; pinned by tests/agent-user.nix (test failed first, then passed)

### F5 — World-accessible daemon sockets give the agent control over lilijoy's VPN and a view of the tailnet

- **File:** not in this diff (`/run/mullvad-vpn` `srwxrw-rw-`, `/run/tailscale/tailscaled.sock` 0666, `/run/libvirt/libvirt-sock-ro` 0666). It becomes reachable because of this diff's new principal.
- **Severity:** MEDIUM. It becomes HIGH if the Mullvad account number can be read by a non-root uid (it's the account's only credential, so a secret exposed to a principal that shouldn't hold it).
- **Confidence:** PLAUSIBLE. Socket modes confirmed live. Not verified against source: that the Mullvad daemon applies no per-uid check to its management RPCs (including reading the account), and that tailscaled grants a non-operator uid read-only LocalAPI. Torrent sets no `--operator`. I deliberately did not query the account value.
- **Axis:** hardening
- **Reachability:** a prompt-injected agent can connect to these sockets directly: no network involved, and the egress chain doesn't apply. Through Mullvad it could disconnect or reconfigure the system VPN and possibly read the account. Through tailscaled it gets the tailnet peer list (names and IPs: reconnaissance for F1/F2). Through libvirt read-only it gets VM inventory.
- **Rule:** violates the threat model's "must not reach lilijoy's authority" (VPN state is hers). It isn't covered by a `hardening.md` rule.
- **Finding:** the user should check, not the agent: as `run0 -u agent`, see what `mullvad account get` returns. If it shows the account number, rate this HIGH and rotate the account number.
- **Fix risk:** F3's sandbox can't block a Unix socket by path unless `InaccessiblePaths=/run/mullvad-vpn /var/run/mullvad-vpn /run/tailscale /run/libvirt` is set. That covers the service but not interactive sessions. Changing socket modes upstream-wide affects lilijoy's own GUI clients.


**FIXED 2026-10-06:** fixed in the review fix pass; pinned by tests/agent-user.nix (test failed first, then passed)

### F6 — The default bindfs policies let the agent put symlinks, exec bits and arbitrary modes into lilijoy's real tree

- **File:** `modules/nixos/agent-user.nix:118-124`
- **Severity:** LOW
- **Confidence:** CONFIRMED for the policies (pinned bindfs 1.18.1 man page: `chmod-normal` and `chown-normal` are the defaults, and symlink creation is allowed unless `resolve-symlinks` is set). PLAUSIBLE for what consumes them.
- **Axis:** hardening
- **Reachability:** a prompt-injected agent writes to `/home/agent/research`. The results land as `lilijoy:users` in `~/Documents/Vault/Research`: symlinks pointing anywhere, files chmodded executable or setuid (the dataset has `setuid=on`), and so on. The agent gains nothing itself, because `force-user=agent` makes everything look agent-owned on its side, and symlinks resolve in the agent's own context, so they can't read lilijoy's files. The risk is lilijoy-side consumers following them: Obsidian, baloo, any sync tool, or lilijoy opening an agent-planted "note" that's really a symlink into `~/.config`. The vault has no community plugins today (`community-plugins.json` is `[]`). Enabling Dataview JS or Templater later would turn agent-written notes into code that runs as lilijoy.
- **Rule:** new-rule candidate (data the untrusted principal writes is executable config for the trusted one; same shape as rule 7).
- **Fix risk:** `chmod-ignore`, or `chmod-filter` plus `create-with-perms=f-xst:d-st`, strips exec and setuid. Blocking new symlinks via `resolve-symlinks` is **not** safe: bindfs would then resolve existing symlinks as root (the mounter). Prefer a periodic symlink sweep or simply living with them. Add a VM check that a file chmodded 4755 by the agent lands without `s`/`x`.

### F7 — ZFS snapdirs are now traversable by an untrusted uid

- **File:** not in this diff. `zroot/local/home` and `zroot/local/root` are `snapdir=hidden`, with `/home/.zfs/snapshot` and `/.zfs/snapshot` at 0777. Tracked in `docs/plans/todo/2026-09-01-extend-the-zfs-snapshot-traversal-fix-to-the-pc-hosts-without.md`.
- **Severity:** LOW
- **Confidence:** CONFIRMED (mechanism); nothing exploitable demonstrated
- **Axis:** hardening
- **Reachability:** a prompt-injected agent can walk 67 snapshots of each dataset and read anything that was world-readable when the snapshot was taken.
- **Rule:** n/a (existing open plan)
- **Finding:** spot checks were clean. `/home/.zfs/snapshot/*/lilijoy` is 0700 in all 67 snapshots, and `var/lib/sops-nix/key.txt` and `etc/ssh/ssh_host_ed25519_key` are 0600 in the snapshot sampled. It isn't exploitable today, but that plan's "the PCs run nothing comparable" premise no longer holds: torrent now runs untrusted code by design. F3's `ProtectHome=tmpfs` hides `/home/.zfs` from the service. `/.zfs` needs `InaccessiblePaths` or the plan's own fix.
- **Fix risk:** as recorded in that plan (losing snapshot browsing).

### F8 — The agent can authorize its own SSH key, a persistent inbound shell from any tailnet device

- **File:** not in this diff (torrent sshd: `tailscale0:22` open, no `AllowUsers`, `AuthorizedKeysFile` includes `%h/.ssh/authorized_keys`). Reachable because of `users.users.agent` (`isNormalUser`, bash shell).
- **Severity:** LOW
- **Confidence:** CONFIRMED (eval)
- **Axis:** hardening
- **Reachability:** a prompt-injected agent writes `~agent/.ssh/authorized_keys`. Any device on the flat tailnet holding that key can then log in as `agent` whether or not the remote-control service is running, and outside the service's (future) sandbox.
- **Rule:** new-rule candidate
- **Finding:** inbound only (sshd-forwarded sockets for the session still run as `agent` and stay matched), but it's a persistence channel that doesn't depend on Remote Control.
- **Fix risk:** `DenyUsers agent` (or `AllowUsers lilijoy`) as structured `settings`, verified with `sshd -T`. Check it doesn't block anything Task 6 needs; `run0 -u agent` doesn't use sshd.


**FIXED 2026-10-06:** fixed in the review fix pass; pinned by tests/agent-user.nix (test failed first, then passed)

### Checked and clean

Checked and found fine: `id -nG agent` is exactly `agent` (no `users`, `libvirtd` or `podman`). `/home/lilijoy` is 0700 live and in every snapshot. `/run/user/1000` and `/tmp/claude-1000` are 0700. `/run/secrets.d` is 0751 with 0400 root-owned secrets, and `/var/lib/sops-nix/key.txt` and the SSH host keys are 0600. The polkit rules in `10-nixos.rules` are all gated on groups or users the agent doesn't hold, so libvirt read-write (`org.libvirt.unix.manage`) and NetworkManager are denied. `/run/podman/podman.sock` is `root:podman` 0660. The nix daemon config: `trusted-users = [ "root" ]`, `require-sigs = true`, `sandbox = true` (no fallback), no `buildMachines`/`distributedBuilds`, no impure-derivations feature, and `trusted-substituters` empty. The store canonicalises modes, so no setuid store paths. Rootless podman (auto subuid) runs its network helper as `agent`, so it stays matched. `mullvad-exclude` changes routing but not the uid, so it stays matched. The firewall backend is iptables, as assumed. The chain's create/flush and `-C` idempotency look correct, and the stop path tolerates absence. `100.64.0.0/10` and `fc00::/7` cover the tailnet, including MagicDNS `100.100.100.100`. DNS goes through `127.0.0.53` (resolved, its own uid), which is intended, and LAN names that resolve to RFC1918 are still rejected on connect. Loopback listeners the agent can reach: CUPS (631, auth for admin), alloy (127.0.0.1:12345), KDE Connect (1716, pairing-gated), sshd (key-only, but see F8). bindfs: `force-user=agent` means a setuid bit set through the mount runs as `agent`, not lilijoy. Symlinks resolve in the agent's own context, cross-mount hardlinks fail with EXDEV, and `/home/agent` (0700) keeps the `allow_other` mount private. Two things I didn't verify. First, whether Xwayland (`@/tmp/.X11-unix/X0`, an abstract socket reachable from the host netns) accepts any local uid beyond the xauth cookie. `xhost` isn't installed, so this is PLAUSIBLE-unchecked, and it would be HIGH if open. Second, whether systemd refuses to automount over a `/home/agent/research` the agent swapped for a symlink between boots. I believe it does (the "not canonical, contains a symlink" refusal), but haven't confirmed it on the pinned systemd.

_security finished 2026-10-06T17:45:09Z (code 7dd86d9021fc1e95) -- see Findings above._

### F9 -- the egress wall fails open when the firewall is stopped or a reload fails

Whole-branch review, confirmed in a VM.
- After `systemctl stop firewall`, the agent reached the LAN.
- `firewall-reload` runs `extraStopCommands` first, and the stop script on a
  failed start. So any broken `extraCommands` anywhere on the host removes the
  agent's walls while `claude-remote-control` keeps running.

**Fix:** the service gets `bindsTo` + `after` on `firewall.service`.


**FIXED 2026-10-06:** fixed in the review fix pass; pinned by tests/agent-user.nix (test failed first, then passed)

### F10 -- a missing Research folder wedges the automount until reboot

Whole-branch review, confirmed in a VM. A few quick accesses while the source
is missing hit the mount unit's start limit. The automount then fails with
`mount-start-limit-hit`, and the agent gets "Permission denied" even after the
folder exists, until `reset-failed` or a reboot.

**Fix:** `StartLimitIntervalSec = 0` on the mount. Task 6 now creates the
folder before switching.


**FIXED 2026-10-06:** fixed in the review fix pass; pinned by tests/agent-user.nix (test failed first, then passed)

### F11 -- comment rationale moved out of the code (docs pass, 2026-10-06)

`docs/style-guide.md` keeps inline comments to mechanics and labels. This
prose was removed from comments and is kept here verbatim. Line numbers are
as of `f377d40`. Where an existing entry already says the same thing, it's
named.

- `modules/nixos/agent-user.nix:1-3` (file header, now cites this entry):
  "The agent's place: a separate Unix user on torrent where all
  non-sensitive agent work runs with no prompts. It never holds root, the
  user's keys or private data, so the boundary is this user, not a rule."
- `modules/nixos/agent-user.nix:36`: "own group, not the isNormalUser
  default `users` (lilijoy's group)". Same as G2.
- `modules/nixos/agent-user.nix:50-51`: "no inbound ssh: it can write its
  own authorized_keys, and a login shell would sit outside the service
  sandbox". Same as F8.
- `modules/nixos/agent-user.nix:58-60`: "agent-egress: the agent uid can't
  reach the LAN or tailnet (the tailnet ACL is flat); the rest of the
  internet stays open, and loopback stays reachable for DNS via resolved".
  The DNS part is Review focus 5. The comment didn't mention the `nixbld`
  jump; it now does and cites F2.
- `modules/nixos/agent-user.nix:88-91`: "bindfs: only Vault/Research, shown
  to the agent as its own; anything it creates lands lilijoy:users in the
  real folder Obsidian syncs. automount, not boot-time: /home is a late ZFS
  mount, and the source is user data (created once by the user), never by
  root inside their home". The "late ZFS mount" part was wrong; see G3's
  dated note.
- `modules/nixos/agent-user.nix:95-99` (the `claude-remote-control` unit,
  now cites this entry): "the phone reaches the agent through this: Remote
  Control server mode, sessions spawned in ~/work with no permission
  prompts (the walls are this user, agent-egress and the Research-only
  mount). ~ itself can't be the cwd: Claude never saves trust for a home
  dir. Skipped until the one-time `claude auth login` writes credentials".
  The cwd reason is also in Global constraints.
- `modules/nixos/agent-user.nix:151-152`: "systemd units, not fileSystems:
  NixOS VM tests replace fileSystems wholesale (qemu-vm mkVMOverride), which
  would leave the mount untested". Same as G3.
- `modules/nixos/agent-user.nix:160-161`: "a missing source fails each
  access; never let that hit the start limit and wedge the automount until
  reboot". Same as F10.
- `modules/flake/hosts.nix:47` (now cites this entry): "the agent's place:
  torrent only, not profile-pc". Same as Global constraints, "Torrent only".
- `tests/agent-user.nix:1-8` (now cites this entry): "Does the agent user
  actually live in its own place? The agent's place is a separate Unix user
  on torrent: everything non-sensitive runs there with no prompts, so the
  boundary has to hold without anyone watching. A build can't show that — a
  home dir's mode, a group membership or a nix-daemon allow-list only exist
  at runtime — so this boots a VM with a stand-in for the real user's home
  and asserts from the agent's side."
- `tests/agent-user.nix:128`: "IPv6: the LAN's global prefix is dynamic, so
  all v6 but loopback is refused". Same as F1's dated note.
- `tests/agent-user.nix:158`: "no inbound shell: its own authorized_keys
  would be outside the sandbox". Same as F8.


**FIXED 2026-10-06:** prose moved here, comments now cite plan anchors

### F12 -- docs didn't mention the new principal (docs pass, 2026-10-06)

The code shipped without any mention of the `agent` user outside the plan
and the generated inventory. Changed:
- `docs/architecture.md`: the host table was stale. torrent was missing
  `agent-user`, and `backup-canary` was missing on thinkpad, torrent and
  homelab, as was `backup-restore-test` on homelab (checked against
  `modules/flake/hosts.nix`). A short note on torrent's second principal
  now follows the "structurally unusual" hosts.
- `docs/hardening.md`: a new "The `agent` user" convention covering the
  user, the `agent-egress` chain, the `nixbld` jump and its effect on
  lilijoy's own builds, the firewall binding, and the uid-match limit.
- `docs/threat-model.md`: an "Added since the current model" table with
  the `agent` principal. The current model is a dated audit file, so it
  was left alone.
- `hosts/torrent/README.md`: an "Agent user" section, outside the inventory
  markers. `scripts/doc-host.sh torrent` was re-run and the inventory
  block was already current.

**FIXED 2026-10-06:** docs updated in the same docs pass

_docs-updater finished 2026-10-06T17:58:31Z (code 948e00a745ba7d31) -- see Findings above._

### F13 -- the full-scope login brings account-level session tools into the agent

Found in the done-check, 2026-10-06. `/mcp` in a phone session showed one
server, `claude-code-remote`, injected by Remote Control. Its tools act on the
user's whole claude.ai account:
- **`create_session`, `send_message`, `list_sessions`:** messages to the
  user's other sessions are held by default, because the agent bypasses
  permission prompts (`docs/en/cross-session-messaging`).
- **`create_trigger`, `send_later`:** cloud sessions and routines, which run
  **with the user's claude.ai connectors and their Claude GitHub App**.

Those are outside every wall here, so the agent's place could start work with
the user's authority. That's the crossing the design forbids (README, D19/D20).

**Fix:** the oneshot `claude-agent-settings` merges
`deniedMcpServers: [{serverName: "claude-code-remote"}]` and
`disableClaudeAiConnectors: true` into `~agent/.claude/settings.json`. That file
is CLI-owned, so the keys are merged rather than symlinked. The VM test pins
the merge and that CLI keys survive it.

**Not verified:** whether `deniedMcpServers` blocks a server Remote Control
injects itself. The docs say "wherever it's defined" but don't list this case.
Check on the host after switching: a new phone session's MCP list must show
no `claude-code-remote`.
