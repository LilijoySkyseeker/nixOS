# Deploy a revision, not a checkout

## Goal

"lets plan out a proper full declartive fix that will solve this for the
future": the auto-update chain from the agent's flake update through
homelab, vps and the PCs, checked end to end on 2026-10-21.

What that check found, all from hosts deploying "whatever master is now,
read from a git checkout" and gating it with clocks and dirty-checks:

- torrent's scheduled deploy has never succeeded: two untracked files in
  `~/dotfiles` make `require_clean_master` exit 0 every Thursday.
- a manual switch makes the next week's run skip (`minSwitchInterval`),
  so homelab will skip 2026-10-27 while vps still takes the update on
  10-28: push-deploy fetches master itself, so "servers first" is
  calendar order, not a gate.
- every skip exits 0, so only the 21/30-day staleness alerts notice.
- PC deploys run as root on a user-writable checkout (F-P7-01).
- a skipped pull-deploy still runs `reboot-if-kernel-changed` (homelab,
  2026-10-20).
- `agent-flake-update` has never run; a missing credentials file skips it
  silently.

## Your decisions

- 2026-10-21: PCs deploy master HEAD, not homelab's revision.
- 2026-10-21: a host running a manual deploy (a commit not on master's
  history, or a dirty build) is skipped and alerts, never reverted.
- 2026-10-21: no auto-merge of the flake-update PR yet. Your rule: once
  you have merged 6 flake-update PRs in a row without changes, automate
  it. This rule lives in the agent's notes, not in this repo yet.

## State

Implemented on this branch (2026-10-21): every host builds;
`deploy-revision` (fragment, git only) and `push-deploy-sandbox` (VM, real
push through the mirror) are the tests. Rollout needs one manual deploy of
each host from clean master, since no host records a revision yet and
vps's current dispatcher rejects the new revision check. The design:

1. `system.configurationRevision = self.rev or "dirty"` on every host.
2. A deploy makes the running revision equal a target revision:
   - already equal: exit, nothing to do (replaces `minSwitchInterval`);
   - running revision dirty or not an ancestor of the target: skip and
     alert (ancestry via GitHub's compare API, so no local checkout);
   - otherwise `nixos-rebuild <op> --flake
     github:LilijoySkyseeker/nixOS/<rev>#<host>`, then reboot only if
     this run changed the kernel.
3. Targets: homelab and the PCs take master HEAD; vps takes the
   revision homelab is running (read locally by push-deploy).
4. One alert: a host behind master for more than 8 days, or any skip
   other than "already at target". It replaces the profile-mtime and
   `flake.lock` staleness alerts.
5. `agent-flake-update` fails, not skips, when its credentials are
   missing.

Deleted: `deploy-guards.nix`, `minSwitchInterval` and the vps
dispatcher's `stat` exception, `/etc/nixos` and `~/dotfiles` as deploy
sources, `sshKeyPath`, the staleness alerts above, and
`pc-deploy-from-root-owned-checkout.md` (F-P7-01 closes with the
checkout). Manual homelab deploys become `nixos-rebuild switch --flake
.#homelab --target-host root@homelab` from torrent.

Kept: `protectedUnits`, homelab's non-Persistent timers, the Tue/Wed/Thu
schedule, `boot` on the PCs, the `vps-deploy` dispatcher, PR #155.

## Next

1. Write a `runNixOSTest` for the chain (homelab, vps, PC nodes,
   `git+file://` flake source): a new commit reaches homelab then vps
   from homelab's revision; a dirty manual deploy skips and alerts; a
   second run is a no-op; reboot only after a kernel change.
2. Implement, homelab first, then vps, then PCs, in one PR.
3. `/security-review` before the PR opens (deploy auth and root paths).
