---
name: local-ai
description: Use when work should run on torrent's own GPU instead of a cloud model - private material, uncapped tokens, a third opinion, OCR of scans or PDFs - or when calling, adding or downloading a local model, or running Claude Code or Codex against one.
---

# Local models on torrent

`llama-swap` serves local models at `http://127.0.0.1:8080` to every agent
and to the owner. It loads one model at a time on the RX 7900 XTX, starting
it on the first request (about 10–60 s; Flash-Next takes minutes) and
killing it after 5 idle minutes.

## Models

| `model` id | What | Notes |
|---|---|---|
| `qwen3.8-27b` | Qwen3.8-27B, fully on the GPU; reads images | The default. About 40 tok/s, 128K context |
| `qwen3.8-flash-next` | 125B MoE, most experts in system RAM | Stronger and slower: about 16 tok/s, prompts about 680 tok/s, 131k context. Up to about 50 GB of RAM; the first load reads it from disk (about 4–5 min). For private deep work; not while the owner games |
| `paddleocr-vl` | PaddleOCR-VL-1.6 | A page image in, markdown out |

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

**OCR:** render each page (`pdftoppm -r 200 -png in.pdf page`), then send it
as a base64 `image_url` with the text `OCR:` to `paddleocr-vl`, one page per
request.

## A whole agent on a local model

- **Claude Code:** `claude-local -p "<task>"`. It's on PATH and needs no
  Anthropic login. It tells the model it isn't Claude and sets the context
  window. Pick the model with `--model qwen3.8-flash-next`.
- **Codex:** `codex exec -c model_provider=local
  -c 'model_providers.local.name="llama-server"'
  -c 'model_providers.local.base_url="http://127.0.0.1:8080/v1"'
  -c 'model_providers.local.wire_api="responses"' -m qwen3.8-27b "<task>"`.
- **Paseo** (the owner's front end) lists both as "Local in Claude Code" and
  "Local in Codex".

These local models are another model family, so they count as a third
opinion next to Claude and Codex.

## Models on disk

`/srv/models/<model-id>/`, group `models`, backed up to homelab. The
service's command lines (in the nixOS repo, `modules/nixos/local-ai.nix`)
name the exact files. To add a model:
1. Download it there (Hugging Face `resolve/main` URLs work).
2. Add a `models` entry in that module, by PR.

Don't download models into `~/work`: it's backed up too, so every model would be stored twice.

## Sharing the GPU

The owner's desktop and games come first.
- While a game runs, gamemode switches llama-swap to its `gaming` profile:
  every model answers 404. Wait and retry later, and don't switch the
  profile back yourself.
- One request at a time keeps the desktop smooth. Avoid parallel calls.
- Before a big GPU job outside llama-swap, check
  `/sys/bus/pci/devices/0000:03:00.0/mem_info_vram_used`, and unload first:
  `curl -X POST 127.0.0.1:8080/api/models/unload`.
