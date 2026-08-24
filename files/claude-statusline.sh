#!/usr/bin/env bash
# Tide-style powerline statusLine for Claude Code.
# Segments: cwd (blue) -> git branch (green/yellow) -> model (magenta)
#        -> context -> 5h usage -> 7d usage (green/yellow/red) -> time (grey)
#
# Wired up by modules/home-manager/claude-code.nix, which pins jq/git/coreutils
# onto PATH; Claude Code feeds this script its status JSON on stdin.

input=$(cat)

cwd=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input")
model=$(jq -r '.model.display_name // empty' <<<"$input")
ctx_pct=$(jq -r '.context_window.used_percentage // empty' <<<"$input")
five_pct=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")
five_reset=$(jq -r '.rate_limits.five_hour.resets_at // empty' <<<"$input")
week_pct=$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$input")
week_reset=$(jq -r '.rate_limits.seven_day.resets_at // empty' <<<"$input")

short_dir="~"
[ -n "$cwd" ] && short_dir="${cwd/#"$HOME"/\~}"

git_segment=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]; then
    git_bg="196;160;0"   # dirty: yellow, matches tide
    dirty=" *"
  else
    git_bg="78;154;6"    # clean: green
    dirty=""
  fi
  git_segment=" \033[48;2;${git_bg}m\033[38;2;0;0;0m  ${branch}${dirty} \033[0m"
fi

time_str=$(date +%H:%M)

# Shared green/yellow/red scale: under half is fine, 50%+ warns, 80%+ is urgent.
usage_bg() {
  if [ "$1" -ge 80 ]; then
    echo "204;0;0"       # red: nearly exhausted
  elif [ "$1" -ge 50 ]; then
    echo "196;160;0"     # yellow: over halfway
  else
    echo "78;154;6"      # green: plenty of room
  fi
}

# When the window frees up. "date" style spells out the calendar day for the
# 7d window, which lands days out; "clock" keeps the 5h window narrow, only
# naming a weekday when the reset spills past midnight.
reset_time() {
  local ts=$1 style=$2
  [ "$ts" -le "$(date +%s)" ] && { echo "now"; return; }
  if [ "$style" = "date" ]; then
    date -d "@$ts" "+%b %-d %H:%M"
  elif [ "$(date -d "@$ts" +%F)" = "$(date +%F)" ]; then
    date -d "@$ts" +%H:%M
  else
    date -d "@$ts" "+%a %H:%M"
  fi
}

ctx_segment=""
if [ -n "$ctx_pct" ]; then
  ctx_n=$(printf '%.0f' "$ctx_pct")
  ctx_segment=" \033[48;2;$(usage_bg "$ctx_n")m\033[38;2;0;0;0m  ctx ${ctx_n}% \033[0m"
fi

# Rate-limit windows only appear once the API has reported them, and the
# percentages arrive as floats - round before comparing or printing.
rate_segment() {
  local icon=$1 label=$2 pct=$3 reset=$4 style=$5
  [ -n "$pct" ] || return
  local n; n=$(printf '%.0f' "$pct")
  local text="${label} ${n}%"
  # Only spend the extra width on a reset time once the window is nearly spent.
  [ "$n" -ge 80 ] && [ -n "$reset" ] && text="${text} ($(reset_time "$reset" "$style"))"
  printf " \033[48;2;%sm\033[38;2;0;0;0m %s %s \033[0m" "$(usage_bg "$n")" "$icon" "$text"
}

printf "\033[48;2;52;101;164m\033[38;2;228;228;228m  %s \033[0m" "$short_dir"
[ -n "$git_segment" ] && printf "%b" "$git_segment"
[ -n "$model" ] && printf "\033[48;2;135;95;175m\033[38;2;228;228;228m  %s \033[0m" "$model"
[ -n "$ctx_segment" ] && printf "%b" "$ctx_segment"
rate_segment "" "5h" "$five_pct" "$five_reset" clock
rate_segment "" "7d" "$week_pct" "$week_reset" date
printf "\033[48;2;68;68;68m\033[38;2;228;228;228m  %s \033[0m\n" "$time_str"
