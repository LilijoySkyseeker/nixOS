# openrouter-curl <url> [curl args...]: curl with the owner's OpenRouter key as
# a header file, so the key is never in an argument or the caller's output
key=$HOME/.config/openrouter/key
[ -s "$key" ] || {
  echo "openrouter-curl: no key at $key; the owner adds one with: run0 agent-setup" >&2
  exit 1
}
exec curl -sS -H @<(printf 'Authorization: Bearer %s\n' "$(cat "$key")") -H 'Content-Type: application/json' "$@"
