# Local transcription: models and provisioning

`modules/nixos/local-ai-speech.nix` installs `transcribe` on torrent. The
program is declared; the model files aren't, because they're
large downloads. They live in `/home/agent/work/projects/local-ai/models/audio`
(the owner's `~/Agent/projects/local-ai/models/audio`), covered by the normal
`/home` backups to homelab. After a restore they come back with `/home`. On
a fresh install without a backup, download them again:

```sh
d=~/work/projects/local-ai/models/audio; mkdir -p "$d"; cd "$d"
hf=https://huggingface.co
curl -fL -o ggml-large-v3-turbo-q8_0.bin     $hf/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin
curl -fL -o ggml-silero-v6.2.0.bin           $hf/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin
curl -fL -o nemotron-3-diarization-bf16.gguf $hf/audio-cpp/Nemotron-3-Diarization-GGUF/resolve/main/nemotron-3-diarization-bf16.gguf
```

Check them against the copies in use since 2026-10-23 (`sha256sum -c`):

```
317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1  ggml-large-v3-turbo-q8_0.bin
2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987  ggml-silero-v6.2.0.bin
84f6f0f12b9ecf2615548427e884534a72fedbca32d00872d95c0f72a078c953  nemotron-3-diarization-bf16.gguf
```

## What uses what

| File | Used by |
|---|---|
| `ggml-large-v3-turbo-q8_0.bin` | `transcribe`: Whisper speech recognition, every language |
| `ggml-silero-v6.2.0.bin` | `transcribe`: voice-activity detection, so music and silence aren't transcribed |
| `nemotron-3-diarization-bf16.gguf` | `transcribe`: speaker labels |

Keep only files a command uses (the owner, 2026-10-23): delete a model
that's been replaced, and update this table.

## Retiring the other models

After merging the retirement change and switching torrent, confirm
`curl -fsS http://127.0.0.1:8080/v1/models` lists only `qwen3.8-27b` and
`transcribe` works with the three files above. Then the owner can remove
only the retired model directories:

```sh
rm -r -- /srv/models/qwen3.8-flash-next /srv/models/paddleocr-vl /srv/models/audio
```

Keep `/srv/models/qwen3.8-27b`, its model and vision projector, and
`/srv/models/.backup-canary`. Keep `zroot/local/models`, its replication
and the homelab replica: do not destroy either dataset. Existing snapshots
retain deleted files until normal retention expires, so space is not
necessarily freed immediately.
