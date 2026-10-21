# browser-fetch URL CHROMIUM: load URL in Chromium through nodriver, wait
# out a JavaScript challenge, and print the final HTML; exits 1 when no
# page loaded or the one that did is an HTTP error
import asyncio
import sys
import tempfile

import nodriver as uc

CHALLENGE = (
    "just a moment",
    "attention required",
    "please wait",
    "verifying",
    "temporarily unavailable",
)


async def main(url):
    # Chromium may still be writing the profile as it exits
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as profile:
        browser = await uc.start(
            browser_executable_path=sys.argv[2],
            headless=False,
            # Chromium's own sandbox: it runs untrusted pages, and the agent's
            # logins are in its home
            sandbox=True,
            user_data_dir=profile,
        )
        try:
            # nodriver waits on Chromium without timeouts: bound the whole
            # session so a stuck page can't hang an unattended job
            await asyncio.wait_for(fetch(browser, url), 150)
        except asyncio.TimeoutError:
            print("browser-fetch: timed out", file=sys.stderr)
            sys.exit(1)
        finally:
            browser.stop()


async def fetch(browser, url):
    tab = await browser.get(url)
    # Cloudflare's challenge can take 40s or more
    for _ in range(45):
        await tab.sleep(2)
        title = (await tab.evaluate("document.title")) or ""
        ready = await tab.evaluate("document.readyState")
        text = await tab.evaluate("document.body ? document.body.innerText.length : 0")
        # an empty title is the challenge redirecting, and a page can
        # be titled before its body arrives
        if (
            title
            and ready == "complete"
            and (text or 0) > 200
            and not any(c in title.lower() for c in CHALLENGE)
        ):
            break
    # out of time on a challenge, untitled, or still loading: not the
    # page (a real but short page still passes)
    if not title or ready != "complete" or any(c in title.lower() for c in CHALLENGE):
        print(f"browser-fetch: unresolved ({title!r}, {ready})", file=sys.stderr)
        sys.exit(1)
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


uc.loop().run_until_complete(main(sys.argv[1]))
