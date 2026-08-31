---
slug: prune-unvisited-minecraft-chunks-for-terrain-regen-on-current-version
created: 2026-08-31
status: todo
frozen: false
---

# Prune unvisited Minecraft chunks for terrain regen on current version

## Original plan

Homelab's `minecraft-vanilla-plus` world (`modules/services/minecraft.nix`)
was created on an old Minecraft version and has large areas of terrain
generated under old world-gen. Delete chunks that show no meaningful
player presence so they regenerate under the *current* version's terrain
generator the next time a player (or the DistantHorizons LOD system)
approaches them, without touching hand-built/explored areas.

**2026-08-31 addition:** the eventual execution should be a human-runnable
script, not a one-off sequence of commands typed by hand from this file --
this is the kind of operation that's plausible to want again after a
future version bump, and a script also removes the chance of fat-fingering
a path or flag when actually running the destructive steps. See D4.

## State

**2026-08-31, investigation and dry run complete, execution deliberately
paused.** User asked to cancel the live/destructive part for now and
record everything learned for a future session. All recon below was run
read-only against a live ZFS snapshot clone -- the running server
(`docker-minecraft-vanilla-plus.service`) was never stopped and is still
up, uninterrupted, as of this writing.

Resuming this plan later just means: answer D1-D3, then run the four
commands under "Ready-to-run destructive steps." Everything else
(tool choice, exact paths, syntax, backup method) is already verified
against this specific host, not assumed.

One perishable detail: the downloaded jar and CSV selection files live
under `/tmp/mcaselector-work` on homelab, which will not survive a reboot
(see G7) -- check they're still there before reusing the exact commands
below verbatim.

## Progress

- [x] Identify the tool: `mcaselector` (Querz/mcaselector), verified
      against its actual GitHub wiki/issues rather than assumed (G6)
- [x] Confirm actual world layout on homelab (G1)
- [x] Confirm `xvfb-run` is NOT needed on this host/JDK (G2)
- [x] Get real chunk counts via dry run against a live snapshot clone (G3)
- [x] Identify the InhabitedTime blind spot from scarpet scripts (G4)
- [x] Confirm the right backup mechanism to use (G5)
- [ ] D1 -- pick the InhabitedTime threshold
- [ ] D2 -- confirm a safe downtime window
- [ ] D3 -- decide whether to prune nether/end too
- [ ] D4 -- decide the repeatable script's location/form
- [ ] Write the human-runnable script per D4
- [ ] Execute the destructive steps (stop server, snapshot, delete, restart)

## Decisions (D)

### D1 -- what InhabitedTime threshold to prune at?
Dry run (2026-08-31) showed `InhabitedTime < 100` matches **113,193
chunks** out of 4356 region files (1.3G of overworld region data alone).
That's a large fraction of the map -- worth reviewing the selection
against the world's BlueMap render (G4) before committing to a number,
rather than trusting the threshold blind.
~~DISCUSSED 2026-08-31: options laid out (see G3 for the raw numbers),
user paused the whole operation before picking a value.~~ (hand-written by
mistake, not via `plan-decide` -- superseded by the marker below)

**DISCUSSED 2026-08-31:** Options laid out with real numbers (113,193 chunks at <100 ticks); user paused before picking a value.

### D2 -- when is it safe to take the live server down?
No join/leave events in the last 2h of container logs as of 2026-08-31
15:xx PDT, but that doesn't rule out someone already connected before
that window. Needs an explicit go-ahead from a moment with confirmed-zero
players, since the DNAT'd public port means non-Tailscale friends can be
on it too.
~~DISCUSSED 2026-08-31: flagged as a blocker before stopping the
container; user paused the operation before confirming a window.~~
(hand-written by mistake, not via `plan-decide` -- superseded below)


**DISCUSSED 2026-08-31:** Flagged as a blocker before stopping the container; user paused before confirming a window.

### D3 -- prune nether/end too, or overworld only?
The original ask was about "new terrain" generally; overworld is the
highest-value target and was the only dimension dry-run so far. Nether/end
region paths are already confirmed (G1) if this is wanted later:
`world/dimensions/minecraft/the_nether/region`,
`world/dimensions/minecraft/the_end/region`.
~~DISCUSSED 2026-08-31: raised as an option, not decided before pausing.~~
(hand-written by mistake, not via `plan-decide` -- superseded below)


**DISCUSSED 2026-08-31:** Raised as an option, not decided before pausing.

### D4 -- where should the repeatable script live, and in what form?
User asked (2026-08-31) for the destructive steps to become a
human-runnable script rather than hand-typed commands, since this is
plausible to want again after a future version bump. Open: does it live
in this dotfiles repo (e.g. under a `scripts/` dir, checked in like other
admin tooling) or just as a standalone file on homelab; does it take the
threshold/dimension/selection-file as arguments or prompt interactively;
does it fold in the snapshot-before and dry-run-first steps automatically
or still require a separate confirm step before the actual delete.
Not yet answered.

## Gotchas (G)

