#!/usr/bin/env bash
# Shared helpers for the plan-* scripts. Sourced, never executed directly.

PLAN_CHECKSUMS_RELPATH="docs/plans/.checksums" # shared by done/ and rejected/ -- both are frozen states; also hardcoded in .githooks/pre-commit

# also hardcoded in workflow/scripts/plan-touch-guard, which must not
# depend on this file -- keep in sync
# plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F15
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
PLAN_STAMPABLE_AGENTS=("security" "docs-updater")

# Canonical run order. Every agent that writes runs before every agent
# whose stamp must stay valid, so a later edit cannot invalidate an
# earlier reviewer's fingerprint. required-agents emits in this order,
# which makes the script authoritative on both which agents a change
# obliges and when each runs -- printing them in any other order invites
# exactly the stale-stamp block the ordering exists to prevent.
# plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#D7
PLAN_AGENT_ORDER=("/simplify" "docs-updater" "security" "spec-check")

# the plan-file schema's vocabularies and key sets; plan-new, plan-lint and
# the skill docs read these lists from here instead of restating them
# plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#D4
PLAN_KINDS=("task" "map")
PLAN_PRIORITIES=("low" "normal" "high")
# which vocabulary governs which field -- plan-lint reports an entry missing
# here rather than dying on an unbound variable
# plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F15
PLAN_VOCAB_FIELDS=("kind" "priority")
declare -A PLAN_FIELD_VOCAB=([kind]="PLAN_KINDS" [priority]="PLAN_PRIORITIES")
# what plan-new stamps on a new file; members of the vocabularies above, so a
# generated plan lints clean
PLAN_DEFAULT_KIND="task"
PLAN_DEFAULT_PRIORITY="normal"
# carried by every plan, including the 50 frozen ones written before the
# schema grew
PLAN_CORE_FIELDS=("slug" "created" "status" "frozen")
# comma-separated bare plan filenames, same citation form as everywhere else,
# so they survive a file moving between folders. superseded_by is not here:
# it has no writer until plan-supersede exists, and a field nothing sets is
# a lint rule enforced for nobody
# plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#D5
PLAN_REF_FIELDS=("blocked_by")
# added by the map plan's #D4, required of non-frozen plans only -- a frozen
# file can never be edited to gain them; derived from the two lists above so a
# field added to one and forgotten in the other cannot half-land
# plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#G1
PLAN_SCHEMA_FIELDS=("${PLAN_VOCAB_FIELDS[@]}" "${PLAN_REF_FIELDS[@]}")

# section order for a non-frozen plan, State first
# plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#D4
PLAN_SECTIONS=("## State" "## Original plan" "## Progress" "## Decisions (D)" "## Gotchas (G)" "## Findings (F)")

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

# plan_frontmatter <file> -- every frontmatter key as "key<TAB>value", one
# per line, value possibly empty. For a caller wanting several keys: one awk
# instead of one per key, which is what plan-lint used to pay. Presence and
# value both fall out of the one parse, so there is no separate has-this-key
# helper -- an absent key has no line, an empty one an empty value.
# plan_get_field stays the single-key reader every other plan-* script calls.
plan_frontmatter() {
  awk '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---" { exit }
    infm {
      i = index($0, ":")
      if (i > 1) {
        k = substr($0, 1, i - 1)
        # first wins, because plan_get_field stops at its first match; two
        # readers disagreeing over a duplicated key let one file be frozen to
        # one caller and editable to the other
        # plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F12
        if (k in seen) next
        seen[k] = 1
        if (k ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
          v = substr($0, i + 1)
          sub(/^[ \t]+/, "", v)
          sub(/[ \t]+$/, "", v)
          print k "\t" v
        }
      }
    }
  ' "$1"
}

