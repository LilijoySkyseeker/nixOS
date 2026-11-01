# torrent

After a reinstall, or to check it's healthy, run
**`run0 agent-setup`**: it checks every piece the module can't declare (the
logins, the GitHub side) and walks you through only
what's missing. `--check` only reports.

The agent's `~/work` is shared with you at **`~/Agent`** (you're in group `agent`;
setgid plus a default ACL keep everything group-writable). Open, edit and
drop files there; put files for the agent in `~/Agent/inbox/`. Don't run
git, builds, direnv or your own Claude sessions in it as yourself: the
agent writes those files, and hooks or project settings in them would run
as you. Git already refuses agent-owned repos ("dubious ownership"); never
add a `safe.directory` for this path. Review the agent's code through its PRs.
