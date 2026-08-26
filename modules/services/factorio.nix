{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos.factorio =
    { config, pkgs, ... }:
    let
      # Common preStart body, parameterized by the server's own directory
      # and display name (only `name` differs between the two — needed so
      # players can tell them apart in the server browser — everything
      # else, including the shared secrets below, is identical).
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
            mv "$settings.tmp" "$settings"
          fi
        '';
      # container hardening shared by both servers — see
      # modules/services/minecraft.nix for the same general pattern, but
      # factoriotools/factorio's entrypoint isn't compatible with a
      # read-only rootfs like itzg/minecraft-server is: it runs
      # `docker-dlc.sh` (writes into the volume) as root *before* its own
      # `chown -R factorio:factorio`, and that same root-drop step also
      # runs `usermod`/`groupmod` against /etc/passwd, /etc/group to sync
      # PUID/PGID — both need a genuinely writable rootfs, not just the
      # volume/tmpfs. Confirmed live on the old server: with --read-only,
      # every start crash-looped on "docker-dlc.sh: line 17:
      # /factorio/mods/mod-list.json.tmp: Permission denied" (root lacking
      # DAC_OVERRIDE to write into the volume, which is owned by the
      # image's baked-in UID 845, not root) for two straight days before
      # this was caught — the container never actually served traffic
      # despite `docker ps` showing it "Up". No --read-only here;
      # --cap-drop=ALL plus the specific caps this root-then-drop dance
      # needs (chown, the DAC override for the pre-chown volume writes,
      # and setuid/setgid for usermod/groupmod/runuser) still meaningfully
      # restricts it.
      factorioExtraOptions = [
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
      # networking: dropped host-wide allowedUDPPorts (2026-08-26) —
      # homelab's LAN NIC carries a real public IPv6 address (ISP
      # RA-delegated), which turns any host-wide firewall rule into
      # direct internet exposure. These ports only ever legitimately
      # arrive two ways: over the tailnet directly, or over the wg0
      # tunnel from vps (which is how vps's DNAT'd public game ports
      # actually reach this host — see hosts/vps/configuration.nix's
      # networking.nat.forwardPorts) — scope to just those two
      # interfaces.
      networking.firewall.interfaces.tailscale0.allowedUDPPorts = [
        34197 # old.factorio
        34198 # new.factorio
      ];
      networking.firewall.interfaces.wg0.allowedUDPPorts = [
        34197 # old.factorio
        34198 # new.factorio
      ];

      # persistence
      environment.persistence.${vars.persistRoot}.directories = [
        { directory = "/srv/factorio/main"; }
        { directory = "/srv/factorio/new"; }
      ];

      # server-settings.json was previously hand-edited directly on the
      # host — not sops-managed, not declarative, and not reproducible.
      # The factoriotools image doesn't support injecting these via env
      # vars (server-settings.json is only ever auto-created once, from a
      # template, if missing), so this patches every field that's been
      # customized away from the image's own template default back in on
      # every container start instead — anything not listed here is left
      # exactly as-is, so this can't clobber settings we don't know about.
      # `game_password`, `token` (a factorio.com account auth token,
      # equally sensitive), and `username` are secrets; `name`/
      # `description`/`tags`/`non_blocking_saving` aren't. Shared by both
      # servers — new.factorio is meant to have "the same settings" as
      # old.factorio, including login credentials, per explicit decision.
      sops.secrets.factorio_game_password = { };
      sops.secrets.factorio_token = { };
      sops.secrets.factorio_username = { };
      systemd.services.docker-factorio-main.preStart = mkServerSettingsPatch {
        directory = "/srv/factorio/main";
        name = "GC Space Age!! (old)";
      };
      systemd.services.docker-factorio-new.preStart = ''
        # Mirror old.factorio's mods into this server before every start,
        # so "same mods as the old one" stays true declaratively instead
        # of needing to hand-copy a mod list that'll drift the moment
        # someone updates mods on the old server. install -d/rsync rather
        # than a bind-mount: the new server needs to be able to add/update
        # its own mods afterwards (UPDATE_MODS_ON_START) without writing
        # back into old.factorio's volume.
        ${pkgs.coreutils}/bin/install -d -m 0755 /srv/factorio/new/mods
        if [ -d /srv/factorio/main/mods ]; then
          ${pkgs.rsync}/bin/rsync -a --delete /srv/factorio/main/mods/ /srv/factorio/new/mods/
        fi
      ''
      + mkServerSettingsPatch {
        directory = "/srv/factorio/new";
        name = "GC Space Age!! (new)";
      };

      # factorio servers
      virtualisation.oci-containers.containers = {
        factorio-main = {
          autoStart = true;
          # Pinned to the exact version the current save is already in
          # (2.1.14, factoriotools' newer/experimental line) rather than
          # `stable` (2.0.77) — the live save can't be loaded by an older
          # engine (Factorio saves are forward-only compatible: "Map version
          # 2.1.14-1 cannot be loaded because it is higher than the game
          # version (2.0.77-0)", confirmed live when `stable` was briefly
          # tried). No recent-enough ZFS snapshot existed to recover a
          # pre-2.1.14 save (snapshot history has a gap between 2026-06-24
          # and 2026-08-16, and the live save was already 2.1.14-format by
          # the earliest available point in that gap). Revisit this pin once
          # 2.1.14 (or whatever it's since become) reaches `stable`.
          image = "factoriotools/factorio:2.1.14";
          ports = [ "34197:34197/udp" ];
          volumes = [ "/srv/factorio/main:/factorio" ];
          environment = {
            UPDATE_MODS_ON_START = "true";
          };
          extraOptions = factorioExtraOptions;
        };

        # new.factorio — latest *stable* branch (not old.factorio's
        # experimental 2.1.14 pin above), a fresh random world, same
        # settings/mods as old.factorio (mirrored every start, see
        # docker-factorio-new's preStart above). `stable` is a floating tag
        # by design here (per explicit decision) — this server has no
        # existing save to be version-locked against, so it's fine for it
        # to track whatever Factorio currently calls stable and pick up
        # engine updates automatically on restart.
        factorio-new = {
          autoStart = true;
          image = "factoriotools/factorio:stable";
          # PORT tells the entrypoint which port to actually bind inside
          # the container (it isn't just a docker port-map relabeling —
          # the factoriotools image reads this into server-settings.json's
          # own port field), so old.factorio and new.factorio can run with
          # distinct, non-conflicting ports on the same docker host. See
          # factoriotools/factorio-docker's own multi-instance guidance.
          ports = [ "34198:34198/udp" ];
          volumes = [ "/srv/factorio/new:/factorio" ];
          environment = {
            PORT = "34198";
            UPDATE_MODS_ON_START = "true";
          };
          extraOptions = factorioExtraOptions;
        };
      };
    };
}
