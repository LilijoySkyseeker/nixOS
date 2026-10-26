# Tighten Minecraft's mod supply

## Goal

Keep auto-updating (AR-7) but shrink what one bad or lagging mod can do.

## Your decisions

- 2026-08-27: keep the server auto-updating with its mods (AR-7).

## State

Not started. `--memory` and `--pids-limit` ceilings and userns-remap are
in place.

## Next

1. Owner: which of the mods are load-bearing for the world (geyser and
   floodgate almost certainly; a mapper or client-perf mod maybe not).
   Mark the rest optional with a `?` suffix, which also drops them from
   `VERSION_FROM_MODRINTH_PROJECTS`, so one lagging mod stops pinning the
   whole server to an old version.
2. Pin by version (`project:versionId`) any mod that has broken a world.
3. Record once what `MODRINTH_DOWNLOAD_DEPENDENCIES = "required"`
   resolves to, since those transitive mods appear nowhere in the repo.
