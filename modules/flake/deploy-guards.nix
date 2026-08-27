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
    # Supply safe.directory per-invocation instead of writing it into
    # git's global config.
    #
    # A service running as root against a user-owned flakeDir (e.g.
    # myPullDeploy on a PC host, ~lilijoy/dotfiles) otherwise hits git's
    # "dubious ownership" refusal on every git command.
    #
    # This was `git config --global --add safe.directory "$(pwd)"`, which
    # broke every scheduled deploy on the fleet: root's
    # ~/.config/git/config is a home-manager symlink into the nix store,
    # git writes its lockfile beside the target, and the store is
    # read-only. So the guard died on its very first line with "could not
    # lock config file ...: Read-only file system", taking auto-switch and
    # push-deploy-vps with it -- silently, for two days, because a guard
    # failure is not something anything watches (F-P7-09). Writing to a
    # dotfile that another part of the system owns declaratively was the
    # underlying mistake; not writing at all is the fix.
    #
    # `-c` is "command" scope, which git-config(1) SCOPES counts as
    # *protected* configuration, and safe.directory is only honoured in
    # protected scopes -- so this genuinely applies where a repo-local
    # value would be silently ignored. Verified against git's own docs
    # rather than assumed.
    #
    # Wrapped as a function rather than added to each call site because
    # the consumers of this fragment run ~19 git commands between them:
    # patching call sites means a later one silently misses the flag and
    # reintroduces this. `command git` avoids recursing into the wrapper.
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
      # root's own known_hosts may never have trusted the origin remote's
      # host before (e.g. a PC host's root user, vs. lilijoy's own
      # already-populated known_hosts) -- accept-new rather than fail
      # closed on first contact, same pattern myPushDeploy already uses
      # for its own SSH usage.
      local ssh_opts="-o StrictHostKeyChecking=accept-new"
      # a caller running as root against a user-owned flakeDir (e.g. a PC
      # host, where root has no home-manager profile and thus no SSH
      # identity of its own at all) can point this at that user's key --
      # root can read it fine regardless of its file permissions.
      if [ -n "''${DEPLOY_GUARDS_IDENTITY_FILE:-}" ]; then
        ssh_opts="-i $DEPLOY_GUARDS_IDENTITY_FILE $ssh_opts"
      fi
      export GIT_SSH_COMMAND="ssh $ssh_opts"
      git fetch origin
      git merge --ff-only origin/master
    }

    # $1: minimum seconds between switches. $2: epoch timestamp of the last
    # switch (/nix/var/nix/profiles/system's mtime, local or remote).
    check_min_switch_interval() {
      local min_seconds="$1" last_switch_epoch="$2" now elapsed
      # $2 is NOT necessarily local: myPushDeploy feeds it from
      # `ssh <targetHost> stat -c %Y /nix/var/nix/profiles/system`, so its
      # value is whatever the *remote* host chose to print. Bash evaluates
      # arithmetic operands recursively, and an array-subscript payload of
      # the form `x[$(...)]` runs a command substitution inside $(( )) --
      # so passing this straight into arithmetic gave a compromised target
      # host code execution as root on the deployer, reversing the one
      # direction of that relationship the threat model treated as a
      # boundary. Reject anything that is not a plain decimal integer
      # before it reaches arithmetic context.
      #
      # This fails CLOSED (exit 1), unlike the skip-guards below which
      # deliberately exit 0: a non-numeric timestamp means the target is
      # either broken or lying, and neither is a reason to carry on.
      # NB: the empty-string pattern below is written with double quotes
      # rather than the more idiomatic pair of single quotes. This whole
      # fragment lives inside a Nix indented string, and a bare pair of
      # single quotes terminates that string -- including inside what looks
      # to a reader like a shell comment.
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
