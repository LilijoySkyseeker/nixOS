# Updating documentation

How to keep `docs/`, the per-folder READMEs, and inline comments from
drifting away from what the repo actually does. There's no automation
enforcing any of this — it's discipline, backed by this checklist.

## Routine changes (most commits)

Update the doc in the same commit as the code change, not as a
follow-up:

- **Added, removed, or renamed a file** in a folder that has a README
  (`modules/nixos/`, `modules/home-manager/`, `profiles/`, `services/`,
  `secrets/`, `files/`) — update that folder's Inventory list. See
  [`README-template.md`](../README-template.md) for the shape.
- **Discovered a non-obvious cross-cutting gotcha** while making a
  change (an ordering dependency, a footgun, a "don't do X here, do it
  in Y instead") — add it to that folder's Gotchas section. Don't add
  a gotcha that's really just restating what the code says.
- **Made a decision future-you will re-derive from scratch otherwise**
  (a workaround, a surprising constraint, a fix for a specific
  incident) — add an inline why-comment at the point of decision, per
  [`docs/style-guide.md`](../style-guide.md). This is the same
  opportunistic, non-obvious-only policy Phase 4 of the original docs
  effort used — not a mechanical sweep, only where it's actually
  substantiated.
- **Added or removed a host** — update `docs/architecture.md`'s
  per-host table and the root `README.md`'s Hosts table together; they
  should never disagree.
- **Discovered a stale reference** (a folder, file, or command that no
  longer exists but is still described somewhere) — fix it immediately
  if it's a one-line change; if it's bigger, log it to `TODO.md` rather
  than leaving it. The `custom-packages/` reference removed from
  `AGENTS.md` in the original docs pass is the model: caught mid-task,
  fixed on the spot rather than left to rot.

If a change doesn't fall into any of the above, it probably doesn't
need a doc update. Don't pad a README to have something to show.

## Root `README.md` and `AGENTS.md`

These two are the front door, not general-purpose docs, so they get a
narrower trigger than the folder READMEs — don't let every small
change bleed into them.

- **`README.md`**: update the Hosts table when a host is added,
  removed, or its role/purpose changes. Update the Layout section only
  if the top-level directory structure itself changes (a new top-level
  folder, one removed, or the divide between them changing meaning).
  The Interesting stuff section is curated, not comprehensive — add to
  it only when something genuinely worth showing off lands (ask
  before adding on the user's behalf if it's not obvious; see
  `TODO.md`'s docs-plan entry for how the last pass picked additions),
  and don't let it grow into a changelog.
- **`AGENTS.md`**: update when a command changes (new lint tool, a
  build command's flags change), when the repo layout's fast-summary
  bullets drift from `docs/architecture.md`'s real detail, or when a
  new hard rule is established (the kind of thing that would otherwise
  need re-explaining to every fresh agent session). Keep it a fast-load
  summary — if a change needs more than a couple of sentences to
  explain, that detail belongs in `docs/` with a link from here, not
  inline in `AGENTS.md` itself.

Both files are deliberately kept lean (see `docs/agents.md` and the
root README's own intro) — resist the urge to grow them into full
documentation. If something doesn't fit their scope, it belongs in
`docs/` instead.

## Flag issues immediately, don't let them sit

Whenever a documentation issue is *noticed* but isn't being fixed
right now — spotted mid-task, out of scope for the current change, or
too large to fix inline — log it to `TODO.md`'s Active section
immediately, the same session it was found in. Don't rely on memory or
a mental note; write it down before moving on. Include:

- What's stale or wrong, and where (file + what it currently says).
- What triggered noticing it (what you were actually doing when you
  found it).
- Enough context that fixing it later doesn't require re-discovering
  the problem from scratch.

This mirrors how real incidents already get logged in `TODO.md` (see
the "Done" section's crowdsec/caddy entries) — a documentation gap is
the same kind of thing, just lower stakes. The `custom-packages/`
reference was caught and fixed on the spot because it was small; if it
had been bigger, it should have gotten a `TODO.md` entry instead of
being fixed under time pressure or, worse, silently left alone.

## Periodic audit (narrative docs)

`docs/architecture.md` and `docs/style-guide.md` describe things at a
level no single commit's diff naturally forces an update to — they
need an occasional deliberate check, not just change-with-code
discipline. There's no fixed schedule; do this opportunistically when:

- A conversation surfaces a discrepancy between what one of these docs
  says and what the repo actually does.
- A host's role, nixpkgs channel, or profile composition changes in a
  way that isn't purely additive (an addition is covered by the
  routine-changes rule above; a restructuring might not be).
- It's been a long time since either file was touched and a change
  session happens to already be reading through them for other
  reasons — a light pass costs little once you're already there.

The check itself: re-read the doc against the current
`flake.nix`/`hosts/*/configuration.nix`/`profiles/*.nix`, and fix
whatever's drifted. Log what was found and fixed in `TODO.md` if it
was non-trivial, the same way Phase 4's why-comment sweep did, so
there's a record of when the last audit happened and what it caught.

## After a big refactor

A refactor that changes the shape of the repo — not just what's in a
file, but which files/folders exist and how they compose — makes the
routine per-commit updates insufficient, because the *structure* the
docs describe has changed, not just its contents. Examples: splitting
`profiles/` into more/fewer roles, moving what's in `services/` into
proper `modules/nixos/` options modules, changing how hosts are pinned
across nixpkgs channels, restructuring the secrets layout.

When that happens, don't patch `docs/architecture.md` piecemeal —
treat it like the original docs effort and redo it properly:

1. **Re-survey the repo from scratch** the same way the original Phase
   1/2 passes did: read the actual `flake.nix`, every
   `hosts/*/configuration.nix`, every `profiles/*.nix`, and the new
   folder structure, rather than editing the old doc's assumptions in
   place. A structural refactor is exactly the situation where the old
   doc's framing may no longer be the right framing, not just its
   facts.
2. **Rewrite `docs/architecture.md`'s import chain, per-host table, and
   module/service/profile boundary sections** to match the new
   structure — don't leave old sections half-updated.
3. **Re-check `docs/style-guide.md`** for conventions the refactor
   invalidated (e.g. if the `my<Name>` options-module convention
   changed, or the module/service split criterion moved).
4. **Regenerate affected folder READMEs** (per
   [`README-template.md`](../README-template.md)) for any folder whose
   contents changed shape, not just its file list.
5. **Update the root `README.md`'s Hosts table and Layout section** if
   the refactor changed either.
6. **Log the rewrite in `TODO.md`** the same way each phase of the
   original docs effort was logged, so there's a dated record of when
   the docs were last brought back in sync with a structural change,
   for the next person (or the next refactor) to check against.

This is deliberately the same shape as the original documentation
build-out (see `TODO.md`'s docs-plan entry) — a big refactor is
effectively a mini re-run of that plan, scoped to whatever changed.
