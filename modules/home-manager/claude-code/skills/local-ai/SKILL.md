---
name: local-ai
description: Use when work should run on torrent's own GPU instead of a cloud model - private material, uncapped tokens, image reading, transcribing audio (with who said what) - or when calling, adding or downloading a local model.
---

# Local models on torrent

`llama-swap` serves local models at `http://127.0.0.1:8080` to every agent
and to the owner. It loads one model at a time, starting
it on the first request (about 10–60 s) and
killing it after 5 idle minutes.

## Models

`curl -s 127.0.0.1:8080/v1/models` lists them; `curl -s 127.0.0.1:8080/running`
shows what's loaded.

## Calling it

The same models answer two APIs:
- OpenAI chat: `/v1/chat/completions`
- OpenAI Responses: `/v1/responses`

Any API key works.

```sh
curl -s 127.0.0.1:8080/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"..."}]}'
```

## Transcription

`transcribe FILE` prints `[hh:mm:ss] speaker_N: text` lines. One
language per file: `-l auto` detects it once.

## Models on disk

`/srv/models/<model-id>/`, backed up to homelab. The
service's command lines (in the nixOS repo, `modules/nixos/local-ai.nix`)
name the exact files. To add a model:
1. Download it there (Hugging Face `resolve/main` URLs work).
2. Add a `models` entry in that module, by PR.

The store archives only what's in use: a model a service entry or command
names. Test candidates in `~/work/scratch`, or delete a tested model that
lost out, so it doesn't linger here (owner, 2026-10-23).

## Sharing the GPU

- While a game runs, gamemode switches llama-swap to its `gaming` profile:
  every model answers 404. Wait and retry later, and don't switch the
  profile back yourself.
- Before a big GPU job outside llama-swap, unload first:
  `curl -X POST 127.0.0.1:8080/api/models/unload`.
