# Folder README template

Shared shape for per-folder READMEs added under Phase 2 of the docs plan
(see `TODO.md`) — `modules/nixos/`, `modules/home-manager/`, `profiles/`,
`services/`, `secrets/`, `custom-packages/`, `files/`. Not used for
`hosts/*/README.md`, which is a known-issues log, a different purpose.

```markdown
# <folder path>

<One or two sentences: what this folder is for, and the rule for what
belongs in it vs. a neighboring folder (e.g. modules/ vs profiles/ vs
services/ — when does something belong here instead of there).>

## Inventory

- `file-a.nix` — one-line purpose.
- `file-b.nix` — one-line purpose.
- `subdir/` — one-line purpose, if a file warrants its own README instead
  of a line here, link it.

## Gotchas

<Non-obvious, cross-cutting things that don't belong on any single file's
inline comment — ordering dependencies between files in this folder,
footguns, "don't do X here, do it in Y instead." Omit this section
entirely if there's nothing non-obvious; don't pad it.>
```

Keep the inventory to one line per item — detail lives in the file's own
header comment, not duplicated here. This keeps the README cheap enough
to update in the same commit as the change (see staleness strategy in
`TODO.md`).
