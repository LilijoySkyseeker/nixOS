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

# Set by reinstall-host.sh when --dry-run is passed. Every function
# below that touches disk state, the network, or requires physical
# presence checks this instead of duplicating the check at every call
# site.
DRY_RUN="${DRY_RUN:-0}"

dry() { [ "$DRY_RUN" = "1" ]; }

# Pause and require the user to explicitly type "yes" — used before any
# destructive step (disk wipe, LUKS enrollment). Plain enter-to-continue
# is too easy to fat-finger through. In --dry-run, nothing destructive
# actually happens, so this just logs and continues instead of blocking.
confirm() {
  local prompt="$1"
  local reply
  echo -e "${YELLOW}${prompt}${NC}"
  if dry; then
    log "[dry-run] auto-confirmed"
    return 0
  fi
  read -r -p "Type 'yes' to continue: " reply
  [ "$reply" = "yes" ] || die "Aborted by user."
}

# Pause for a manual out-of-band step (BIOS setup mode, plugging in a
# USB drive, etc) and wait for enter rather than a typed confirmation —
# used for non-destructive waypoints. Skipped in --dry-run.
pause() {
  local prompt="$1"
  echo -e "${YELLOW}${prompt}${NC}"
  if dry; then
    log "[dry-run] auto-continued"
    return 0
  fi
  read -r -p "Press enter once done: "
}

# run_cmd <command...> — the one place that actually executes a local
# state-changing command (run0 syncoid, run0 systemd-cryptenroll, ...).
# In --dry-run, logs what would run instead of running it.
run_cmd() {
  if dry; then
    log "[dry-run] would run: $*"
    return 0
  fi
  log "$*"
  "$@"
}

ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

# ssh_to <user@host> <command...> — thin wrapper so every remote call
# uses the same options and shows what's being run. In --dry-run, logs
# the command instead of connecting (no ssh attempt at all, so this
# works even against a host/IP that doesn't exist yet).
ssh_to() {
  local target="$1"
  shift
  if dry; then
    log "[dry-run] would run: ssh $target -- $*"
    return 0
  fi
  log "ssh $target -- $*"
  ssh "${ssh_opts[@]}" "$target" -- "$@"
}

# ssh_tty_to <user@host> <command...> — like ssh_to but allocates a tty
# (-t), for interactive remote commands like disko-install. Same
# --dry-run behavior.
ssh_tty_to() {
  local target="$1"
  shift
  if dry; then
    log "[dry-run] would run: ssh -t $target -- $*"
    return 0
  fi
  log "ssh -t $target -- $*"
  ssh -t "${ssh_opts[@]}" "$target" -- "$@"
}

require_host_conf() {
  local host="$1"
  local conf="$SCRIPTS_DIR/hosts/${host}.conf"
  [ -f "$conf" ] || die "No scripts/hosts/${host}.conf — copy scripts/hosts/thinkpad.conf as a template and fill in this host's values."
  # shellcheck disable=SC1090
  source "$conf"
}
