"""transcribe: speech-to-text on torrent, with who said what.

Whisper large-v3-turbo recognizes the speech in every mode.
Speaker labels come from Nemotron diarization, which works on any language.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

AUDIO = os.environ["LOCAL_AI_AUDIO"]
VRAM_DEV = os.environ["VRAM_DEV"]
GAMING_MARKER = os.environ["GAMING_MARKER"]
RATE = 16000


def gpu_free():
    # desktop and games first: the GPU only when no game runs and VRAM is free
    if os.path.exists(GAMING_MARKER):
        return False, "a game is running"
    read = lambda f: int(open(f"{VRAM_DEV}/{f}").read())
    if read("mem_info_vram_total") - read("mem_info_vram_used") < 3 << 30:
        return False, "under 3 GiB of VRAM free (a local model is loaded?)"
    return True, ""


def run(cmd, log):
    with open(log, "a") as f:
        return subprocess.run(cmd, stdout=f, stderr=f).returncode == 0


def audiocpp(backend, log, *args):
    return run(["audiocpp_cli", "--backend", backend, "--threads", str(os.cpu_count()), *args], log)


def stamp(seconds):
    s = int(seconds)
    return f"[{s // 3600:02d}:{s % 3600 // 60:02d}:{s % 60:02d}]"


def diarize(work, backend, log):
    args = ["--task", "diar", "--family", "nemotron_3_diar", "--mode", "streaming",
            "--model", f"{AUDIO}/nemotron-3-diarization-bf16.gguf", "--audio", f"{work}/in.wav",
            "--turns-out", f"{work}/diar.json", "--out-dir", f"{work}/diar"]
    return audiocpp(backend, log, *args)


def whisper(work, backend, log, speakers, lang):
    cmd = ["whisper-cli", "-m", f"{AUDIO}/ggml-large-v3-turbo-q8_0.bin", "-l", lang,
           "-t", str(os.cpu_count()), "-np", "-oj", "-of", f"{work}/w", "-f", f"{work}/in.wav",
           # skip music and silence, where whisper otherwise invents text
           "--vad", "-vm", f"{AUDIO}/ggml-silero-v6.2.0.bin"]
    if speakers:
        # one segment per word, so each word goes to the speaker talking then
        cmd += ["-ml", "1", "-sow"]
    if backend == "cpu":
        cmd.append("-ng")
    if not run(cmd, log):
        return None
    out = json.load(open(f"{work}/w.json"))
    print(f"transcribe: language {out.get('result', {}).get('language', '?')}", file=sys.stderr)
    # word segments carry their own leading space (none in chinese or japanese)
    segs = [(s["offsets"]["from"] / 1000, s["offsets"]["to"] / 1000, s["text"])
            for s in out["transcription"] if s["text"].strip()]
    if not speakers:
        return [f"{stamp(a)} {t.strip()}" for a, _, t in segs]
    if not diarize(work, backend, log):
        return None
    turns = [(t["start_sample"] / RATE, t["end_sample"] / RATE, t["speaker_id"])
             for t in json.load(open(f"{work}/diar.json"))]
    lines, last = [], None
    for a, b, text in segs:
        # the speaker whose turns overlap this segment most
        overlap = {}
        for ta, tb, spk in turns:
            overlap[spk] = overlap.get(spk, 0) + max(0, min(b, tb) - max(a, ta))
        if overlap and max(overlap.values()) > 0:
            spk = max(overlap, key=overlap.get)
        elif turns:
            # a word just outside every turn goes to the nearest one
            spk = min(turns, key=lambda t: min(abs(a - t[1]), abs(b - t[0])))[2]
        else:
            spk = "unknown"
        if spk == last:
            lines[-1] += text
        else:
            lines.append(f"{stamp(a)} {spk}: {text.strip()}")
            last = spk
    return lines


def main():
    p = argparse.ArgumentParser(
        prog="transcribe",
        description="Speech-to-text on torrent, with who said what. English by default "
        "(Whisper large-v3-turbo); any language with -l. "
        "Any audio or video file ffmpeg reads.")
    p.add_argument("file")
    p.add_argument("-l", "--lang", help="any language: 'auto' to detect, or a code such as de, ja, zh")
    p.add_argument("--no-speakers", action="store_true", help="skip speaker labels")
    p.add_argument("--cpu", action="store_true", help="force the CPU (speaker labels then run at about 1/3 real time)")
    p.add_argument("-o", "--out", help="also write transcript.txt (and turns.json) to this directory")
    a = p.parse_args()
    if not os.access(a.file, os.R_OK):
        sys.exit(f"transcribe: can't read {a.file}")

    work = tempfile.mkdtemp(prefix="transcribe.")
    try:
        log = f"{work}/log"
        subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", a.file, "-vn",
                        "-ac", "1", "-ar", str(RATE), "-f", "wav", f"{work}/in.wav"], check=True)
        backend = "cpu"
        if not a.cpu:
            ok, why = gpu_free()
            backend = "vulkan" if ok else "cpu"
            if not ok:
                print(f"transcribe: {why}, using the CPU (slower)", file=sys.stderr)
        # assign speakers after recognition, so diarization does not gate speech
        go = lambda b: whisper(work, b, log, not a.no_speakers, a.lang or "en")
        lines = go(backend)
        if lines is None and backend == "vulkan":
            print("transcribe: the GPU run failed, retrying on the CPU", file=sys.stderr)
            lines = go("cpu")
        if lines is None:
            sys.exit(open(log).read())
        text = "\n".join(lines) + "\n"
        sys.stdout.write(text)
        if a.out:
            os.makedirs(a.out, exist_ok=True)
            open(f"{a.out}/transcript.txt", "w").write(text)
            for f in ("turns.json", "diar.json", "w.json"):
                if os.path.exists(f"{work}/{f}"):
                    shutil.copy(f"{work}/{f}", a.out)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
