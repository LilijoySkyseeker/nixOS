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
      # deliberately separate from the pre-existing Picard/ tree
      libraryDir = "/storage/Music/Library";

      # shared by every bucket in `paths`; they differ only in the prefix
      pathSuffix = "$year_bracket $album%if{$albumdisambig, ($albumdisambig)}%aunique{}/$disc_prefix$track_padded $title$feat_bracket";

      beetsConfigName = "beets-config";
    in
    {
      # single-purpose account, only runs beets-import.service
      users.users.beets = {
        isSystemUser = true;
        group = "beets";
        description = "beets music tagger/importer (no shell/SSH login)";
      };
      users.groups.beets = { };
      users.groups.multimedia.members = [ "beets" ];

      sops.secrets.homelab_beets_acoustid_apikey = { };

      # renders to /run/secrets/rendered/<name> with the apikey spliced in,
      # never the nix store; ported from files/PicardNamingScript.txt
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
            # a crash mid-batch leaves an entry half-moved; resume from session state
            resume: yes
            incremental: yes
            duplicate_action: skip

          # default 0.04 rejects correct AcoustID-confirmed matches at 0.12-0.14
          match:
            strong_rec_thresh: 0.15

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
            # gstreamer: already linked into every pkgs.beets build
            backend: gstreamer

          # don't probe torrent-drop clutter (readme.txt, .cue, .log) as tracks;
          # extras are relocated separately by the import script
          filefilter:
            path: '(?i).*\.(mp3|flac|m4a|m4b|mp4|ogg|opus|wma|wv|ape|mpc|aac|aiff?|dsf|wav)$'

          # item_fields/album_fields must be top-level, not under `inline:`: the
          # inline plugin reads the global config (check with `beet fields`)
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

          # soundtrack/other/single before the `comp` (Various Artists) catch-all,
          # matching PicardNamingScript.txt's override order
          paths:
            albumtype:soundtrack: "[Soundtracks]/${pathSuffix}"
            albumtype:other: "[Other]/${pathSuffix}"
            albumtype:single: "~ $initial ~/$albumartist_sort/[~Singles~]/${pathSuffix}"
            comp: "[Various Artists]/${pathSuffix}"
            default: "~ $initial ~/$albumartist_sort/${pathSuffix}"
        '';
      };

      # drop/review folders and the library root (2770, setgid, root:multimedia)
      systemd.tmpfiles.rules = [
        "d ${importDir} 2770 root multimedia -"
        "d ${reviewDir} 2770 root multimedia -"
        "d ${libraryDir} 2770 root multimedia -"
      ];

      systemd.services.beets-import = {
        description = "beets: import+tag new drops from Music/Import, sweep unmatched into Music/NeedsReview";
        # the rendered config must exist before the timer's first run
        after = [ "sops-nix.service" ];
        wants = [ "sops-nix.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "beets";
          # process gid, not just setgid dirs (unreliable), so every new file is
          # group multimedia
          Group = "multimedia";
          StateDirectory = "beets";
          # multimedia-group-only, not systemd's default 022
          UMask = "0007";
          # "+": root for just this claim step; NFS/SMB drops arrive with the
          # dropper's umask, often owner-only and unreadable to beets
          ExecStartPre = "+${
            lib.getExe (
              pkgs.writeShellApplication {
                name = "beets-import-claim";
                text = ''
                  chown -R beets:multimedia ${lib.escapeShellArg importDir}
                  chmod -R u+rwX,g+rwX ${lib.escapeShellArg importDir}
                '';
              }
            )
          }";
          ExecStart = lib.getExe (
            pkgs.writeShellApplication {
              name = "beets-import-sweep";
              runtimeInputs = [
                pkgs.beets
                pkgs.findutils
              ];
              text = ''
                config_path=${lib.escapeShellArg config.sops.templates.${beetsConfigName}.path}
                # $HOME (/var/empty) is read-only and beets ignores -c for its app dir
                export BEETSDIR=/var/lib/beets

                move_to_review() {
                  dest=${lib.escapeShellArg reviewDir}/"$(basename "$1")"
                  if [ -e "$dest" ]; then
                    # an empty leftover from an interrupted cross-mount mv isn't a
                    # real collision: reclaim the name
                    rmdir "$dest" 2>/dev/null || dest="$dest-$(date +%Y%m%d%H%M%S)"
                  fi
                  mv "$1" "$dest"
                }

                settle_min=5
                shopt -s nullglob
                for entry in ${lib.escapeShellArg importDir}/*; do
                  [ -e "$entry" ] || continue

                  # a symlink could point beet's walk outside Import
                  if [ -L "$entry" ]; then
                    move_to_review "$entry"
                    continue
                  fi

                  # still being copied into -- catch it on a later run instead of racing it
                  if find "$entry" -newermt "-''${settle_min} minutes" -print -quit | grep -q .; then
                    continue
                  fi

                  # O(1) item-level "added since" query, not an O(library) before/after diff
                  start_ts="$(date '+%Y-%m-%dT%H:%M:%S')"
                  beet -c "$config_path" import --quiet "$entry" || true

                  # leftovers are extras (art/booklets/.cue/.log); only relocated
                  # when exactly one destination album came out of this entry.
                  # '$path' is beets format syntax, must stay single-quoted
                  # shellcheck disable=SC2016
                  new_dirs="$(beet -c "$config_path" list -f '$path' "added:''${start_ts}.." 2>/dev/null | xargs -r -I{} dirname {} | sort -u)"
                  new_dir_count=0
                  if [ -n "$new_dirs" ]; then
                    new_dir_count="$(printf '%s\n' "$new_dirs" | grep -c .)"
                  fi
                  if [ -e "$entry" ] && [ "$new_dir_count" -eq 1 ]; then
                    # -n: collisions stay in $entry and surface via the review sweep
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

      # the Music dirs are ZFS datasets; only the library db needs impermanence
      environment.persistence.${vars.persistRoot}.directories = [
        {
          directory = "/var/lib/beets";
          user = "beets";
          group = "beets";
        }
      ];
    };
}
