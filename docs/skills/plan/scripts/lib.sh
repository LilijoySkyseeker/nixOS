#!/usr/bin/env bash
# Shared helpers for the plan-* scripts. Sourced, never executed directly.

PLAN_CHECKSUMS_RELPATH="docs/plans/.checksums" # shared by done/ and rejected/ -- both are frozen states
PLAN_ACTIVE_MARKER_RELPATH=".claude/.active-plan"

plan_die() { printf 'plan: %s\n' "$*" >&2; exit 1; }
plan_note() { printf '%s\n' "$*" >&2; }

plan_today() { date +%Y-%m-%d; }  # local date -- matches how the rest of the repo dates entries

plan_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || plan_die "not inside a git repository."
}

# plan_slugify <title> -- lowercase, non-alnum runs -> single hyphen, trimmed.
plan_slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\+/-/g' -e 's/^-\+//' -e 's/-\+$//' | cut -c1-50
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
