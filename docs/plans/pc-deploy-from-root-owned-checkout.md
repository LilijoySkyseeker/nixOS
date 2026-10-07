# PC deploys run as root on a user-writable checkout

## Goal

Close audit finding F-P7-01 (part of C2): torrent's and thinkpad's
`pull-deploy` runs as root in `/home/lilijoy/dotfiles`, which `lilijoy`
can write, so code running as `lilijoy` can get root through it.

## Your decisions

- 2026-10-06: noted for future work. Turning the PC timers back on
  (deploy-schedules PR) went ahead, because it doesn't widen the hole:
  the same code already ran on every manual deploy, and `lilijoy` has
  other root-equivalent paths today (`libvirtd`, the `input` group, a
  passphrase-less SSH key trusted by root on the servers).

## State

Open. How it works today:

- `modules/flake/deploy-guards.nix` runs git with
  `-c safe.directory="$PWD"`, switching off git's ownership refusal.
- `fetch_and_merge_master` does `git merge --ff-only origin/master`,
  which exits 0 doing nothing when local `master` is ahead, so a local
  commit gets built and installed as the next boot entry.
- git runs any `core.fsmonitor`, `core.hooksPath` or `post-merge` hook
  the user configured, as root.

## Next

Pick one:

1. **Root-owned checkout** outside `$HOME`, for example
   `/var/lib/pull-deploy/nixOS`, cloned over HTTPS (public repo, so no
   user key and no `sshKeyPath`), with the `safe.directory` wrapper
   dropped for it.
2. **Minimum hardening** of the existing path: after the fetch, require
   `HEAD == origin/master`, and run git with
   `-c core.hooksPath=/dev/null -c core.fsmonitor=false`.

Option 1 fixes the cause; option 2 narrows it. The other root-equivalent
paths in C2 (`libvirtd`, `input`, the SSH key) are separate work.
