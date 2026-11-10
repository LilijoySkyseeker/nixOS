#!/usr/bin/env bash
# Merge the daily update PR when it changes nothing but flake.lock, the
# update job has asked for it (status hosts-built), and every input that
# moved is a newer commit of the same source on the same branch, with the
# hash Nix computes from that source. Anything else waits for the owner.
#
#   update-automerge.sh check [PR]   checks; prints the head it approved of
#                                    (and writes sha= to $GITHUB_OUTPUT)
#   update-automerge.sh merge SHA    approves exactly SHA and merges it
#
# check needs read access and nix; merge needs write and runs no checks of
# its own beyond the head still being SHA. Tests: SKIP_STATUS=1 skips the
# hosts-built check (old PRs have none); TEST_LOCKS="old new" compares
# those files instead of the PR's locks.
set -euo pipefail

repo=${GITHUB_REPOSITORY:-LilijoySkyseeker/nixOS}
bot=LilijoySkyseeker-agent
context=hosts-built
say() { echo "update-automerge: $*" >&2; }
skip() {
  say "not merging: $*"
  exit 0
}

pr_info() { gh api "repos/$repo/pulls/$1"; }
open_pr() { gh pr list -R "$repo" --head update --base master --state open --json number -q '.[0].number // empty'; }
# the PR is the bot's, from this repo's update branch, ready, into master
eligible() {
  jq -e --arg bot "$bot" --arg repo "$repo" '
    .user.login == $bot and .head.ref == "update" and .base.ref == "master"
    and .head.repo.full_name == $repo and (.draft | not)' >/dev/null
}
# is $3 on $2 and not behind $4 (when given), in GitHub repo $1
on_branch() {
  local status
  status=$(gh api "repos/$1/compare/$2...$3" --jq .status 2>/dev/null) || return 1
  case $status in behind | identical) ;; *) return 1 ;; esac
  [ -z "${4:-}" ] && return 0
  status=$(gh api "repos/$1/compare/$4...$3" --jq .status 2>/dev/null) || return 1
  case $status in ahead | identical) return 0 ;; *) return 1 ;; esac
}

