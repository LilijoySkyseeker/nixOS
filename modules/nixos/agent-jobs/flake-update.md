You are running unattended as `agent-flake-update`, the first of the
weekly agent jobs: nobody is watching this session, and your reply only
stays in its Paseo session. Your results are a pull request the owner reviews and
the "Updates" section of this week's fleet report.

Update the nixOS flake's inputs, move the stable inputs to a new NixOS
release when one has shipped, and drop the workarounds the update makes
unnecessary.

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
   Never move `nixpkgs-homelab` or `home-manager-homelab` to a new release
   while their `TODO: drop when` in `flake.nix` is there (step 3 still
   updates them within their release); that move is a planned step, not
   this job's.
3. Run `nix flake update`. If neither the lock nor `flake.nix` changed,
   skip to step 8.
4. Build every host in `nixosConfigurations` with
   `nixos-rebuild build --flake .#<host>`, and run
   `nix flake check --no-build`. Fix breakage the update caused when the
   fix is clear (a renamed option, a package with a direct replacement).
   Leave anything you can't fix confidently failing, and say so in the PR.
5. **Workarounds.** Find every `# TODO: drop when <condition>` in the repo
   (`git grep -n "TODO: drop when"`). For each whose condition the new lock
   meets (the upstream fix is in the locked revision of the input it names:
   check the package version, or that the fix's commit is an ancestor of
   the locked rev), remove the workaround in its own commit, and rebuild
   the hosts it touched. Leave the others; `agent-maintenance` watches
   them.
6. For each host, compare the closures against the current `master` build
   (`nix store diff-closures`). Note the bumps that matter (kernel, desktop,
   services the host runs) and anything removed.
7. Commit (a release move is its own commit), push,
   and open or update the PR. The description says what moved, the
   notable per-host changes, the release-note items that touch this repo,
   the workarounds dropped, how far you verified (the `verify-a-change`
   skill's rungs), and what you couldn't fix.
8. **Report.** Create this week's fleet report at
   `~/research/Fleet/Weekly/YYYY-MM-DD.md`, dated by this week's Monday,
   so every job writes to one file all week. The folders may not
   exist yet. Give it a `# Fleet report YYYY-MM-DD` title if it's new, and write its
   `## Updates` section: the PR link, the moves that matter, workarounds
   dropped, anything failing. A quiet week is one line.
