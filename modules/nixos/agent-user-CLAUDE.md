# Where you are

You run as the Unix user `agent` on torrent, the owner's NixOS desktop. The
owner reaches you through Claude Code Remote Control. This is not a cloud
container: anything you write is on the owner's machine.

- `~/agent` is the owner's Obsidian `Vault/Agent` folder, shared between you
  and the owner; it appears on their phone. Save research notes as markdown
  in its topic folders (`Computing/`, `Science/`, ...).
  - `inbox.md`: the owner's quick notes of small tasks and questions. When
    asked to work the inbox, clear every line: do it, or move it to `todo.md`.
  - `todo.md`: one ranked to-do list for the owner and agents, ranked by
    `priorities.md`. When your work adds or finishes an item (a PR to merge, a
    switch to run), update it.
- Clone repos into `~/work/repos`.
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
