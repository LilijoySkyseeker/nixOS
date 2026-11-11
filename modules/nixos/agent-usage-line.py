"""Hook for Claude Code and Codex: tell the model its plan limits and context.

Reads the hook event on stdin and prints hookSpecificOutput.additionalContext:
- UserPromptSubmit: always one line.
- PostToolUse: a line only when a figure has crossed 50, 75 or 90% since the
  last line in this session.

Sources:
- Claude limits: Claude Code's get_usage control request (no model call),
  cached for every agent, since they share one account.
- Codex limits: `codex app-server`'s account/rateLimits/read (no model
  call), cached like Claude's; if that fails, the newest token_count record
  in Codex's session files, which is only as fresh as the last Codex turn.
- Codex context: the token_count records in its own session file. Claude's
  own context comes from Claude Code itself
  (CLAUDE_CODE_ENABLE_TOKEN_USAGE_ATTACHMENT), not from here.

Any failure prints nothing: a hook must never break a session.
"""

import fcntl
import json
import os
import pwd
import select
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

INNER = "AGENT_USAGE_LINE_INNER"
BANDS = (50, 75, 90)
TTL = 300
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
        capture_output=True, text=True, timeout=10, env=env,
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


def fetch_codex():
    """Codex's windows from its app-server; it must keep stdin open until it
    answers (closed early, it exits without replying). Raw reads on the pipe,
    so the deadline bounds every wait and no reply sits unseen in a buffer."""
    reqs = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"clientInfo": {"name": "agent-usage-line", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read"},
    ]
    p = subprocess.Popen(["codex", "app-server"], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        p.stdin.write("".join(json.dumps(r) + "\n" for r in reqs).encode())
        p.stdin.flush()
        fd = p.stdout.fileno()
        buf = b""
        deadline = time.time() + 10
        while True:
            *lines, buf = buf.split(b"\n")
            for line in lines:
                windows = codex_reply(line)
                if windows is not False:
                    return windows
            left = deadline - time.time()
            if left <= 0 or not select.select([fd], [], [], left)[0]:
                return None
            chunk = os.read(fd, 65536)
            if not chunk:
                return None
            buf += chunk
    finally:
        p.kill()
        p.wait()


def codex_reply(line):
    """The windows in app-server's rateLimits reply (None if it has none),
    or False for any other line."""
    try:
        d = json.loads(line)
    except ValueError:
        return False
    if not isinstance(d, dict) or d.get("id") != 2:
        return False
    rl = (d.get("result") or {}).get("rateLimits") or {}
    windows = []
    for key, name in (("primary", "5h"), ("secondary", "week")):
        w = rl.get(key)
        if w and w.get("usedPercent") is not None and w.get("resetsAt"):
            windows.append((name, w["usedPercent"], w["resetsAt"]))
    return windows or None


def cached(family, fetch):
    """A family's cached windows and when they were read; one agent refreshes
    while the rest read, and a failed refresh waits a full TTL too."""
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / f"{family}.json"
    try:
        entry = json.loads(path.read_text())
    except (OSError, ValueError):
        entry = {"tried": 0, "at": 0, "windows": []}
    if time.time() - entry["tried"] < TTL:
        return entry["windows"], entry["at"]
    with open(CACHE / f"{family}.lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return entry["windows"], entry["at"]
        entry["tried"] = time.time()
        try:
            windows = fetch()
        except (OSError, subprocess.SubprocessError, ValueError, KeyError):
            windows = None
        if windows is not None:
            entry.update(at=entry["tried"], windows=windows)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(entry))
        tmp.replace(path)
        return entry["windows"], entry["at"]


def last_token_count(path, need_limits=False):
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
        if p.get("type") == "token_count" and (
                not need_limits or codex_limits(p)):
            return p
    return None


def newest_codex_limits():
    """Codex windows from the most recently written session file that has
    them, across the last week of session folders (any session counts:
    the account is shared)."""
    days = sorted(CODEX_SESSIONS.glob("*/*/*"), reverse=True)[:8]
    files = [f for d in days for f in d.glob("rollout-*.jsonl")]
    files.sort(key=lambda f: f.stat().st_mtime, reverse=True)
    for f in files[:20]:
        tc = last_token_count(f, need_limits=True)
        if tc:
            return codex_limits(tc), f.stat().st_mtime
    return [], 0


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


def fmt_windows(family, windows, read_at):
    now = time.time()
    parts = []
    for name, pct, reset in windows:
        if reset <= now:
            # read before the reset: says nothing about the new window
            parts.append(f"{name} unknown (reset {when(reset)})")
        else:
            parts.append(f"{name} {pct:.0f}% (resets {when(reset)})")
    if not parts:
        return None
    text = f"{family} " + ", ".join(parts)
    if now - read_at > 3 * TTL:
        text += f" [as of {when(read_at)}]"
    return text


def main():
    # Codex's managed hooks are system-wide; only the agents get the line
    if os.environ.get(INNER) or pwd.getpwuid(os.geteuid()).pw_name != "agent":
        return
    event = json.load(sys.stdin)
    name = event.get("hook_event_name", "")
    if name not in ("UserPromptSubmit", "PostToolUse"):
        return
    transcript = event.get("transcript_path") or ""
    is_codex = "/.codex/" in transcript

    ctx = None
    if is_codex:
        try:
            ctx = codex_context(last_token_count(transcript))
        except OSError:
            pass
    # the live read, unless a Codex turn has recorded newer figures since
    codex, codex_at = cached("codex", fetch_codex)
    try:
        logged, logged_at = newest_codex_limits()
    except OSError:
        logged, logged_at = [], 0
    if logged and logged_at > codex_at:
        codex, codex_at = logged, logged_at
    claude, claude_at = cached("claude", fetch_claude)

    # one threshold band per figure; a window's reset time is part of its
    # key, so a reset starts it again
    now = time.time()
    bands = {f"claude {n} {r}": band(p) for n, p, r in claude if r > now}
    bands.update({f"codex {n} {r}": band(p) for n, p, r in codex if r > now})
    if ctx:
        bands["context"] = band(ctx[0])
    state = CACHE / "sessions" / (event.get("session_id") or "none")
    try:
        seen = json.loads(state.read_text())
    except (OSError, ValueError):
        seen = {}
    crossed = any(b > seen.get(k, 0) for k, b in bands.items())
    if name == "PostToolUse" and not crossed:
        return
    state.parent.mkdir(parents=True, exist_ok=True)
    state.write_text(json.dumps(bands))

    parts = [fmt_windows("Claude", claude, claude_at),
             fmt_windows("Codex", codex, codex_at)]
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
