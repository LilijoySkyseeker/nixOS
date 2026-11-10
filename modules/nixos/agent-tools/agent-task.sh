# agent-task: run a long job as its own service, agent-task@NAME, in the
# agents' sandbox and memory cap. It outlives the session that started it,
# Claude Code's background limit, Paseo restarts and switches; a reboot
# stops it, and it stays stopped.
# the path agent-task@.service reads, fixed in agent-user.nix
state=/home/agent/.local/state/agent-task
usage() {
  cat >&2 <<'EOF'
usage: agent-task start NAME -- COMMAND [ARG...]   run COMMAND in the current directory
       agent-task ls                               the running tasks
       agent-task log NAME [-f]                    its output, ending "=== ... exited" (-f: follow)
       agent-task stop NAME                        stop it and everything it started
       agent-task status NAME                      its unit's state
NAME: letters, digits, '.', '_' and '-', not starting with '.' or '-'.
The task gets this shell's environment (credential-named variables
dropped) but its own /tmp: keep its files elsewhere, ~/work/scratch say.
Output goes to
~/.local/state/agent-task/NAME/log.
EOF
  exit 2
}
unit() { echo "agent-task@$1.service"; }
# root starts and stops the unit for us: see agent-task-broker in agent-user.nix
broker() {
  local out
  out=$(printf '%s %s\n' "$1" "$2" | socat -t 120 - UNIX-CONNECT:/run/agent-task.sock) || {
    echo "agent-task: no answer from /run/agent-task.sock" >&2
    return 1
  }
  [ "$(tail -n 1 <<<"$out")" = ok ] || {
    echo "$out" >&2
    return 1
  }
}
name_ok() {
  [[ ${1:-} =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]] || {
    echo "agent-task: bad name '${1:-}'" >&2
    usage
  }
}

case ${1:-} in
start)
  name_ok "${2:-}"
  name=$2
  shift 2
  [ "${1:-}" = -- ] && shift
  [ $# -gt 0 ] || usage
  # the task has its own /tmp: a path in this one wouldn't be there
  for a in "$PWD" "$@"; do
    case $a in /tmp | /tmp/* | /var/tmp | /var/tmp/*)
      echo "agent-task: '$a' is in /tmp, which the task can't see; move it under ~/work/scratch" >&2
      exit 2
      ;;
    esac
  done
  dir=$state/$name
  mkdir -p "$dir"
  # one start per name at a time, from the check to the unit's start
  exec 9>"$dir/.lock"
  flock 9
  if systemctl is-active -q "$(unit "$name")"; then
    echo "agent-task: $name is already running; stop it or pick another name" >&2
    exit 1
  fi
  # the unit runs this script: the command, in the directory and environment
  # it was started from (a dev shell's PATH, say), minus credentials and
  # this shell's own bookkeeping
  tmp=$(mktemp "$dir/.run.XXXXXX")
  {
    echo '#!/usr/bin/env bash'
    # env -0, not compgen: writeShellApplication's bash has no compgen
    while IFS= read -r -d '' kv; do
      v=${kv%%=*}
      [[ $v =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
      case $v in
      *KEY* | *TOKEN* | *SECRET* | *PASSWORD* | PWD | OLDPWD | SHLVL | _ | INVOCATION_ID | JOURNAL_STREAM | SYSTEMD_EXEC_PID) ;;
      *) printf 'export %s=%q\n' "$v" "${kv#*=}" ;;
      esac
    done < <(env -0)
    printf 'cd %q || exit 1\n' "$PWD"
    printf 'exec'
    printf ' %q' "$@"
    echo
  } >"$tmp"
  mv "$tmp" "$dir/run"
  printf '\n=== %s started: %s\n' "$(date -Is)" "$*" >>"$dir/log"
  broker start "$name"
  echo "agent-task: started $name; output: agent-task log $name"
  ;;
ls)
  systemctl list-units --all --no-pager 'agent-task@*'
  ;;
log)
  name_ok "${2:-}"
  if [ "${3:-}" = -f ]; then exec tail -n 50 -f "$state/$2/log"; fi
  exec cat "$state/$2/log"
  ;;
stop)
  name_ok "${2:-}"
  broker stop "$2"
  ;;
status)
  name_ok "${2:-}"
  systemctl status --no-pager "$(unit "$2")" || true
  ;;
*) usage ;;
esac
