"""Hook for Claude Code and Codex: tell the model its plan limits and context.

Reads the hook event on stdin and prints hookSpecificOutput.additionalContext:
- UserPromptSubmit: always one line.
- PostToolUse: a line only when a figure has crossed 50, 75 or 90% since the
  last line in this session.

Sources:
- Claude limits: Claude Code's get_usage control request (no model call),
  cached for every agent, since they share one account.
- Codex limits and context: the token_count records Codex writes to its
  session file. Claude's own context comes from Claude Code itself
  (CLAUDE_CODE_ENABLE_TOKEN_USAGE_ATTACHMENT), not from here.

Any failure prints nothing: a hook must never break a session.
"""

import fcntl
import getpass
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

INNER = "AGENT_USAGE_LINE_INNER"
BANDS = (50, 75, 90)
CLAUDE_TTL = 300
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
CACHE = CACHE / "agent-usage-line"
CODEX_SESSIONS = Path.home() / ".codex" / "sessions"


def band(pct):
    return sum(pct >= b for b in BANDS)


def when(ts):
    """A reset time, local, short: '14:10' today, else 'Mon 16 Nov 00:00'."""
    t = datetime.fromtimestamp(ts).astimezone()
    if t.date() == datetime.now().astimezone().date():
        return t.strftime("%H:%M")
    return t.strftime("%a %d %b %H:%M")


def iso_ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def fetch_claude():
    reqs = [
        {"type": "control_request", "request_id": "i",
         "request": {"subtype": "initialize"}},
        {"type": "control_request", "request_id": "u",
         "request": {"subtype": "get_usage", "skip_behaviors": True}},
    ]
    env = dict(os.environ, **{INNER: "1"})
    out = subprocess.run(
        ["claude", "-p", "--input-format", "stream-json",
         "--output-format", "stream-json", "--verbose",
         "--setting-sources", "", "--strict-mcp-config"],
        input="".join(json.dumps(r) + "\n" for r in reqs),
        capture_output=True, text=True, timeout=30, env=env,
    ).stdout
    for line in out.splitlines():
        try:
            d = json.loads(line)
        except ValueError:
            continue
        resp = d.get("response") or {}
        if d.get("type") == "control_response" and resp.get("request_id") == "u":
            rl = (resp.get("response") or {}).get("rate_limits")
            if not rl:
                return None
            windows = []
            for key, name in (("five_hour", "5h"), ("seven_day", "week")):
                w = rl.get(key)
                if w and w.get("utilization") is not None:
                    windows.append((name, w["utilization"], iso_ts(w["resets_at"])))
            for m in rl.get("model_scoped") or []:
                if m.get("utilization") is not None and m.get("resets_at"):
                    windows.append((m["display_name"] + " week", m["utilization"],
                                    iso_ts(m["resets_at"])))
            return windows
    return None


def claude_limits():
    """Cached Claude windows; one agent refreshes while the rest read."""
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / "claude.json"
    try:
        cached = json.loads(path.read_text())
    except (OSError, ValueError):
        cached = None
    if cached and time.time() - cached["at"] < CLAUDE_TTL:
        return cached["windows"]
    with open(CACHE / "claude.lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return cached["windows"] if cached else None
        try:
            windows = fetch_claude()
        except (OSError, subprocess.SubprocessError, ValueError, KeyError):
            windows = None
        if windows is None:
            return cached["windows"] if cached else None
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps({"at": time.time(), "windows": windows}))
        tmp.replace(path)
        return windows


def last_token_count(path):
    """The last token_count record in a Codex session file (reads its tail)."""
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        f.seek(max(0, size - 1_000_000))
        tail = f.read().decode("utf-8", "replace")
    for line in reversed(tail.splitlines()):
        if '"token_count"' not in line:
            continue
        try:
            p = json.loads(line).get("payload") or {}
        except ValueError:
            continue
        if p.get("type") == "token_count":
            return p
    return None


def newest_codex_session():
    days = sorted(CODEX_SESSIONS.glob("*/*/*"), reverse=True)[:2]
    files = [f for d in days for f in d.glob("rollout-*.jsonl")]
    return max(files, key=lambda f: f.stat().st_mtime, default=None)


def codex_limits(tc):
    rl = (tc or {}).get("rate_limits") or {}
    windows = []
    for key, name in (("primary", "5h"), ("secondary", "week")):
        w = rl.get(key)
        if w and w.get("used_percent") is not None and w.get("resets_at"):
            windows.append((name, w["used_percent"], w["resets_at"]))
    return windows


def codex_context(tc):
    info = (tc or {}).get("info") or {}
    last, window = info.get("last_token_usage"), info.get("model_context_window")
    if not last or not window:
        return None
    used = last.get("input_tokens", 0) + last.get("output_tokens", 0)
    return 100 * used / window, window


def fmt_windows(family, windows):
    now = time.time()
    parts = []
    for name, pct, reset in windows:
        if reset <= now:
            parts.append(f"{name} 0% (reset since)")
        else:
            parts.append(f"{name} {pct:.0f}% (resets {when(reset)})")
    return f"{family} " + ", ".join(parts) if parts else None


def main():
    # Codex's managed hooks are system-wide; only the agents get the line
    if os.environ.get(INNER) or getpass.getuser() != "agent":
        return
    event = json.load(sys.stdin)
    name = event.get("hook_event_name", "")
    transcript = event.get("transcript_path") or ""
    is_codex = "/.codex/" in transcript

    tc_own = None
    if is_codex and transcript:
        try:
            tc_own = last_token_count(transcript)
        except OSError:
            pass
    tc_codex = tc_own
    if tc_codex is None or not codex_limits(tc_codex):
        try:
            newest = newest_codex_session()
            tc_codex = last_token_count(newest) if newest else None
        except OSError:
            tc_codex = None

    claude = claude_limits() or []
    codex = codex_limits(tc_codex)
    ctx = codex_context(tc_own) if is_codex else None

    figures = [p for _, p, r in claude + codex if r > time.time()]
    if ctx:
        figures.append(ctx[0])
    top = max((band(p) for p in figures), default=0)

    if name not in ("UserPromptSubmit", "PostToolUse"):
        return
    state = CACHE / "sessions" / (event.get("session_id") or "none")
    try:
        seen = int(state.read_text())
    except (OSError, ValueError):
        seen = 0
    if name == "PostToolUse" and top <= seen:
        return
    state.parent.mkdir(parents=True, exist_ok=True)
    state.write_text(str(top))

    parts = [fmt_windows("Claude", claude), fmt_windows("Codex", codex)]
    line = "Plan usage, shared by every agent on the account: "
    line += "; ".join(p for p in parts if p) or "unknown"
    if ctx:
        line += f". Your context: {ctx[0]:.0f}% of {ctx[1] // 1000}k used"
    line += "."
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": name, "additionalContext": line}}))


if __name__ == "__main__":
    try:
        main()
    except Exception:  # noqa: BLE001 - never break the session
        pass
