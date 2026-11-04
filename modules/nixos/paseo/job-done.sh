# job-done: a job run's last command, before its report (agent-jobs/ending.md).
# Detached, it waits for the run's turn to end, then archives the run's
# workspace (and so the run) if the report ends with the marker line: a run
# stopped mid-report, on a usage limit or otherwise, stays visible.
if [ "${1:-}" != --detached ]; then
  setsid -f "$0" --detached </dev/null >/dev/null 2>&1
  exit 0
fi
paseo wait "$PASEO_AGENT_ID" >/dev/null
last=$(paseo logs "$PASEO_AGENT_ID" --filter text --tail 1 | grep -v '^[[:space:]]*$' | tail -n 1)
[ "$last" = "END OF REPORT" ] || exit 0
# each scheduled run gets a workspace of its own; its run record names it
for s in $(paseo schedule ls -q); do
  paseo schedule inspect "$s" --json
done | jq -r '.runs[] | select(.agentId == env.PASEO_AGENT_ID) | .workspaceId // empty' |
  xargs -r -n1 paseo workspace archive >/dev/null
