# browser-fetch URL CHROMIUM XDOTOOL [file]: load URL in Chromium through
# nodriver, get past a Cloudflare checkbox if there is one, and print the final
# HTML; exits 1 when no page loaded or the one that did is an HTTP error. With
# "file", loads the URL's site instead and prints the URL's raw bytes.
import asyncio
import base64
import fcntl
import glob
import json
import os
import re
import signal
import subprocess
import sys
import time

import nodriver as uc

# keep in step with web-fetch.sh's blocked()
CHALLENGE = re.compile(
    r"just a moment|attention required|please wait|verifying( you|\.\.\.|…)"
    r"|temporarily unavailable|prove your humanity|making sure you.{0,8}not a bot"
    r"|client challenge|checking your browser|checking if the site",
    re.IGNORECASE,
)
CHROMIUM, XDOTOOL = sys.argv[2], sys.argv[3]
FILE_URL = sys.argv[1] if sys.argv[4:] == ["file"] else None
STATE = os.path.expanduser("~/.cache/web-fetch")
PROFILE = f"{STATE}/profile"
# the virtual display is 1920x1080 (web-fetch.sh), and a screen smaller than
# its window gives a browser away
WINDOW = [
    "--window-size=1920,1080",
    "--window-position=0,0",
    "--force-device-scale-factor=1",
    "--disk-cache-size=52428800",
]
# where Turnstile's widget sits, in the page
WIDGET = """JSON.stringify((() => {
  const i = document.querySelector('input[name="cf-turnstile-response"], #challenge-stage');
  if (!i) return null;
  const n = i.tagName == 'INPUT' ? i.parentElement : i;
  const r = n.getBoundingClientRect();
  return {x: r.x, y: r.y, h: r.height, top: outerHeight - innerHeight};
})())"""


# a download starts no page of its own to read, so ask from inside the site
DOWNLOAD = """(async () => {
  const r = await fetch(%s, {credentials: 'include'});
  if (!r.ok) return 'HTTP ' + r.status;
  // a download that lands on a page is a login or an error, not the file
  if (r.redirected && (r.headers.get('content-type') || '').includes('html'))
    return 'redirected to a page: ' + r.url;
  const bytes = new Uint8Array(await r.arrayBuffer());
  let text = '';
  for (let i = 0; i < bytes.length; i += 32768)
    text += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
  return 'OK' + btoa(text);
})()"""


def lock():
    # one browser at a time on the one profile, which also keeps every agent
    # together to the pace of one reader; a stuck holder mustn't hang the rest
    handle = open(f"{STATE}/lock", "w")
    deadline = time.monotonic() + 180
    while True:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return handle
        except BlockingIOError:
            if time.monotonic() > deadline:
                print("browser-fetch: busy for 180s", file=sys.stderr)
                sys.exit(1)
            time.sleep(1)


def running(pid):
    try:
        with open(f"/proc/{pid}/stat") as stat:
            return stat.read().rsplit(")", 1)[1].split()[0] != "Z"
    except FileNotFoundError:
        return False


def end(pid):
    # the lock may only pass on once Chromium has let go of the profile
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            return
        deadline = time.monotonic() + 10
        while running(pid) and time.monotonic() < deadline:
            time.sleep(0.1)
        if not running(pid):
            return


def free_profile():
    # a Chromium outlives a browser-fetch that was killed: its link says which
    # one, and holding the lock means nothing else should be using the profile
    try:
        pid = int(os.readlink(f"{PROFILE}/SingletonLock").rsplit("-", 1)[1])
    except (OSError, ValueError, IndexError):
        pid = None
    if pid and running(pid):
        with open(f"/proc/{pid}/cmdline", "rb") as cmdline:
            if f"--user-data-dir={PROFILE}".encode() in cmdline.read():
                end(pid)
    for stale in glob.glob(f"{PROFILE}/Singleton*"):
        os.unlink(stale)


def window_title():
    found = subprocess.run(
        [XDOTOOL, "search", "--name", "."], capture_output=True, text=True
    ).stdout.split()
    for window in found:
        name = subprocess.run(
            [XDOTOOL, "getwindowname", window], capture_output=True, text=True
        ).stdout.strip()
        if name.endswith("Chromium"):
            return name
    return ""


