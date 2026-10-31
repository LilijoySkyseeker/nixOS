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

## Transcription

`transcribe FILE`. One
language per file: `-l auto` detects it once.

## Models on disk

`/srv/models/<model-id>/`. The
service's command lines (in the nixOS repo, `modules/nixos/local-ai.nix`)
name the exact files. To add a model:
1. Download it there.
2. Add a `models` entry in that module.

The store archives only what's in use: a model a service entry or command
names. Test candidates in `~/work/scratch`, or delete a tested model that
lost out, so it doesn't linger here (owner, 2026-10-23).
