# local-ai-speech: speech tools on torrent for every agent and the user
# - transcribe: speech-to-text with who said what (audio.cpp: nemotron
#   diarization + asr), on the RX 7900 XTX when no game runs and VRAM is free
# - speak: kokoro v1.0 text-to-speech from text or IPA phonemes, or qwen3-tts
#   (--hq) for nicer voices
# models live in /srv/models/audio (local-ai's model store)
{ inputs, ... }:
{
  flake.modules.nixos."local-ai-speech" =
    { lib, pkgs, ... }:
    let
      audio = "/srv/models/audio";
      # built against this flake's nixpkgs (follows), so it loads the system's mesa
      audiocpp = inputs.audio-cpp.packages.${pkgs.stdenv.hostPlatform.system}.vulkan;
      espeak = pkgs.espeak-ng;

      transcribe = pkgs.writeShellApplication {
        name = "transcribe";
        runtimeInputs = [
          audiocpp
          pkgs.ffmpeg-headless
          pkgs.jq
          pkgs.coreutils
          pkgs.gnused
        ];
        text = ''
          AUDIO=${audio}
          # the RX 7900 XTX, as in local-ai's gpu
          VRAM_DEV=/sys/bus/pci/devices/0000:03:00.0
          # local-ai's gamemode hook
          GAMING_MARKER=/run/local-ai/gaming
        ''
        + builtins.readFile ./local-ai/transcribe.sh;
      };

      speakPython = pkgs.python3.withPackages (ps: [
        ps.kokoro
        ps.soundfile
        ps.numpy
        ps.torch
      ]);
      speak = pkgs.writeShellApplication {
        name = "speak";
        text = ''
          export LOCAL_AI_AUDIO=${audio}
          export AUDIOCPP_CLI=${lib.getExe' audiocpp "audiocpp_cli"}
          export VRAM_DEV=/sys/bus/pci/devices/0000:03:00.0
          export GAMING_MARKER=/run/local-ai/gaming
          # audio.cpp's kokoro phonemizes text with espeak-ng
          export LD_LIBRARY_PATH=${espeak}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
          export ESPEAK_DATA_PATH=${espeak}/share
          exec ${speakPython}/bin/python3 -I ${./local-ai/speak.py} "$@"
        '';
      };
    in
    {
      environment.systemPackages = [
        transcribe
        speak
      ];
    };
}
