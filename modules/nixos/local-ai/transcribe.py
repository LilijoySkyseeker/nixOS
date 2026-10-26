"""transcribe: speech-to-text on torrent, with who said what.

Whisper large-v3-turbo recognizes the speech in every mode, and a second
pass re-transcribes the stretches where it looped.
Speaker labels come from Nemotron diarization, which works on any language.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import wave

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


def recognize(wav, out, backend, log, speakers, lang, extra=()):
    cmd = ["whisper-cli", "-m", f"{AUDIO}/ggml-large-v3-turbo-q8_0.bin", "-l", lang,
           "-t", str(os.cpu_count()), "-np", "-oj", "-of", out, "-f", wav,
           # skip music and silence, where whisper otherwise invents text
           "--vad", "-vm", f"{AUDIO}/ggml-silero-v6.2.0.bin", *extra]
    if speakers:
        # one segment per word, so each word goes to the speaker talking then
        cmd += ["-ml", "1", "-sow"]
    if backend == "cpu":
        cmd.append("-ng")
    if not run(cmd, log):
        return None
    res = json.load(open(f"{out}.json"))
    # word segments carry their own leading space (none in chinese or japanese)
    segs = [(s["offsets"]["from"] / 1000, s["offsets"]["to"] / 1000, s["text"])
            for s in res["transcription"] if s["text"].strip()]
    return segs, res.get("result", {}).get("language", "?")


def looping(segs):
    """Indices of the segments where whisper repeats itself: a run of 6 words
    that comes back 3 or more times within 60 words."""
    words = [(re.sub(r"\W", "", w.lower()), i) for i, (_, _, t) in enumerate(segs) for w in t.split()]
    words = [(w, i) for w, i in words if w]
    grams = [tuple(w for w, _ in words[k:k + 6]) for k in range(len(words) - 5)]
    hit = set()
    for k, gram in enumerate(grams):
        at = [j for j in range(k, min(k + 60, len(grams))) if grams[j] == gram]
        if len(at) >= 3:
            hit.update(i for j in at for _, i in words[j:j + 6])
    return sorted(hit)


def repair(work, segs, backend, log, speakers, lang):
    """Re-transcribe each looping stretch without carried-over context (-mc 0).
    That setting ends most loops but drops more words on clean speech, so it
    runs only where the first pass looped (sweep, 2026-10-25)."""
    hit = looping(segs)
    # stretches of looping segments, merged when under 30 s apart
    spans = []
    for i in hit:
        if spans and segs[i][0] - segs[spans[-1][1]][1] < 30:
            spans[-1][1] = i
        else:
            spans.append([i, i])
    fixed = 0
    for first, last in reversed(spans):
        # from the end of the segment before to the start of the one after
        a = segs[first - 1][1] if first else 0.0
        b = segs[last + 1][0] if last + 1 < len(segs) else segs[last][1]
        clip = f"{work}/clip.wav"
        with wave.open(f"{work}/in.wav") as src, wave.open(clip, "wb") as dst:
            dst.setparams(src.getparams())
            src.setpos(int(a * RATE))
            dst.writeframes(src.readframes(int((b - a) * RATE)))
        got = recognize(clip, f"{work}/clip", backend, log, speakers, lang, ["-mc", "0"])
        if got is None:
            continue
        new = [(x + a, y + a, t) for x, y, t in got[0]]
        # keep the second pass only if it loops less than the first
        if len(looping(new)) < len(looping(segs[first:last + 1])):
            segs[first:last + 1] = new
            fixed += 1
    if spans:
        print(f"transcribe: {len(spans)} looping stretches, {fixed} re-transcribed", file=sys.stderr)
    return segs


def whisper(work, backend, log, speakers, lang):
    got = recognize(f"{work}/in.wav", f"{work}/w", backend, log, speakers, lang)
    if got is None:
        return None
    segs, detected = got
    print(f"transcribe: language {detected}", file=sys.stderr)
    segs = repair(work, segs, backend, log, speakers, lang)
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
