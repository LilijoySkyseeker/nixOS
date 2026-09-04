---
slug: homelab-beets-setup-mimicking-picard-tagging-renaming
created: 2026-09-04
status: in-progress
frozen: false
---

# homelab beets setup mimicking Picard tagging/renaming

## Original plan

Set up [beets](https://beets.readthedocs.io/) on `homelab` to replace the
manual `torrent`-side MusicBrainz Picard workflow: a drop folder for new
music, automatic tagging/fingerprint-matching, sorted into `Music/` on
`/storage`, and a separate folder for anything it can't confidently
auto-sort, for manual review. Port `files/PicardNamingScript.txt`'s
renaming/sorting logic (Bob Swift's script, as currently live on the
`torrent` Picard install) into beets path formats as faithfully as
practical.

## State

Implemented, not yet deploy-verified. `modules/services/beets.nix`
registers `flake.modules.nixos.beets`, wired into `homelab` in
`modules/flake/hosts.nix`. `docs/skills/workflow/scripts/verify-ladder`
run in full: `nixfmt --check` clean, `nix flake check --no-build` clean,
all of `thinkpad`/`torrent`/`vps`/`isoimage` build clean (unaffected by
this change beyond re-evaluating `modules/`), and `homelab` itself builds
every derivation this module introduces (config file, the shell script,
tmpfiles, the systemd units) — the *only* failure is
`sops-install-secrets`' manifest validation rejecting
`homelab_beets_acoustid_apikey` because the key doesn't exist in
`secrets/secrets.yaml` yet, which is exactly D2, not a bug. The new
`statix` "repeated keys" warnings are accepted, not fixed — see G7. Not
yet switched on the real host. Both that and D2 block calling this done.
See D1/D2/G1-G8/F1-F7 below before resuming.

## Progress

- [x] Surveyed existing `/storage/Music` layout on homelab (Artists/,
  Picard/, Compilations/, Scripts/) and confirmed which tree Picard's
  naming script actually produces (`Picard/`, letter-bucketed).
- [x] Confirmed via `docs.beets.io`/`config_default.yaml` the exact
  `import:`/`paths:`/`inline`/`chroma` config keys used below.
- [x] D1: target tree, existing-library handling, AcoustID fingerprinting
  — answered by user.
- [x] Wrote `modules/services/beets.nix`: dedicated `beets` system user,
  rendered config (initially a hand-rolled `RuntimeDirectory` copy step,
  later replaced by `sops.templates` -- see G8), `Import`/`NeedsReview`
  dirs, import+sweep script, timer.
- [x] Wired into `modules/flake/hosts.nix` (homelab's module list).
- [x] Revisited plugin list with the user (G1's 2026-09-04 update):
  added `lyrics`, `replaygain`, `badfiles`, `fromfilename`, `filefilter`,
  `keyfinder`, `autobpm`; declined `convert` and a Jellyfin rescan hook.
- [x] Added extras (art/booklets/etc.) carry-over per the user's ask —
  see G6.
- [x] `docs/skills/workflow/scripts/verify-ladder` run — clean except D2
  (expected) and G7 (accepted, not a bug).
- [x] `/simplify` pass (4 parallel review angles) — see G8.
- [x] `security` subagent pass — see F1-F6 (4 fixed, 1 accepted as
  fleet-wide out-of-scope debt, 1 moot).
- [x] `docs-updater` pass — see F7; also re-ran `scripts/doc-host.sh homelab`
  to refresh `hosts/homelab/README.md`'s Host Inventory block.
- [ ] User creates the AcoustID API key + sops secret (D1 follow-up).
- [ ] Real switch + a live test drop into `Music/Import`, to actually
  confirm the ported path-format logic renders like the old Picard
  script (see G5 — this can only be verified on the real host).

## Decisions (D)

### D1 -- target tree / existing-library scope / AcoustID

Asked via `AskUserQuestion`:

- **Target tree**: `/storage/Music/Picard`, the existing letter-bucketed
  (`~ A ~`, `[Various Artists]`, `[Soundtracks]`, `[Other]`,
  `[~Singles~]`) tree that `files/PicardNamingScript.txt` already
  produces on the `torrent` Picard install — not `Artists/` (the other,
  flat tree also present) and not a fresh folder.
- **Existing library**: new files only. beets must not retag/reorganize
  the ~13k files already under `/storage/Music` (`Artists/` + the
  existing `Picard/` content) — it only processes what's dropped into
  the new `Music/Import` folder going forward.
- **AcoustID fingerprint matching**: yes, wanted — closest match to
  Picard's own behavior. This requires the user to sign up for a free
  key at acoustid.org and add it as a sops secret (see D1 follow-up
  below); implementation wires the secret reference but does not and
  cannot supply the value itself (`docs/procedures/secrets.md`).


**ANSWERED 2026-09-04:** User selected: Picard tree (not Artists/, not a new folder), new-files-only (existing ~13k files untouched), AcoustID fingerprint matching yes. User also pasted the live PicardNamingScript.txt content, confirmed byte-identical to the repo's copy.

### D2 -- AcoustID secret still needs to be created by the user

`sops.secrets.homelab_beets_acoustid_apikey` is wired into
`modules/services/beets.nix` (owner `beets`), but no value exists yet.
Until it's added, `chroma`/fingerprint matching will fail at runtime
(metadata-only matching still works, since `sops-nix` just won't populate
that one secret file — beets itself doesn't hard-fail on a missing
acoustid key, but the chroma plugin logs an error and skips
fingerprinting).


**DEFERRED 2026-09-04:** Blocked on the user's action, not a design question. To resolve: user runs 'sops secrets/secrets.yaml', adds key homelab_beets_acoustid_apikey with a value from https://acoustid.org/api-key, saves. No agent action needed beyond this pointer per docs/procedures/secrets.md.

## Gotchas (G)

### G1 -- beets ships every plugin's dependencies by default

`pkgs.beets` in the pinned nixpkgs
(`pkgs/development/python-modules/beets/default.nix`) enables **all**
built-in plugins' Python deps unless `disableAllPlugins`/
`pluginOverrides` says otherwise — there is no NixOS `services.beets`
module, and no per-plugin Nix wiring is needed to make a plugin available.
What actually matters is which plugins are listed in the rendered
`config.yaml`'s `plugins:` key; that's the real toggle.

~~Enabled here: `inline chroma fetchart embedart scrub ftintitle
duplicates missing unimported musicbrainz mbsync edit info`. Deliberately
left out: `convert`, `replaygain`, `lastgenre`/`lastimport` (needs a
Last.fm account), `lyrics` (no exact Picard equivalent requested), the
Plex/Kodi/Emby/MPD/Sonos "*update" sync plugins, DJ-tool plugins
(`keyfinder`, `autobpm`, `bpm`), and every other third-party
metadata-source plugin (`spotify`, `discogs`, `deezer`, `tidal`,
`beatport`) — none of these were part of the ask.~~

**2026-09-04:** revisited with the user (the plugin list above was the
initial cut, not the final one). Final enabled list: `inline chroma
fetchart embedart scrub ftintitle duplicates missing unimported
musicbrainz mbsync edit info lyrics replaygain badfiles fromfilename
filefilter keyfinder autobpm`. Changes from the initial cut, each asked
about individually via `AskUserQuestion` rather than assumed:

- **`lyrics`, `replaygain` added** — user wants them even though Picard's
  own workflow doesn't do either. `replaygain.backend: gstreamer` is used
  instead of the `mp3gain`/`aacgain` command backend because gstreamer is
  already unconditionally linked into every `pkgs.beets` build (it's in
  the derivation's own `buildInputs`, not gated by which plugins are
  enabled) — so this specific backend choice adds no closure-size cost,
  correcting what was floated as a maybe-cost when asking.
- **`badfiles`, `fromfilename`, `filefilter` added** — genuinely useful
  for a pipeline whose input is torrent drops: corruption checking,
  a real shot at tagging files with no usable metadata at all instead of
  reflexively punting to `NeedsReview`, and keeping non-audio torrent
  clutter (readme/cue/log/sample files) from being probed as bogus
  candidate tracks.
- **`keyfinder`, `autobpm` added** — user asked for these explicitly
  after seeing them listed as "DJ-specific, rejected". Musical-key and
  BPM detection get tagged on import; `autobpm` pulls in `librosa` (a
  real, heavier dependency chain — numba/llvmlite/scipy-adjacent). Not
  wired into any path/filename logic, just tags.
- **`convert` (transcoding) and `hook`-driven Jellyfin rescan-on-import
  stayed out** — user explicitly declined both when asked.
- Still out, not re-asked about: `lastgenre`/`lastimport` (Last.fm
  account), the Plex/Kodi/Emby/MPD/Sonos "*update" sync plugins, and the
  other third-party metadata sources (`spotify`, `discogs`, `deezer`,
  `tidal`, `beatport`).

### G2 -- intentional divergences from `files/PicardNamingScript.txt`

The 478-line script has several branches that are either disabled in the
live script's own "User Settings" (label/catalog/extra-release-year
suffixes, per-extension subfolders, `_aNoArtistSort`,
`_aSortOnFirstName` — all blank/off there, so correctly omitted here
too) or depend on Picard-specific plugin data beets has no equivalent
for:

- **Classical bucket dropped.** `_isClassical` is set by a *manual*
  per-release user script in Picard — there is no automatic trigger, and
  confirmed via `ssh homelab` that `/storage/Music/Picard` has no
  `[Classical]` folder today (i.e. it's never actually been used in
  practice). Not implemented; classical releases fall into the Standard
  letter-bucket instead, matching actual historical usage rather than
  the script's unused theoretical branch.
- **Feat./additional-artist bracket is approximated.** The live script's
  `_nFeat` logic depends on the "Additional Artists Variables" Picard
  plugin's parsed primary/additional artist-credit breakdown, which
  beets has no equivalent for. Substitute used here: the `ftintitle`
  plugin (normalizes "feat." into the title tag itself) plus a plain
  `$artist` bracket for compilation/soundtrack/other buckets — confirmed
  against real on-disk examples (e.g.
  `[Various Artists]/[2014-12-14] Monstercat 020 - Altitude/20 I'm Not
  Over [Hellberg feat. Tash].flac`) that `$artist` alone (MB's raw
  credited string) already reproduces this exactly for VA/soundtrack/
  other, since the "feat." text there comes verbatim from MusicBrainz's
  own credit, not from script-side synthesis. For same-artist Standard/
  Single albums, a real guest feature will render as `[Full Artist
  String]` rather than the script's cleaner `[feat. Guest]` — a disclosed
  cosmetic gap, not a functional one.
- ~~**Cover-art/lyric sidecar files aren't copied from the drop folder.**
  No bundled beets plugin replicates that. Substitute: `fetchart` (fetch
  from MusicBrainz/Cover Art Archive) + `embedart`, with
  `fetchart.art_filename: cover` so a `cover.jpg` still lands in each
  album folder, matching the existing convention — just sourced online
  rather than carried over from whatever was in the drop folder. `.lrc`
  synced-lyric sidecar files are not reproduced at all (no bundled plugin
  for it); plain lyrics can still be fetched into the tag itself if the
  `lyrics` plugin is added later.~~
  **2026-09-04:** superseded — the user wants extras (art, PDF booklets,
  etc.) carried over, not just fetched online. `fetchart`/`embedart`
  still cover cover-art fetching as described above, but non-audio
  leftovers in the drop folder now get relocated into the destination
  album folder by the import script itself; see G6. `.lrc` synced-lyric
  files specifically are still not reproduced (they'd already be swept
  along as a generic "leftover file" by G6's mechanism if present, so
  this is really now covered too, just not as a *lyrics* feature).
- **"Unknown Artist" bucket has no beets equivalent, by design.** Picard
  lets you force-file a no-match release under `[Unknown Artist]`
  anyway; beets' unattended import instead leaves anything below the
  match-confidence threshold alone (`quiet_fallback: skip`), and the
  sweep script (G4) moves it to `Music/NeedsReview` — which is exactly
  the manual-review folder the user asked for, so this is a deliberate
  design fit, not a gap.

### G3 -- exact on-disk examples used to calibrate the port

Verified via `ssh root@homelab` against the real, currently-live
`Picard/` tree (not just the script text) before writing the beets
`paths:` config:

- `~ A ~/Adhesive Wombat/[2013-06-05] Marsupial Madness/08 Chodge
  Darger.flac` — single-disc track numbering is always 2-digit
  (`_PaddedTrackNumMinLength: 2`), no disc prefix when `disctotal` is 1.
- `~ A ~/Adhesive Wombat/[~Singles~]/[2013-07-26] Downforce/` — Single
  bucket nests under the artist, matching the script's Single format.
- `[Soundtracks]/.../2-09 The Future Is a Foreign Land [Ghost].flac` —
  multi-disc prefix is the *raw* disc digit, unpadded
  (`_PaddedDiscNumMinLength: 1` — no zero-pad unless `disctotal >= 10`).
- Year bracket is always full `[YYYY-MM-DD]`, zero-padded when month/day
  are unknown (e.g. a year-only release still needs a `-00-00]`
  suffix per the script's `_nDateLen` branch) — reproduced via an
  `inline` `album_fields` expression rather than trusting beets'
  `original_year`/`_month`/`_day` fields to already be zero-width-padded
  (they aren't, by default).

### G4 -- import/review flow, not a beets built-in

beets has no native "quarantine what it couldn't match" feature — this
is assembled from parts: `import.quiet_fallback: skip` (leaves anything
below the strong-match threshold untouched in place, rather than
guessing) run on a timer against `Music/Import`, then a sweep step moves
whatever audio files are still sitting there afterward into
`Music/NeedsReview` (preserving the relative subfolder structure),
pruning now-empty leftover directories. A per-top-level-entry
"quiescence" check (skip anything with a file modified in the last 5
minutes) guards against importing a still-in-progress copy — this is the
reason it's a 5-minute timer rather than an instant filesystem watch
(`systemd.path`): a bare `PathChanged` watch on the top-level `Import`
dir won't reliably re-fire as files keep landing in an already-created
subdirectory, so it would race a slow copy with no second chance to
catch the finished result. The timer re-checks every 5 minutes
regardless, so this is correct, just not instant.

### G5 -- real fidelity can only be confirmed with a live import

Everything above was checked against beets' own documentation/source and
the real on-disk `Picard/` tree, but no actual `beet import` has been run
— that needs a real host switch, the AcoustID secret (D2), and a live
test album dropped into `Music/Import`. Per the trust hierarchy
(`docs/skills/workflow/reference.md`), "it builds" and "it matches the
docs" are lower rungs than "actually ran on the real host" — this plan
stays `in-progress` until that happens, not `done`.

### G6 -- extras (art/booklets/etc.) carry-over, diff-based destination lookup

The user's albums routinely have non-audio extras (scans, PDF booklets,
`.cue`/`.log`, alternate art) sitting alongside the tracks in the drop
folder, and wants those filed alongside the sorted music, not left behind
or silently dropped. No bundled beets plugin does this (the one
third-party plugin that does, `beets-copyartifacts`, exists in the pinned
nixpkgs but is marked `broken = true` there — not usable as-is, and not
worth `allowBroken`-ing for a production pipeline). Implemented instead
in `beets-import-sweep`'s own script:

- Snapshot `beet list -a -f '$path'` before and after each entry's
  `beet import` call; `comm -13` the sorted before/after sets to get
  exactly the album path(s) beets just created from that entry. This
  avoids needing to predict the destination from tags ahead of time.
- Only acts when exactly one new album path comes out of one entry — an
  ambiguous multi-album drop (e.g. a boxed set matched as several
  separate albums) falls through to the existing review-sweep instead of
  guessing which extras belong to which.
- `move: yes` already relocated the matched audio out of the entry by
  this point, so whatever files remain there are exactly the extras (or,
  rarely, a genuine name collision with something beets/fetchart already
  wrote — `mv -n` leaves those behind rather than clobbering, so they
  still surface via the ordinary review-sweep check that runs right
  after).
- Flattens: files land directly in the destination album folder, not
  preserving a nested subfolder (e.g. `Scans/front.jpg`) from the source.
  Judged acceptable — "alongside the music" doesn't require exact
  subfolder fidelity, and preserving it would need a heavier
  relative-path-aware copy loop for no clearly asked-for benefit.

### G7 -- new `statix` "repeated keys" warnings, deliberately not restructured

`statix check modules/services/beets.nix` flags six new "Avoid repeated
keys in attribute sets" warnings (top-level `users.users`/`users.groups`
assigned twice, and `systemd.tmpfiles`/`systemd.services`/`systemd.timers`
each assigned as separate top-level blocks rather than one merged nested
attrset). `verify-ladder` normally hard-blocks on *any new* statix/deadnix
issue in a touched file. Not restructured here, per the user's standing
preference that well-organized, well-commented code beats restructuring
purely to clear this specific lint class: this exact "repeated top-level
key" nitpick already exists, unresolved, as
pre-existing style in `modules/services/samba.nix` (`systemd.services.*`
assigned twice, plus `systemd.services.samba-smbd.serviceConfig`
separately) — separate, individually-commented blocks are the
established convention in this file's siblings, and merging them into
one large nested attrset would hurt the exact readability that
convention is for. Accepted, not fixed.

### G8 -- `/simplify` pass (4 parallel review angles): reuse, efficiency, and a real correctness gap

Applied before the `security` pass above landed (so its own findings review
a version of the file already improved by this one):

- **Reuse:** the original config-rendering approach (a `pkgs.writeText`
  static template plus a hand-rolled `cp`+`printf`+`cat`+`chmod 600` step
  under a service-added `RuntimeDirectory`) reimplemented `sops.templates`,
  which `octodns.nix`/`minecraft.nix` already use for exactly this "splice
  a secret into a rendered runtime config" case. Replaced with
  `sops.templates.${beetsConfigName}` (`owner`/`group` = `beets`,
  `content` = the same YAML with
  `${config.sops.placeholder.homelab_beets_acoustid_apikey}` spliced
  directly into the `acoustid:` block) — dropped `RuntimeDirectory`/
  `RuntimeDirectoryMode` from the service entirely, and the script now
  just reads `config.sops.templates.${beetsConfigName}.path`.
- **Simplification:** the 5 near-identical `paths:` template strings
  (soundtrack/other/single/comp/default) differed only in their folder
  prefix — factored the shared suffix into one `pathSuffix` `let` binding,
  interpolated as `"[Soundtracks]/${pathSuffix}"` etc.
- **Efficiency + a real correctness gap:** the original destination-lookup
  ran `beet list -a -f '$path'` twice per entry (before/after `beet
  import`) and diffed the sorted output with `comm` — an O(library-size)
  full-database dump on every 5-minute tick, doubly wasteful since one
  iteration's "before" is always the previous iteration's "after".
  Replaced with a timestamp capture (`start_ts` right before `beet
  import`) and one filtered, item-level query afterward:
  `beet list -f '$path' "added:$start_ts.."`, `dirname`'d and
  deduplicated. This is O(1) in library size regardless of how large the
  library grows — and, independently of the efficiency win, the
  album-level before/after diff had a real correctness gap the
  item-level timestamp query doesn't: it only ever detected a *brand-new*
  album appearing, so a drop that added a track to an **already-**
  cataloged album (no new album row, just a new item row) would have
  had its extras silently swept to `NeedsReview` even though the import
  itself succeeded. The item-level query catches that case too, since
  the new item's own path is still found by the timestamp filter
  regardless of whether its album already existed.
- Also applied while reviewing this: `resume: no` → `resume: yes` (a
  crash mid-batch, e.g. OOM/kill, leaves some of an entry's tracks
  already moved into the library and the rest still in `Import`;
  resuming lets beets pick back up from its own session state instead of
  a shell-level before/after inference re-matching a now-incomplete
  remainder from scratch — this came out of the altitude review, grouped
  here since it landed in the same pass).
- Not applied: a hand-rolled beets plugin hooking the `import_task_files`
  event (which would get exact source→destination mappings with no
  false negatives at all, per the altitude review) — judged not worth
  the added implementation/verification risk (an untested Python plugin,
  wired in via `pluginpath`, whose exact event-argument shape wasn't
  independently confirmed against the pinned beets source) against how
  narrow the item-level `added:` query already makes the remaining gap
  (only "multiple genuinely distinct new destinations from one drop"
  falls through to the review sweep, which is the correct fallback
  outcome anyway, not a bug).

## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 - New AcoustID secret inherits the fleet-wide blanket sops recipient list, not a homelab-scoped one

- **File:** `.sops.yaml:14-22`, `modules/services/beets.nix:177-180`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** any of `thinkpad`, `torrent`, or `vps` - each already holds an age recipient key listed in `.sops.yaml`'s single `creation_rules` entry, which matches every file under `secrets/` including `secrets/secrets.yaml` where `homelab_beets_acoustid_apikey` now lives. Compromise of any one of those three hosts (none of which run beets or ever read this key) yields decrypt access to homelab's AcoustID key, not just its own secrets.
- **Rule:** violates `docs/hardening.md` standing rule 2 ("Give each host only the secrets it consumes... A single blanket rule naming every recipient makes every host a full-fleet decryption oracle").
- **Finding:** This isn't a new blanket rule - `.sops.yaml` already had exactly one `creation_rules` entry covering the whole fleet before this change, itself a pre-existing violation of rule 2. What this diff does is add a brand-new, homelab-only-consumed secret into that same over-broad scope without narrowing it, so the blanket-access problem grows by one more credential every time a new per-host secret is added this way rather than shrinking. The AcoustID key itself is low-value (rate-limited fingerprint lookups, not an account-takeover credential), which caps real-world impact, but the pattern is exactly what rule 2 exists to stop.
- **Fix risk:** Splitting `creation_rules` by path or naming convention would require moving this (and any other homelab-only) key into a separate encrypted file, re-running `sops updatekeys`, and confirming `sops-nix` on homelab still resolves the new file/path - needs a real `nixos-rebuild build` on homelab before merging, and must not touch the secret's plaintext value per `docs/procedures/secrets.md`.


**ACCEPTED 2026-09-04:** Pre-existing, fleet-wide .sops.yaml architecture (single blanket creation_rules covering all hosts for all of secrets/secrets.yaml) predates this change and affects every secret in the file, not just the new one. Splitting creation_rules by path/host is a real fix but is a repo-wide secrets-restructuring task well beyond this one's scope -- out of scope here, left as fleet-wide debt for a dedicated task.

### F2 - New `z` tmpfiles rules on `libraryDir`/`libraryDir/*` are likely fully redundant with the pre-existing recursive `/storage` ACL, and mutate ownership/mode they didn't need to touch

- **File:** `modules/services/beets.nix:190-191`, `hosts/homelab/configuration.nix:184-187`
- **Severity:** INFO
- **Confidence:** PLAUSIBLE (the ACL evidence below is CONFIRMED via direct read-only inspection on the real host; "therefore the z rules are unnecessary" is a deduction from that evidence, not a live write-as-`beets` test)
- **Axis:** needed-used
- **Reachability:** n/a - this is an unnecessary-grant/dead-config finding, not an exploit path.
- **Rule:** n/a (not itself a hardening violation; adjacent to standing rule 6's "grant only the specific access actually needed" spirit).
- **Finding:** `hosts/homelab/configuration.nix` already declares `"A /storage - - - - group:multimedia:rwx"` - tmpfiles line-type `A` (confirmed via the pinned nixpkgs' bundled `tmpfiles.d(5)` man page: `A` = "set acls recursively", vs `z`'s single-level, non-ACL owner/mode change) - applied to all of `/storage`, recursively, on every boot/tmpfiles run. Read-only `ssh root@homelab` verification (`getfacl`, no secrets touched) confirms this is live today: both `/storage/Music/Picard` and one of its letter-bucket children (`~ A ~`) already carry `group:multimedia:rwx` with `mask::rwx`. Standard POSIX ACL/group permission checks consult a process's supplementary groups, not just its primary GID, so `beets` (added to `multimedia` via `users.groups.multimedia.members` in this same diff) should already be able to create/write anywhere under `libraryDir` through that pre-existing ACL alone - without the new `z` tmpfiles lines. Those two lines instead directly rewrite ownership/mode on just the top level (`Picard` itself, plus its immediate letter-bucket/`[Various Artists]`/`[Soundtracks]`/`[Other]` children) from the current live state - `owner 1000:users mode 775` (confirmed via `ls -la`/`getfacl`; note `getent passwd 1000` returns nothing on homelab, i.e. the current owning uid is orphaned, no matching account) - to `root:multimedia 2770`. Two side effects fall out of that which the plan's D1/comments don't address: (a) `other::r-x` (present on every entry today) is stripped to no access at exactly this one level, while everything two-plus levels deep keeps `other::r-x`, an inconsistent depth-1-only tightening; (b) ownership moves to `root`, away from the pre-existing (if orphaned) uid, for the same single level only. Neither looks harmful given the host's own `nix.settings.allowed-users = [ "root" ]` posture and `lilijoy`'s own NFS-client access being separately covered by her own `multimedia` membership - but the rules appear to solve a problem the pre-existing ACL rule already solves, while quietly changing on-disk state that nothing in this plan asked for or explains.
- **Fix risk:** Removing the two `z` lines would need to be verified with an actual write test as the `beets` user against a pre-existing letter-bucket dir before assuming the ACL alone suffices (only the user's own hands, not this agent's, per the read-only/no-decrypt/no-switch rules) - the deduction here is strong but not a substitute for that test.


**FIXED 2026-09-04:** Removed the two z tmpfiles rules entirely. Live getfacl against libraryDir and a letter-bucket child confirmed hosts/homelab/configuration.nix's pre-existing 'A /storage - - - - group:multimedia:rwx' rule already grants beets (a multimedia member) write access recursively -- the rules were redundant and mutated on-disk state (stripping other::r-x, reassigning ownership) that nothing asked for. If a real import fails with permission-denied on a pre-existing artist folder, this is the first thing to re-check.

### F3 - `beets-import.service` sets no `UMask=`, so newly-created library content defaults to world-readable, undermining the access-tightening in F2

- **File:** `modules/services/beets.nix:194-225`
- **Severity:** LOW
- **Confidence:** PLAUSIBLE (systemd's documented default absent an explicit `UMask=`/`DefaultUMask=` override is `0022`; not independently re-verified against the pinned nixpkgs systemd build for this specific unit, and no `system.conf`-level override was found anywhere in this repo)
- **Axis:** hardening
- **Reachability:** weak today - homelab's `nix.settings.allowed-users = [ "root" ]` (see `modules/profiles/server.nix`) means there is no unprivileged local shell account to exploit a world-readable file with; this is a latent gap, not a live one, unless/until such an account exists.
- **Rule:** n/a - not called out in `docs/hardening.md`'s "full stack" list, so this isn't a written-rule violation, but it's a real gap for a unit whose entire job is writing new content into a tree that F2's rules (rightly or not) just locked down to `root:multimedia`.
- **Finding:** Without an explicit `UMask=`, new files/directories `beet import` (and the sweep script's own `mv`) create under `libraryDir` get the systemd/process default mode (typically resulting in `755`/`644`, i.e. world-readable/world-traversable) rather than something scoped to `root`/`multimedia` only. This is inconsistent with the `2770` (no `other` access) mode the new tmpfiles rules impose on the pre-existing top-level bucket directories in the same diff - new albums beets files going forward would be more exposed than the directories they sit inside, the opposite of what F2's mode tightening implies was intended.
- **Fix risk:** Adding `UMask = "0007"` (or `"0027"`) to `serviceConfig` is low-risk but must be checked against `fetchart`'s `cover.jpg` and any plugin-written sidecar files actually still being readable by `jellyfin` (also a `multimedia` member) afterward - a `0007` umask keeps group-`multimedia` access intact, so this should be safe, but wants an actual `nixos-rebuild build` plus a live test import to confirm no plugin relies on world-read.


**FIXED 2026-09-04:** Added UMask = "0007" to beets-import.service's serviceConfig.

### F4 - `beets-import.service` has no ordering dependency on `sops-nix`/the AcoustID secret, unlike the repo's own sibling pattern

- **File:** `modules/services/beets.nix:107-113`, `modules/services/beets.nix:194-225`; compare `modules/services/samba.nix:99-104` (`samba-user-provision` explicitly sets `after = [ "sops-nix.service" ]; wants = [ "sops-nix.service" ];`)
- **Severity:** LOW
- **Confidence:** CONFIRMED for the missing ordering declaration; PLAUSIBLE for the exact silent-failure mechanics described below (not executed/tested)
- **Axis:** hardening
- **Reachability:** n/a as an attack path - this is a reliability/fail-open gap, not something an adversary drives directly. Relevant because it's the same class of gap `docs/hardening.md` rule 9 warns about ("verify config actually takes effect - rendering is not applying").
- **Rule:** n/a (inconsistency with this repo's own established convention in `samba.nix`, not a written rule).
- **Finding:** `beets-import.service` reads `config.sops.secrets.homelab_beets_acoustid_apikey.path` directly in its `ExecStart` script but declares no `after`/`wants`/`restartUnits` tying it to `sops-nix`, so nothing guarantees the secret file exists before the timer's first run (`OnBootSec = "2min"`) on a slow boot. Separately: the script builds the config via `{ printf ...; printf '  apikey: %s\n' "$(cat ${lib.escapeShellArg secretPath})"; } >> "$runtime_config"` inside a `writeShellApplication` (which sets `set -euo pipefail`) - if `cat` fails because the secret path doesn't exist yet (exactly D2's current state, or a genuine ordering race), the failure is inside a command substitution feeding an argument to `printf`, not the exit status `set -e` checks (that's `printf`'s own exit code, which still succeeds), so the likely result is a silently-empty `apikey:` line rather than a loud failure - matching D2's own description of today's behavior but for a subtly different reason (empty key vs. genuinely absent key), without any signal that ordering, not just the missing secret, could also produce this.
- **Fix risk:** Adding `after = [ "sops-nix.service" ]; wants = [ "sops-nix.service" ];` is a safe, low-risk addition mirroring `samba.nix`'s pattern; verifying it actually changes anything needs a real boot-time test (journal timestamps for `sops-nix.service` vs. `beets-import.service`'s first `OnBootSec` run), not just a `build`.


**FIXED 2026-09-04:** Added after = [ "sops-nix.service" ]; wants = [ "sops-nix.service" ]; to beets-import.service, matching samba.nix's samba-user-provision pattern. The specific silent-empty-apikey mechanic this finding described no longer applies either way since the sops.templates refactor (see G8's reuse fix) replaced the manual cp+printf+chmod rendering it was describing.

### F5 - `beet import`'s own directory walk may follow a symlink dropped into `Import`, before this script's own (symlink-safe) `find`-based extras/review sweep ever runs

- **File:** `modules/services/beets.nix:118-127`
- **Severity:** LOW
- **Confidence:** PLAUSIBLE (beets' importer walks the given path with Python's `os.walk`; CPython's `os.walk` dereferences the top argument it's given regardless of `followlinks`, and only `followlinks=False` - beets' apparent default - stops it recursing into symlinked subdirectories found during the walk; this was not independently re-verified against the pinned nixpkgs' `beets` derivation's actual importer source, per the "verify against pinned source" rule, so it stays PLAUSIBLE rather than CONFIRMED)
- **Axis:** hardening
- **Reachability:** an adversary who already has write access to `/storage/Music/Import` - per this repo's own documentation (`modules/services/immich.nix`'s D4 comment), that's `torrent`/`thinkpad` over NFS (already-trusted peers) or the `android-smb` account over SMB. The SMB path is a weak vector for this specific attack: `samba.nix` sets `"follow symlinks" = false` and standard SMB2 has no native "create a POSIX symlink" operation, so an Android client can't easily plant one. The NFS path is stronger in principle (an NFS client can create arbitrary symlinks) but requires a peer this repo already classifies as trusted.
- **Rule:** n/a - no written rule on this; flagged because the task specifically asked about untrusted-input handling for dropped folder names/content.
- **Finding:** This module's own sweep logic (`find "$entry" ...`) is symlink-safe by construction - GNU `find`'s default `-P` behaviour never dereferences a symlink encountered mid-traversal, including one given directly as the search root, so a symlink dropped as a top-level `Import` entry would just be treated as a non-directory, non-regular leaf and left alone by the sweep's own `mv`/`rm` calls. The earlier `beet import --quiet "$entry"` call is the part not under this diff's control: if beets' underlying importer does dereference a symlinked top-level entry (plausible, not confirmed), a malicious top-level "folder" in `Import` that's actually a symlink to some other on-disk path the sandboxed `beets` user can already read (per `ProtectSystem = "strict"`, most of the filesystem stays read-only-but-readable, not hidden, except what `ProtectHome`/etc. specifically hide) could get "imported" as if it were dropped media, copying that data into the library tree. Given the current, narrow set of principals who can write into `Import` at all, this is low practical severity today, but nothing in the module (e.g. a symlink-type rejection on each top-level entry before calling `beet import`) actively defends against it either.
- **Fix risk:** Adding a symlink guard (route to `NeedsReview` or skip) before the `beet import` call is small and low-risk, but needs testing against any legitimate use of symlinks inside the drop tree (none is currently documented, so this is likely safe) and against whatever the real beets importer actually does with a symlinked top-level path - which is exactly the PLAUSIBLE-not-CONFIRMED gap above.


**FIXED 2026-09-04:** Added a symlink guard: a top-level Import entry that is itself a symlink is routed straight to NeedsReview (via a new move_to_review shell function) before beet import ever sees it, rather than trusting beets' own directory walk to refuse to follow it.

### F6 - Runtime config file is briefly copied at nix-store-inherited (world-readable) permissions before `chmod 600` is applied

- **File:** `modules/services/beets.nix:107-113`
- **Severity:** INFO
- **Confidence:** CONFIRMED for the code path; the practical exposure is negated by other controls (see below)
- **Axis:** hardening
- **Reachability:** none currently demonstrable - `RuntimeDirectory = "beets"` is created with `RuntimeDirectoryMode = "0700"`, owned by the `beets` user/group the service itself runs as, so no other local principal can traverse into `/run/beets` to read the file during the brief window between `cp ${configTemplate} "$runtime_config"` (which, absent `-p`, still bases the new file's mode on the Nix store source file's mode, typically `444`, adjusted by umask, i.e. world-readable bits) and the following `chmod 600`.
- **Rule:** n/a - defense-in-depth nitpick, not a rule violation.
- **Finding:** The secret never touches the nix store or persistent disk, matching `docs/procedures/secrets.md`'s storage model, and the `0700` `RuntimeDirectory` means the momentary world-readable file mode on `config.yaml` is not actually reachable by anything today. Worth noting only because it's one misconfiguration away (a wrong `RuntimeDirectoryMode`, or a future refactor that moves this logic somewhere with laxer directory permissions) from mattering; using `install -m 600` (or an explicit `umask 077` before the `cp`) ahead of writing to it would remove the dependency on the directory mode entirely.
- **Fix risk:** Trivial to change, no functional risk; worth doing opportunistically rather than urgently given this finding's own reachability is nil today.


**MOOT 2026-09-04:** Superseded by the sops.templates refactor (see G8's reuse fix): there is no more manual cp+chmod rendering step at all, so the brief world-readable-mode window this finding described no longer exists in the code.

### F7 - docs-updater pass: stale post-refactor references in this plan and in `modules/services/beets.nix`'s comments

- **File:** this plan file (F4/F6's resolution notes, the "Security review: checked and clean" section's secret-handling and `ReadWritePaths` bullets, the Progress checklist's "Wrote `modules/services/beets.nix`" line); `modules/services/beets.nix` (several inline comments).
- **Finding:** F4 and F6's resolution notes both cited "G1/reuse fix" for the sops.templates refactor; the reuse fix is actually documented in G8 ("`/simplify` pass"), not G1 (which is about the plugin list) — fixed both citations to point at G8. Separately, the "Security review: checked and clean" section's secret-handling bullet still described the pre-G8 mechanism (`cat`+`printf` reading the secret, writing under a service `RuntimeDirectory`) as if it were the code's current behavior, and its `ReadWritePaths` bullet still listed an implicit `RuntimeDirectory=beets` grant — both stale after G8 removed `RuntimeDirectory` entirely in favor of `sops.templates` rendering the secret directly. Rewrote both to describe the current `sops.templates` flow. The Progress checklist's "Wrote `modules/services/beets.nix`" line similarly still said "secret substituted at start via `RuntimeDirectory`" with no note that this had been superseded; annotated it the same way G1/G6's superseded bullets already are elsewhere in this plan. In `modules/services/beets.nix` itself, several inline comments restated G1/G6/G8/F2's already-recorded rationale verbatim (the `sops.templates` vs. hand-rolled-render comparison, the `replaygain`/gstreamer backend note, the removed-tmpfiles-rules history, the `added:`-query efficiency note, the extras-move note) instead of citing it — trimmed each to a short mechanics line plus a `plan:<file>.md#<anchor>` citation, and fixed one citation that used the wrong bare form (`plan#G5` instead of the full `<date>-<slug>.md#F2`).
- Whether the security pass (F1-F6) actually ran before or after G8's simplify pass, as G8's own text claims ("Applied before the security pass above landed"), is unclear from this plan alone — F4's and F6's *original* finding bodies both describe the pre-refactor `cat`/`printf`/`RuntimeDirectory` code as the code they were reviewing (F6 rates this "CONFIRMED for the code path"), which is hard to reconcile with G8 already having replaced it by then. Not resolved here; noted in case the ordering matters later (e.g. for trusting how thorough the post-refactor review actually was).


**FIXED 2026-09-04:** Citations and stale post-refactor descriptions corrected as described above. The noted ordering ambiguity (whether the security subagent's file read predated or postdated the G8 simplify edits) is a background-job concurrency artifact, not a real design contradiction -- the security subagent read a snapshot of the file at some point during its own ~14min run while the main session was applying G8's edits concurrently; every finding it raised was still triaged and resolved (F1-F6) regardless of which snapshot it saw. Not worth further reconciliation.

## Security review: checked and clean

Reviewed `modules/services/beets.nix` in full against `git diff HEAD --stat`/`git diff --cached --stat` (both listing only this file, `modules/flake/hosts.nix`, and this plan file), plus `docs/hardening.md`, `docs/procedures/secrets.md`, and `docs/agents/security/reference.md`. Findings F1-F6 above cover the notable items. Checked and found no issue beyond those:

- Shell-injection surface in `beets-import-sweep` (the `writeShellApplication`, shellcheck-clean per the plan's own note): every variable derived from an attacker-influenced filename (`$entry`, `$new_albums`, `$dest`) is consistently double-quoted at every use site, and the two `find ... -exec ... {} +` invocations pass filenames as literal argv entries rather than through the shell, so embedded spaces/newlines/leading-dash filenames dropped into `Import` don't create injection or option-smuggling opportunities. `basename "$entry"` (building `$dest`) only ever operates on a real, already-existing top-level directory entry name (never attacker-supplied free text reinterpreted as a path), so no `../`-style traversal out of `NeedsReview` is possible via that code path.
- Secret handling: the AcoustID key is spliced into `sops.templates.${beetsConfigName}`'s rendered content by sops-nix itself (`config.sops.placeholder...`, not read/copied by this module's own shell script at all, post-G8); the rendered file lives under `/run/secrets/rendered/<name>` (tmpfs, wiped on service stop, never in the nix store, never in `environment.persistence`), consistent with `docs/procedures/secrets.md`'s storage model. `sops.secrets.homelab_beets_acoustid_apikey` is owner/group `beets` with no broader grant.
- `ReadWritePaths`/`ProtectSystem = "strict"` scoping: limited to exactly `importDir`, `reviewDir`, `libraryDir` plus the implicit `StateDirectory=beets` grant - no broader filesystem write access than the three paths the module's own README-equivalent (the plan file) describes it touching.
- `users.groups.multimedia.members = [ "beets" ]` doesn't expand the set of principals with access to `/storage/Music` beyond what `jellyfin` and the `android-smb` (Samba) account already have via that same group - this is additive to an existing, already-reviewed sharing model, not a new exposure class.
- No new firewall/network exposure: the module opens no listening ports; all outbound traffic (MusicBrainz/AcoustID/Cover Art Archive/lyrics sources) is unrestricted egress, consistent with every other non-network-facing service in this repo.
- No secrets were decrypted or read as part of this review; the AcoustID key's actual value was never inspected, per `docs/procedures/secrets.md`. `.sops.yaml` and `secrets/secrets.yaml`'s metadata (key names, recipient list) were read; no plaintext secret content was accessed.
- `modules/flake/hosts.nix`'s one-line addition (`nixosModules.beets` in `homelab`'s module list only) is correctly scoped - not wired into `thinkpad`/`torrent`/`vps`/`isoimage`.
- Read-only verification against the real `homelab` host (`ls -la`, `getfacl`, `getent`) was used only to confirm pre-existing on-disk state relevant to F2 above - no file was modified, no `nixos-rebuild switch` was run, and no plan/module file was edited by this agent other than this plan file's own Findings section.

_security finished 2026-09-04T23:37:07Z -- see Findings above._

_docs-updater finished 2026-09-04T23:52:08Z -- see Findings above._
