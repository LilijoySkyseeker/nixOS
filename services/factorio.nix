{ ... }:
{
  # networking
  networking.firewall.allowedUDPPorts = [ 34197 ];

  # persistence
  environment.persistence."/nix/state".directories = [ { directory = "/srv/factorio/main"; } ];

  # factorio server
  virtualisation.oci-containers.containers.factorio-main = {
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
    # container hardening — see services/minecraft.nix for the same
    # general pattern, but factoriotools/factorio's entrypoint isn't
    # compatible with a read-only rootfs like itzg/minecraft-server is:
    # it runs `docker-dlc.sh` (writes into the volume) as root *before*
    # its own `chown -R factorio:factorio`, and that same root-drop
    # step also runs `usermod`/`groupmod` against /etc/passwd,
    # /etc/group to sync PUID/PGID — both need a genuinely writable
    # rootfs, not just the volume/tmpfs. Confirmed live: with
    # --read-only, every start crash-looped on
    # "docker-dlc.sh: line 17: /factorio/mods/mod-list.json.tmp:
    # Permission denied" (root lacking DAC_OVERRIDE to write into the
    # volume, which is owned by the image's baked-in UID 845, not
    # root) for two straight days before this was caught — the
    # container never actually served traffic despite `docker ps`
    # showing it "Up". No --read-only here; --cap-drop=ALL plus the
    # specific caps this root-then-drop dance needs (chown, the
    # DAC override for the pre-chown volume writes, and setuid/setgid
    # for usermod/groupmod/runuser) still meaningfully restricts it.
    extraOptions = [
      "--tmpfs=/tmp:rw,nosuid,nodev,size=512m"
      "--cap-drop=ALL"
      "--cap-add=CHOWN"
      "--cap-add=DAC_OVERRIDE"
      "--cap-add=SETUID"
      "--cap-add=SETGID"
      "--security-opt=no-new-privileges:true"
    ];
  };
}
