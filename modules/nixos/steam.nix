_: {
  flake.modules.nixos."steam" = { lib, pkgs-unstable, ... }: {
    # no remotePlay.openFirewall (host-wide ports); if wanted, scope to an interface
    programs.steam = {
      enable = true;
    };

    programs.gamemode = {
      enable = true;
      settings = {
        cpu = {
          park_cores = "no";
          pin_cores = "yes";
        };
      };
    };

    # every steam game starts under `reaper SteamLaunch AppId=…`: register
    # each one with gamemode, whose reaper drops it again when it exits
    systemd.user.services.steam-gamemode = {
      description = "Run every Steam game under gamemode";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = lib.getExe (
          pkgs-unstable.writeShellApplication {
            name = "steam-gamemode";
            runtimeInputs = with pkgs-unstable; [
              procps
              systemd
            ];
            text = ''
              gm=(com.feralinteractive.GameMode /com/feralinteractive/GameMode com.feralinteractive.GameMode)
              while sleep 3; do
                # own processes only: another user (agent) can't toggle this session's gamemode
                for pid in $(pgrep -u "$UID" -f '^[^ ]*/reaper SteamLaunch AppId='); do
                  # 2: gamemode is on and this pid is registered
                  [ "$(busctl --user call "''${gm[@]}" QueryStatusByPID ii $$ "$pid" 2>/dev/null)" = "i 2" ] && continue
                  busctl --user call "''${gm[@]}" RegisterGameByPID ii $$ "$pid" >/dev/null || true
                done
              done
            '';
          }
        );
        Restart = "on-failure";
      };
    };
  };
}
