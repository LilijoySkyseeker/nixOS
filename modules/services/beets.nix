{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos.beets =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      importDir = "/storage/Music/Import";
      reviewDir = "/storage/Music/NeedsReview";
      libraryDir = "/storage/Music/Picard";

      # shared by every non-default bucket below and by `default` itself --
      # they differ only in which folder prefix comes before this.
      pathSuffix = "$year_bracket $album%if{$albumdisambig, ($albumdisambig)}%aunique{}/$disc_prefix$track_padded $title$feat_bracket";

      beetsConfigName = "beets-config";
    in
    {
      # dedicated, single-purpose account -- only ever runs beets-import.service.
      # multimedia membership declared from the group side (matching jellyfin.nix's
      # own users.groups.multimedia.members pattern), since this user's whole
      # purpose already is exactly this one task.
      users.users.beets = {
        isSystemUser = true;
        group = "beets";
        description = "beets music tagger/importer (no shell/SSH login)";
      };
      users.groups.beets = { };
      users.groups.multimedia.members = [ "beets" ];

      sops.secrets.homelab_beets_acoustid_apikey = { };

      # renders atomically to /run/secrets/rendered/<name> with the apikey
      # spliced in -- never touches the nix store or persistent disk
      # plan: 2026-09-04-homelab-beets-setup-mimicking-picard-tagging-renaming.md#G8
      #
      # plan: 2026-09-04-homelab-beets-setup-mimicking-picard-tagging-renaming.md#D1
      # ported from files/PicardNamingScript.txt -- see that plan's G2/G3 for the
      # divergences (dropped Classical bucket, ftintitle instead of Picard's
      # Additional Artist Variables plugin) and the real on-disk examples this
      # was checked against; G6 for the extras (art/booklets/etc.) carry-over.
      sops.templates.${beetsConfigName} = {
        owner = "beets";
        group = "beets";
        content = ''
          directory: ${libraryDir}
          library: /var/lib/beets/library.db

          plugins: inline chroma fetchart embedart scrub ftintitle duplicates missing unimported musicbrainz mbsync edit info lyrics replaygain badfiles fromfilename filefilter keyfinder autobpm

          import:
            move: yes
            copy: no
            write: yes
            autotag: yes
            quiet: yes
            quiet_fallback: skip
            timid: no
            # crash mid-batch (OOM, kill) leaves some of an entry's tracks
            # already moved into the library and the rest still in Import --
            # resuming lets beets pick back up from its own session state
            # instead of re-matching a now-incomplete remainder from scratch.
            resume: yes
            incremental: yes
            duplicate_action: skip

          acoustid:
            apikey: ${config.sops.placeholder.homelab_beets_acoustid_apikey}

          chroma:
            auto: yes

          scrub:
            auto: yes

          ftintitle:
            auto: yes

          fetchart:
            auto: yes

          art_filename: cover

          lyrics:
            auto: yes

          replaygain:
            auto: yes
            # gstreamer: already unconditionally linked into every pkgs.beets build
            # plan: 2026-09-04-homelab-beets-setup-mimicking-picard-tagging-renaming.md#G1
            backend: gstreamer

          # keeps beets from probing torrent-drop clutter (readme.txt, .cue, .log,
          # sample clips) as bogus candidate tracks during the tagging pass itself.
          # Orthogonal to the extras carry-over in the import script below -- that
          # relocates whatever's left in the source folder after import,
          # regardless of what filefilter let through as a track candidate.
          # plan: 2026-09-04-homelab-beets-setup-mimicking-picard-tagging-renaming.md#G6
          filefilter:
            path: '(?i).*\.(mp3|flac|m4a|m4b|mp4|ogg|opus|wma|wv|ape|mpc|aac|aiff?|dsf|wav)$'

          inline:
            album_fields:
              initial: >
                next((c.upper() for c in (albumartist_sort or albumartist or "") if c.isalpha()), '#')
              year_bracket: >
                '[%04d-%02d-%02d]' % (original_year or year or 0, original_month or 0, original_day or 0)
            item_fields:
              track_padded: >
                ('%02d' % track) if (tracktotal or 0) < 100 else ('%03d' % track)
              disc_prefix: >
                ('%d-' % disc) if (disctotal or 1) > 1 else ""
              feat_bracket: >
                "" if (artist or "").strip().lower() == (albumartist or "").strip().lower() else ' [%s]' % artist

          # queries soundtrack/other/single before the `comp` (Various Artists)
          # catch-all, matching PicardNamingScript.txt's override order
          # (soundtrack/other/classical checks run after and win over the single
          # check; VA is only a sub-case of its remaining "Standard" branch).
          paths:
            albumtype:soundtrack: "[Soundtracks]/${pathSuffix}"
            albumtype:other: "[Other]/${pathSuffix}"
            albumtype:single: "~ $initial ~/$albumartist_sort/[~Singles~]/${pathSuffix}"
            comp: "[Various Artists]/${pathSuffix}"
            default: "~ $initial ~/$albumartist_sort/${pathSuffix}"
        '';
      };

      # new, human-facing drop/review folders -- libraryDir needs no rule of
      # its own, hosts/homelab/configuration.nix's pre-existing
      # "A /storage - - - - group:multimedia:rwx" already covers it recursively
      # plan: 2026-09-04-homelab-beets-setup-mimicking-picard-tagging-renaming.md#F2
      systemd.tmpfiles.rules = [
        "d ${importDir} 2770 root multimedia -"
        "d ${reviewDir} 2770 root multimedia -"
      ];

      systemd.services.beets-import = {
        description = "beets: import+tag new drops from Music/Import, sweep unmatched into Music/NeedsReview";
        # matches samba.nix's samba-user-provision pattern: without this, nothing
        # guarantees the rendered config (with the acoustid key spliced in)
        # exists yet before the timer's first OnBootSec run on a slow boot.
        after = [ "sops-nix.service" ];
        wants = [ "sops-nix.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "beets";
          Group = "beets";
          StateDirectory = "beets";
          # new files/dirs beets creates default to systemd's usual 022 (world-
          # readable) otherwise -- this keeps them multimedia-group-only,
          # matching the rest of /storage's convention rather than the Picard
          # subtree's looser legacy other::r-x holdover.
          UMask = "0007";
          ExecStart = lib.getExe (
            pkgs.writeShellApplication {
              name = "beets-import-sweep";
              runtimeInputs = [
                pkgs.beets
                pkgs.findutils
              ];
              text = ''
                config_path=${lib.escapeShellArg config.sops.templates.${beetsConfigName}.path}

                move_to_review() {
                  dest=${lib.escapeShellArg reviewDir}/"$(basename "$1")"
                  if [ -e "$dest" ]; then
                    dest="$dest-$(date +%Y%m%d%H%M%S)"
                  fi
                  mv "$1" "$dest"
                }

                settle_min=5
                shopt -s nullglob
                for entry in ${lib.escapeShellArg importDir}/*; do
                  [ -e "$entry" ] || continue

                  # a symlinked top-level entry could point beet import's own
                  # directory walk at something outside Import entirely --
                  # route to review instead of ever handing it to beet.
                  if [ -L "$entry" ]; then
                    move_to_review "$entry"
                    continue
                  fi

                  # still being copied into -- catch it on a later run instead of racing it
                  if find "$entry" -newermt "-''${settle_min} minutes" -print -quit | grep -q .; then
                    continue
                  fi

                  # O(1) item-level "added since" query, not an O(library) before/after diff
                  # plan: 2026-09-04-homelab-beets-setup-mimicking-picard-tagging-renaming.md#G8
                  start_ts="$(date '+%Y-%m-%dT%H:%M:%S')"
                  beet -c "$config_path" import --quiet "$entry" || true

                  # move: yes already relocated matched audio out -- remaining files
                  # are extras (art/booklets/.cue/.log); only relocated when exactly
                  # one destination album came out of this entry
                  # plan: 2026-09-04-homelab-beets-setup-mimicking-picard-tagging-renaming.md#G6
                  new_dirs="$(beet -c "$config_path" list -f '$path' "added:''${start_ts}.." 2>/dev/null | xargs -r -I{} dirname {} | sort -u)"
                  new_dir_count=0
                  if [ -n "$new_dirs" ]; then
                    new_dir_count="$(printf '%s\n' "$new_dirs" | grep -c .)"
                  fi
                  if [ -e "$entry" ] && [ "$new_dir_count" -eq 1 ]; then
                    # -n: a genuine name collision with something beets/fetchart
                    # already wrote is left behind in $entry instead of clobbered,
                    # so it still surfaces via the review sweep below.
                    find "$entry" -type f -exec mv -n -t "$new_dirs" {} +
                    find "$entry" -depth -type d -empty -delete
                  fi

                  if [ -e "$entry" ]; then
                    if find "$entry" -type f -print -quit | grep -q .; then
                      move_to_review "$entry"
                    else
                      rm -rf "$entry"
                    fi
                  fi
                done
              '';
            }
          );
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          RestrictNamespaces = true;
          SystemCallArchitectures = "native";
          ReadWritePaths = [
            importDir
            reviewDir
            libraryDir
          ];
        };
      };

      systemd.timers.beets-import = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "5min";
          Unit = "beets-import.service";
        };
      };

      # /storage/Music/{Import,NeedsReview,Picard} are already-persistent ZFS
      # datasets (see zdata/storage/storage in hosts/homelab/configuration.nix),
      # not impermanence paths -- only the beets library db itself needs this.
      environment.persistence.${vars.persistRoot}.directories = [
        {
          directory = "/var/lib/beets";
          user = "beets";
          group = "beets";
        }
      ];
    };
}
