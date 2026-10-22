# read-feed URL < body: an RSS or Atom feed's entries as markdown, newest
# first as the feed lists them; when the body is an HTML page instead,
# prints the feed it links to and exits 3
import re
import sys
import time
from html.parser import HTMLParser
from urllib.parse import urljoin

import feedparser
import html2text

FEED_TYPES = ("application/rss+xml", "application/atom+xml", "application/feed+json")


class FeedLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if (
            tag == "link"
            and "alternate" in (a.get("rel") or "").lower().split()
            and (a.get("type") or "").lower() in FEED_TYPES
            and a.get("href")
        ):
            self.links.append(a["href"])


def text(html, limit=500):
    t = html2text.HTML2Text(bodywidth=0)
    t.ignore_images = True
    s = re.sub(r"\s+", " ", t.handle(html)).strip()
    return s if len(s) <= limit else s[:limit].rsplit(" ", 1)[0] + " …"


url = sys.argv[1]
body = sys.stdin.buffer.read()
feed = feedparser.parse(body)
if not feed.entries:
    finder = FeedLinks()
    finder.feed(body.decode("utf-8", "replace"))
    if finder.links:
        print(urljoin(url, finder.links[0]))
        sys.exit(3)
    print(f"read-feed: no feed entries at {url}", file=sys.stderr)
    sys.exit(1)
print(f"# {feed.feed.get('title', url)}\n")
for e in feed.entries:
    when = e.get("published_parsed") or e.get("updated_parsed")
    date = time.strftime("%Y-%m-%d %H:%M UTC", when) if when else "undated"
    print(f"- **{date}** [{e.get('title', '(untitled)')}]({e.get('link', '')})")
    if e.get("summary"):
        print(f"  {text(e.summary)}")
