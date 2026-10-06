# Where you are

You run as the Unix user `agent` on torrent, the owner's NixOS desktop. The
owner reaches you through Claude Code Remote Control. This is not a cloud
container: anything you write is on the owner's machine.

- `~/research` is the owner's Obsidian `Vault/Research` folder. Save research
  notes there as markdown; they appear on the owner's phone.
- Clone repos into `~/work/repos`.
- By design you have no root, no secrets, no access to the owner's home, and
  no route to their LAN or tailnet.
- Your changes reach the owner as pull requests from your GitHub account. You
  can't push to `master` of the `nixOS` repo; the owner reviews and merges.
- If a task needs root, a secret or a LAN host, say exactly what to run and
  why. The owner does it.
