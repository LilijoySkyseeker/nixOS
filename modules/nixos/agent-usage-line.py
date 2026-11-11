"""UserPromptSubmit hook for Claude Code and Codex: pass the model its plan
limits (and Codex's context) as hookSpecificOutput.additionalContext.

- Claude limits: Claude Code's get_usage control request (no model call).
- Codex limits: `codex app-server`'s account/rateLimits/read (no model call).
- Both cached for 5 minutes, shared by every agent (one account each).
- Codex context: the last token_count record in its own session file.
  Claude's comes from Claude Code itself (CLAUDE_CODE_ENABLE_TOKEN_USAGE_ATTACHMENT).

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
TTL = 300
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
CACHE = CACHE / "agent-usage-line"


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
    """Codex's windows from its app-server, which exits without answering if
    stdin closes first. Raw reads, so the deadline bounds every wait."""
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
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if isinstance(d, dict) and d.get("id") == 2:
                    rl = (d.get("result") or {}).get("rateLimits") or {}
                    windows = []
                    for key, name in (("primary", "5h"), ("secondary", "week")):
                        w = rl.get(key)
                        if w and w.get("usedPercent") is not None and w.get("resetsAt"):
                            windows.append((name, w["usedPercent"], w["resetsAt"]))
                    return windows or None
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


def codex_context(path):
    """Context used, from the last token_count record in a Codex session file."""
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        f.seek(max(0, f.tell() - 1_000_000))
        tail = f.read().decode("utf-8", "replace")
    for line in reversed(tail.splitlines()):
        if '"token_count"' not in line:
            continue
        try:
            info = (json.loads(line).get("payload") or {}).get("info") or {}
        except ValueError:
            continue
        last, window = info.get("last_token_usage"), info.get("model_context_window")
        if last and window:
            used = last.get("input_tokens", 0) + last.get("output_tokens", 0)
            return 100 * used / window, window
    return None


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
    if event.get("hook_event_name") != "UserPromptSubmit":
        return
    transcript = event.get("transcript_path") or ""

    ctx = None
    if "/.codex/" in transcript:
        try:
            ctx = codex_context(transcript)
        except OSError:
            pass
    parts = [fmt_windows("Claude", *cached("claude", fetch_claude)),
             fmt_windows("Codex", *cached("codex", fetch_codex))]
    line = "Plan usage, shared by every agent on the account: "
    line += "; ".join(p for p in parts if p) or "unknown"
    if ctx:
        line += f". Your context: {ctx[0]:.0f}% of {ctx[1] // 1000}k used"
    line += "."
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit", "additionalContext": line}}))


if __name__ == "__main__":
    try:
        main()
    except Exception:  # noqa: BLE001 - never break the session
        pass
