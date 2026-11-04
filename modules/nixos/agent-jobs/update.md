You are running unattended as `agent-update`, the daily agent job
(00:15): nobody is watching this session. Your results are one pull
request the owner reviews, the fleet's security file
`~/research/Fleet/Security.md`, and your last message. Nothing
auto-merges: the owner merges the PR by hand. The hosts deploy master
every night (homelab and the PCs 03:00, vps 04:00): a merged update is
live on homelab and vps the next night, and staged on the PCs, live
after their next reboot (thinkpad stages it only on AC power).

Update the nixOS flake's inputs, check the security news against the
fleet and against what the update fixes, and keep `Security.md` true.

## The update

1. Work in `~/work/repos/nixOS` (clone `LilijoySkyseeker/nixOS` there if it
   is missing). Fetch `origin`, and make a fresh worktree of `origin/master`
   on branch `update`. If an open PR from `update` already exists, redo
   the update on that branch from the new `origin/master` and force-push
   it: the branch belongs to this job alone.
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
3. Run `nix flake update`.
4. Build every host in `nixosConfigurations` with
   `nixos-rebuild build --flake .#<host>`, and run `nix flake check -L`,
   which also runs every VM test. Fix breakage the update caused when the
   fix is clear (a renamed option, a package with a direct replacement).
   Leave anything you can't fix confidently failing, and say so.
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

## Security

7. **Know the fleet:** each host's services and what faces the internet
   (`vps` above all), and the versions that ship, on `master` and in your
   update (`nix eval --raw .#nixosConfigurations.<host>.pkgs.<pkg>.version`,
   `.config.boot.kernelPackages.kernel.version`). Include the agents' own
   tools (Claude Code, Codex, Paseo) and the agent-user setup on torrent.
8. **Know what's already known:** `Security.md` (its "Checked through"
   date says when the last run looked) and the open PRs in
   `LilijoySkyseeker/nixOS`.
9. **Look** at everything since that date (the past 7 days if there is
   none):
   - NixOS: nixpkgs issues and PRs labelled `1.severity: security`, the
     NixOS Discourse security category, and whether fixes have reached
     the channels the fleet follows (status.nixos.org);
   - advisories: oss-security (`https://seclists.org/rss/oss-sec.rss`),
     the CISA Known Exploited Vulnerabilities catalog, GitHub security
     advisories and OSV for software the fleet runs. A project's whole
     advisory list against the version the fleet ships, not only what's
     new: older advisories have been missed this way;
   - upstream announcements: the Linux kernel, OpenSSH, systemd,
     Tailscale, Mullvad, and each self-hosted service;
   - news: LWN (`https://lwn.net/headlines/rss`; its daily distro-update
     lists too), Ars Technica, BleepingComputer, Hacker News, for big
     events like #140's (a compromised CA, found in the news, fixed with a
     small stopgap that names its own removal condition).
   Read a source through its feed where it has one (`web-fetch --feed`).
10. **Judge each item:** does a host run the affected version, on master
    and after your update? Is it reachable (internet, tailnet, LAN, local
    only)? Is it exploited in the wild? Is the fix in a channel yet?
11. **Act.**
    - A fix that fits in the repo (a stopgap like #140, a version pin or
      override, a config mitigation, an option to turn off): its own
      commit in your PR, marked `# TODO: drop when <condition>` with a
      link, and build every host it touches.
    - Something only the owner can do (a device's firmware, a key to
      rotate, an account), or urgent (exploited, and reachable on the
      fleet): it goes under "You do" in your report, and this run stays
      unarchived.
12. **Keep `Security.md` true.** Its sections, by state; every entry has
    a date and its exit:
    - **Exposed and unfixed:** the fleet runs it and no fix is in a
      channel or the repo. Exit: the fix condition.
    - **Fixed upstream, not yet here:** fixed in a channel or your PR,
      not yet on `master`. Exit: the PR or channel that brings it.
    - **Accepted:** a risk the owner chose to keep, with the reason and
      its end condition.
    - **Checked, doesn't touch the fleet:** one line each, with why.
      Exit: 30 days after the date.
    Move an entry when its state changes, and delete it when its exit
    has come (fixed on `master`, end condition met, 30 days passed):
    delete, don't archive. The file holds only what's true and relevant
    today; git and the vault's snapshots keep the past. Update its
    "Checked through" date. The file is private: it stays in the vault.

## The PR

13. If the lock, `flake.nix` and the repo are unchanged, open no PR.
    Otherwise commit (a release move is its own commit), push, and open
    or update the PR. The repo is public, so its body says what the
    update fixes (by advisory or CVE) and the owner's actions, and never
    names an issue the fleet is still exposed to: those live in
    `Security.md` only. It also has what moved, the notable per-host
    changes, the release-note items that touch this repo, the
    workarounds dropped, and what you couldn't fix.
