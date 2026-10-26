---
name: web-research
description: How to read the web from torrent. Use when a site refuses you (a 403 or 429, a "Just a moment" or CAPTCHA page, a Cloudflare challenge), to follow what's new on a site through its feed, or to get a paper's full text.
---

# Reading the web from torrent

## web-fetch

`web-fetch URL` prints a page's main text as markdown. It tries curl with
browser headers, then curl-impersonate, then real Chromium through nodriver
in a virtual display, which waits out Cloudflare-style challenges.

- `--html` prints the raw page; `-o FILE` saves a PDF or other file.
- Save long pages to a file rather than printing them whole.
- `web-fetch --feed URL` prints an RSS or Atom feed's entries, dated and
  linked. Given a site's page, it finds the feed the page links to. For
  "what's new on this site", a feed is quicker than the pages and is rarely
  walled.
- It discards 4xx bodies. Some sites answer "no record" as a 404 with a
  page; when that matters, use curl-impersonate yourself and keep the body.
- Plain `curl` works on many docs sites (code.claude.com's `.md` URLs) where
  the browser tier is slower.

## Papers

The open routes are often quicker than the publisher: arXiv, Europe PMC,
and the Unpaywall, OpenAlex and Crossref APIs.

## The line

The owner authorizes getting past bot walls whenever you read for their
work, with any tool that does it (`nix shell` the ones you need). The line
is access control: don't get around paywalls or logins, don't use
CAPTCHA-solving services or proxy networks, and keep to the pace of a person
reading.

A wall `web-fetch` can't pass goes in `~/work/ENVIRONMENT.md` (date, agent,
URL, the error per tier, what you did instead). Known hard walls:
archive.today (429s), some Cloudflare "interactive" challenges
(FastPeopleSearch detail pages, Planet Minecraft, Fimfiction). The Wayback
Machine (`web.archive.org/web/<ts>id_/<url>`) is often the fallback; its
availability API (`archive.org/wayback/available`) 429s, so ask for
snapshot URLs directly.

Routes that work where the obvious one doesn't:

- **Reddit:** thread pages and `.json` are walled; append `.rss?limit=500`
  to the thread URL (`web-fetch --feed`, or `-o FILE` for the whole Atom).
  Images come from `i.redd.it/<id>.jpeg`.
- **Search engines:** Google search and Lens 429 or CAPTCHA from torrent's
  IP, and DuckDuckGo's HTML endpoint challenges. Google News RSS
  (`news.google.com/rss/search?q=...`) and Bing through plain curl work.
- **YouTube:** every client gets "Sign in to confirm you're not a bot",
  so captions and audio can't be fetched. Ask the owner for the file and
  transcribe it locally (the `local-ai` skill).
- **PubMed:** pages want cookies; use the E-utilities API
  (`eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi`).
- **PDFs:** WebFetch returns them as binary; save them with
  `web-fetch -o` and run `pdftotext`.
- **Tailscale:** the security bulletins page loads only its first entries;
  read `tailscale.com/changelog`.

## GitHub

`gh` is logged in as the agents' bot account. Its REST quota (5000 requests
an hour) is shared by every agent session, so for bulk reading prefer
`git clone --depth 1` or `raw.githubusercontent.com` over many `gh api` calls.
