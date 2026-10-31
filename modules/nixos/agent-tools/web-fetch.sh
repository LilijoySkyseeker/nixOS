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
body=$(mktemp) status=$(mktemp)
trap 'rm -f "$body" "$status"' EXIT
ua='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'

# a wall: an error status, or a challenge page served with 200
# (keep the phrases in step with browser-fetch.py's CHALLENGE)
blocked() {
  case $1 in 2??) ;; *) return 0 ;; esac
  grep -qiE '<title>[^<]*(just a moment|attention required|access denied|please wait|verifying|are you a robot|temporarily unavailable|prove your humanity|not a bot|client challenge|checking (you|your))' "$body"
}
# the site's own origin as Referer: some serve PDFs only to their own pages
referer=$(printf '%s' "$url" | grep -oE '^https?://[^/]+')/

# prints "STATUS TYPE"; 000 when the connection failed
fetch() {
  "$@" -sL --compressed --max-time 30 -o "$body" -e "$referer" \
    -w '%{http_code} %{content_type}\n' "$url" || echo 000
}
read -r code type < <(fetch curl -A "$ua" \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
  -H 'Accept-Language: en-US,en;q=0.9')
tier=curl
if blocked "$code"; then
  read -r code type < <(fetch curl_chrome150)
  tier=curl-impersonate
fi
# a PDF, JSON or plain-text answer is the thing itself, not a page to render
is_page() {
  case ${type:-} in '' | *html* | *xml*) return 0 ;; esac
  return 1
}
# a page that builds itself in JavaScript arrives untitled or near-empty
shell_only() {
  [ "$mode" = file ] || [ "$mode" = feed ] && return 1
  is_page || return 1
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
  # at a desktop's size, not xvfb-run's default 640x480; browser-fetch's
  # own exit status, since xvfb-run's can fail in its cleanup after a good page
  # shellcheck disable=SC2016 # expanded by the inner sh
  timeout --kill-after=10 170 xvfb-run -a -s '-screen 0 1920x1080x24' \
    sh -c 'browser-fetch "$1"; echo $? > "$2"' sh "$url" "$status" > "$body" || true
  [ "$(cat "$status")" = 0 ] || code=000
  type=text/html
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
text)
  if is_page; then
    extract-text "$url" < "$body"
  else
    case $type in
    *pdf*) pdftotext -layout "$body" - ;;
    *) cat "$body" ;;
    esac
  fi
  ;;
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
