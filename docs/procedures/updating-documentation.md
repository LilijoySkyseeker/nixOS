# Updating documentation

How to keep `AGENTS.md`, `README.md`, `docs/`, the `hosts/*/README.md`
files, and commit messages from drifting away from what the repo actually
does. There's no automation enforcing any of this — it's discipline, backed
by this checklist. (There are no per-module-folder READMEs — `modules/`,
`profiles/`, `services/`, `secrets/` don't have their own; only the five
`hosts/<name>/README.md` files and the root `README.md` exist.)

## Routine changes (most commits)

Update docs in the same commit as the code change, not as a follow-up:

- **Added, removed, or renamed a host** — update `docs/architecture.md`'s
  per-host table and the root `README.md`'s Hosts table together; they
  should never disagree. Give the new host its own `hosts/<name>/README.md`
  if it has anything host-specific worth recording (see the existing ones
  for shape).
- **Changed something host-specific worth remembering later** (an incident,
  a gotcha, a deploy quirk) — record it in that host's own
  `hosts/<name>/README.md`, not a shared doc.
- **Discovered a non-obvious cross-cutting gotcha** while making a change
  (an ordering dependency, a footgun, a "don't do X here, do it in Y
  instead") — add it to `docs/architecture.md`'s Gotchas section if it's
  about the module system, or the relevant procedure doc otherwise.
- **Made a decision future-you will re-derive from scratch otherwise** (a
  workaround, a surprising constraint, a fix for a specific incident) —
  record it in the commit message, per
  [`docs/style-guide.md`](../style-guide.md); split into multiple commits
  if different pieces of the change need different rationale.
- **Discovered a stale reference** (a folder, file, or command that no
  longer exists but is still described somewhere) — fix it immediately if
  it's a one-line change; if it's bigger, log it to `TODO.md` rather than
  leaving it.

If a change doesn't fall into any of the above, it probably doesn't need a
doc update. Don't pad a doc to have something to show.

## Root `README.md` and `AGENTS.md`

These two are the front door, not general-purpose docs, so they get a
narrower trigger than the rest — don't let every small change bleed into
them.

- **`README.md`**: update the Hosts table when a host is added, removed, or
  its role/purpose changes. Update the Layout section only if the top-level
  directory structure itself changes. The Interesting stuff section is
  curated, not comprehensive — add to it only when something genuinely
  worth showing off lands (ask before adding on the user's behalf if it's
  not obvious), and don't let it grow into a changelog.
- **`AGENTS.md`**: it's a map, not a reference — a docs table plus the
  handful of rules that matter most (see `docs/agents.md` for why it's kept
  this lean). Update it when a doc moves/is added/is removed (keep the
  table accurate), a command changes (new lint tool, a build command's
  flags change), or a new hard-confirm rule is established. If a change
  needs more than a couple of sentences to explain, that detail belongs in
  `docs/` with a link from `AGENTS.md`'s table, not inline in `AGENTS.md`
  itself.

## Flag issues immediately, don't let them sit

Whenever a documentation issue is *noticed* but isn't being fixed right
now — spotted mid-task, out of scope for the current change, or too large
to fix inline — log it to `TODO.md`'s Active section immediately, the same
session it was found in. Don't rely on memory or a mental note. Include:

- What's stale or wrong, and where (file + what it currently says).
- What triggered noticing it (what you were actually doing when you found
  it).
- Enough context that fixing it later doesn't require re-discovering the
  problem from scratch.

## Periodic audit (narrative docs)

`docs/architecture.md` and `docs/style-guide.md` describe things at a level
no single commit's diff naturally forces an update to — they need an
occasional deliberate check, not just change-with-code discipline. There's
no fixed schedule; do this opportunistically when:

- A conversation surfaces a discrepancy between what one of these docs says
  and what the repo actually does.
- A host's role, nixpkgs channel, or profile composition changes in a way
  that isn't purely additive.
- It's been a long time since either file was touched and a change session
  happens to already be reading through them for other reasons.

The check itself: re-read the doc against the current
`modules/flake/hosts.nix`/`hosts/*/configuration.nix`/`modules/profiles/*.nix`,
and fix whatever's drifted. Log what was found and fixed in `TODO.md` if it
was non-trivial, so there's a record of when the last audit happened and
what it caught.

## After a big refactor

A refactor that changes the shape of the repo — not just what's in a file,
but which files/folders exist and how they compose — makes the routine
per-commit updates insufficient, because the *structure* the docs describe
has changed, not just its contents. Examples: splitting `modules/profiles/`
into more/fewer roles, changing how hosts are pinned across nixpkgs
channels, restructuring the secrets layout, or (already happened once, see
`TODO.md`'s 2026-08-20 entry) migrating the whole composition mechanism, as
the dendritic flake-parts + import-tree migration did.

When that happens, don't patch `docs/architecture.md` piecemeal — redo it
properly:

1. **Re-survey the repo from scratch**: read the actual `flake.nix`/
   composition entry point, every `hosts/*/configuration.nix`, every
   module-organization file, and the new folder structure, rather than
   editing the old doc's assumptions in place.
2. **Rewrite `docs/architecture.md`'s composition-mechanism, per-host
   table, and module-organization boundary sections** to match the new
   structure — don't leave old sections half-updated.
3. **Re-check `docs/style-guide.md`** for conventions the refactor
   invalidated (e.g. if the `my<Name>` options-module convention changed,
   or the module/service split criterion moved).
4. **Update `AGENTS.md`'s docs table** if any doc was added, removed, or
   renamed by the refactor.
5. **Update the root `README.md`'s Hosts table and Layout section** if the
   refactor changed either.
6. **Log the rewrite in `TODO.md`** so there's a dated record of when the
   docs were last brought back in sync with a structural change, for the
   next person (or the next refactor) to check against.
