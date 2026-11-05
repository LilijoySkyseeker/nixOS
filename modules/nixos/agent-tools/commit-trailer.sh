# Appends `Agent: <model> <agent-id>` to an agent's commit, so the session
# behind it can be found later. Runs as git's prepare-commit-msg event in every
# repo. Never blocks the commit: on any failure it warns and leaves the trailer
# out.

[[ -n "${PASEO_AGENT_ID:-}" ]] || exit 0

msg_file="$1"
source="${2:-}"
reused="${3:-}"

warn() {
  echo "commit-trailer: $1; no Agent trailer on this commit." >&2
  exit 0
}

# `git commit -m` concluding a conflicted merge reports "message", not "merge";
# amending a finished merge reports "commit" and HEAD
[[ "$source" == merge ]] && exit 0
git rev-parse -q --verify MERGE_HEAD >/dev/null && exit 0
if [[ -n "$reused" ]] && git rev-parse -q --verify HEAD^2 >/dev/null &&
  [[ "$(git rev-parse -q --verify "$reused")" == "$(git rev-parse -q --verify HEAD)" ]]; then
  exit 0
fi

# this runs before any editor: an empty message may yet abort the commit, and
# a lone trailer would let it through
git stripspace --strip-comments <"$msg_file" | grep -q . ||
  warn "no message yet (an editor?); use -m or -F"

model="$(timeout 10 paseo inspect "$PASEO_AGENT_ID" --json 2>/dev/null |
  jq -er 'first((.Model, .Provider) | select(type == "string" and . != ""))' 2>/dev/null)" ||
  warn "cannot read the model from paseo"

# doNothing: an amend or rebase keeps the trailer the commit already has
git interpret-trailers --in-place --if-exists doNothing --if-missing add \
  --trailer "Agent: $model $PASEO_AGENT_ID" "$msg_file" ||
  warn "git interpret-trailers failed"
exit 0
