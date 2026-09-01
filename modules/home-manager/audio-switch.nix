{ ... }:
{
  flake.modules.homeManager."audio-switch" =
    { pkgs-unstable, inputs, ... }:
    let
      # Resolves a PipeWire node.name to its current numeric id via pw-dump
      # (ids are reassigned per session/reconnect; node.name is stable) and
      # sets it as the default sink with wpctl.
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

      # Declarative KDE global shortcuts, kept out of System Settings so a
      # host rebuild always reproduces them. One dedicated key per physical
      # output (torrent's desk setup) rather than a single cycle key.
      #
      # Bound to Hyper+F13/F14/F15 (Ctrl+Shift+Alt+GUI, matching the
      # doio.vil HYPR() keycodes) rather than bare F13-24, to avoid
      # colliding with the karousel/launcher shortcuts already registered
      # on plain Meta+Ctrl+Alt+Shift+F1-F12 -- Hyper+F13-24 is otherwise
      # untouched keyspace.
      programs.plasma.enable = true;
      programs.plasma.hotkeys.commands = {
        # No quotes around the node.name argument: plasma-manager writes
        # `command` verbatim into a .desktop file's Exec= key, whose
        # Desktop Entry spec treats a bare `'` as a reserved character
        # outside of its own (different) quoting rules -- single-quoting
        # the arg like a shell command breaks the build. Safe to omit
        # here since none of these three node.names contain whitespace.
        "audio-output-monitor" = {
          key = "Meta+Ctrl+Alt+Shift+F13";
          command = "${audioSwitchOutput}/bin/audio-switch-output alsa_output.pci-0000_03_00.1.hdmi-stereo-extra1";
          comment = "Audio output: Monitor (HDMI)";
        };
        "audio-output-rc505" = {
          key = "Meta+Ctrl+Alt+Shift+F14";
          command = "${audioSwitchOutput}/bin/audio-switch-output alsa_output.usb-BOSS_RC-505MK2_USB_Audio-00.analog-stereo";
          comment = "Audio output: Boss RC-505";
        };
        "audio-output-audioengine" = {
          key = "Meta+Ctrl+Alt+Shift+F15";
          command = "${audioSwitchOutput}/bin/audio-switch-output alsa_output.usb-Apple__Inc._USB-C_to_3.5mm_Headphone_Jack_Adapter_DWH524406HK2FN3AR-00.analog-stereo";
          comment = "Audio output: AudioEngine A5+";
        };
      };
    };
}