# plan_headings <file> -- top-level "## " headings outside fenced code, as
# "line<TAB>heading". Fence handling is plan_state_body's, and for the same
# reason: a plain grep counts a heading quoted inside a fence, which both
# passes a file whose only sections are an example template and blocks a
# correct file that quotes one
# plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F13
plan_headings() {
  awk '
    match($0, /^[ \t]*(`{3,}|~{3,})/) {
      m = substr($0, RSTART, RLENGTH)
      sub(/^[ \t]+/, "", m)
      if (!fence) { fence = 1; open = m }
      else if (substr(m, 1, 1) == substr(open, 1, 1) && length(m) >= length(open)) fence = 0
      next
    }
    !fence && /^## / { print FNR "\t" $0 }
  ' "$1"
}

# plan_active_plan_problem <root> -- prints why the active-plan marker cannot
# be used, empty if it can or if there is no marker at all. The distinction is
# the whole point: plan_active_plan returns 1 both for "no marker" and for
# "marker naming a deleted file", and a caller that cannot tell them apart
# skips its check under a line that reads like a pass.
# plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F10
plan_active_plan_problem() {
  local root="${1:-.}" marker="${1:-.}/$PLAN_ACTIVE_MARKER_RELPATH"
  [ -s "$marker" ] || return 0
  plan_active_plan "$root" >/dev/null && return 0
  printf "%s names '%s', which is not a usable plan file" \
    "$PLAN_ACTIVE_MARKER_RELPATH" "$(head -n 1 "$marker")"
}

# plan_normalise_rel <rel> -- collapse leading and embedded ./ segments, so
# the same file spelled two ways compares equal. Shared, because a reader that
# normalises and a writer that does not will disagree about which entry they
# are talking about.
# plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F39
plan_normalise_rel() {
  local rel="${1#./}"
  while [ "$rel" != "${rel//\/.\//\/}" ]; do rel="${rel//\/.\//\/}"; done
  printf '%s' "$rel"
}

# plan_manifest_frozen <root> <rel> -- frozen according to the checksum
# manifest, which is the authority .githooks/pre-commit enforces. The file's
# own `frozen:` field is self-declared: a todo/ plan can assert it and switch
# off every rule that applies only to editable files
# plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F11
plan_manifest_frozen() {
  local manifest="$1/$PLAN_CHECKSUMS_RELPATH" rel
  rel="$(plan_normalise_rel "$2")"
  [ -f "$manifest" ] || return 1
  # Exact match on the path field, not a substring of the line: `grep -F`
  # matched any entry this path is a suffix of.
  awk -v want="$rel" '
    { i = index($0, "  "); if (i > 0 && substr($0, i + 2) == want) { found = 1; exit } }
    END { exit(found ? 0 : 1) }
  ' "$manifest"
}

# plan_manifest_problem <root> -- prints why the freeze manifest cannot be
# trusted, empty if it can. A helper rather than inline in verify-ladder for
# the reason #F10 gives: a decision a gate makes is only testable where it can
# be called, and this one is the difference between "no frozen plan changed"
# and "nothing checked".
# plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F57
plan_manifest_problem() {
  local root="${1:-.}" manifest="${1:-.}/$PLAN_CHECKSUMS_RELPATH" bad
  # Empty is not "nothing is frozen": `sha256sum -c` exits 0 on an empty
  # file, so an emptied manifest verifies vacuously and reads as a clean run.
  [ -s "$manifest" ] ||
    { printf '%s is missing or empty, so every frozen plan is unverifiable' "$PLAN_CHECKSUMS_RELPATH"; return 0; }
  bad="$(cd "$root" && sha256sum -c "$PLAN_CHECKSUMS_RELPATH" 2>&1 | grep -v ': OK$')"
  [ -z "$bad" ] ||
    { printf '%s no longer matches:\n%s' "$PLAN_CHECKSUMS_RELPATH" "$bad"; return 0; }
  return 0
}

# plan_field_refs <file> <key> -- one bare plan filename per line from a
# comma-separated ref field. Empty output for an empty or absent field.
plan_field_refs() {
  local raw
  raw="$(plan_get_field "$1" "$2")"
  [ -n "$raw" ] || return 0
  # printf '%s\n', not '%s': without the trailing newline the last entry
  # reaches `while read` unterminated, read returns non-zero at EOF, and the
  # loop body never runs for it -- every ref list silently skipped its final
  # reference, which is the one a caller is most likely to have just added
  # plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F17
  printf '%s\n' "$raw" | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d'
}

plan_is_frozen() {
  [ "$(plan_get_field "$1" frozen)" = "true" ]
}

# plan_require_not_frozen <root> <rel> -- refuse to touch a frozen plan.
# Consults the manifest as well as the file's own field, and the manifest is
# the one that matters: it is what .githooks/pre-commit enforces, and the
# field is self-declared. Editing a done/ plan's `frozen:` back to false
# otherwise walked straight past this, and `plan-move` would then carry it
# into in-progress/ -- after which pre-commit looks the file up under its
# *new* path, finds no entry, and passes appended content.
# plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F56
# plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F11
plan_require_not_frozen() {
  local root="$1" rel="$2"
  plan_manifest_frozen "$root" "$rel" &&
    plan_die "$rel is frozen ($PLAN_CHECKSUMS_RELPATH records it; done/ and rejected/ plans get zero further edits, ever). New information becomes a new plan file that cites it."
  plan_is_frozen "$root/$rel" &&
    plan_die "$root/$rel is frozen (done/ and rejected/ plans get zero further edits, ever). New information becomes a new plan file that cites it."
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

# plan_state_body <file> [skip-fences] -- the ## State section's text,
# without the heading. Returns non-zero if the file has no State heading
# at all. With a non-empty second argument, fenced blocks inside the
# section are dropped: quoting the declaration is not making it, and the
# fence rule lives here once rather than in each caller's own scanner.
# Shared by the two State-quality checks below so the section's
# boundaries have one definition.
#
# The first heading only, and never one inside a code fence: a plan that
# *documents* this schema quotes a whole example plan, headings and all,
# and a reader that re-arms on every match reads the example's State as
# the file's own -- so a plan with no State section passed both checks
# below on the strength of a fenced sample.
# plan: 2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md#F12
plan_state_body() {
  awk -v skip="${2:-}" '
    # CommonMark: a fence closes only on the same character, at least as
    # long as the opener. A toggle on any marker desyncs on a nested
    # fence and leaves the rest of the file misread in whichever
    # direction happens to be worse.
    # Leading whitespace allowed: CommonMark permits three spaces, and a
    # fence nested in a list item must be indented further. Anchoring at
    # column 0 left every indented fence invisible, and this repo writes
    # dozens of them.
    # plan: 2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md#F17
    match($0, /^[ \t]*(`{3,}|~{3,})/) {
      m = substr($0, RSTART, RLENGTH)
      sub(/^[ \t]+/, "", m)
      if (!fence) { fence = 1; open = m }
      else if (substr(m, 1, 1) == substr(open, 1, 1) && length(m) >= length(open)) fence = 0
      if (skip != "") next
    }
    fence && skip != "" { next }
    !fence && !seen && /^## State$/ { seen = 1; f = 1; next }
    !fence && /^## /                { f = 0; next }
    f
    END { exit seen ? 0 : 1 }
  ' "$1"
}

