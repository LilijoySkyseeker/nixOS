_: {
  flake.modules.nixos."docker-userns-remap" =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.myDockerUserns;

      # container uid/gid 0 maps to this host id, container id N to
      # subIdStart + N. Fixed rather than Docker's "default"
      # auto-provisioning, whose /etc/subuid and /etc/subgid writes NixOS
      # overwrites on every switch. Not 100000: that is where NixOS's
      # autoSubUidGidRange pool for isNormalUser accounts starts, and its
      # collision check never sees manually-declared ranges
      subIdStart = 10000000;
    in
    {
      options.myDockerUserns = {
        enable = lib.mkEnableOption "docker userns-remap";
      };

      config = lib.mkIf cfg.enable {
        users.groups.dockremap = { };
        users.users.dockremap = {
          isSystemUser = true;
          group = "dockremap";
          subUidRanges = [
            {
              startUid = subIdStart;
              count = 65536;
            }
          ];
          subGidRanges = [
            {
              startGid = subIdStart;
              count = 65536;
            }
          ];
        };

        virtualisation.docker.daemon.settings.userns-remap = "dockremap";
      };
    };
}
