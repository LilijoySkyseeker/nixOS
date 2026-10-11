# AGENTS.md

A flake-based NixOS/home-manager config for four hosts (`thinkpad`,
`torrent`, `homelab`, `vps`; see `nixosConfigurations` in
`flake.nix`), organized with the dendritic pattern: every `.nix` file
under `modules/` self-registers through flake-parts + import-tree. Secrets
are sops-nix. These are real machines the user relies on, and `vps` is
public-facing.

## Commands

Run tooling inside the dev shell: `direnv exec . <command>`, or a shell
where direnv is loaded. It provides `nixfmt`, `statix` and `deadnix`, and
sets `core.hooksPath` so the git hooks run.

- Build a host (never switch): `nixos-rebuild build --flake .#<host>`
- Evaluate everything: `nix flake check --no-build`
- VM and runtime tests: `nix build .#checks.x86_64-linux.<name>`
- How far to verify, and landing on a live host: the `verify-a-change` skill

The git hooks enforce the floor: `pre-commit` blocks plaintext secrets and
runs nixfmt, statix and deadnix on staged `.nix` files; `pre-push` runs
`nix flake check` and builds every host the push affects.

## Never do these unprompted

- **`nixos-rebuild switch`, or a deploy to a live host.** Building is
  free; switching changes a machine someone is using. Even when asked,
  prefer the user doing it or confirming first.
- **Edit or decrypt `secrets/*`**, even to debug. See
  `docs/procedures/secrets.md`.
- **Restart or reboot `torrent`**, the user's daily driver. Same tier as
  `git push --force` or `rm -rf`.
- **Install or invoke real `sudo`.** Every host aliases `sudo` to `run0`.

If a destructive local mistake happens anyway: every `myZrepl` host
(`homelab`, `torrent`, `thinkpad`) snapshots locally every 5 minutes, so
copy the path back from `<mountpoint>/.zfs/snapshot/<timestamp>/` (see
`docs/procedures/backup-restore.md`), then tell the user what happened.

## Before changing things

- **Check the nixpkgs channel.** `homelab` is on stable, the rest on
  unstable, so an option can exist on one host and not another
  (`docs/architecture.md` has the per-host table).
- **Before deleting a file, grep the repo for it.** Files under `files/`
  are often read by external tools (VIA/Vial, Picard, an ICC loader),
  not by Nix.
- **Missing tooling is a bug.** Add debug tools to
  `modules/flake/debug-tools.nix` (shared by the dev shell and every
  host, always from unstable); dev-only tools go in `devshell.nix`. Don't
  work around a missing tool with a raw `/nix/store` path: that once
  produced a false "the sets are gone" from an `ipset` that wasn't on
  PATH.
- **Remote installs:** boot it in a local VM first, and build locally,
  never on the target (`vps` can run out of memory building its own
  closure). See `docs/procedures/new-host.md`.
- **Security review:** a change that touches firewall rules, open ports,
  secrets wiring, authentication, or adds or exposes a service gets
  `/security-review` before the PR opens. `docs/hardening.md` has the
  standing rules.

## Git and PRs

- Branch from an up-to-date `master` and open a PR; the user reviews and
  merges every one, with a real merge commit. A direct commit to `master`
  is only for a typo-sized fix.
- Conventional Commits, enforced by the `commit-msg` hook:
  `type(scope): subject`.
- **The why goes in the commit body**: the constraint, the decision and
  who made it, what was tried. `git blame` finds it there. Code comments
  say what the code does, tersely (`.claude/rules/nix.md`).
- **The PR description** carries the goal, the user's decisions, how far
  the change was verified ("Verified to rung N", see `verify-a-change`),
  and anything knowingly left open.
- No AI attribution in commits or PRs. Claude Code's `attribution`
  setting is off for this; don't add it by hand.
- On a `flake.lock` conflict, regenerate with `nix flake lock` rather than
  hand-editing.
- Update docs in the same commit as the change they describe. When a host
  is added or removed, `docs/architecture.md`'s table and `README.md`'s
  must still agree.

## Handoff notes

Only for work that spans sessions, or holds a user decision that hasn't
reached a PR yet: one file at `docs/plans/<slug>.md`, short, with four
sections: **Goal** (the user's words), **Your decisions** (dated, only
what the user actually said), **State** (rewritten in place), **Next**.
Read any matching note before starting. When the work merges, its goal
and decisions go into the PR description and the note is deleted.

`docs/plans/{todo,in-progress,done,rejected}/` and the
`# plan: <date>-<slug>.md#D2` comments in code are an archive of the
earlier plan system. Grep them for history; don't edit them or add new
citations.

## Access

`homelab` and `vps` accept `root@<host>` SSH from torrent's own keys (`vps`
over Tailscale only). A failed bare `ssh <host>` isn't proof of no
access; retry as root. On `torrent` itself, run commands locally.
`torrent` and `thinkpad` accept no interactive root SSH, and `thinkpad`
may be offline. The `agent` user has no route to the LAN or tailnet at
all. Details: `docs/procedures/remote-access.md`.

## Tools

This file is the user's standing request to use the full toolset
(subagents, web search, workflows) without checking in first. That covers
which tools to use, never which actions: the rules above bind a subagent
exactly as they bind you.

## Where to look

| Doing | Read |
|---|---|
| Anything touching services, ports, secrets, containers | `docs/hardening.md` |
| Deciding whether exposing something is acceptable | `docs/threat-model.md`, `docs/accepted-risks.md` |
| Backups, replication, restores | `docs/backups.md`, `docs/procedures/backup-restore.md` |
| A new host or service | `docs/procedures/new-host.md`, `new-service.md` |
| Secrets | `docs/procedures/secrets.md` |
| How modules and hosts compose | `docs/architecture.md`, `docs/adr/` |
