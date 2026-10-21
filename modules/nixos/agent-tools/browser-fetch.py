# browser-fetch URL: load URL in Chromium through nodriver, wait out a
# JavaScript challenge, and print the final HTML
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
            sandbox=False,
            user_data_dir=profile,
        )
        try:
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
            print(await tab.get_content())
        finally:
            browser.stop()


uc.loop().run_until_complete(main(sys.argv[1]))
