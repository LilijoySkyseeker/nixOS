#!/usr/bin/env bash
# Shared helpers for verify-ladder and required-agents. Sourced, never executed.

# review agents in run order: the code-rewriting one first, docs-updater
# last so it documents what actually merges
WF_AGENT_ORDER=("/simplify" "security" "docs-updater")

# paths whose change alters what a machine or a gate does
WF_CODE_GLOBS=(
  "*.nix"
  "*/scripts/*"
  "scripts/*"
  ".githooks/*"
  ".github/workflows/*"
  ".claude/settings.json"
  ".claude/agents/*"
  ".claude/skills/*"
  "docs/agents/*"
  ".sops.yaml"
  "secrets/*"
  "flake.lock"
  "*.gitignore"
  "*.gitattributes" # `*.pem -diff` switches off the pre-commit secret scan
)
WF_DOC_GLOBS=("*.md")

wf_die() { printf '%s: %s\n' "$(basename "$0")" "$*" >&2; exit 1; }

wf_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || wf_die "not inside a git repository."
}

# filters paths on stdin to those that still exist (drops staged deletions)
wf_existing_files() {
  local f
  while IFS= read -r f; do
    if [ -f "$f" ]; then printf '%s\n' "$f"; fi
  done
}

wf_in_list() {
  local n="$1" x
  shift
  for x in "$@"; do
    [ "$x" = "$n" ] && return 0
  done
  return 1
}

wf_path_matches() {
  local p="$1" g
  shift
  for g in "$@"; do
    # shellcheck disable=SC2053  # $g is a pattern
    [[ "$p" == $g ]] && return 0
  done
  return 1
}
wf_is_code_path() { wf_path_matches "$1" "${WF_CODE_GLOBS[@]}"; }
wf_is_doc_path() { wf_path_matches "$1" "${WF_DOC_GLOBS[@]}"; }

# wf_worktree_files [<pathspec>...] -- unstaged, staged and untracked
# changes against HEAD, one per line; fails rather than printing nothing
# when a git call fails
wf_worktree_files() {
  local unstaged staged untracked
  unstaged="$(git -c core.quotePath=false diff --name-only HEAD -- "$@")" || return 1
  staged="$(git -c core.quotePath=false diff --cached --name-only -- "$@")" || return 1
  untracked="$(git -c core.quotePath=false ls-files --others --exclude-standard -- "$@")" || return 1
  printf '%s\n%s\n%s\n' "$unstaged" "$staged" "$untracked" | sed '/^$/d' | LC_ALL=C sort -u
}
