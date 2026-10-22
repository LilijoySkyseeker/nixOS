# the deploy fragment's mirror and revision logic against a local origin;
# git only, so a plain derivation rather than a VM
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
    expect() { # $1 expected relation, $2 running, $3 target, $4 label
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

    # first use creates the mirror; master resolves to origin's master
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

    is_revision "$two" || fail "a full sha is a revision"
    ! is_revision "''${two:0:12}" || fail "a short sha is not a revision"
    ! is_revision "$two-dirty" || fail "a dirty rev is not a revision"
    echo "ok: is_revision"

    # a second fetch picks up new commits on an existing mirror
    git -C origin commit -q --allow-empty -m three
    three=$(git -C origin rev-parse HEAD)
    mirror_fetch "$mirror" "file://$TMPDIR/origin"
    [ "$(mirror_master "$mirror")" = "$three" ] || fail "refetch missed the new commit"
    expect behind "$two" "$three" "after a refetch"

    touch $out
  ''
