#!/usr/bin/env bash
# Shared helpers for scripts/reinstall-host.sh. Not meant to be run
# directly — sourced by the stage scripts.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}==>${NC} $*"; }
ok() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}==>${NC} $*"; }
err() { echo -e "${RED}==>${NC} $*" >&2; }
die() {
  err "$*"
  exit 1
}

# Pause and require the user to explicitly type "yes" — used before any
# destructive step (disk wipe, LUKS enrollment). Plain enter-to-continue
# is too easy to fat-finger through.
confirm() {
  local prompt="$1"
  local reply
  echo -e "${YELLOW}${prompt}${NC}"
  read -r -p "Type 'yes' to continue: " reply
  [ "$reply" = "yes" ] || die "Aborted by user."
}

# Pause for a manual out-of-band step (BIOS setup mode, plugging in a
# USB drive, etc) and wait for enter rather than a typed confirmation —
# used for non-destructive waypoints.
pause() {
  local prompt="$1"
  echo -e "${YELLOW}${prompt}${NC}"
  read -r -p "Press enter once done: "
}

ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

# ssh_to <user@host> <command...> — thin wrapper so every remote call
# uses the same options and shows what's being run.
ssh_to() {
  local target="$1"
  shift
  log "ssh $target -- $*"
  ssh "${ssh_opts[@]}" "$target" -- "$@"
}

require_host_conf() {
  local host="$1"
  local conf="$SCRIPTS_DIR/hosts/${host}.conf"
  [ -f "$conf" ] || die "No scripts/hosts/${host}.conf — copy scripts/hosts/thinkpad.conf as a template and fill in this host's values."
  # shellcheck disable=SC1090
  source "$conf"
}
