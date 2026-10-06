---
name: verify-a-change
description: How far to verify a change to this NixOS fleet before it lands, and the order for landing it on a live host. Use when deciding whether a build is enough or a VM test is needed, when a change will be switched on vps or homelab, when touching zrepl/backups, or when writing the "verified to rung N" line in a PR.
---

# Verifying a change

Two separate questions: how much a claim about a change is warranted (the
evidence ladder), and the order of operations for landing it on a live
host (the deploy sequence).

**A fix that is not declarative and reproducible is no fix at all.** A
value patched by hand on a live host doesn't count until it's in this
repo's Nix and deployed from it; the next rebuild silently reverts it.

## The evidence ladder

Each rung outranks the ones below it when they disagree, because each can
be wrong in a way the next one catches. Climb as far as the change
warrants, not to the cheapest rung that agrees with you.

1. **Documentation**: what a doc or option description says. Drifts from
   the config it describes.
2. **Source code**: the module, the pinned nixpkgs implementation, the
   upstream project. What the code *would* do.
3. **Ran it locally, and read what came out.** For Nix: it evaluates
   (`nix flake check --no-build`) and builds
   (`nixos-rebuild build --flake .#<host>`), and you read the result:
   the generated unit or config file, or
   `nvd diff /run/current-system <new-closure>`. For a script or hook:
   run it on input it should accept *and* input it should refuse. A
   green exit with unread output is only the mechanical half.
4. **VM test**, the default before anything touches a live host. See
   [vm-testing.md](vm-testing.md): `system.build.vm` for "does it still
   boot", a `runNixOSTest` under `tests/` for "does it actually work".
   Skip only for a specific, statable reason (docs-only, or sops-backed
   so the VM has no host key), never "it'll probably be fine".
5. **A real switch, observed.** Only when the user asks for it.

Lint (`nixfmt`, `statix`, `deadnix`) is not a rung: the git hooks enforce
it, and it says nothing about what the change does.

**Declare the rung in the PR description**: the highest rung actually
reached, then what was skipped and why. For example: "Verified to rung 3
(built, output inspected); rung 4 skipped because the secret is
sops-backed and the VM has no host key."

## The deploy sequence

For a change going to a live host (`vps`, `homelab`):

1. **Build** the target host.
2. **`nvd diff /run/current-system <new-closure>`** on that host, and read
   what would change: versions, added or removed units, restarts.
3. **Switch**, only when explicitly asked.
4. **Observe** the units that changed actually running.

## Which rung for which change

- Small, low-risk edit (a comment, a README, a package added to a list):
  the hooks plus reading what they printed.
- A module's options surface, or `modules/flake/hosts.nix`'s composition:
  `nix flake check --no-build` first for fast eval feedback.
- Anything that will be switched on `vps` or `homelab`: rung 4, then the
  deploy sequence.
- `modules/nixos/zrepl.nix` or any `myZrepl` block: also run
  `nix build .#checks.x86_64-linux.zrepl-replication`. Retention rules
  fail silently in a build: a keep rule that condemns the wrong snapshots
  is a perfectly valid config file. See `docs/backups.md`, "Gotchas".
- A change to a shared module or profile: build every affected host
  locally before pushing; the pre-push hook will, but slower to fail.