# plan_state_problem <file> -- prints a reason if the ## State section is
# missing or empty; empty output = present and non-empty. State is the one
# section rewritten in place rather than appended to (see plan/SKILL.md),
# so its presence can't be inferred from Progress/Decisions/Gotchas/Findings
# ever having had content.
plan_state_problem() {
  local file="$1" body
  # Presence comes from the same reader as the content, so a heading
  # this check accepts cannot be one plan_state_body ignores.
  # plan: 2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md#F12
  body="$(plan_state_body "$file")" || { echo "no '## State' heading found."; return; }
  [ -n "${body//[[:space:]]/}" ] ||
    echo "'## State' section is empty -- summarize the current status before freezing."
}

# plan_rung_problem <file> -- prints a reason if ## State declares no
# verification rung; empty output = declared. Require-declaration, not
# check: refuses a plan that does not say how far up the evidence ladder
# (docs/procedures/testing-changes.md) it was verified, without judging
# the verification itself.
# plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#D6
#
# Anchored on the blank-line block, not on punctuation: the phrase must
# open a paragraph or list item. State is hard-wrapped, so a line start
# means nothing and a sentence start is unrecognizable in prose -- three
# rounds of widening a preceding-character class each left another way
# to mention the phrase without declaring it. A blank line survives
# rewrapping, and a mention never opens the paragraph it sits in.
# plan: 2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md#F3
# plan: 2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md#F8
# plan: 2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md#F9
plan_rung_problem() {
  # Fenced blocks dropped: a plan documenting this schema quotes the
  # required form, and a quoted declaration is a mention.
  # plan: 2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md#F12
  plan_state_body "$1" skip-fences |
    awk '
      function check(   b) {
        b = block
        gsub(/[ \t]+/, " ", b)
        # emphasis deleted outright, backticks never: styling can wrap
        # any part of a real declaration, while code formatting is how a
        # doc quotes the phrase instead of claiming it
        gsub(/[*_]/, "", b)
        sub(/^ /, "", b)
        sub(/ $/, "", b)   # a trailing space must not refuse a real one
        # bullet and quote markers only with their trailing space, so a
        # "--" clause opening a sentence *about* the phrase is not
        # mistaken for one
        sub(/^[0-9]+[.)] /, "", b)      # numbered list item
        sub(/^[->] /, "", b)            # bullet or blockquote
        # what follows the rung is punctuation or nothing, never another
        # word: a mention in subject position ("Verified to rung 3 is the
        # phrase the gate wants") opens the paragraph too, so position
        # alone cannot tell it from a claim
        # plan: 2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md#F13
        if (tolower(b) ~ /^verified to rung [1-5]( ?[^0-9a-z ].*)?$/) found = 1
        block = ""
      }
      /^[ \t]*$/ { check(); next }
      { block = (block == "" ? $0 : block " " $0) }
      END { check(); exit found ? 0 : 1 }
    ' ||
    echo "no verification-rung declaration in ## State. Give it its own paragraph, opening with the phrase itself -- 'Verified to rung 3 (ran it locally, output inspected).' -- per docs/procedures/testing-changes.md, 'Declaring the rung'. Mentioning the phrase mid-sentence does not count, and neither does naming a rung you did not reach: declare the highest one you did, then say what you skipped."
}

