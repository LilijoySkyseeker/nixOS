# Testing a change before it lands

Evaluation and build success against real host configs carry most of the
weight here; `tests/` adds a small number of NixOS VM tests where a build
genuinely cannot tell you whether something works. This consolidates
what's scattered across `AGENTS.md`'s command list into one place: what
each check actually catches, and when to reach for it.

## The layers, cheapest to most thorough

1. **`nixfmt <file>` / `statix check .` / `deadnix .`** — formatting
   and lint only. Catches style issues and genuinely dead code, not
   correctness. Cheap enough to run on every edit.
2. **`nix flake check --no-build`** — evaluates every
   `nixosConfiguration` (and any other flake output) without
   realizing a build. Catches option-type errors, missing arguments,
   infinite recursion, and anything else that fails at eval time.
   Fast relative to a build, but a config can evaluate fine and still
   fail to build (a package that doesn't exist on the pinned channel,
   a build script bug) or fail at runtime (a systemd unit that
   evaluates fine but crashes when it actually starts).
3. **`nixos-rebuild build --flake .#<host>` (never `switch` without
   asking)** — actually realizes the closure. This is what the
   `pre-push` git hook runs automatically (see below) and what
   `AGENTS.md` calls "the closest thing this repo has to a test
   suite." Catches build failures `flake check` doesn't (missing
   packages, failing derivations) but says nothing about runtime
   behavior — a unit can build fine and still be broken when it
   actually runs.
4. **VM-test the change — the default before anything touches a live
   host, not an occasional extra.** Two forms, see
   `docs/procedures/vm-testing.md` for the full mechanics and traps:
   - `nix build .#nixosConfigurations.<host>.config.system.build.vm` —
     boots the real host config in a throwaway VM. Generic, works for
     any host, and is the default sanity check ("does this still boot,
     do its units start") before switching `vps`/`homelab` or after
     any change with real activation risk.
   - `nix build .#checks.x86_64-linux.<name>` — a targeted
     `runNixOSTest` asserting on actual runtime behavior (multi-host
     interaction, a service doing its job), where it exists for the
     module being touched. Lives in `tests/`, wired up in
     `modules/flake/checks.nix`; currently `zrepl-replication` and
     `zfs-space-guard`. Write one per `vm-testing.md`'s guidance when a
     change's failure mode is runtime-only and none already covers it.

   Slow (minutes, boots one or more VMs), so skip only when something
   concrete prevents it — no meaningful boot behavior to check (a
   docs-only or comment-only edit), or a documented VM limitation makes
   the result meaningless (e.g. anything sops-backed, since the host
   key isn't in the VM — see `vm-testing.md`'s table). "It'll probably
   be fine" is not a reason to skip; a specific, statable blocker is.
5. **`nvd diff /run/current-system <new-closure-path>`** — a readable
   diff between what's currently running and a built-but-not-switched
   closure. Use this before ever switching a live host, to see exactly
   what would change (package versions, added/removed units,
   service restarts) rather than switching blind.
6. **Actually switching and observing** — the only layer that catches
   real runtime behavior (a service that builds and starts but
   misbehaves, a firewall rule that's syntactically fine but wrong).
   Only done when explicitly asked for — see `AGENTS.md`'s "never run
   `nixos-rebuild switch` ... unprompted" rule and `docs/agents.md`
   for why that's load-bearing here (these are real machines other
   people/services depend on, not disposable CI runners).

## What's automated vs. what isn't

- **`pre-commit` hook** — blocks obviously-plaintext secrets: a
  `secrets.yaml` file without a `sops:` metadata block, or a staged
  file containing a private-key PEM block. Not a full secrets scanner,
  just a last-resort catch for the most common mistake.
- **`commit-msg` hook** — enforces Conventional Commits format on the
  subject line (`<type>(<scope>)?: <subject>`), skipping merge/
  fixup/squash commits.
- **`pre-push` hook** — the main automated layer. For every commit
  being pushed, diffs the range against `hosts/`, `modules/`,
  `flake.nix`, `flake.lock`; for each host whose own directory changed
  *or* any of those shared paths changed (`modules/` covers
  `modules/nixos/`, `modules/home-manager/`, `modules/profiles/`,
  `modules/services/`, and `modules/flake/` alike, since they're all
  nested under it), runs `nixos-rebuild build --flake .#<host>` and
  blocks the push if any build fails. Bypass with `git push
  --no-verify` if you know what you're doing (e.g. already built it
  manually). This is why a docs-only commit that happens to touch
  `hosts/<name>/README.md` still triggers a real build — the hook
  matches by path prefix, not by file extension.
- **Not automated at all**: `nix flake check`, the `tests/` VM checks,
  `statix`, `deadnix`, `nvd diff`, and anything runtime (actually
  switching and watching a service) — all manual, run when relevant to
  what's being changed. The `pre-push` hook deliberately does not run
  the VM tests; they cost minutes each, and a push is the wrong place
  to discover that.

## When to reach for which layer

- Small, low-risk edit (a comment, a README, a package added to an
  existing list): `nixfmt` + let the `pre-push` hook catch anything
  real.
- Adding/changing a module's options surface, or anything touching
  `modules/flake/hosts.nix`'s composition: `nix flake check` first
  (fast feedback on eval errors) before waiting on a full build.
- Anything that will eventually need switching on a live host
  (`vps`, `homelab`): build, then `nvd diff` against
  `/run/current-system` on that host, and read the diff before asking
  to switch — don't just build-and-switch blind.
- Touching `modules/nixos/zrepl.nix` or any host's `myZrepl` block:
  run `nix build .#checks.x86_64-linux.zrepl-replication` as well as
  building the hosts. The retention rules in particular fail silently
  in a build — a keep rule that condemns the wrong snapshots produces
  a perfectly valid config file. See `docs/backups.md`'s "Gotchas".
- A change spanning multiple hosts sharing a module/profile: build all
  affected hosts, not just the one you're thinking about — the
  `pre-push` hook does this for you on push, but it's worth doing
  locally first for faster feedback than waiting for the push to fail.