check() {
  local pr=${1:-$(open_pr)} info head base files old new shape changed node
  [ -n "$pr" ] || skip "no open PR from update"
  info=$(pr_info "$pr")
  eligible <<<"$info" || skip "#$pr isn't a ready PR by $bot from update to master"
  head=$(jq -r .head.sha <<<"$info")
  # what the PR changes against: master, or for a merged PR (tests) its base
  if jq -e .merged <<<"$info" >/dev/null; then base=$(jq -r .base.sha <<<"$info"); else base=master; fi
  base=$(gh api "repos/$repo/compare/$base...$head" --jq .merge_base_commit.sha)

  # 1. the update job asked for it, on this exact commit
  if [ -z "${SKIP_STATUS:-}" ]; then
    gh api "repos/$repo/commits/$head/statuses" --paginate |
      jq -se --arg c "$context" --arg bot "$bot" '
        [.[][] | select(.context == $c)] | first
        | . != null and .state == "success" and .creator.login == $bot' >/dev/null ||
      skip "no $context success from $bot on $head"
  fi

  # 2. nothing but the lock
  files=$(gh api "repos/$repo/compare/$base...$head" --jq '[.files[].filename] | join(" ")')
  [ "$files" = flake.lock ] || skip "changes more than flake.lock: $files"

  # 3. the same inputs from the same places; only revisions and hashes move
  old=$(mktemp) new=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$old' '$new'" EXIT
  gh api "repos/$repo/contents/flake.lock?ref=$base" -H 'Accept: application/vnd.github.raw' >"$old"
  gh api "repos/$repo/contents/flake.lock?ref=$head" -H 'Accept: application/vnd.github.raw' >"$new"
  if [ -n "${TEST_LOCKS:-}" ]; then read -r o n <<<"$TEST_LOCKS"; cp "$o" "$old"; cp "$n" "$new"; fi
  shape='{version, root, nodes: (.nodes | map_values(
    del(.locked.rev, .locked.narHash, .locked.lastModified, .locked.revCount, .locked.url)))}'
  [ "$(jq -S "$shape" "$old")" = "$(jq -S "$shape" "$new")" ] ||
    skip "the lock's inputs, sources or graph changed, not only revisions"

  # 4. each input that moved: forward on its own branch or tag (not an older
  # commit, not a fork's commit served through the upstream repo), and the
  # hash Nix gets from that source, so the lock can't name one tree and
  # fetch another
  changed=$(jq -rn --slurpfile o "$old" --slurpfile n "$new" '
    $n[0].nodes | to_entries[] | select(.value.locked)
    | select(.value.locked != $o[0].nodes[.key].locked) | .key')
  for node in $changed; do
    local type owner name ref pin rev oldrev url oldurl hash src got
    IFS=$'\t' read -r type owner name ref pin rev oldrev url oldurl hash < <(
      jq -rn --slurpfile o "$old" --slurpfile n "$new" --arg k "$node" '
        $n[0].nodes[$k] as $x | $o[0].nodes[$k].locked as $p
        | [$x.locked.type, $x.locked.owner // "-", $x.locked.repo // "-",
           $x.original.ref // "-", $x.original.rev // "-", $x.locked.rev // "-",
           $p.rev // "-", $x.locked.url // "-", $p.url // "-", $x.locked.narHash // "-"] | @tsv')
    [ "$pin" = - ] || skip "$node is pinned to $pin in flake.nix, yet its lock moved"
    case $type in
    github)
      [ "$ref" != - ] || ref=$(gh api "repos/$owner/$name" --jq .default_branch)
      on_branch "$owner/$name" "$ref" "$rev" "$oldrev" ||
        skip "$node: $rev isn't on $owner/$name $ref at or after $oldrev"
      src="github:$owner/$name/$rev"
      ;;
    tarball)
      # a NixOS channel release: same channel, a nixpkgs commit that is on
      # the channel's branch and not older than the last one
      local dir='^https://releases\.nixos\.org/nixos/[^/]+/'
      [[ $url =~ ${dir}nixos-[0-9.]+(pre[0-9]+)?\.([0-9a-f]{12})/nixexprs\.tar\.(xz|zst)$ ]] &&
        [ "${BASH_REMATCH[2]}" = "${rev:0:12}" ] &&
        [[ $oldurl =~ $dir ]] && [ "${url%/nixos-*}" = "${oldurl%/nixos-*}" ] ||
        skip "$node: $url isn't a release of $oldurl's channel at $rev"
      on_branch NixOS/nixpkgs "$ref" "$rev" "$oldrev" ||
        skip "$node: $rev isn't on nixpkgs $ref at or after $oldrev"
      src=$url
      ;;
    *) skip "$node: a $type input moved; only GitHub and channel inputs are checked" ;;
    esac
    # fetched afresh, without the lock's hash, so no cache can stand in
    got=$(nix flake prefetch --json --refresh "$src" | jq -r .hash) ||
      skip "$node: couldn't fetch $src"
    [ "$got" = "$hash" ] || skip "$node: $src hashes to $got, the lock says $hash"
  done

  say "#$pr at $head changes only flake.lock, every input forward on its own source"
  echo "$head"
  [ -z "${GITHUB_OUTPUT:-}" ] || echo "sha=$head" >>"$GITHUB_OUTPUT"
}

merge() {
  local sha=$1 pr info review
  pr=$(open_pr)
  [ -n "$pr" ] || skip "no open PR from update"
  info=$(pr_info "$pr")
  eligible <<<"$info" || skip "#$pr isn't a ready PR by $bot from update to master"
  [ "$(jq -r .head.sha <<<"$info")" = "$sha" ] || skip "#$pr moved past the checked $sha"
  # the approval names the checked commit; master dismisses it on any push
  review=$(gh api "repos/$repo/pulls/$pr/reviews" -f commit_id="$sha" -f event=APPROVE \
    -f body="Only flake.lock changed: every moved input is a newer commit on its own branch, with the hash Nix computed from it, and the update job asked for the merge." --jq .id)
  if [ "$(pr_info "$pr" | jq -r .head.sha)" != "$sha" ]; then
    gh api -X PUT "repos/$repo/pulls/$pr/reviews/$review/dismissals" -f message="The PR moved after the check." >/dev/null
    skip "#$pr moved while approving; approval dismissed"
  fi
  gh pr merge "$pr" -R "$repo" --merge --match-head-commit "$sha"
  say "merged #$pr at $sha"
}

case ${1:-} in
check) check "${2:-}" ;;
merge) merge "${2:?merge needs the checked SHA}" ;;
*)
  echo "usage: update-automerge.sh check [PR] | merge SHA" >&2
  exit 2
  ;;
esac
