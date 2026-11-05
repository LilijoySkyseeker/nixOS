{ pkgs, deployRevisionScript }:
pkgs.runCommand "deploy-revision"
  {
    nativeBuildInputs = [ pkgs.git ];
  }
  ''
    set -euo pipefail
    ${deployRevisionScript}

    export HOME=$TMPDIR
    git config --global user.email t@example.invalid
    git config --global user.name test
    git config --global init.defaultBranch master

    fail() { echo "FAIL: $*" >&2; exit 1; }
    expect() {
      local got
      got=$(revision_relation "$mirror" "$2" "$3")
      [ "$got" = "$1" ] || fail "$4: expected $1, got $got"
      echo "ok: $4 -> $got"
    }

    git init -q origin
    cd origin
    git commit -q --allow-empty -m one
    one=$(git rev-parse HEAD)
    git commit -q --allow-empty -m two
    two=$(git rev-parse HEAD)
    git checkout -q -b side "$one"
    git commit -q --allow-empty -m side
    side=$(git rev-parse HEAD)
    git checkout -q master
    cd ..

    mirror=$TMPDIR/mirror.git

    mirror_fetch "$mirror" "file://$TMPDIR/origin"
    [ "$(mirror_master "$mirror")" = "$two" ] || fail "mirror master is not origin's"
    echo "ok: mirror created at master"

    expect current "$two" "$two" "running the target"
    expect behind "$one" "$two" "running an ancestor"
    expect manual "$two" "$one" "running ahead of the target"
    expect manual "$side" "$two" "running a branch commit"
    expect manual "" "$two" "revision unknown"
    expect manual "$two-dirty" "$two" "dirty build"
    expect manual "$(printf 'f%.0s' {1..40})" "$two" "sha not in the mirror"
    expect manual '$(touch pwned)' "$two" "shell in the revision"
    [ ! -e pwned ] || fail "revision string was executed"

    decide() {
      local got
      got=$(deploy_decision "$mirror" "$2" "$3" "$4")
      [ "$got" = "$1" ] || fail "$5: expected $1, got $got"
      echo "ok: $5 -> $got"
    }
    decide current "$two" "$two" "$two" "running and installed the target"
    decide deploy "$one" "$one" "$two" "both behind"
    decide deploy "$one" "$two" "$two" "profile set, activation failed or boot not rebooted"
    decide manual "$one" "$side" "$two" "a manual boot staged in the profile"
    decide manual "$side" "$two" "$two" "running a manual switch"
    decide manual "" "$two" "$two" "running revision unknown"

    git -C origin merge -q --no-ff -m merge side
    merged=$(git -C origin rev-parse HEAD)
    mirror_fetch "$mirror" "file://$TMPDIR/origin"
    expect behind "$side" "$merged" "a merged branch commit"

    is_revision "$two" || fail "a full sha is a revision"
    ! is_revision "''${two:0:12}" || fail "a short sha is not a revision"
    ! is_revision "$two-dirty" || fail "a dirty rev is not a revision"
    echo "ok: is_revision"

    git -C origin commit -q --allow-empty -m three
    three=$(git -C origin rev-parse HEAD)
    mirror_fetch "$mirror" "file://$TMPDIR/origin"
    [ "$(mirror_master "$mirror")" = "$three" ] || fail "refetch missed the new commit"
    expect behind "$merged" "$three" "after a refetch"

    touch $out
  ''
