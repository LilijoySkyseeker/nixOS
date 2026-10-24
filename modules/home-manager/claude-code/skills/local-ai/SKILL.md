---
name: local-ai
description: Transcribe audio or video locally with speaker labels, or generate speech from text or IPA on torrent. Use the installed transcribe and speak commands; local LLMs and the model server have been retired.
---

# Local speech on torrent

Two commands on `PATH`, for files the invoking user can read:

- `transcribe FILE` prints `[hh:mm:ss] speaker_N: text`. Whisper
  large-v3-turbo recognizes English by default; Nemotron diarization adds
  speaker labels afterward. `-l auto` detects a language once for the file;
  `-l de`, `-l ja`, etc. select one. `--no-speakers` skips speaker labeling.
  `-o DIR` saves the transcript and JSON. Any format ffmpeg reads, including
  video. One language per file; mixed-language speech is not reliable.
- `speak "text" -o out.wav` uses Kokoro v1.0. English first (`af_*`,
  `am_*`, `bf_*`, `bm_*`), plus Spanish, French, Hindi, Italian, Portuguese
  and Mandarin voices (`-v`, by prefix). Japanese text needs MeCab and
  UniDic, which are not installed; Japanese voices accept only `--ipa`.
- `speak --ipa "χaˈlɛθ" -o out.wav` accepts Kokoro's phoneme inventory.
  Unsupported symbols are reported and dropped; the output is not an
  exact pronunciation if any were dropped.

Both use the RX 7900 XTX when no game runs and enough VRAM is free, and
fall back to the CPU otherwise. `transcribe --cpu` forces the CPU. They
exit after the job, releasing their GPU memory. Avoid simultaneous GPU
jobs; the owner's desktop and games come first. Check VRAM before a big
job: `/sys/bus/pci/devices/0000:03:00.0/mem_info_vram_used`.

The model files are in
`~/work/projects/local-ai/models/audio/` (the owner's `~/Agent` view),
covered by the normal home backups. There is no dedicated model archive,
LLM server or local agent provider. Provisioning and migration are in
`docs/procedures/local-speech.md` in the nixOS repo.

Transcripts need review for quotations, names and important figures. The
Whisper path can still omit speech; GPU success is not evidence that a
transcript is complete. Prefer good uploaded captions when available.
