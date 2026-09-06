#!/usr/bin/env bash
# Shared helpers for the plan-* scripts. Sourced, never executed directly.

PLAN_CHECKSUMS_RELPATH="docs/plans/.checksums" # shared by done/ and rejected/ -- both are frozen states
PLAN_ACTIVE_MARKER_RELPATH=".claude/.active-plan"

# Review agents whose completion is *mechanically recorded*: they are
# subagents, so SubagentStop fires and subagent-stamp writes a stamp.
# Recorded, not proven -- see plan_stamp_line for what a stamp is and is
# not evidence of.
# Deliberately narrower than the set of agents a change obliges (see
# workflow/scripts/required-agents) -- /simplify is a slash command with
# no such event, and spec-check does not exist yet. Both the writer
# (subagent-stamp) and the reader (plan-gate) take the list from here, so
# adding an agent cannot half-land: a stamper with no checker silently
# degrades the gate to a no-op.
PLAN_STAMPABLE_AGENTS="security docs-updater"

plan_die() { printf 'plan: %s\n' "$*" >&2; exit 1; }
plan_note() { printf '%s\n' "$*" >&2; }

plan_today() { date +%Y-%m-%d; }  # local date -- matches how the rest of the repo dates entries

plan_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || plan_die "not inside a git repository."
}

# plan_slugify <title> -- lowercase, non-alnum runs -> single hyphen, trimmed,
# capped at 70 chars backing up to the last hyphen so a long title truncates
# at a word boundary instead of mid-word.
plan_slugify() {
  local raw slug cap=70
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\+/-/g' -e 's/^-\+//' -e 's/-\+$//')"
  if [ "${#raw}" -gt "$cap" ]; then
    slug="${raw:0:$cap}"
    case "$slug" in *-*) slug="${slug%-*}" ;; esac
  else
    slug="$raw"
  fi
  printf '%s' "$slug"
}

# plan_get_field <file> <key> -- scalar value of a top-level frontmatter key.
plan_get_field() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---" { exit }
    infm {
      n = length(key)
      if (substr($0,1,n+1) == key ":") {
        val = substr($0, n+2)
        sub(/^[ \t]+/, "", val)
        print val
        exit
      }
    }
  ' "$file"
}

# plan_set_field <file> <key> <value> -- rewrite a frontmatter scalar in place.
# Never touches body text.
plan_set_field() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    NR==1 && $0=="---" { infm=1; print; next }
    infm && $0=="---" { infm=0; print; next }
    infm {
      n = length(key)
      if (substr($0,1,n+1) == key ":") { print key ": " value; next }
    }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

plan_is_frozen() {
  [ "$(plan_get_field "$1" frozen)" = "true" ]
}

plan_require_not_frozen() {
  plan_is_frozen "$1" && plan_die "$1 is frozen (done/ and rejected/ plans get zero further edits, ever). New information becomes a new plan file that cites it."
  return 0
}

# plan_locate <path-or-filename> <repo-root> -- resolves either a
# repo-root-relative path or a bare filename to the one matching file under
# docs/plans/*/, printed relative to repo root. Dies on zero or >1 matches.
plan_locate() {
  local arg="$1" root="$2" base cand n
  # Reject any '..' segment before anything else. A bash `case` pattern's
  # `*` matches '/' (this is not pathname-expansion globbing), so
  # `docs/plans/*/*.md` below matches strings like
  # `docs/plans/../../../etc/passwd.md` -- without this check that arm's
  # `[ -f "$root/$arg" ]` would happily resolve outside docs/plans/
  # entirely. Every legitimate plan filename is `<date>-<slug>.md` with a
  # slug from plan_slugify (alnum/hyphen only), so '..' can never appear
  # in a real citation -- this can't reject anything legitimate. Matters
  # now that plan-gate feeds this function attacker-influenced input (a
  # PR's own commit-trailer text), not just agent-supplied CLI arguments.
  case "$arg" in
    *..*) plan_die "'$arg' contains '..' -- not a valid plan path or filename." ;;
  esac
  case "$arg" in
    docs/plans/*/*.md)
      [ -f "$root/$arg" ] || plan_die "$arg: no such file."
      printf '%s\n' "$arg"
      return 0
      ;;
  esac
  base="$(basename "$arg")"
  cand="$(cd "$root" && ls -1 docs/plans/*/"$base" 2>/dev/null)"
  n="$(printf '%s\n' "$cand" | grep -c .)"
  [ "$n" -eq 1 ] || plan_die "could not uniquely locate '$arg' under docs/plans/ (found $n match(es))."
  printf '%s\n' "$cand"
}

