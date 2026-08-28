#!/usr/bin/env bash
# Shared JSON-payload helpers for the workflow skill's hooks. Sourced,
# never executed directly. Same jq-or-awk-fallback approach as
# tcr-skill/scripts/tcr-guard-hook, since this sandbox and some minimal
# systems don't ship jq.

hook_extract_top() { # hook_extract_top <json> <key>
  awk -v key="$2" '
  BEGIN { needle = "\"" key "\""; ORS=""; }
  { text = text $0 "\n" }
  END {
    n = length(text); idx = index(text, needle)
    if (idx == 0) { exit 1 }
    i = idx + length(needle)
    while (i <= n) {
      c = substr(text, i, 1)
      if (c == " " || c == "\t" || c == "\n" || c == ":") { i++ } else break
    }
    if (substr(text, i, 1) != "\"") { exit 1 }
    i++; out = ""
    while (i <= n) {
      c = substr(text, i, 1)
      if (c == "\\") {
        nc = substr(text, i + 1, 1)
        if (nc == "n") out = out "\n"
        else if (nc == "t") out = out "\t"
        else out = out nc
        i += 2; continue
      }
      if (c == "\"") break
      out = out c; i++
    }
    printf "%s", out
  }' <<<"$1"
}

hook_extract_obj() { # hook_extract_obj <json> <key> -- raw "key": { ... }
  awk -v key="$2" '
  BEGIN { needle = "\"" key "\""; ORS=""; }
  { text = text $0 "\n" }
  END {
    n = length(text); idx = index(text, needle)
    if (idx == 0) { exit 1 }
    i = idx + length(needle)
    while (i <= n) {
      c = substr(text, i, 1)
      if (c == " " || c == "\t" || c == "\n" || c == ":") { i++ } else break
    }
    if (substr(text, i, 1) != "{") { exit 1 }
    depth = 0; start = i; instr = 0
    while (i <= n) {
      c = substr(text, i, 1)
      if (instr) {
        if (c == "\\") { i += 2; continue }
        if (c == "\"") instr = 0
        i++; continue
      }
      if (c == "\"") { instr = 1; i++; continue }
      if (c == "{") { depth++; i++; continue }
      if (c == "}") { depth--; i++; if (depth == 0) break; continue }
      i++
    }
    printf "%s", substr(text, start, i - start)
  }' <<<"$1"
}

hook_json_str() { # hook_json_str <json> <top-level-key>
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r --arg k "$2" '.[$k] // empty' 2>/dev/null
  else
    hook_extract_top "$1" "$2" 2>/dev/null
  fi
}

hook_json_command() { # hook_json_command <json> -- .tool_input.command
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '.tool_input.command // empty' 2>/dev/null
  else
    local obj
    obj="$(hook_extract_obj "$1" tool_input 2>/dev/null)" || return 0
    [ -n "$obj" ] && hook_extract_top "$obj" command
  fi
}

hook_deny() { # hook_deny <event-name> <reason>
  local reason
  reason="$(printf '%s' "$2" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\t' '  ')"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1" "$reason"
  exit 0
}

# anchored <command> <pattern> -- true if <pattern> matches at the start of
# <command> or right after ;/&&/|/( -- not just anywhere as a substring
# (e.g. inside a quoted commit-message argument).
hook_anchored() {
  printf '%s' "$1" | grep -Eq "(^|[;&|(][[:space:]]*)$2"
}