### G1 -- world layout is not the classic region/DIM-1/DIM1 layout
All three dimensions -- including the vanilla overworld/nether/end, not
just custom ones -- live under
`world/dimensions/minecraft/{overworld,the_nether,the_end}/region`. The
legacy `world/DIM-1` and `world/DIM1` folders exist but only contain a
`data` subfolder, no actual chunk data. Point mcaselector's `--world` flag
directly at the dimension folder (e.g.
`.../dimensions/minecraft/overworld`), not the top-level `world/` folder --
confirmed working this way.

### G2 -- mcaselector CLI mode is NOT actually broken headless on this host
Upstream has an open, unresolved issue (Querz/mcaselector#465, "CLI mode
isn't headless: Unable to open DISPLAY") with no documented maintainer fix.
Tested directly on homelab: plain `java -jar mcaselector-2.8.jar --mode
select ...` via `nix-shell -p jdk21` ran clean with no display attached,
no `xvfb-run` wrapper, no crash (OpenJDK 21.0.12, nixpkgs). Don't reflexively
reach for `xvfb-run` for this tool/host combo -- plain `java` already works
here.

### G3 -- real chunk counts from the 2026-08-31 dry run
Run against a read-only mount of ZFS snapshot
`zroot/local/state@zrepl_20260831_222645_000` (5 minutes old at the time),
not the live world:
- `--query "InhabitedTime < 100"` on the overworld -> **113,193 matched
  chunks**
- Region file count: 4356 (this is what the progress bar's denominator
  tracks -- it is not a chunk count, easy to misread)
- Overworld region data: 1.3G; nether: 124M; end: 206M
113,193 is a large share of the map for a single threshold value -- treat
this as a "check before you commit," not a green light to just run it.

### G4 -- InhabitedTime blind spot: scarpet scripts / command-driven builds
This world has a live `scripts/` folder (Carpet scarpet scripts) and
build-adjacent mods (e.g. easy-shulker-boxes). Anything placed via a
script or command rather than by a player physically standing there won't
accumulate `InhabitedTime`, so it can get flagged for deletion despite
being a real, intentional build (a pre-generated highway, a farm laid out
by script, etc). BlueMap is already installed and rendering this world
(`/srv/minecraft/vanilla-plus/bluemap/web`) -- cross-check the mcaselector
selection against that render before running the real delete; don't trust
`InhabitedTime` alone for a world with scripted building history.

### G5 -- backup mechanism: use the existing zrepl snapshots, not a manual copy
`/srv/minecraft/vanilla-plus` is not its own ZFS dataset -- it's a
bind-mounted subdirectory inside the shared `zroot/local/state` dataset
(44G total, also holds other services' persisted state). That dataset is
already snapshotted every 5 minutes by zrepl (`/etc/zrepl/zrepl.yml`,
`snapshotting.interval: 5m`) and replicated offsite to `thinkpad` every 15
min. Take one more clearly-labeled manual snapshot immediately before the
real delete:
```
zfs snapshot zroot/local/state@pre-chunk-prune-<date>
```
instant and free -- no need for a slow `cp -a` of the 28G world.
**Rollback:** mount that snapshot read-only elsewhere (same technique used
for the dry run) and copy back just the `srv/minecraft/vanilla-plus/world`
subtree. Never `zfs rollback` this dataset -- that would also roll back
every other service sharing `zroot/local/state`.

### G6 -- exact mcaselector CLI syntax (verified against the project wiki)
```
--mode select --world <dir> --query "<filter>" --output <csv>
--mode delete --world <dir> --query "<filter>"
--mode delete --world <dir> --selection <csv>
```
No built-in backup flag exists in mcaselector itself -- see G5 for the
actual backup path. Jar: `mcaselector-2.8.jar`, downloaded from
`https://github.com/Querz/mcaselector/releases/download/2.8/mcaselector-2.8.jar`.

### G7 -- work files on homelab are in `/tmp`, not durable
`/tmp/mcaselector-work/mcaselector-2.8.jar` and
`/tmp/mcaselector-work/sel-overworld.csv` (the saved selection from the
2026-08-31 dry run) will not survive a reboot of homelab. Re-download the
jar and re-run the `--mode select` dry run if they're gone by the time
this plan is resumed.

## Ready-to-run destructive steps (blocked on D1-D3)

Everything above was read-only. These four steps are the actual live
operation, run on homelab as root:

```bash
# 1. fresh labeled snapshot right before touching anything
zfs snapshot zroot/local/state@pre-chunk-prune-<date>

# 2. stop the running server (systemd owns restarts -- use the unit, not `docker stop`)
run0 systemctl stop docker-minecraft-vanilla-plus.service

# 3. delete, reusing the exact selection already computed in the dry run (G3),
#    or re-run --mode select first if sel-overworld.csv is gone (G7)
java -jar /tmp/mcaselector-work/mcaselector-2.8.jar --mode delete \
  --world /srv/minecraft/vanilla-plus/world/dimensions/minecraft/overworld \
  --selection /tmp/mcaselector-work/sel-overworld.csv

# 4. restart
run0 systemctl start docker-minecraft-vanilla-plus.service
```

Repeat step 3 against `world/dimensions/minecraft/the_nether` /
`the_end` (per D3) if those dimensions are wanted too -- rerun `--mode
select` against each first to get a dimension-specific selection CSV.

## Findings (F)
*(populated by security/docs-updater when invoked)*
