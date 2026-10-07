_: {
  flake.modules.homeManager."audio-switch" =
    { pkgs-unstable, inputs, ... }:
    let
      # resolve a PipeWire node.name to its current id (ids change per
      # session/reconnect, node.name is stable) and make it the default sink
      audioSwitchOutput = pkgs-unstable.writeShellApplication {
        name = "audio-switch-output";
        runtimeInputs = with pkgs-unstable; [
          pipewire
          wireplumber
          jq
        ];
        text = ''
          node_name="$1"
          id=$(pw-dump | jq -r --arg name "$node_name" \
            '.[] | select(.info.props."node.name" == $name) | .id' | head -n1)
          if [ -z "$id" ]; then
            echo "audio-switch-output: no sink with node.name=$node_name (is it plugged in?)" >&2
            exit 1
          fi
          wpctl set-default "$id"
        '';
      };
    in
    {
      imports = [ inputs.plasma-manager.homeModules.plasma-manager ];

      # KDE global shortcuts: one key per audio output (torrent's desk)
      # Hyper+F1-F3 (doio.vil's HYPR()), not F13-F15: XKB evdev maps those
      # to XF86 Launch5/Tools/Launch6, so an "F13" binding never matches
      programs.plasma.enable = true;
      programs.plasma.hotkeys.commands = {
        # no quotes around node.name: `command` lands verbatim in a .desktop
        # Exec= key, where `'` is reserved and breaks the build
        "audio-output-monitor" = {
          key = "Meta+Ctrl+Alt+Shift+F1";
          command = "${audioSwitchOutput}/bin/audio-switch-output alsa_output.pci-0000_03_00.1.hdmi-stereo-extra1";
          comment = "Audio output: Monitor (HDMI)";
        };
        "audio-output-rc505" = {
          key = "Meta+Ctrl+Alt+Shift+F2";
          command = "${audioSwitchOutput}/bin/audio-switch-output alsa_output.usb-BOSS_RC-505MK2_USB_Audio-00.analog-stereo";
          comment = "Audio output: Boss RC-505";
        };
        "audio-output-audioengine" = {
          key = "Meta+Ctrl+Alt+Shift+F3";
          command = "${audioSwitchOutput}/bin/audio-switch-output alsa_output.usb-Apple__Inc._USB-C_to_3.5mm_Headphone_Jack_Adapter_DWH524406HK2FN3AR-00.analog-stereo";
          comment = "Audio output: AudioEngine A5+";
        };
      };

      # clear stale per-app launch shortcuts occupying Meta+Ctrl+Alt+Shift+F1-F3
      programs.plasma.shortcuts = {
        "services/feishin.desktop"."_launch" = [ ];
        "services/sh.cider.genten.desktop"."_launch" = [ ];
        "services/spotify.desktop"."_launch" = [ ];
      };
    };
}