plan_checksum() { sha256sum "$1" | awk '{print $1}'; }

# plan_record_checksum <root> <rel> -- record this file's current checksum in
# the manifest, replacing any entry it already has. The one writer, called by
# plan_do_freeze and plan-repair; the path field is compared exactly, as in
# plan_manifest_frozen.
# plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F24
plan_record_checksum() {
  local root="$1" rel sum checksums tmp
  rel="$(plan_normalise_rel "$2")"
  sum="$(plan_checksum "$root/$rel")"
  checksums="$root/$PLAN_CHECKSUMS_RELPATH"
  mkdir -p "$(dirname "$checksums")"
  touch "$checksums"
  tmp="$(mktemp)" || plan_die "cannot create a temporary file"
  out="$(mktemp)" || { rm -f "$tmp"; plan_die "cannot create a temporary file"; }
  # Every step checked, and the manifest replaced by a rename rather than by
  # a redirect onto itself. `sort -k2 "$tmp" > "$checksums"` truncates the
  # manifest *before* sort runs: one failure there left it empty, for every
  # frozen plan at once, and the checked `git add` below then staged the
  # empty file and exited 0. The freeze evidence destroyed itself and
  # reported success.
  # plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F54
  awk -v want="$rel" '
    { i = index($0, "  "); if (i > 0 && substr($0, i + 2) == want) next }
    { print }
  ' "$checksums" > "$tmp" || { rm -f "$tmp" "$out"; plan_die "cannot rewrite $PLAN_CHECKSUMS_RELPATH."; }
  printf '%s  %s\n' "$sum" "$rel" >> "$tmp" ||
    { rm -f "$tmp" "$out"; plan_die "cannot append to $PLAN_CHECKSUMS_RELPATH."; }
  sort -k2 "$tmp" > "$out" ||
    { rm -f "$tmp" "$out"; plan_die "cannot sort $PLAN_CHECKSUMS_RELPATH."; }
  # The manifest may only stay the same size (a re-record) or grow by one (a
  # new freeze). Anything else means a step above lost entries, and losing
  # one is losing the proof that that plan has not changed.
  if [ "$(grep -c . "$out")" -lt "$(grep -c . "$checksums")" ]; then
    rm -f "$tmp" "$out"
    plan_die "refusing to write a $PLAN_CHECKSUMS_RELPATH with fewer entries than it had; the freeze evidence would be lost."
  fi
  mv "$out" "$checksums" || { rm -f "$tmp" "$out"; plan_die "cannot replace $PLAN_CHECKSUMS_RELPATH."; }
  rm -f "$tmp"
  # Checked: the manifest on disk and the manifest in the index are what
  # .githooks/pre-commit compares, so a silent failure here is a freeze whose
  # evidence never reaches the commit.
  # plan: 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F47
  git -C "$root" add "$rel" "$PLAN_CHECKSUMS_RELPATH" ||
    plan_die "recorded the checksum for $rel but could not stage it or $PLAN_CHECKSUMS_RELPATH."
}

