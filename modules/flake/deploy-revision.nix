_: {
  # shared shell fragment for pull-deploy/push-deploy: a host deploys a
  # revision of master from a root-owned bare mirror, never a checkout. a
  # plain string, not a derivation, so it works on any pkgs variant.
  # consumers must capture config.flake.deployRevisionScript in their outer
  # `let`, before the inner module's `config` shadows it (docs/architecture.md)
  flake.deployRevisionScript = ''
    # $1: mirror directory (a bare repo, created on first use), $2: repo URL
    mirror_fetch() {
      [ -d "$1/objects" ] || git init -q --bare "$1"
      git -C "$1" fetch -q --prune "$2" "+refs/heads/master:refs/heads/master"
    }

    # $1: mirror directory. prints master's revision
    mirror_master() {
      git -C "$1" rev-parse refs/heads/master
    }

    # $1: a revision read from a host's nixos-version or from another host
    # over ssh; it lands in a flake URL, so only a full hex sha passes
    is_revision() {
      case "$1" in
        "" | *[!0-9a-f]*) return 1 ;;
      esac
      [ ''${#1} -eq 40 ]
    }

    # $1: mirror directory, $2: revision the host runs ("" when unknown),
    # $3: target revision. prints:
    #   current  the host already runs the target
    #   behind   the host runs an ancestor of the target: deploy it
    #   manual   anything else (a branch commit, a dirty or unknown build):
    #            someone deployed by hand, so don't replace it
    revision_relation() {
      if [ "$2" = "$3" ]; then
        echo current
      elif is_revision "$2" && git -C "$1" merge-base --is-ancestor "$2" "$3" 2>/dev/null; then
        echo behind
      else
        echo manual
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
