"""speak: Kokoro v1.0 text-to-speech, from text or from IPA phonemes."""

import argparse
import os
import re
import subprocess
import sys
import warnings

# torch's deprecation chatter on every run says nothing about the audio
warnings.filterwarnings("ignore")

AUDIO = os.environ["LOCAL_AI_AUDIO"]
AUDIOCPP_CLI = os.environ["AUDIOCPP_CLI"]
VRAM_DEV = os.environ["VRAM_DEV"]
GAMING_MARKER = os.environ["GAMING_MARKER"]
RATE = 24000
# kokoro's input limit is 510 symbols per chunk
MAX_CHUNK = 400


def gpu_free():
    # desktop and games first: the GPU only when no game runs and VRAM is free
    if os.path.exists(GAMING_MARKER):
        return False
    read = lambda f: int(open(f"{VRAM_DEV}/{f}").read())
    return read("mem_info_vram_total") - read("mem_info_vram_used") > 1 << 30


def speak_text(text, voice, speed, out):
    # japanese text needs mecab and unidic, which aren't installed
    if voice.startswith("j"):
        sys.exit("speak: Japanese voices can't read text here (no MeCab/UniDic); "
                 "use another voice, or give Japanese phonemes with --ipa")
    # audio.cpp's kokoro, with eSpeak-ng as the phonemizer
    backend = "vulkan" if gpu_free() else "cpu"
    cmd = [AUDIOCPP_CLI, "--task", "tts", "--family", "kokoro_tts",
           "--model", f"{AUDIO}/kokoro-82m-q8_0.gguf", "--backend", backend,
           "--voice-id", voice, "--text", text, "--out", out]
    if speed != 1.0:
        cmd += ["--request-option", f"speed={speed}"]
    run = subprocess.run(cmd, capture_output=True, text=True)
    if run.returncode != 0 and backend == "vulkan":
        cmd[cmd.index("vulkan")] = "cpu"
        run = subprocess.run(cmd, capture_output=True, text=True)
    if run.returncode != 0:
        sys.exit(f"speak: audio.cpp failed:\n{run.stderr.strip()}")


def chunks(phonemes):
    # split after sentence or clause punctuation, then at spaces, to stay under the limit
    parts, cur = [], ""
    for piece in re.split(r"(?<=[.!?;:,])\s+", phonemes.strip()):
        if len(cur) + len(piece) + 1 <= MAX_CHUNK:
            cur = f"{cur} {piece}".strip()
            continue
        if cur:
            parts.append(cur)
        while len(piece) > MAX_CHUNK:
            cut = piece.rfind(" ", 0, MAX_CHUNK)
            cut = cut if cut > 0 else MAX_CHUNK
            parts.append(piece[:cut])
            piece = piece[cut:].strip()
        cur = piece
    if cur:
        parts.append(cur)
    return parts


def speak_ipa(phonemes, voice, speed, out):
    import numpy as np
    import soundfile as sf
    import torch
    from kokoro import KModel

    base = f"{AUDIO}/kokoro-82m-hf"
    model = KModel(repo_id="hexgrad/Kokoro-82M", config=f"{base}/config.json",
                   model=f"{base}/kokoro-v1_0.pth").eval()
    missing = sorted({c for c in phonemes if c not in model.vocab and not c.isspace()})
    if missing:
        print(f"speak: not in Kokoro's symbol set, dropped: {' '.join(missing)}", file=sys.stderr)
        phonemes = "".join(c for c in phonemes if c in model.vocab or c.isspace())
    pack = torch.load(f"{base}/voices/{voice}.pt", weights_only=True)
    gap = np.zeros(int(0.15 * RATE), dtype=np.float32)
    audio = []
    with torch.no_grad():
        for part in chunks(phonemes):
            n = len([c for c in part if c in model.vocab])
            audio += [model(part, pack[max(n - 1, 0)], speed).numpy(), gap]
    sf.write(out, np.concatenate(audio[:-1]), RATE)


def main():
    p = argparse.ArgumentParser(
        prog="speak",
        description="Kokoro v1.0 text-to-speech. Give TEXT, or --ipa with phonemes in "
        "Kokoro's IPA alphabet for exact pronunciations.")
    p.add_argument("text", nargs="?", help="text to speak (English and other eSpeak languages)")
    p.add_argument("--ipa", help="IPA phonemes to speak instead of TEXT, e.g. 'χaˈlɛθ'")
    p.add_argument("-v", "--voice", default="af_heart",
                   help="voice id (default af_heart); the list: ls " + AUDIO + "/kokoro-82m-hf/voices")
    p.add_argument("-s", "--speed", type=float, default=1.0)
    p.add_argument("-o", "--out", default="speech.wav", help="output WAV (default speech.wav)")
    a = p.parse_args()
    if bool(a.text) == bool(a.ipa):
        p.error("give TEXT or --ipa, not both")
    if a.ipa:
        speak_ipa(a.ipa, a.voice, a.speed, a.out)
    else:
        speak_text(a.text, a.voice, a.speed, a.out)
    print(a.out)


if __name__ == "__main__":
    main()
