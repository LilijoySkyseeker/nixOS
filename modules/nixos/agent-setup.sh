# agent-setup: check the agent's place on torrent and, after asking, fix what's missing.
# run as root: `run0 agent-setup` (check and fix) or `run0 agent-setup --check` (report only)
# plan: 2026-10-06-make-the-agent-s-place-reproducible-with-an-agent-setup-check-and-fix.md

check_only=0
[ "${1:-}" = "--check" ] && check_only=1
if [ "$(id -u)" -ne 0 ]; then
  echo "run as root: run0 agent-setup${1:+ $1}" >&2
  exit 2
fi

agent_home=/home/agent
research=/home/lilijoy/Documents/Vault/Research
settings=$agent_home/.claude/settings.json
state=$agent_home/.claude.json

# run0 keeps the caller's cwd, which the other user may not be able to read
# (git then refuses to run), so each helper starts in that user's home
as_agent() { runuser -u agent -- env -C "$agent_home" HOME="$agent_home" PATH="$PATH:/etc/profiles/per-user/agent/bin:/run/current-system/sw/bin" "$@"; }
as_user() { runuser -u lilijoy -- env -C /home/lilijoy HOME=/home/lilijoy PATH="$PATH:/etc/profiles/per-user/lilijoy/bin:/run/current-system/sw/bin" "$@"; }

if [ -t 1 ]; then green=$'\033[32m' red=$'\033[31m' dim=$'\033[2m' reset=$'\033[0m'; else green='' red='' dim='' reset=''; fi
failed=0
ok() { printf '%s✓%s %s\n' "$green" "$reset" "$1"; }
bad() { printf '%s✗%s %s\n' "$red" "$reset" "$1"; failed=$((failed + 1)); }
note() { printf '  %s%s%s\n' "$dim" "$1" "$reset"; }
confirm() {
  local ans
  printf '  fix: %s? [Y/n] ' "$1"
  read -r ans
  [ "$ans" != n ] && [ "$ans" != N ]
}

# item LABEL CHECK FIX_LABEL FIX: pass, or (unless --check) offer the fix and re-check
item() {
  local label=$1 check=$2 fix_label=$3 fix=$4
  if "$check"; then ok "$label"; return; fi
  if [ "$check_only" -eq 0 ] && [ -n "$fix" ] && confirm "$fix_label"; then
    "$fix" || true
    if "$check"; then ok "$label (fixed)"; return; fi
  fi
  bad "$label"
  note "to fix: $fix_label"
}

chk_module() { id agent >/dev/null 2>&1 && systemctl cat claude-remote-control >/dev/null 2>&1; }

chk_research() { [ -d "$research" ]; }
fix_research() { as_user mkdir -p "$research"; }

chk_mount() { as_agent sh -c 'touch ~/research/.agent-setup-probe && rm ~/research/.agent-setup-probe' 2>/dev/null; }
fix_mount() {
  systemctl reset-failed home-agent-research.mount home-agent-research.automount 2>/dev/null || true
  systemctl restart home-agent-research.automount
}

chk_settings() {
  jq -e '(.deniedMcpServers | any(.serverName == "claude-code-remote"))
    and (.permissions.deny | index("RemoteTrigger")) and .disableClaudeAiConnectors' "$settings" >/dev/null 2>&1
}
fix_settings() { systemctl restart claude-agent-settings; }

chk_egress() {
  iptables -C OUTPUT -m owner --uid-owner agent -j agent-egress 2>/dev/null &&
    ip6tables -C OUTPUT -m owner --uid-owner agent -j agent-egress 2>/dev/null
}
fix_egress() { systemctl reload firewall; }

chk_git() { [ "$(as_agent git config user.name 2>/dev/null)" = "$BOT" ]; }

chk_gh() { [ "$(as_agent gh api user -q .login 2>/dev/null)" = "$BOT" ]; }
fix_gh() {
  note "authorize in a browser logged in as $BOT, not your own account"
  as_agent gh auth login --hostname github.com --git-protocol https --web
}

chk_claude() {
  [ -s "$agent_home/.claude/.credentials.json" ] &&
    jq -e '.projects["/home/agent/work"].hasTrustDialogAccepted == true' "$state" >/dev/null 2>&1
}
fix_claude() {
  note "accept the trust dialog, log in with your claude.ai account if asked, then type /exit"
  as_agent env -C "$agent_home/work" ENABLE_CLAUDEAI_MCP_SERVERS=false claude || true
}

# remoteDialogSeen is undocumented; it's what the first consent run wrote
chk_consent() { jq -e '.remoteDialogSeen == true' "$state" >/dev/null 2>&1; }
fix_consent() {
  note "answer y to \"Enable Remote Control?\", wait for the session URL, then press Ctrl+C"
  as_agent env -C "$agent_home/work" ENABLE_CLAUDEAI_MCP_SERVERS=false \
    claude remote-control --spawn same-dir --name "$NAME" || true
}

chk_service() { systemctl is-active --quiet claude-remote-control; }
fix_service() {
  systemctl restart claude-agent-settings claude-remote-control
  sleep 3
}

chk_collab() {
  local repo
  for repo in $BOT_REPOS; do
    as_user gh api "repos/$OWNER/$repo/collaborators/$BOT" >/dev/null 2>&1 || return 1
  done
}

chk_protection() {
  local n
  n=$(as_user gh api "repos/$OWNER/nixOS/branches/master/protection" \
    -q '.required_pull_request_reviews.required_approving_review_count' 2>/dev/null) || return 1
  [ "${n:-0}" -ge 1 ]
}

echo "agent's place on torrent"
if ! chk_module; then
  bad "agent-user module deployed"
  note "switch to a configuration that imports agent-user, then rerun"
  exit 1
fi
ok "agent-user module deployed"
item "research folder" chk_research "create $research (as lilijoy)" fix_research
item "research mount" chk_mount "reset and restart the research automount" fix_mount
item "agent settings merged" chk_settings "rerun claude-agent-settings" fix_settings
item "LAN/tailnet egress blocked" chk_egress "reload the firewall" fix_egress
item "git identity" chk_git "it's declared by the module: switch" ""
item "gh logged in as $BOT" chk_gh "log the agent's gh in as the bot" fix_gh
item "Claude login and workspace trust" chk_claude "run claude once in ~agent/work" fix_claude
item "Remote Control consent" chk_consent "run claude remote-control once" fix_consent
item "remote-control service running" chk_service "restart the agent services" fix_service
item "bot is a collaborator on: $BOT_REPOS" chk_collab "invite $BOT in each repo's Settings → Collaborators" ""
item "nixOS master needs a PR + review" chk_protection "Settings → Branches → protect master (1 approval, admin bypass on)" ""
note "not checkable here: Trusted Devices (claude.ai → Settings → Account)"

if [ "$failed" -eq 0 ]; then
  echo "all good"
else
  echo "$failed item(s) need attention"
  exit 1
fi
