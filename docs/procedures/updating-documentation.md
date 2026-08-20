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