# plan_append_under_heading <file> <heading-regex> <text>
# Inserts <text> as a new line at the end of the section introduced by the
# first line matching <heading-regex> (a POSIX ERE) -- i.e. just before the
# next line starting with '#', or at EOF. Never rewrites an existing line.
plan_append_under_heading() {
  local file="$1" heading_re="$2" text="$3" tmp rc
  tmp="$(mktemp)"
  awk -v re="$heading_re" -v text="$text" '
    BEGIN { in_section=0; found=0; inserted=0 }
    {
      if (in_section && $0 ~ /^#/ && !inserted) {
        print ""
        print text
        print ""
        inserted=1
        in_section=0
      }
      print
      if ($0 ~ re) { in_section=1; found=1 }
    }
    END {
      if (in_section && !inserted) { print ""; print text }
      if (!found) exit 1
    }
  ' "$file" > "$tmp"
  rc=$?
  if [ $rc -ne 0 ]; then
    rm -f "$tmp"
    plan_die "no heading matching '$heading_re' found in $file."
  fi
  mv "$tmp" "$file"
}

# plan_unresolved_decisions <file> -- one line per D<N> heading that is
# neither ANSWERED nor (DEFERRED and CARRIED). Empty output = all resolved.
plan_unresolved_decisions() {
  awk '
    function report() {
      if (id != "" && !answered && !(deferred && carried)) print id
    }
    /^### D[0-9]+/ { report(); id=$0; answered=0; deferred=0; carried=0; next }
    /\*\*ANSWERED/ { answered=1 }
    /\*\*DEFERRED/ { deferred=1 }
    /\*\*CARRIED/  { carried=1 }
    END { report() }
  ' "$1"
}

# plan_unresolved_findings <file> -- one line per F<N> heading that is
# none of FIXED, ACCEPTED, or MOOT. Empty output = all resolved.
plan_unresolved_findings() {
  awk '
    function report() {
      if (id != "" && !resolved) print id
    }
    /^### F[0-9]+/ { report(); id=$0; resolved=0; next }
    /\*\*FIXED/    { resolved=1 }
    /\*\*ACCEPTED/ { resolved=1 }
    /\*\*MOOT/     { resolved=1 }
    END { report() }
  ' "$1"
}

# plan_state_problem <file> -- prints a reason if the ## State section is
# missing or empty; empty output = present and non-empty. State is the one
# section rewritten in place rather than appended to (see plan/SKILL.md),
# so its presence can't be inferred from Progress/Decisions/Gotchas/Findings
# ever having had content.
plan_state_problem() {
  local file="$1" body
  grep -q '^## State$' "$file" || { echo "no '## State' heading found."; return; }
  body="$(awk '/^## State$/{f=1;next} /^## /{f=0} f' "$file" | tr -d '[:space:]')"
  [ -n "$body" ] || echo "'## State' section is empty -- summarize the current status before freezing."
}

plan_checksum() { sha256sum "$1" | awk '{print $1}'; }

# plan_do_freeze <root> <rel> -- the mechanical half of freezing, shared by
# plan-freeze (done/, gated on resolved decisions) and plan-reject
# (rejected/, gated on a mandatory reason instead): sets frozen: true,
# records the checksum. Does not check which folder <rel> is in or
# anything about decisions -- callers do their own gating first.
plan_do_freeze() {
  local root="$1" rel="$2" sum checksums tmp
  plan_set_field "$root/$rel" frozen true
  sum="$(plan_checksum "$root/$rel")"

  checksums="$root/$PLAN_CHECKSUMS_RELPATH"
  mkdir -p "$(dirname "$checksums")"
  touch "$checksums"
  tmp="$(mktemp)"
  grep -vF "  $rel" "$checksums" > "$tmp" 2>/dev/null || true
  printf '%s  %s\n' "$sum" "$rel" >> "$tmp"
  sort -k2 "$tmp" > "$checksums"
  rm -f "$tmp"

  git -C "$root" add "$rel" "$PLAN_CHECKSUMS_RELPATH"
  plan_mark_touched "$root" "$rel"
}

# plan_mark_touched <repo-root> <rel-path> -- records "this plan file was
# just worked on" for the current session. Never git-added (ephemeral,
# gitignored) -- read by the workflow skill's commit-time and SubagentStop
# hooks, which is the whole reason it exists: they need *some* concrete,
# on-disk fact to check, since a skill invoking a subagent doesn't reliably
# block on it.
plan_mark_touched() {
  local root="$1" rel="$2" marker="$root/$PLAN_ACTIVE_MARKER_RELPATH"
  mkdir -p "$(dirname "$marker")"
  printf '%s\n' "$rel" > "$marker"
}

# plan_is_stampable <agent> -- is this agent one subagent-stamp records?
plan_is_stampable() {
  local a="$1" x
  for x in $PLAN_STAMPABLE_AGENTS; do
    [ "$x" = "$a" ] && return 0
  done
  return 1
}

