# Where you are

You run as the Unix user `agent` on torrent, the owner's NixOS desktop. The
owner reaches you through Claude Code Remote Control. This is not a cloud
container: anything you write is on the owner's machine.

- torrent's hardware, as of 2026-10-17:
  - CPU: AMD Ryzen 7 9800X3D, 8 cores / 16 threads, up to 5.27 GHz, 96 MiB L3
  - RAM: 96 GB, plus a 16 GiB swap partition
  - GPU: AMD Radeon RX 7900 XTX (24 GB VRAM), plus the CPU's iGPU. Your
    sessions can't reach either: the unit's `PrivateDevices` hides `/dev/dri`
    (and `/dev/kvm`).
  - Disk: one 4 TB Samsung 990 PRO NVMe, a single ZFS pool (`zroot`) shared
    with the owner's home and `/nix`, about 80% full
  - Board: Gigabyte X870 AORUS ELITE WIFI7 ICE; Linux 6.18, NixOS unstable
- You may use the machine's full resources: run builds, tests and jobs
  in parallel and as large as the work needs, without asking first. The
  limits are hard ones, so you can't hurt the desktop by trying. Your
  sessions are capped at 24 GiB of memory and 4096 tasks, and have a lower
  CPU weight, which only matters when the CPU is contended. Nix builds
  run in the nix daemon, outside that cap, with 16 jobs and `kvm` and
  `nixos-test`, so VM tests do run. Disk is the one shared limit: clean
  up caches and build outputs you no longer need.
- `~/research` is the owner's Obsidian `Vault/Research` folder. Save research
  notes there as markdown; they appear on the owner's phone.
- `~/work` is shared with the owner, who sees it as `~/Agent` and opens,
  edits and drops files there. Sessions start here (not `~`: Claude Code
  doesn't save trust for a home directory). Keep nothing else at the top:
  - `repos/`: every clone goes in `~/work/repos`.
  - `projects/`: work that isn't a repo, one folder per project.
  - `scratch/`: downloads, one-off scripts and source material. Anything
    here can be deleted; move what turns out to matter into a project.
  - `inbox/`: files the owner drops for you. Move each into a project
    when you use it.
  Finished research goes to `~/research`, not `~/work`.
- Auto-memory is off in `~/work`. Keep notes about a project in that
  project's folder, in `CLAUDE.local.md` (excluded from git). Save
  cross-project memory only when the owner asks; facts about this machine
  belong in this file.
- Codex (OpenAI's CLI, logged in, with the `codex` plugin) is your second
  opinion from a different model. Before a PR that would be costly to get
  wrong (agent-user, firewall, deploys, migrations, deletions), have it
  review the branch: `/codex:review` and `/codex:adversarial-review` are
  the owner's to type, so run the plugin's
  `scripts/codex-companion.mjs adversarial-review --wait --base master`
  with `node`, or hand the question to the `codex:codex-rescue` agent.
  Use it, too, when you're stuck or two designs look equally good. Treat
  its findings as input, not a verdict: check each against the code.
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
