# extract-text URL < page.html: the page's main text as markdown
import sys

import html2text
import trafilatura

html = sys.stdin.read()
text = trafilatura.extract(html, url=sys.argv[1], output_format="markdown", include_links=True)
print(text or html2text.html2text(html))
