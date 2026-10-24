# Local speech: models and provisioning

`modules/nixos/local-ai-speech.nix` installs `transcribe` and `speak` on
torrent. The programs are declared; the model files aren't, because they're
large downloads. They live in `/home/agent/work/projects/local-ai/models/audio`
(the owner's `~/Agent/projects/local-ai/models/audio`), covered by the normal
`/home` backups to homelab. After a restore they come back with `/home`. On
a fresh install without a backup, download them again:

```sh
d=~/work/projects/local-ai/models/audio; mkdir -p "$d/kokoro-82m-hf/voices"; cd "$d"
hf=https://huggingface.co
curl -fL -o ggml-large-v3-turbo-q8_0.bin     $hf/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin
curl -fL -o ggml-silero-v6.2.0.bin           $hf/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin
curl -fL -o kokoro-82m-q8_0.gguf             $hf/audio-cpp/audio.cpp-gguf/resolve/main/Kokoro-82M-GGUF/kokoro-82m-q8_0.gguf
curl -fL -o nemotron-3-diarization-bf16.gguf $hf/audio-cpp/Nemotron-3-Diarization-GGUF/resolve/main/nemotron-3-diarization-bf16.gguf
for f in config.json kokoro-v1_0.pth; do curl -fL -o kokoro-82m-hf/$f $hf/hexgrad/Kokoro-82M/resolve/main/$f; done
curl -s $hf/api/models/hexgrad/Kokoro-82M/tree/main/voices | jq -r '.[].path' |
  while read -r v; do curl -fL -o kokoro-82m-hf/$v $hf/hexgrad/Kokoro-82M/resolve/main/$v; done
```

Check them against the copies in use since 2026-10-23 (`sha256sum -c`):

```
317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1  ggml-large-v3-turbo-q8_0.bin
2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987  ggml-silero-v6.2.0.bin
9a4ca6176460cdc8c7845b804c0bbe85a4791ee3ffff568a3fdadbb708c63f47  kokoro-82m-q8_0.gguf
84f6f0f12b9ecf2615548427e884534a72fedbca32d00872d95c0f72a078c953  nemotron-3-diarization-bf16.gguf
5abb01e2403b072bf03d04fde160443e209d7a0dad49a423be15196b9b43c17f  kokoro-82m-hf/config.json
496dba118d1a58f5f3db2efc88dbdc216e0483fc89fe6e47ee1f2c53f18ad1e4  kokoro-82m-hf/kokoro-v1_0.pth
```

`kokoro-82m-hf/voices/` holds the 54 voice packs (`*.pt`).

## What uses what

| File | Used by |
|---|---|
| `ggml-large-v3-turbo-q8_0.bin` | `transcribe`: Whisper speech recognition, every language |
| `ggml-silero-v6.2.0.bin` | `transcribe`: voice-activity detection, so music and silence aren't transcribed |
| `nemotron-3-diarization-bf16.gguf` | `transcribe`: speaker labels |
| `kokoro-82m-q8_0.gguf` | `speak` from text (audio.cpp, eSpeak-ng) |
| `kokoro-82m-hf/` | `speak --ipa` (nixpkgs `kokoro`, offline) |

Keep only files a command uses (the owner, 2026-10-23): delete a model
that's been replaced, and update this table.