# plan_do_freeze <root> <rel> -- the mechanical half of freezing, shared by
# plan-freeze (done/, gated on resolved decisions) and plan-reject
# (rejected/, gated on a mandatory reason instead): sets frozen: true,
# records the checksum, marks the plan touched. Does not check which folder
# <rel> is in or anything about decisions -- callers do their own gating.
plan_do_freeze() {
  local root="$1" rel="$2"
  plan_set_field "$root/$rel" frozen true
  plan_record_checksum "$root" "$rel"
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

# plan_active_plan [<root>] -- the reader for the marker above: prints
# the plan's relpath, or returns non-zero when there is no live session
# or the marker names nothing. One definition because three call sites
# had invented three different existence tests, and `-r` succeeds on a
# directory where `-f` does not.
plan_active_plan() {
  local root="${1:-.}" marker rel
  marker="$root/$PLAN_ACTIVE_MARKER_RELPATH"
  [ -f "$marker" ] || return 1
  rel="$(cat "$marker")" || return 1
  [ -n "$rel" ] && [ -f "$root/$rel" ] || return 1
  # Same two-arm shape as plan_locate's path guard, and for the same
  # reason: subagent-stamp appends to whatever this names, so the marker
  # must not be able to point outside docs/plans/. The '..' arm comes
  # first because a case `*` matches '/', so the allowlist arm alone
  # would pass 'docs/plans/../x'. An absolute path fails the allowlist
  # arm on its own. A real marker is always written by plan_mark_touched,
  # whose input went through plan_locate, so nothing legitimate is
  # rejected.
  # plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F59
  case "$rel" in
    *..*) return 1 ;;
    docs/plans/*/*.md) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$rel"
}

# plan_existing_files -- filters paths on stdin down to those that still
# exist. A deletion staged but not committed is a normal mid-work state,
# and a consumer that passes filenames to another program (a linter, awk)
# would otherwise fail on it.
plan_existing_files() {
  local f
  while IFS= read -r f; do
    # `if`, not `&&` -- see plan_code_fingerprint
    # plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F32
    if [ -f "$f" ]; then printf '%s\n' "$f"; fi
  done
}

# plan_in_list <name> <member>... -- exact-string membership. The one
# definition: the padded-string `case " ${list[*]} "` idiom this replaces
# was re-derived at three sites, and it is the subtle one -- correct only
# while no member contains a space.
plan_in_list() {
  local n="$1" x
  shift
  for x in "$@"; do
    [ "$x" = "$n" ] && return 0
  done
  return 1
}

# plan_is_stampable <agent> -- is this agent one subagent-stamp records?
plan_is_stampable() {
  plan_in_list "$1" "${PLAN_STAMPABLE_AGENTS[@]}"
}

# Behavior, not prose: what a change to this file set can alter is what
# the machine does. Plan files and explanatory docs stay out so a stamp
# cannot invalidate itself -- see workflow/reference.md, "What a
# completion stamp proves". Wider than "*.nix" because the enforcement
# machinery is not all Nix.
# plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#G11
PLAN_CODE_GLOBS=(
  "*.nix"
  "*/scripts/*"        # skill scripts, incl. those outside docs/skills/
  "scripts/*"
  ".githooks/*"
  ".github/workflows/*"
  # named individually, not `.claude/*` -- the harness writes untracked
  # local-only files into this directory
  # plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F28
  ".claude/settings.json"
  ".claude/agents/*"
  ".claude/skills/*"
  "docs/agents/*"      # an agent definition is behavior, not prose
  ".sops.yaml"         # who can decrypt every secret in the repo
  "secrets/*"
  "flake.lock"
  "*.gitignore"        # --exclude-standard means this decides the hash's own inputs
  "*.gitattributes"    # `*.pem -diff` switches off the pre-commit secret scan
)

# The docs counterpart, one definition for the same reason: encoding the
# set twice lets a doc change without obliging docs-updater, or without
# plan-citations scanning it.
PLAN_DOC_GLOBS=("*.md")

# Where a plan citation can live: the code set minus the members that
# cannot hold one. Derived rather than restated, because a hand-kept
# second list is a copy -- this one silently missed two entries within a
# day of being written, and a citation checker that skips a file reports
# OK over it.
# plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F30
PLAN_NONTEXT_GLOBS=(
  ".claude/settings.json"  # JSON, no comment syntax
  ".sops.yaml"             # generated key material
  "secrets/*"              # encrypted
  "flake.lock"             # generated JSON
  ".claude/agents/*"       # symlinks to docs/agents/*, already scanned
  ".claude/skills/*"       # symlinks to docs/skills/*, already scanned
)
# Compared as literal strings, not patterns: both arrays hold globs, and
# the question is "is this the same glob", not "does this path match".
# Matching is inlined rather than using plan_path_matches, which is
# defined further down and would not exist yet at source time.
# One pass: build the derived set and record which exclusions were used,
# so the drift check below is a flat lookup rather than a second copy of
# the same nested scan -- two copies of "is this the same glob" is how
# the detector goes blind to the drift it exists for.
declare -A _hit=()
PLAN_TEXT_GLOBS=()
for _g in "${PLAN_CODE_GLOBS[@]}"; do
  _skip=0
  for _n in "${PLAN_NONTEXT_GLOBS[@]}"; do
    if [ "$_g" = "$_n" ]; then _skip=1; _hit["$_n"]=1; break; fi
  done
  if [ "$_skip" = 0 ]; then PLAN_TEXT_GLOBS+=("$_g"); fi
done
# An exclusion matching no code glob is a typo or a half-done rename, and
# it fails in the dangerous direction: the entry it was meant to exclude
# (secrets/*, .sops.yaml) stays in the citation scan set.
# plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F43
for _n in "${PLAN_NONTEXT_GLOBS[@]}"; do
  [ -n "${_hit[$_n]:-}" ] ||
    printf 'plan: PLAN_NONTEXT_GLOBS entry %s matches no PLAN_CODE_GLOBS entry -- it excludes nothing\n' "$_n" >&2
done
unset _g _n _skip _hit

# plan_code_fingerprint -- content hash of the reviewable code in the
# working tree. Self-locating: pathspecs are cwd-relative, so from a
# subdirectory this used to hash a subset and return *success*, and a
# wrong-but-successful hash cannot be told from a real one by any caller.
#
# Content, not history. An agent reviews uncommitted work and the commit
# lands *after* the stamp, so anything keyed on HEAD or on commit time
# reports a review that genuinely happened as stale -- an un-passable
# gate, which is worse than a weak one.
# plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#D11
plan_code_fingerprint() {
  local out r
  r="$(git rev-parse --show-toplevel)" || return 1
  out="$(
    cd "$r" || exit 1
    set -o pipefail
    # -z throughout: a path may contain a newline.
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
    # The -f test below drops symlinks-to-directories, so .claude/skills/*
    # obliges review without moving the hash.
    # plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F31
    #
    # Absent-but-tracked files are skipped rather than failing the hash:
    # a deletion that is not yet committed is a normal mid-work state,
    # and CI, where the deletion *is* committed, also omits the file.
    #
    # `if`, not `[ -f ] &&`: a while loop exits with its last body
    # command's status, so the `&&` form returned 1 whenever the
    # sort-last path was not a regular file, and pipefail turned that
    # into an empty fingerprint -- a gate no re-run could clear.
    # plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F32
    git ls-files -z --cached --others --exclude-standard -- "${PLAN_CODE_GLOBS[@]}" |
      while IFS= read -r -d '' f; do
        if [ -f "$f" ]; then printf '%s\0' "$f"; fi
      done |
      LC_ALL=C sort -zu |
      xargs -0 -r sha256sum |
      sha256sum
  )" || return 1
  printf '%.16s' "${out%% *}"
}

# plan_is_code_path <path> -- does this path fall inside PLAN_CODE_GLOBS?
# required-agents' only test for "is this reviewable code", reading the
# same array plan_code_fingerprint hashes, so what obliges review cannot
# drift from what invalidates a stamp.
# plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F29
plan_is_code_path() { plan_path_matches "$1" "${PLAN_CODE_GLOBS[@]}"; }

# plan_is_doc_path <path> -- does this path fall inside PLAN_DOC_GLOBS?
plan_is_doc_path() { plan_path_matches "$1" "${PLAN_DOC_GLOBS[@]}"; }

# plan_path_matches <path> <glob>... -- shared by both predicates above so
# the matching semantics have one definition.
plan_path_matches() {
  local p="$1" g
  shift
  for g in "$@"; do
    # shellcheck disable=SC2053  # $g is a pattern here, deliberately
    [[ "$p" == $g ]] && return 0
  done
  return 1
}

# plan_worktree_files [<pathspec>...] -- every path changed in the working
# tree relative to HEAD: unstaged, staged, and untracked, one per line.
# Untracked files count -- a brand-new module is the change most in need
# of review, and it appears in none of git's diff views until staged. One
# definition, because three call sites each spelling this union is how
# the untracked leg went missing from one of them.
# The --cached leg looks redundant against `diff HEAD` and is not: a file
# staged and then reverted in the working tree shows in --cached only,
# and its staged content is what a commit would take.
#
# core.quotePath=false: git otherwise C-quotes a non-ASCII path
# ("modules/caf\303\251.nix"), and the quoted form matches none of the
# globs -- so a .nix file with an accented name obliged no review at all
# while the fingerprint, which uses -z, still hashed it.
#
# It demotes bytes >= 0x80 only. A quote, backslash, tab or newline in a
# path is still quoted, and a newline additionally splits one path across
# two lines here. Only -z with a NUL-safe reader closes that, which the
# fingerprint and plan-citations do and this line-based helper does not.
# plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F42
#
# Each leg's status is checked separately. A `{ a; b; c; }` group reports
# only c's status, so a failing first leg was invisible and the function
# returned success with empty output -- "nothing changed, so no agents
# obliged", the same fail-open required-agents closes for range mode.
# plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F37
plan_worktree_files() {
  local unstaged staged untracked
  unstaged="$(git -c core.quotePath=false diff --name-only HEAD -- "$@")" || return 1
  staged="$(git -c core.quotePath=false diff --cached --name-only -- "$@")" || return 1
  untracked="$(git -c core.quotePath=false ls-files --others --exclude-standard -- "$@")" || return 1
  printf '%s\n%s\n%s\n' "$unstaged" "$staged" "$untracked" | sed '/^$/d' | LC_ALL=C sort -u
}

# plan_stamp_line <agent> <timestamp> <fingerprint> -- the single
# definition of the completion-stamp format. subagent-stamp writes it and
# plan_stamp_fingerprint reads it; with the two in separate files and no
# shared definition, a reworded stamp would silently block every merge.
#
# A stamp records that an agent of that type ran to completion against
# code with that fingerprint. It is a record, not proof -- see
# workflow/reference.md, "What a completion stamp proves".
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

# plan_heading_re <id> -- the one definition of "### <id> is a real
# heading". The trailing boundary is what stops '### D1' from matching
# '### D12'. Appenders need the pattern (plan-decide, plan-carry,
# plan-resolve feed it to plan_append_under_heading); readers want the
# boolean below. Both come from here so they cannot disagree.
plan_heading_re() {
  printf '^### %s([[:space:]]|$)' "$1"
}

# plan_has_heading <file> <id> -- does "### <id>" exist as a real heading?
plan_has_heading() {
  grep -qE "$(plan_heading_re "$2")" "$1"
}
