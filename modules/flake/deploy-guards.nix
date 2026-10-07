_: {
  # shared shell fragment for pull-deploy/push-deploy safe-switch checks; a
  # plain string, not a derivation, so it works on any pkgs variant.
  # consumers must capture config.flake.deployGuardsScript in their outer
  # `let`, before the inner module's `config` shadows it (docs/architecture.md)
  flake.deployGuardsScript = ''
    # per-invocation safe.directory: root's global git config is a read-only
    # home-manager store symlink. `-c` is protected scope, where
    # safe.directory is honoured; a function so no call site misses it
    git() { command git -c safe.directory="$PWD" "$@"; }

    require_clean_master() {
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
      # root may never have seen the origin host before
      local ssh_opts="-o StrictHostKeyChecking=accept-new"
      # root has no SSH identity of its own on PC hosts; use the user's key
      if [ -n "''${DEPLOY_GUARDS_IDENTITY_FILE:-}" ]; then
        ssh_opts="-i $DEPLOY_GUARDS_IDENTITY_FILE $ssh_opts"
      fi
      export GIT_SSH_COMMAND="ssh $ssh_opts"
      git fetch origin
      git merge --ff-only origin/master
    }

    # $1: minimum seconds between switches. $2: epoch timestamp of the last
    # switch (/nix/var/nix/profiles/system's mtime, local or remote)
    check_min_switch_interval() {
      local min_seconds="$1" last_switch_epoch="$2" now elapsed
      # security: $2 may be printed by the remote target, and bash arithmetic
      # executes `x[$(...)]` payloads; validate as a plain integer first.
      # fails closed (exit 1), unlike the skip-guards (exit 0).
      # "" not a pair of single quotes: that would end the Nix string
      case "$last_switch_epoch" in
        "" | *[!0-9]*)
          echo "Refusing non-numeric last-switch timestamp from target: [$last_switch_epoch]" >&2
          exit 1
          ;;
      esac
      now=$(date +%s)
      elapsed=$(( now - last_switch_epoch ))
      if [ "$elapsed" -lt "$min_seconds" ]; then
        echo "Last switch activated $elapsed seconds ago (minimum $min_seconds), skipping this scheduled run."
        exit 0
      fi
    }

    # $1: space-separated systemd unit names. skips (does not kill) if any
    # is currently active
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
