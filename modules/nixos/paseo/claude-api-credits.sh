#!/usr/bin/env bash
# Read the key only in the launched process; never put it in Paseo's config.
set -eu
claude_binary=$1
claude_credit_key_file=$2
shift 2

# Provider discovery must work before the owner provisions the key.
if [ "${1:-}" = --version ]; then
  exec "$claude_binary" "$@"
fi

if [ ! -r "$claude_credit_key_file" ] || [ ! -s "$claude_credit_key_file" ]; then
  echo 'Claude API credits key is missing or unreadable; refusing to use subscription credentials.' >&2
  exit 1
fi
ANTHROPIC_API_KEY="$(cat "$claude_credit_key_file")"
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo 'Claude API credits key is empty; refusing to use subscription credentials.' >&2
  exit 1
fi
export ANTHROPIC_API_KEY
# These outrank the API key or select an endpoint outside the included credit.
unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_CUSTOM_HEADERS
unset CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
unset CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR
exec "$claude_binary" "$@"
