{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos.factorio =
    { config, pkgs, ... }:
    let
      # preStart body, parameterized by server directory and display name
      mkServerSettingsPatch =
        { directory, name }:
        ''
          settings=${directory}/config/server-settings.json
          if [ -f "$settings" ]; then
            ${pkgs.jq}/bin/jq \
              --arg pw "$(cat ${config.sops.secrets.factorio_game_password.path})" \
              --arg token "$(cat ${config.sops.secrets.factorio_token.path})" \
              --arg username "$(cat ${config.sops.secrets.factorio_username.path})" \
              '.game_password = $pw
               | .token = $token
               | .username = $username
               | .name = "${name}"
               | .description = "we gonna go to da mun"
               | .tags = ["game"]
               | .non_blocking_saving = true' \
              "$settings" >"$settings.tmp"
            # take owner from config/ (kept right by the userns migration):
            # a root-owned file breaks the entrypoint's chown under userns-remap
            chown --reference="${directory}/config" "$settings.tmp"
            chmod --reference="$settings" "$settings.tmp"
            mv "$settings.tmp" "$settings"
          fi
        '';
      # container hardening, like minecraft.nix but without --read-only: the
      # entrypoint writes the volume and runs usermod/groupmod as root before
      # dropping privileges; the cap-adds below are exactly what that needs
      factorioExtraOptions = [
        # --memory: no container may exceed 50% of host memory (homelab: 15.5 GiB);
        # a blast-radius bound, not a tuned figure -- don't size it down to
        # measured use or it becomes an OOM-kill loop. recompute on another host
        "--memory=7g"
        # --pids-limit: ~27x measured peak; too low fails as "cannot spawn thread"
        "--pids-limit=512"
        "--tmpfs=/tmp:rw,nosuid,nodev,size=512m"
        "--cap-drop=ALL"
        "--cap-add=CHOWN"
        "--cap-add=DAC_OVERRIDE"
        "--cap-add=SETUID"
        "--cap-add=SETGID"
        "--security-opt=no-new-privileges:true"
      ];
    in
    {
      # networking: tailnet and wg0 (vps's DNAT'd game port) only; the LAN NIC
      # has a public IPv6. INPUT rules don't constrain docker publishes:
      # myDockerPublishGuard on homelab enforces this list -- change both together
      networking.firewall.interfaces.tailscale0.allowedUDPPorts = [
        34197 # factorio
      ];
      networking.firewall.interfaces.wg0.allowedUDPPorts = [
        34197 # factorio
      ];

      # persistence
      environment.persistence.${vars.persistRoot}.directories = [
        { directory = "/srv/factorio/main"; }
      ];

      # state dir holds the factorio.com token and game password: deny non-owner
      # access. mode only (user/group `-`) since the owning uid comes from the
      # image; non-recursive and not retroactive (snapshots keep old modes)
      systemd.tmpfiles.settings."10-factorio-state"."/srv/factorio/main".z.mode = "0700";

      # docker userns-remap ownership migration; 845 is the factoriotools image's
      # baked-in uid -- if it changes, `chown --from` silently matches nothing
      myDockerUserns.migrations = [
        {
          path = "/srv/factorio/main";
          uid = 845;
          gid = 845;
        }
      ];

      # the image only creates server-settings.json once, so preStart patches the
      # customized fields in on every start; unlisted fields are left as-is.
      # restartUnits: secrets are baked into that file at start, so a rotation
      # without a restart leaves the revoked credentials live
      sops.secrets.factorio_game_password.restartUnits = [ "docker-factorio-main.service" ];
      sops.secrets.factorio_token.restartUnits = [ "docker-factorio-main.service" ];
      # not a credential, but lands in the same generated file
      sops.secrets.factorio_username.restartUnits = [ "docker-factorio-main.service" ];
      systemd.services.docker-factorio-main.preStart = mkServerSettingsPatch {
        directory = "/srv/factorio/main";
        name = "GC Space Age!!";
      };

      # factorio server
      virtualisation.oci-containers.containers = {
        factorio-main = {
          autoStart = false; # set true to bring it back (data persists)
          # pinned: the live save is 2.1.14-format and can't load on an older
          # engine (e.g. `stable`); revisit once 2.1.14 reaches stable
          image = "factoriotools/factorio:2.1.14";
          ports = [ "34197:34197/udp" ];
          volumes = [ "/srv/factorio/main:/factorio" ];
          environment = {
            UPDATE_MODS_ON_START = "true";
          };
          extraOptions = factorioExtraOptions;
        };
      };
    };
}
