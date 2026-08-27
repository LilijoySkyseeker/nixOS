{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos.factorio =
    { config, pkgs, ... }:
    let
      # preStart body, parameterized by the server's own directory and
      # display name. Kept parameterized rather than inlined even though
      # there is only one server again: it was written for two, and the
      # parameters are what a second one would need.
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
      # container hardening — see
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
        # Resource ceilings (docs/hardening.md standing rule 10). Without
        # them, container OOM pressure is *host* OOM pressure on the box
        # holding zbackup, and the kernel picks its own victim among
        # jellyfin, smbd, nfsd and the restic job. Before this, both
        # containers ran with memory.max = "max" and the host-default
        # pids.max of 19038.
        #
        # --memory: user decision D15 — "no container may exceed 50% of
        # host memory". homelab's MemTotal is 15.54 GiB, so half is
        # 7.77 GiB; 7g is the round value comfortably under that. This is
        # deliberately a *bound on the blast radius*, not a tuned figure:
        # the server is mostly idle playerwise, so there is no real
        # load data to size from, and the measured 1.06 GB peak
        # (2026-08-27, 37 minutes uptime, idle) is a floor rather than a
        # peak. Sizing down toward that measurement is the thing not to
        # do — a ceiling below what the runtime needs becomes an OOM-kill
        # loop that reads as a game crash.
        #
        # NB both containers carry the same 50% cap, so if both ever hit
        # it at once the host is exhausted. That is inherent in a
        # per-container percentage and is accepted: it still stops any
        # *single* runaway from taking the whole machine, which is the
        # failure this guards against. Revisit together with real load
        # data (D16-style re-measure), not one container at a time.
        #
        # This figure is homelab-specific. If these game servers ever run
        # on another host, recompute it there.
        "--memory=7g"
        # --pids-limit: measured peak was 19. 512 is ~27x that and still
        # 37x below the host default, so it stops a fork bomb without any
        # realistic chance of refusing a thread the server actually
        # wanted. Erring generous is deliberate — too low fails as
        # "cannot spawn thread", which looks nothing like its cause.
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
      # networking: dropped host-wide allowedUDPPorts (2026-08-26) —
      # homelab's LAN NIC carries a real public IPv6 address (ISP
      # RA-delegated), which turns any host-wide firewall rule into
      # direct internet exposure. These ports only ever legitimately
      # arrive two ways: over the tailnet directly, or over the wg0
      # tunnel from vps (which is how vps's DNAT'd public game ports
      # actually reach this host — see hosts/vps/configuration.nix's
      # networking.nat.forwardPorts) — scope to just those two
      # interfaces.
      #
      # These rules are NOT what enforces that for the published ports —
      # a `-p` publish never traverses INPUT, so an INPUT rule cannot
      # constrain it (F-P4-02). Enforcement lives in
      # `myDockerPublishGuard` on homelab, which applies the same
      # interface list in FORWARD via DOCKER-USER. Change both together.
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
      # `description`/`tags`/`non_blocking_saving` aren't.
      sops.secrets.factorio_game_password = { };
      sops.secrets.factorio_token = { };
      sops.secrets.factorio_username = { };
      systemd.services.docker-factorio-main.preStart = mkServerSettingsPatch {
        directory = "/srv/factorio/main";
        name = "GC Space Age!!";
      };

      # factorio server
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
      };
    };
}
