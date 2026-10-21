You are running unattended from the `agent-flake-update` timer: nobody is
watching this session, and your reply only goes to the journal. Your
result is a pull request the owner reviews.

Update the nixOS flake's inputs, and move the stable inputs to a new NixOS
release when one has shipped.

1. Work in `~/work/repos/nixOS` (clone `LilijoySkyseeker/nixOS` there if it
   is missing). Fetch `origin`, and make a fresh worktree of `origin/master`
   on branch `flake-update`. If an open PR from `flake-update` already
   exists, redo the update on that branch from the new `origin/master` and
   force-push it: the branch belongs to this job alone.
2. **Stable release.** `flake.nix` pins `nixpkgs-stable` to
   `nixpkgs/nixos-YY.MM` and `home-manager-stable` to `release-YY.MM`.
   Move both to a newer release only when both of these are true:
   - `https://endoflife.date/api/nixos.json` lists that release with a
     `releaseDate` on or before today (a beta branch doesn't count);
   - `git ls-remote --heads https://github.com/nix-community/home-manager`
     shows `release-YY.MM` for it.
   When you move them, update both URLs and the comments that name the
   release, then read that release's notes (the "Backward Incompatibilities"
   section above all) for anything this repo's stable hosts use, and fix
   it. Never change `system.stateVersion` or `home.stateVersion`.
3. Run `nix flake update`. If neither the lock nor `flake.nix` changed,
   stop: no commit, no PR.
4. Build every host in `nixosConfigurations` with
   `nixos-rebuild build --flake .#<host>`, and run
   `nix flake check --no-build`. Fix breakage the update caused when the
   fix is clear (a renamed option, a package with a direct replacement).
   Leave anything you can't fix confidently failing, and say so in the PR.
5. For each host, compare the closures against the current `master` build
   (`nix store diff-closures`). Note the bumps that matter (kernel, desktop,
   services the host runs) and anything removed.
6. Commit with a Conventional Commit (`chore(flake): ...`; a release move is
   its own commit, `feat(flake): move stable hosts to NixOS YY.MM`), push,
   and open or update the PR. The description says what moved, the
   notable per-host changes, the release-note items that touch this repo,
   how far you verified (the `verify-a-change` skill's rungs), and what you
   couldn't fix.

The repo's `AGENTS.md` applies in full: never switch or deploy, never touch
`secrets/`. Log environment failures to `~/work/ENVIRONMENT.md` as usual.
