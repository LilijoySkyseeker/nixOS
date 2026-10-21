_: {
  flake.modules.nixos."reboot-notice" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.myRebootNotice;

      notice = pkgs.writeShellApplication {
        name = "reboot-notice";
        runtimeInputs = with pkgs; [
          coreutils
          libnotify
        ];
        text = ''
          booted=$(readlink -f /run/booted-system)
          current=$(readlink -f /run/current-system)
          installed=$(readlink -f /nix/var/nix/profiles/system)
          seen="''${XDG_STATE_HOME:-$HOME/.local/state}/reboot-notice"

          # nothing waiting: the installed system is running, kernel included
          if [[ $installed == "$current" ]]; then
            same=1
            for part in kernel initrd kernel-modules; do
              [[ $(readlink -f "$booted/$part") == $(readlink -f "$installed/$part") ]] || same=0
            done
            [[ $same == 1 ]] && exit 0
          fi
          # already shown for this update
          [[ -f $seen && $(cat "$seen") == "$installed" ]] && exit 0

          notify-send --app-name="System update" --icon=system-reboot \
            "Restart when convenient" \
            "An installed update takes effect at the next restart. Resuming from hibernation doesn't apply it."
          mkdir -p "$(dirname "$seen")"
          printf '%s\n' "$installed" >"$seen"
        '';
      };
    in
    {
      options.myRebootNotice.enable = lib.mkEnableOption "a desktop notification, once per update, when an installed system is waiting for a restart";

      config = lib.mkIf cfg.enable {
        systemd.user.services.reboot-notice = {
          description = "Notify when an installed update is waiting for a restart";
          partOf = [ "graphical-session.target" ];
          after = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe notice;
          };
        };

        # the profile symlink is swapped in this directory by every install
        systemd.user.paths.reboot-notice = {
          wantedBy = [ "graphical-session.target" ];
          pathConfig.PathChanged = "/nix/var/nix/profiles";
        };
      };
    };
}
