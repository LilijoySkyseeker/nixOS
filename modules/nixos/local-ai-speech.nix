# local-ai-speech: local transcription on torrent for every agent and the user
# - transcribe: whisper.cpp large-v3-turbo with optional nemotron speaker labels,
#   on the RX 7900 XTX when no game runs and VRAM is free
# models live in the shared work folder, covered by the normal home backups
{ inputs, ... }:
{
  flake.modules.nixos."local-ai-speech" =
    { pkgs, ... }:
    let
      audio = "/home/agent/work/projects/local-ai/models/audio";
      # built against this flake's nixpkgs (follows), so it loads the system's mesa
      audiocpp = inputs.audio-cpp.packages.${pkgs.stdenv.hostPlatform.system}.vulkan;

      # whisper large-v3-turbo for any language, on vulkan
      whisperCpp = pkgs.whisper-cpp.override { vulkanSupport = true; };
      transcribe = pkgs.writeShellApplication {
        name = "transcribe";
        runtimeInputs = [
          audiocpp
          whisperCpp
          pkgs.ffmpeg-headless
        ];
        text = ''
          export LOCAL_AI_AUDIO=${audio}
          # the RX 7900 XTX, as in local-ai's gpu
          export VRAM_DEV=/sys/bus/pci/devices/0000:03:00.0
          # speech yields the GPU when gamemode is active
          export GAMING_MARKER=/run/local-ai/gaming
          exec ${pkgs.python3}/bin/python3 -I ${./local-ai/transcribe.py} "$@"
        '';
      };

    in
    {
      systemd.tmpfiles.rules = [ "d /run/local-ai 1777 root root -" ];
      programs.gamemode.settings.custom = {
        start = "${pkgs.coreutils}/bin/touch /run/local-ai/gaming";
        end = "${pkgs.coreutils}/bin/rm -f /run/local-ai/gaming";
      };

      environment.systemPackages = [ transcribe ];
    };
}
