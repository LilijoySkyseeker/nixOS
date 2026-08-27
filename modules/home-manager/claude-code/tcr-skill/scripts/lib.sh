#!/usr/bin/env bash
# Shared helpers for the tcr-* scripts. Sourced, never executed directly.
# Deliberately avoids bash4+-only features (associative arrays, ${var,,})
# so it runs unmodified on the bash 3.2 shipped as /bin/bash on macOS.

TCR_MAX_ATTEMPTS_DEFAULT=3
TCR_STATE_RELPATH=".tcr/state.json"
TCR_FAILURES_RELPATH=".tcr/failures.md"

tcr_die() { printf 'tcr: %s\n' "$*" >&2; exit 1; }
tcr_note() { printf '%s\n' "$*" >&2; }

tcr_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Escapes backslash and double-quote; flattens newlines/tabs to spaces so the
# result is always safe to embed as a single-line JSON string value.
tcr_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\t' '  '
}

# Walk upward from $PWD looking for .tcr/state.json. Prints the directory
# containing it (the TCR "work root") and returns 0, or returns 1 if none
# is found by the time we reach /.
tcr_find_root() {
  local d
  d="$(pwd -P)"
  while :; do
    if [ -f "$d/$TCR_STATE_RELPATH" ]; then
      printf '%s\n' "$d"
      return 0
    fi
    [ "$d" = "/" ] && break
    d="$(dirname "$d")"
  done
  return 1
}

tcr_require_root() {
  local root
  root="$(tcr_find_root)" || tcr_die "no active TCR session found here (or in any parent directory). Run 'tcr-status init --task \"...\"' first."
  printf '%s\n' "$root"
}

# tcr_get <file> <key>  -- extract a scalar (string/bool/number) value for a
# top-level key from a JSON file we ourselves generated (one key per line).
# Not a general JSON parser; only safe for files written by tcr_save_state.
tcr_get() {
  local file="$1" key="$2" line val
  [ -f "$file" ] || return 1
  line="$(grep -m1 "\"$key\"[[:space:]]*:" "$file")" || return 1
  val="${line#*:}"
  val="$(printf '%s' "$val" | sed -e 's/^[[:space:]]*//' -e 's/,[[:space:]]*$//' -e 's/[[:space:]]*$//')"
  case "$val" in
    \"*\") val="${val#\"}"; val="${val%\"}" ;;
  esac
  printf '%s\n' "$val"
}

# Loads all known fields from a state file into TCR_* globals.
tcr_load_state() {
  local f="$1"
  TCR_ACTIVE="$(tcr_get "$f" active)"
  TCR_MODE="$(tcr_get "$f" mode)"
  TCR_BASELINE_COMMIT="$(tcr_get "$f" baseline_commit)"
  TCR_FULL_CHECK="$(tcr_get "$f" full_check)"
  TCR_FAST_CHECK="$(tcr_get "$f" fast_check)"
  TCR_WORKTREE_MODE="$(tcr_get "$f" worktree_mode)"
  TCR_WORKTREE_PATH="$(tcr_get "$f" worktree_path)"
  TCR_WORKTREE_BRANCH="$(tcr_get "$f" worktree_branch)"
  TCR_MAIN_REPO_ROOT="$(tcr_get "$f" main_repo_root)"
  TCR_TASK="$(tcr_get "$f" task)"
  TCR_CURRENT_STEP="$(tcr_get "$f" current_step)"
  TCR_ATTEMPT="$(tcr_get "$f" attempt)"
  TCR_MAX_ATTEMPTS="$(tcr_get "$f" max_attempts)"
  TCR_LAST_RESULT="$(tcr_get "$f" last_result)"
  TCR_LAST_TEST_AT="$(tcr_get "$f" last_test_at)"
  TCR_LAST_VERIFIED_RESULT="$(tcr_get "$f" last_verified_result)"
  TCR_LAST_VERIFIED_AT="$(tcr_get "$f" last_verified_at)"
  TCR_PREEXISTING_STASH_REF="$(tcr_get "$f" preexisting_stash_ref)"
  TCR_CORRUPTED="$(tcr_get "$f" corrupted)"
  TCR_STARTED_AT="$(tcr_get "$f" started_at)"
  TCR_FAILURE_LOG_PATH="$(tcr_get "$f" failure_log_path)"
  : "${TCR_MAX_ATTEMPTS:=$TCR_MAX_ATTEMPTS_DEFAULT}"
  : "${TCR_ATTEMPT:=0}"
  : "${TCR_FAILURE_LOG_PATH:=$TCR_FAILURES_RELPATH}"
}

