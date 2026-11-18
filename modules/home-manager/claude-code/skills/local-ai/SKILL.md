---
name: local-ai
description: Use when work should run on torrent's own GPU instead of a cloud model - private material, uncapped tokens, image reading, transcribing audio (with who said what) - or when calling, adding or downloading a local model.
---

# Local models on torrent

## Calling it

```sh
curl -s 127.0.0.1:8080/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"..."}]}'
```

It thinks first, at medium effort (the server's default). For a quick
answer, add `"chat_template_kwargs":{"enable_thinking":false}` with Qwen's
non-thinking sampling: `"temperature":0.7,"top_p":0.8,"presence_penalty":1.5`.
Context is 64K tokens. Send images as PNG or JPEG.

As an agent: Paseo's `local-pi` provider (`paseo run --provider local-pi`).

## Transcription

`transcribe FILE`. One
language per file: `-l auto` detects it once.
Each line is one speaker's spoken paragraph, broken where they pause.
`-f json` gives the same lines with every word's start and end, for
tools that line text up with the audio. `--sounds` adds non-speech
sounds (laughter, music, rain, effects): an AudioSet classifier's
guesses, unreliable (it missed dice and called a combat effect a cat),
about 3× slower.

## Models on disk

`/srv/models/<model-id>/`. The
service's command lines (in the nixOS repo, `modules/nixos/local-ai.nix`)
name the exact files. To add a model:
1. Download it there, from your session: agent-task units can't write
   `/srv/models`.
2. Add a `models` entry in that module.

The store archives only what's in use: a model a service entry or command
names. Test candidates in `~/work/scratch`, or delete a tested model that
lost out, so it doesn't linger here (owner, 2026-10-23).
