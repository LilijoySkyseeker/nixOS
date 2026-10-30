# web-fetch: get a page past bot walls, cheapest way first.
# 1. curl with browser headers; 2. curl-impersonate (Chrome's TLS
# fingerprint); 3. real Chromium driven by nodriver in a virtual display,
# which waits out JavaScript challenges such as Cloudflare's.
usage() {
  echo "usage: web-fetch [--html | --feed | -o FILE] URL" >&2
  echo "  default: the page's main text as markdown; --html: the raw HTML;" >&2
  echo "  --feed: an RSS or Atom feed's entries, or the feed a page links to;" >&2
  echo "  -o FILE: the raw body to FILE (PDFs and other files)" >&2
  exit 2
}
mode="text" out=""
while [ $# -gt 1 ]; do
  case $1 in
  --html) mode="html" ;;
  --feed) mode="feed" ;;
  -o)
    out=$2
    mode="file"
    shift
    ;;
  *) usage ;;
  esac
  shift
done
[ $# -eq 1 ] || usage
# a lone flag (--help, -h, or --feed with no URL) isn't a URL
case $1 in -*) usage ;; esac
url=$1
body=$(mktemp)
trap 'rm -f "$body"' EXIT
ua='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'

# a wall: an error status, or a challenge page served with 200
blocked() {
  case $1 in 2??) ;; *) return 0 ;; esac
  grep -qiE '<title>[^<]*(just a moment|attention required|access denied|please wait|verifying you are human|are you a robot|temporarily unavailable)' "$body"
}

code=$(curl -sL --compressed --max-time 30 -o "$body" -w '%{http_code}' -A "$ua" \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
  -H 'Accept-Language: en-US,en;q=0.9' "$url") || code=000
tier=curl
if blocked "$code"; then
  code=$(curl_chrome150 -sL --compressed --max-time 30 -o "$body" -w '%{http_code}' "$url") || code=000
  tier=curl-impersonate
fi
# a page that builds itself in JavaScript arrives untitled or near-empty
shell_only() {
  [ "$mode" = file ] || [ "$mode" = feed ] && return 1
  ! grep -qiE '<title>[^<]+' "$body" && return 0
  [ "$(extract-text "$url" < "$body" | wc -c)" -lt 300 ]
}
if blocked "$code" || shell_only; then
  # file downloads and feeds stay on the curl tiers: Chromium shows XML
  # as a page of its own
  case $mode in file | feed)
    echo "web-fetch: blocked ($code) at $tier" >&2
    exit 1
    ;;
  esac
  code=200
  # backstop for the browser's own 150s limit
  timeout --kill-after=10 170 xvfb-run -a browser-fetch "$url" > "$body" || code=000
  tier=browser
fi
if blocked "$code"; then
  echo "web-fetch: blocked or failed after every tier (last: $tier, $code)" >&2
  exit 1
fi
echo "web-fetch: $tier" >&2
case $mode in
file) cp "$body" "$out" ;;
html) cat "$body" ;;
text) extract-text "$url" < "$body" ;;
feed)
  # a page rather than a feed: follow the feed it links to, once
  if entries=$(read-feed "$url" < "$body"); then
    printf '%s\n' "$entries"
  elif [ $? -eq 3 ] && [ -z "${WEB_FETCH_FOLLOWED:-}" ]; then
    echo "web-fetch: following $entries" >&2
    WEB_FETCH_FOLLOWED=1 exec "$0" --feed "$entries"
  else
    exit 1
  fi
  ;;
esac