def clear_checkbox(url, widget):
    # Cloudflare rejects the checkbox under nodriver, even with a real click;
    # its debugging connection is the suspect, not proven. So this visit is a
    # plain Chromium and X input only. Its
    # clearance cookie stays in the profile for nodriver's visit afterwards.
    x = round(widget["x"] + 21)
    y = round(widget["top"] + widget["y"] + widget["h"] / 2)
    browser = subprocess.Popen(
        [CHROMIUM, f"--user-data-dir={PROFILE}", "--no-first-run", *WINDOW, url],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(12)
        for _ in range(2):
            if not CHALLENGE.search(window_title()):
                break
            for at, pause in (((x - 200, y + 90), 0.4), ((x - 40, y + 12), 0.3), ((x, y), 0.4)):
                subprocess.run([XDOTOOL, "mousemove", str(at[0]), str(at[1])])
                time.sleep(pause)
            subprocess.run([XDOTOOL, "click", "1"])
            time.sleep(15)
    finally:
        end(browser.pid)
        browser.wait()


async def main(url):
    os.makedirs(STATE, exist_ok=True)
    held = lock()
    free_profile()
    try:
        # nodriver waits on Chromium without timeouts: bound the whole session
        # so a stuck page can't hang an unattended job
        widget = await asyncio.wait_for(visit(url, wait_out=False), 100)
        # no checkbox: that visit has already printed the page
        if widget:
            clear_checkbox(url, widget)
            await asyncio.wait_for(visit(url, wait_out=True), 100)
    except asyncio.TimeoutError:
        print("browser-fetch: timed out", file=sys.stderr)
        sys.exit(1)
    finally:
        held.close()


async def visit(url, wait_out):
    browser = await uc.start(
        browser_executable_path=CHROMIUM,
        headless=False,
        # Chromium's own sandbox: it runs untrusted pages, and the agent's
        # logins are in its home
        sandbox=True,
        user_data_dir=PROFILE,
        browser_args=WINDOW,
    )
    try:
        return await fetch(browser, url, wait_out)
    finally:
        # nodriver's stop() returns before Chromium has exited
        end(browser._process_pid)


async def fetch(browser, url, wait_out):
    tab = await browser.get(url)
    text = 0
    # Cloudflare's challenge can take 40s or more
    for i in range(40):
        await tab.sleep(2)
        title = (await tab.evaluate("document.title")) or ""
        ready = await tab.evaluate("document.readyState")
        before, text = text, await tab.evaluate(
            "document.body ? document.body.innerText.length : 0"
        ) or 0
        # a page whose ads never finish still counts once its text has settled
        loaded = ready == "complete" or (ready == "interactive" and text > 2000 and text == before)
        # an empty title is the challenge redirecting, and a page can
        # be titled before its body arrives
        if title and loaded and text > 200 and not CHALLENGE.search(title):
            break
        # first visit: a checkbox that's still there after 10s needs clicking
        if not wait_out and i == 5 and CHALLENGE.search(title):
            raw = await tab.evaluate(WIDGET)
            widget = json.loads(raw) if raw and raw != "null" else None
            if widget:
                return widget
    # out of time on a challenge, untitled, or still loading: not the
    # page (a real but short page still passes)
    if not title or not loaded or CHALLENGE.search(title):
        print(f"browser-fetch: unresolved ({title!r}, {ready})", file=sys.stderr)
        sys.exit(1)
    if FILE_URL:
        return await download(tab)
    # the status of the document that finally loaded, after any
    # challenge's redirect
    status = await tab.evaluate(
        "(performance.getEntriesByType('navigation')[0] || {}).responseStatus || 0"
    )
    # 0 means no response at all: DNS, connection or TLS failure, and
    # the HTML is Chromium's own error page
    if not status or status >= 400:
        print(f"browser-fetch: HTTP {status or 'none'}", file=sys.stderr)
        sys.exit(1)
    print(await tab.get_content())
    return None


async def download(tab):
    answer = await tab.evaluate(DOWNLOAD % json.dumps(FILE_URL), await_promise=True)
    if not (isinstance(answer, str) and answer.startswith("OK")):
        print(f"browser-fetch: {str(answer)[:100]}", file=sys.stderr)
        sys.exit(1)
    sys.stdout.buffer.write(base64.b64decode(answer[2:]))
    return None


target = sys.argv[1]
if FILE_URL:
    target = re.match(r"https?://[^/?#]+", FILE_URL).group(0) + "/"
uc.loop().run_until_complete(main(target))
