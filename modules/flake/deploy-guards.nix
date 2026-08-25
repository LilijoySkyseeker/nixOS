{ ... }:
{
  # Shared shell fragment for the auto-update/pull-deploy/push-deploy
  # modules' safe-switch checks: dirty/branch guard, fetch+ff-only-merge,
  # min-time-since-last-switch (via /nix/var/nix/profiles/system's mtime,
  # which updates on any switch -- manual, push-deployed, or scheduled), and
  # a protected-unit guard so a scheduled switch defers instead of killing a
  # long-running job. A plain string, not a derivation, so it works
  # regardless of which pkgs variant (stable/unstable) the consuming host is
  # pinned to -- each consumer interpolates it straight into its own
  # `pkgs.writeShellScript`/service `script`.
  #
  # Consumers must capture `config.flake.deployGuardsScript` under a
  # distinct name in their own outer `let`, before their inner module's own
  # `config` shadows the flake-parts one (see docs/architecture.md's
  # "config shadowing" gotcha).
  flake.deployGuardsScript = ''
    require_clean_master() {
      # a service running as root against a user-owned flakeDir (e.g.
      # myPullDeploy on a PC host, ~lilijoy/dotfiles) otherwise hits git's
      # "dubious ownership" refusal on every run -- idempotent, harmless
      # to repeat, and scoped to $PWD (the caller has already cd'd into
      # flakeDir before sourcing this).
      git config --global --add safe.directory "$(pwd)"
      if [ -n "$(git status --porcelain)" ]; then
        echo "Working tree dirty, skipping this scheduled run."
        exit 0
      fi
      local branch
      branch=$(git rev-parse --abbrev-ref HEAD)
      if [ "$branch" != "master" ]; then
        echo "Not on master (on $branch), skipping this scheduled run."
        exit 0
      fi
    }

    fetch_and_merge_master() {
      # root's own known_hosts may never have trusted the origin remote's
      # host before (e.g. a PC host's root user, vs. lilijoy's own
      # already-populated known_hosts) -- accept-new rather than fail
      # closed on first contact, same pattern myPushDeploy already uses
      # for its own SSH usage.
      export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new"
      git fetch origin
      git merge --ff-only origin/master
    }

    # $1: minimum seconds between switches. $2: epoch timestamp of the last
    # switch (/nix/var/nix/profiles/system's mtime, local or remote).
    check_min_switch_interval() {
      local min_seconds="$1" last_switch_epoch="$2" now elapsed
      now=$(date +%s)
      elapsed=$(( now - last_switch_epoch ))
      if [ "$elapsed" -lt "$min_seconds" ]; then
        echo "Last switch activated $elapsed seconds ago (minimum $min_seconds), skipping this scheduled run."
        exit 0
      fi
    }

    # $1: space-separated systemd unit names. Skips (does not kill) if any
    # is currently active.
    check_protected_units_inactive() {
      local unit
      for unit in $1; do
        if systemctl is-active --quiet "$unit"; then
          echo "$unit is active, skipping this scheduled run."
          exit 0
        fi
      done
    }
  '';
}
