---
slug: tighten-minecraft-factorio-mod-supply-auto-update-
created: 2026-08-27
status: todo
frozen: false
---

# Tighten Minecraft/Factorio mod-supply auto-update (three items)

## Original plan

- [ ] **2026-08-27: the three Minecraft/Factorio mod-supply tightenings
      that survive auto-update.** D14 was answered "keep auto-updating"
      and the risk is accepted in `docs/accepted-risks.md` AR-7 — but
      three things can still be tightened *without* giving up
      auto-update, and none was done yet. All three need a start-and-play
      check, which is why they are here rather than done.

      1. **Mark non-critical projects optional with a `?` suffix.**
         Upstream supports `pl3xmap?`, and optional projects are
         **excluded from the `VERSION_FROM_MODRINTH_PROJECTS`
         calculation** — so one lagging mod stops holding the whole
         server on an old Minecraft version, and merely warns instead of
         aborting startup when it has no compatible build. This is the
         highest-value one: it directly serves the "track the newest
         stable automatically" goal, because today *any single* mod of
         the sixteen can pin the server indefinitely. Needs a judgement
         call per mod on what is actually load-bearing for the world
         (e.g. geyser/floodgate almost certainly are; a mapper or a
         client-perf mod may not be), which is the user's call, not an
         agent's.
      2. **Pin individual projects by version** where a specific mod
         matters more than its freshness — syntax is `project:versionId`
         or `project:2.21.2`, and it composes with `?`. Worth doing for
         anything that has broken a world before.
      3. **Reconsider `MODRINTH_DOWNLOAD_DEPENDENCIES = "required"`.**
         It pulls transitive artifacts that appear nowhere in this repo,
         so the actual installed set is larger than the sixteen listed
         projects and is not visible from the config. At minimum, record
         what it actually resolves to once, so there is a baseline.

      Related but separate, already tracked above: ~~the containers still
      have no `--pids-limit`/`--memory` ceilings, and~~ `userns-remap` is
      unset. *(F-P4-03, F-P4-13, AR-7)*

      **2026-09-04:** `--memory`/`--pids-limit` ceilings (D15) are already
      set on both containers (`modules/services/minecraft.nix`,
      `modules/services/factorio.nix`) — struck through above as stale.
      Only `userns-remap` is still genuinely unset.

## State

Not started. D1 (which mods are load-bearing) is the blocker for item 1;
items 2-3 can proceed independently. `--memory`/`--pids-limit` ceilings
are already landed (D15) and out of scope here; only `userns-remap`
remains genuinely open on the container-hardening side.

## Progress

- [ ] Mark non-critical projects optional with `?` (excludes them from VERSION_FROM_MODRINTH_PROJECTS, so one lagging mod stops pinning the whole server -- highest-value item, needs D1 first).
- [ ] Pin individual projects by version (`project:versionId` or `project:2.21.2`, composes with `?`) where freshness matters less than stability, for anything that's broken a world before.
- [ ] Reconsider `MODRINTH_DOWNLOAD_DEPENDENCIES = "required"` -- record what it actually resolves to once (transitive artifacts appear nowhere in this repo), so there's a baseline.

## Decisions (D)

### D1 -- which of the sixteen mod-supply projects are actually load-bearing for the world, vs. safe to mark optional (`?` suffix)?
A judgement call per mod on what's genuinely load-bearing (geyser/floodgate almost certainly are; a mapper or client-perf mod may not be) -- explicitly the user's call, not an agent's, since it depends on what the world actually needs.

## Gotchas (G)

### G1 -- this doesn't reopen the auto-update-vs-pin decision
D14 already answered "keep auto-updating" and the risk is accepted in docs/accepted-risks.md AR-7 -- these three items tighten the blast radius without giving up auto-update, they don't relitigate it.

## Findings (F)
*(populated by security/docs-updater when invoked)*
