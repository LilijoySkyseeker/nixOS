---
name: media-generation
description: Generate images, video or music with cloud models through the owner's OpenRouter key (GPT Image, Nano Banana, FLUX, Seedream; Veo, Kling, Seedance, Runway; Lyria). Use when a project needs a generated image, illustration, icon, video clip or piece of music, or when asked which media models exist and what they cost. Not for editing media locally or for speech.
---

# Media generation through OpenRouter

Call OpenRouter with `openrouter-curl <url> [curl args...]`. It is curl
with the owner's OpenRouter key added as a header, read from
`~/.config/openrouter/key`, so the key never appears in a command or your
output; don't read or print the file yourself. If it says there's no key,
the owner adds one with `run0 agent-setup`.

The key pays for every call, up to the credit limit the owner set on it.
Before generating video or a batch, work out the cost from the model's
listed price, and put the cost of what you generated in your reply.

Save outputs in the project's own folder, not in `scratch/`, and give the
owner the path under `~/Agent`.

## Pick a model

These lists need no key. Each entry carries its price and supported
parameters:

```bash
curl -s https://openrouter.ai/api/v1/images/models | jq -r '.data[].id'
curl -s https://openrouter.ai/api/v1/videos/models | jq -c '.data[] | {id, pricing}'
curl -s 'https://openrouter.ai/api/v1/models?output_modalities=audio' | jq -r '.data[] | "\(.id): \(.description[:80])"'
```

## Images

`POST /api/v1/images` takes:

- `model` and `prompt` (required);
- optionally `n`, `aspect_ratio` (`16:9`, `auto`), `resolution` (`1K`, `2K`) or `size` (`2048x2048`);
- optionally `input_references`, a list of `{"type": "image_url", "image_url": {"url": ...}}`, where the URL can be an HTTPS URL or a base64 data URL.

Each result in `data[]` holds `b64_json` and `media_type`, and `usage.cost` is in dollars.

```bash
openrouter-curl https://openrouter.ai/api/v1/images \
  -d '{"model": "google/gemini-nano-banana-2.1", "prompt": "...", "aspect_ratio": "16:9"}' > /tmp/img.json
jq -r '.data[0].b64_json' /tmp/img.json | base64 -d > out.png
jq '.usage.cost' /tmp/img.json
```

## Video

The video API is asynchronous.

1. **Submit** with `POST /api/v1/videos`. It takes `model` and `prompt`, plus `duration` (seconds), `resolution`, `aspect_ratio` and `generate_audio`, each within the model's `supported_*` lists. Add `frame_images` (`frame_type` `first_frame` or `last_frame`) to turn an image into video. The answer is a job `id` with a `polling_url`.
2. **Poll** every 30 seconds until `status` is `completed` or `failed`.
3. **Download** from `/api/v1/videos/<id>/content?index=0`, with the key.

```bash
job=$(openrouter-curl https://openrouter.ai/api/v1/videos \
  -d '{"model": "google/veo-3.1-lite", "prompt": "...", "duration": 8, "aspect_ratio": "16:9"}' | jq -r .id)
openrouter-curl "https://openrouter.ai/api/v1/videos/$job" | jq '{status, error, cost: .usage.cost}'
openrouter-curl "https://openrouter.ai/api/v1/videos/$job/content?index=0" -o out.mp4
```

Prices are per second of output. As of 2026-10-24:

| Model | Price |
|---|---|
| `google/veo-3.1` | $0.40/s with audio (an 8 s clip is $3.20) |
| `google/veo-3.1-lite` | $0.08/s with audio |
| `kwaivgi/kling-v3.0-pro` | $0.112/s, or $0.168/s with audio |

Start with a Lite or Fast model and a short duration.

## Music

Google's Lyria models do music:

- `google/lyria-3-pro-preview`: a full song for $0.08;
- `google/lyria-3-clip-preview`: a 30 s clip for $0.04.

They go through `POST /api/v1/chat/completions`. OpenRouter's audio guide
asks for `"modalities": ["text", "audio"]`, an `audio` object with a
`format`, and `"stream": true`, and streams base64 audio in
`choices[0].delta.audio.data`. No one here has run Lyria this way yet. The
first agent to do so should record the working request in this skill, by
PR.
