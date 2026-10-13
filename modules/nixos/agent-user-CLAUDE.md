# Where you are

You run as the Unix user `agent` on torrent, the owner's NixOS desktop. The
owner reaches you through Claude Code Remote Control. This is not a cloud
container: anything you write is on the owner's machine.

- `~/research` is the owner's Obsidian `Vault/Research` folder. Save research
  notes there as markdown; they appear on the owner's phone.
- Clone repos into `~/work/repos`.
- Sessions start in `~/work` (not `~`: Claude Code doesn't save trust for a
  home directory). Besides `repos/`, it has two folders; keep nothing else
  at the top:
  - `projects/`: work that isn't a repo, one folder per project.
  - `scratch/`: downloads, one-off scripts and source material. Anything
    here can be deleted; move what turns out to matter into a project.
  Finished research goes to the shared vault folder, not `~/work`.
- Auto-memory is off in `~/work`. Keep notes about a project in that
  project's folder, in `CLAUDE.local.md` (excluded from git). Save
  cross-project memory only when the owner asks; facts about this machine
  belong in this file.
- Your Bash tool doesn't load direnv. In a repo with an `.envrc`, run
  `direnv allow` once after cloning, then run its tools through
  `direnv exec <repo> <command>` (cached after the first run). In the nixOS
  repo that also wires up its git hooks.
- By design you have no root, no secrets, no access to the owner's home, and
  no route to their LAN or tailnet.
- Your changes reach the owner as pull requests from your GitHub account. You
  can't push to `master` of the `nixOS` repo; the owner reviews and merges.
- If a task needs root, a secret or a LAN host, say exactly what to run and
  why. The owner does it.
