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

## Never do these unprompted

- **Edit or decrypt `secrets/*`**, even to debug.

## Before changing things

- **Missing tooling is a bug.** Add debug tools to
  `modules/flake/debug-tools.nix` (shared by the dev shell and every
  host, always from unstable); dev-only tools go in `devshell.nix`.
- **Remote installs:** boot it in a local VM first, and build locally,
  never on the target (`vps` can run out of memory building its own
  closure). See `docs/procedures/new-host.md`.
- **Security review:** a change that touches firewall rules, open ports,
  secrets wiring, authentication, or adds or exposes a service gets
  a security review before the PR opens (Claude's `/security-review`),
  and in parallel a
  review of the branch against `master` by an agent of another model
  family, started with `paseo run` (the `other-agents` skill).

## Git and PRs

- **The why goes in the commit body**: the constraint, the decision and
  who made it, what was tried. `git blame` finds it there. Code comments
  say what the code does, tersely.
- **The PR description** carries the goal, the user's decisions, how far
  the change was verified ("Verified to rung N", see `verify-a-change`),
  and anything knowingly left open.
- Update docs in the same commit as the change they describe.

## Access

`homelab` and `vps` accept `root@<host>` SSH from torrent's own keys (`vps`
over Tailscale only). A failed bare `ssh <host>` isn't proof of no
access; retry as root. On `torrent` itself, run commands locally.
`torrent` and `thinkpad` accept no interactive root SSH, and `thinkpad`
may be offline. The `agent` user has no route to the LAN or tailnet at
all.

## Where to look

| Doing | Read |
|---|---|
| Restores | `docs/procedures/backup-restore.md` |
| A new host | `docs/procedures/new-host.md` |
| Secrets | `docs/procedures/secrets.md` |
| A job at the machine (reinstall, disks, firmware, anything across reboots) | `docs/procedures/toolbox-stick.md` |
| Editing any `.nix` file | `.claude/rules/nix.md` |
| Editing `hosts/`, `modules/` or `.sops.yaml` | `.claude/rules/hardening.md` |
