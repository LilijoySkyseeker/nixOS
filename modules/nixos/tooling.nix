{ pkgs, lib, ... }:
{
  # Git
  programs.git = {
    enable = true;
    config = {
      push.autoSetupRemote = true;
    };
  };

  # fish
  programs.fish = {
    enable = true;
    vendor.completions.enable = true;
  };
  programs.bash = {
    # switch to fish in interactive shell
    interactiveShellInit = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then
        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      fi
    '';
  };
  environment.shellAliases = lib.mkForce { }; # clear all shell aliases, using fish functions instead

}
