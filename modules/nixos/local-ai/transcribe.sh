# transcribe: speech-to-text on torrent's GPU, with who said what
usage() {
  cat <<'USAGE'
usage: transcribe [--no-speakers] [--cpu] [-o DIR] FILE

Speech-to-text with audio.cpp, on the RX 7900 XTX when it's free.
  default        who said what: Nemotron diarization + Nemotron ASR (English)
  --no-speakers  plain text with Parakeet v3 (25 European languages)
  --cpu          force the CPU (speaker labels then run at about 1/3 real time)
  -o DIR         keep transcript.txt and turns.json (speaker mode) in DIR
Any audio or video file ffmpeg reads. Prints the transcript.
USAGE
}

speakers=1 backend=auto out="" file=""
while [ $# -gt 0 ]; do
  case $1 in
    --no-speakers) speakers=0 ;;
    --cpu) backend=cpu ;;
    -o) out=$2; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) file=$1 ;;
  esac
  shift
done
[ -n "$file" ] || { usage >&2; exit 2; }
[ -r "$file" ] || { echo "transcribe: can't read $file" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ffmpeg -nostdin -loglevel error -i "$file" -vn -ac 1 -ar 16000 -f wav "$work/in.wav"

# desktop and games first: the GPU only when no game runs and VRAM is free
if [ "$backend" = auto ]; then
  backend=vulkan
  free=$(($(cat "$VRAM_DEV/mem_info_vram_total") - $(cat "$VRAM_DEV/mem_info_vram_used")))
  if [ -e "$GAMING_MARKER" ]; then
    backend=cpu reason="a game is running"
  elif [ "$free" -lt $((3 * 1024 * 1024 * 1024)) ]; then
    backend=cpu reason="under 3 GiB of VRAM free (a local model is loaded?)"
  fi
  [ "$backend" = cpu ] && echo "transcribe: $reason, using the CPU (slower)" >&2
fi

cli() { audiocpp_cli --backend "$backend" --threads "$(nproc)" "$@" >>"$work/log" 2>&1; }
run() {
  if [ "$speakers" = 1 ]; then
    cli --task diar --family nemotron_3_diar --mode streaming \
      --model "$AUDIO/nemotron-3-diarization-bf16.gguf" --audio "$work/in.wav" \
      --session-option nemotron_3_diar.latency_profile=asr_la13 \
      --request-option return_frame_probabilities=true --out-dir "$work/diar" &&
      cli --task asr --family nemotron_asr \
        --model "$AUDIO/nemotron-3.5-asr-streaming-0.6b-q8_0.gguf" --audio "$work/in.wav" \
        --request-option speaker_probabilities="$work/diar/speaker_probabilities.safetensors" \
        --turns-out "$work/turns.json" --out-dir "$work/asr"
  else
    cli --task asr --family parakeet_tdt \
      --model "$AUDIO/parakeet-tdt-0.6b-v3-q8_0.gguf" --audio "$work/in.wav" --out-dir "$work/asr"
  fi
}
if ! run; then
  if [ "$backend" = vulkan ]; then
    echo "transcribe: the GPU run failed, retrying on the CPU" >&2
    backend=cpu
    run || { cat "$work/log" >&2; exit 1; }
  else
    cat "$work/log" >&2
    exit 1
  fi
fi

if [ "$speakers" = 1 ]; then
  jq -r 'def pad: tostring | if length < 2 then "0" + . else . end;
    .[] | (.start_sample / 16000 | floor) as $t
    | "[\($t / 3600 | floor | pad):\($t % 3600 / 60 | floor | pad):\($t % 60 | pad)] \(.speaker_id): \(.text)"' \
    "$work/turns.json" >"$work/transcript.txt"
else
  sed -n 's/^text_output=//p' "$work/log" >"$work/transcript.txt"
fi
cat "$work/transcript.txt"
if [ -n "$out" ]; then
  mkdir -p "$out"
  cp "$work/transcript.txt" "$out/"
  [ -e "$work/turns.json" ] && cp "$work/turns.json" "$out/"
fi
