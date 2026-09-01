# AGENTS.md

Guidance for Claude Code and other AI agents working in this repo. This file
is a **map, not the territory** — a short entrypoint into `docs/`, where the
actual conventions, rationale, and runbooks live. If something below and
something in `docs/` ever disagree, `docs/` wins; fix this file.

## What this is

A flake-based NixOS/home-manager dotfiles configuration managing multiple
hosts (`thinkpad`, `torrent`, `homelab`, `vps`, `isoimage` — see
`nixosConfigurations` in `flake.nix`), organized with the **dendritic
pattern** (flake-parts + import-tree): every `.nix` file under `modules/`
self-registers instead of being manually listed in an `imports`. Secrets are
encrypted with sops-nix.

## Where things live

| Doc | What's there |
|---|---|
| `docs/architecture.md` | How hosts/profiles/modules/services compose, the dendritic registration model, navigating "what does host X run," adding a new module, module-system gotchas. |
| `docs/style-guide.md` | Nix conventions actually in use (formatting, `my<Name>` options pattern, comment style, naming). |
| `docs/backups.md` | ZFS snapshotting and replication (zrepl): roles the shared module exposes, retention presets, the pruning/transport behaviours that are easy to get wrong, and what happens when a host is offline. |
| `docs/hardening.md` | Security-hardening conventions (sudo/run0, dedicated service users, systemd sandboxing, SSH lockdown, swap, rate-limiting). Opens with **eleven standing rules** harvested from the 2026-08-26 audit — secrets, network exposure, privilege, backups, verification, containers, observability. Read those before adding a service or opening a port. |
| `docs/skills/security-audit/` | The method for running a full fleet security + dead-config audit: threat model, parallel part audits, consolidation, remediation waves, doc harvest. Symlinked to `.claude/skills/security-audit`, so it is also invocable as a skill. Carries the worked examples from the 2026-08-26 run; `reference/lessons.md` is the traps list, worth reading before any audit-shaped work. |
| `docs/threat-model.md` | The standing threat model — adversaries, trust boundaries, severity rubric. A stable pointer at the current model (the copy inside the dated audit the part reports cite), plus how to supersede it. Read it before deciding whether exposing something is acceptable. |
| `docs/accepted-risks.md` | Risks audited and knowingly **not** fixed, with reasoning — so a later pass can tell "decided against" from "never noticed". Also lists what cannot be accepted yet because a decision is open. |
| `docs/audits/` | Point-in-time security audits, one dated directory each. Findings that become standing rules move to `docs/hardening.md`; risks left in place move to `docs/accepted-risks.md`. `2026-08-26/RESUME.md` is written to be picked up cold. |
| `docs/agents.md` | The reasoning *behind* the rules in this file and in `docs/procedures/workflow.md` — read when the summary alone isn't enough to act correctly. |
| `docs/procedures/workflow.md` | Pre-work checks and hard-confirm rules (never switch/reboot/sudo unprompted, VM-test before real deploys, build locality). Read this before making any change. |
| `docs/procedures/testing-changes.md` | Which validation layer to reach for (`nixfmt`/lint → `nix flake check` → `nixos-rebuild build` → `nvd diff` → switch), maps those layers onto `workflow.md`'s trust hierarchy, and what's automated (git hooks, plus the `workflow` skill's `verify-ladder` gate). |
| `docs/procedures/vm-testing.md` | Booting a change in a throwaway VM: `system.build.vm` for "does this host still boot", `runNixOSTest` (`tests/`, wired up in `modules/flake/checks.nix`) for "does it actually work". When a VM test is worth its minutes, and the traps in writing one. |
| `docs/procedures/backup-restore.md` | Getting data back out — file-level recovery, rollback, full dataset restore, and the offsite restic path. |
| `docs/procedures/new-host.md` / `new-service.md` | Runbooks for adding a host or a service. |
| `docs/procedures/secrets.md` | Secret rotation and the manual-secret-management policy — agents never edit or decrypt `secrets/*` themselves. |
| `docs/procedures/remote-access.md` | SSH/Tailscale key model, which hosts are Tailscale-only, the `vps-deploy` account. |
| `docs/procedures/updating-documentation.md` | Keeping this documentation itself in sync; where to log issues you spot but don't fix (`plan-new`, see below). |
| `docs/GIT_WORKFLOW.md` | Commit conventions, git hooks, day-to-day branching. |
| `docs/plans/{todo,in-progress,done,rejected}/` | Per-task plan files — decisions, gotchas, findings, citeable by bare filename. Check before assuming a described feature is fully deployed. Mechanics: `docs/skills/plan/SKILL.md`. |
| `docs/skills/`, `docs/agents/` | Project skills/subagents (`plan`, `workflow`, `security`, `docs-updater`) — canonical source, symlinked into `.claude/skills/`/`.claude/agents/`. |

## Commands

Enter the dev shell first (`nix develop`, or `direnv allow`) — it wires up
git hooks and `pull.rebase true`.

- Build (never switch) a host: `nixos-rebuild build --flake .#<host>` — the
  closest thing this repo has to a test suite.
- Whole-flake check: `nix flake check --no-build`.
- Runtime/VM tests: `nix build .#checks.x86_64-linux.<name>` — see
  `docs/procedures/vm-testing.md`. Not run by any hook.
- Lint: `statix check .` and `deadnix .`. Format: `nixfmt <file>`.
- Full breakdown of when to use which: `docs/procedures/testing-changes.md`.

## You have real SSH access

`homelab` and `vps` both accept interactive `root@<host>` SSH from this
machine's own keys (`vps` is Tailscale-only) — a failed bare `ssh <host>`
with no username is not evidence you lack access; retry as `root`. This
machine *is* `torrent` (check `hostname` if unsure) — don't SSH to it,
just run commands locally. `torrent` and `thinkpad` both set
`PermitRootLogin = "forced-commands-only"`, so neither accepts interactive
root SSH from anywhere, by design; `thinkpad` may also simply be offline
(it's a laptop). Full key model and per-host detail:
`docs/procedures/remote-access.md`.

## Missing tooling is a bug, not an obstacle to route around

If a tool you need for debugging isn't there, **add it declaratively** —
don't work around it with raw `/nix/store/...` paths.

**`modules/flake/debug-tools.nix` is the single source of truth**, shared
by the devshell *and* every host (via `profiles/default.nix`, which
`profile-pc` also imports). Add a tool there once and it lands in both
places, so the two can never drift into "I have it locally but not on the
host I'm debugging". Always resolved against **unstable**, including on
homelab, which is otherwise stable-pinned — debug tooling should behave
identically everywhere.

Only put dev-machine-only tooling (`nixfmt`, `statix`, `gh`, `sops`,
`nixos-anywhere`) directly in `devshell.nix`. Keep the shared list short:
it lands on every host including the public-facing one, so add on demand,
not speculatively.

Working around a missing tool with a store path is slow, easy to get
wrong, and has produced a **false negative** here — an `ipset list` that
printed nothing and looked like "the sets are gone" when the command
simply wasn't on `PATH`. Note the same trap with an unprivileged
`ip6tables -S`, which returns what looks like an empty chain when it is
really permission denied.

## The two rules that matter most

- **Never run `nixos-rebuild switch` or push a build to a live remote host
  unprompted.** Build-only is free; switching changes a running machine.
- **Never edit or decrypt `secrets/*` yourself**, even to debug.

Everything else that could bite you unprompted (reboot, real `sudo`, remote
build locality, VM-testing before a real install) is in
`docs/procedures/workflow.md` — read it before starting non-trivial work.

## Keeping this file and `docs/` current

This repo's documentation is expected to be updated as work happens: log new
patterns, mistakes to avoid, and insights to the right `docs/` file (not
here — this file should stay a short map). See
`docs/procedures/updating-documentation.md` for when to do a routine update
vs. flag something with `plan-new` vs. do a full rewrite.