tcr_save_state() {
  local f="$1"
  mkdir -p "$(dirname "$f")"
  cat > "$f" <<EOF
{
  "active": ${TCR_ACTIVE:-false},
  "mode": "$(tcr_json_escape "${TCR_MODE:-normal}")",
  "baseline_commit": "$(tcr_json_escape "${TCR_BASELINE_COMMIT:-}")",
  "full_check": "$(tcr_json_escape "${TCR_FULL_CHECK:-}")",
  "fast_check": "$(tcr_json_escape "${TCR_FAST_CHECK:-}")",
  "worktree_mode": ${TCR_WORKTREE_MODE:-false},
  "worktree_path": "$(tcr_json_escape "${TCR_WORKTREE_PATH:-}")",
  "worktree_branch": "$(tcr_json_escape "${TCR_WORKTREE_BRANCH:-}")",
  "main_repo_root": "$(tcr_json_escape "${TCR_MAIN_REPO_ROOT:-}")",
  "task": "$(tcr_json_escape "${TCR_TASK:-}")",
  "current_step": "$(tcr_json_escape "${TCR_CURRENT_STEP:-}")",
  "attempt": ${TCR_ATTEMPT:-0},
  "max_attempts": ${TCR_MAX_ATTEMPTS:-$TCR_MAX_ATTEMPTS_DEFAULT},
  "last_result": "$(tcr_json_escape "${TCR_LAST_RESULT:-none}")",
  "last_test_at": "$(tcr_json_escape "${TCR_LAST_TEST_AT:-}")",
  "last_verified_result": "$(tcr_json_escape "${TCR_LAST_VERIFIED_RESULT:-none}")",
  "last_verified_at": "$(tcr_json_escape "${TCR_LAST_VERIFIED_AT:-}")",
  "preexisting_stash_ref": "$(tcr_json_escape "${TCR_PREEXISTING_STASH_REF:-}")",
  "corrupted": ${TCR_CORRUPTED:-false},
  "started_at": "$(tcr_json_escape "${TCR_STARTED_AT:-}")",
  "failure_log_path": "$(tcr_json_escape "${TCR_FAILURE_LOG_PATH:-$TCR_FAILURES_RELPATH}")"
}
EOF
}

# The directory TCR is actually mutating right now: the isolated worktree if
# one was created, otherwise the main repo (in-place mode).
tcr_work_root() {
  if [ "$TCR_WORKTREE_MODE" = "true" ] && [ -n "$TCR_WORKTREE_PATH" ]; then
    printf '%s\n' "$TCR_WORKTREE_PATH"
  else
    printf '%s\n' "$TCR_MAIN_REPO_ROOT"
  fi
}

# tcr_run_check <root> <command> <logfile>
# Runs the FULL_CHECK/FAST_CHECK command with $root as cwd, teeing combined
# stdout+stderr into <logfile>. Returns the command's exit code.
tcr_run_check() {
  local root="$1" cmd="$2" log="$3" rc
  mkdir -p "$(dirname "$log")"
  ( cd "$root" && eval "$cmd" ) >"$log" 2>&1
  rc=$?
  return $rc
}

tcr_tail_log() {
  local log="$1" n="${2:-40}"
  [ -f "$log" ] || return 0
  printf -- '--- last %s lines of %s ---\n' "$n" "$log" >&2
  tail -n "$n" "$log" >&2
}

tcr_git_identity_ensure() {
  local root="$1"
  if [ -z "$(git -C "$root" config user.email 2>/dev/null)" ]; then
    git -C "$root" config user.email "tcr@localhost"
  fi
  if [ -z "$(git -C "$root" config user.name 2>/dev/null)" ]; then
    git -C "$root" config user.name "TCR"
  fi
}
