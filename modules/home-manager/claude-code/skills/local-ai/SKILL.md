---
name: local-ai
description: Use when work should run on torrent's own GPU instead of a cloud model - private material, uncapped tokens, image reading, transcribing audio (with who said what) - or when calling, adding or downloading a local model, or running Claude Code or Codex against one.
---

# Local models on torrent

`llama-swap` serves local models at `http://127.0.0.1:8080` to every agent
and to the owner. It loads one model at a time on the RX 7900 XTX, starting
it on the first request (about 10–60 s) and
killing it after 5 idle minutes.

## Models

| `model` id | What | Notes |
|---|---|---|
| `qwen3.8-27b` | Qwen3.8-27B, fully on the GPU; reads images | The default. About 40 tok/s, 128K context |

`curl -s 127.0.0.1:8080/v1/models` lists them; `curl -s 127.0.0.1:8080/running`
shows what's loaded.

## Calling it

The same models answer three APIs:
- OpenAI chat: `/v1/chat/completions`
- OpenAI Responses: `/v1/responses`
- Anthropic Messages: `/v1/messages`

Any API key works.

```sh
curl -s 127.0.0.1:8080/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"..."}]}'
```

## Transcription

`transcribe FILE` prints `[hh:mm:ss] speaker_N: text` lines. Whisper
large-v3-turbo handles speech recognition in every supported language;
Nemotron optionally adds speaker labels. Use `--no-speakers` for a plain
timestamped transcript, `-l auto` to detect the language or `-l de`,
`-l ja`, etc. to select it. One language per file: `-l auto` detects it
once. `-o DIR` keeps the transcript and JSON. Any format ffmpeg reads,
video included.

Transcription uses the GPU directly, outside llama-swap, when no game runs
and VRAM is free, and falls back to the CPU otherwise. Audio models live
in `/home/agent/work/projects/local-ai/models/audio`; provisioning and
restore instructions are in the nixOS repo's
`docs/procedures/local-speech.md`.

## A whole agent on a local model

- **Claude Code:** `claude-local -p "<task>"`. It's on PATH and needs no
  Anthropic login. It tells the model it isn't Claude and sets the context
  window. It uses `qwen3.8-27b`.
- **Codex:** `codex exec -c model_provider=local
  -c 'model_providers.local.name="llama-server"'
  -c 'model_providers.local.base_url="http://127.0.0.1:8080/v1"'
  -c 'model_providers.local.wire_api="responses"' -m qwen3.8-27b "<task>"`.
- **Paseo** (the owner's front end) lists both as "Local in Claude Code" and
  "Local in Codex".

The local agent has the same access and tools and may do work like the
cloud agents. It is not their capability peer: do not use it for reviews,
alternative opinions or independent checks of another agent's work.

## Models on disk

`/srv/models/<model-id>/`, group `models`, backed up to homelab. The
service's command lines (in the nixOS repo, `modules/nixos/local-ai.nix`)
name the exact files. To add a model:
1. Download it there (Hugging Face `resolve/main` URLs work).
2. Add a `models` entry in that module, by PR.

Keep llama-swap model downloads in `/srv/models`, not `~/work`, to avoid
duplicate backups. The audio models above use their existing project path.

The store archives only what's in use: a model a service entry or command
names. Test candidates in `~/work/scratch`, or delete a tested model that
lost out, so it doesn't linger here (owner, 2026-10-23).

## Sharing the GPU

The owner's desktop and games come first.
- While a game runs, gamemode switches llama-swap to its `gaming` profile:
  every model answers 404. Wait and retry later, and don't switch the
  profile back yourself.
- One request at a time keeps the desktop smooth. Avoid parallel calls.
- Before a big GPU job outside llama-swap, check
  `/sys/bus/pci/devices/0000:03:00.0/mem_info_vram_used`, and unload first:
  `curl -X POST 127.0.0.1:8080/api/models/unload`.