# Files whose content a review agent actually reads. Code only: `.md` is
# deliberately excluded, because every stamp appends to a plan file and
# docs-updater edits docs, so folding prose in would make each stamp
# invalidate itself and every stamp before it.
PLAN_CODE_GLOBS=("*.nix" "docs/skills/*/scripts/*" ".githooks/*")

# plan_code_fingerprint -- content hash of the reviewable code in the
# working tree. Must be run from the repo root.
#
# Content, not history. An agent reviews uncommitted work and the commit
# lands *after* the stamp, so anything keyed on HEAD or on commit time
# reports a review that genuinely happened as stale -- an un-passable
# gate, which is worse than a weak one. See D11 in
# 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md
plan_code_fingerprint() {
  local out
  out="$(
    set -o pipefail
    # -z throughout: a path may contain a newline, which `tr '\n' '\0'`
    # would mangle into two paths.
    #
    # --cached and --others together, so a file's presence in the hash
    # does not change when it goes from untracked to tracked at commit
    # time -- it is in the union either way. That is what lets a stamp
    # written before the commit still match in CI after it. (A scratch
    # code file that never gets committed *will* skew the local hash;
    # remove it before the review rather than after the gate complains.)
    #
    # LC_ALL=C because sort order is part of the hash, and the writer
    # (a local hook, typically a UTF-8 locale) and the reader (CI, which
    # sets no LANG) otherwise disagree -- measured: identical content
    # hashes differently under en_US.UTF-8 and C, which would report
    # every correctly stamped plan as stale in CI.
    #
    # Absent-but-tracked files are skipped rather than failing the hash:
    # a deletion that is not yet committed is a normal mid-work state,
    # and CI, where the deletion *is* committed, also omits the file.
    git ls-files -z --cached --others --exclude-standard -- "${PLAN_CODE_GLOBS[@]}" |
      while IFS= read -r -d '' f; do
        [ -f "$f" ] && printf '%s\0' "$f"
      done |
      LC_ALL=C sort -zu |
      xargs -0 -r sha256sum |
      LC_ALL=C sort |
      sha256sum
  )" || return 1
  printf '%.16s' "${out%% *}"
}

# plan_is_code_path <path> -- does this path fall inside PLAN_CODE_GLOBS?
# The single test for "is this reviewable code", so required-agents,
# plan-citations and the fingerprint cannot drift into three different
# answers -- one missed edit there means a file changes without obliging
# review, or changes without ever invalidating a stamp.
plan_is_code_path() {
  local p="$1" g
  for g in "${PLAN_CODE_GLOBS[@]}"; do
    # shellcheck disable=SC2053  # $g is a pattern here, deliberately
    [[ "$p" == $g ]] && return 0
  done
  return 1
}

# plan_stamp_line <agent> <timestamp> <fingerprint> -- the single
# definition of the completion-stamp format. subagent-stamp writes it and
# plan_stamp_fingerprint reads it; with the two in separate files and no
# shared definition, a reworded stamp would silently block every merge.
#
# What a stamp is evidence of, precisely: an agent of that type ran to
# completion against code with that fingerprint. It is *not* proof a
# review happened. SubagentStop fires for any subagent of the type
# whatever it did, so a no-op prompt yields an identical valid stamp, and
# the line is plaintext in a file the author controls, so one printf
# forges one. That is acceptable against the adversary this system has --
# an agent that forgets -- and useless against one that lies. Do not
# describe it as proof.
plan_stamp_line() {
  printf '_%s finished %s (code %s) -- see Findings above._' "$1" "$2" "$3"
}

# plan_stamp_fingerprint <file> <agent> -- prints the code fingerprint
# <agent>'s most recent stamp recorded. Returns non-zero if it never
# stamped. Prints "legacy" for a stamp written before fingerprints
# existed, so an older plan cited by a live range degrades to a warning
# rather than an unfixable block.
plan_stamp_fingerprint() {
  local line fp
  line="$(grep -E "^_$2 finished " "$1" | tail -n 1)"
  [ -n "$line" ] || return 1
  case "$line" in
    *"(code "*)
      fp="${line#*(code }"
      fp="${fp%%)*}"
      # An empty capture is a truncated stamp, not a fingerprint of "".
      # Reported as malformed so it cannot be silently compared against
      # the real hash and reported as an ordinary staleness.
      [ -n "$fp" ] || { printf 'malformed'; return 0; }
      printf '%s' "$fp"
      ;;
    *) printf 'legacy' ;;
  esac
}

# plan_has_heading <file> <id> -- does "### <id>" exist as a real heading?
# Shared by plan-lint's sequencing check and plan-citations' anchor
# resolution so the two cannot drift on what counts as a match.
plan_has_heading() {
  grep -qE "^### $2([[:space:]]|\$)" "$1"
}
