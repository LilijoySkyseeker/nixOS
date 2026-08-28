---
slug: fix-plan-tick-multi-line-matching-slug-truncation-
created: 2026-08-28
status: in-progress
frozen: false
---

# Fix plan-tick multi-line matching, slug truncation, and date-first filenames (G3, G11, G17, G37)

## Original plan

User asked to tackle four related gotchas tracked in
`2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md`:
`G3` (`plan-tick`'s ID matching is line-bound and fails on a wrapped
multi-line bullet), `G11`/`G17` (`plan-new`'s 50-char slug truncation cuts
mid-word and can collide), and `G37` (plan filenames are `<slug>-<date>.md`;
date-first would let plain directory listings sort chronologically).

## Progress
- [x] D1 -- decide G37 migration scope
- [x] D2 -- decide G3 fix approach
- [x] D3 -- decide G11/G17 truncation fix
- [x] implement block-aware `plan-tick` matching (G3)
- [x] raise `plan_slugify` cap to 70 chars, truncate at word boundary (G11/G17)
- [x] flip `plan-new` to `<date>-<slug>.md` ordering (G37)
- [x] migrate all existing plan files to date-first filenames (G37)
- [x] sweep every citation of a renamed file, repo-wide, to the new filename
- [x] update `docs/plans/.checksums` for renamed/edited frozen files
- [x] update skill docs (`plan/SKILL.md`, `plan/reference.md`, and every
      other doc using the `<slug>-<date>.md` placeholder pattern)
- [x] verify all three script changes against fixtures before touching real data

## Decisions (D)
### D1 -- should the existing 44 plan files be renamed to date-first too, or does the new order only apply going forward?
**ANSWERED 2026-08-28:** migrate everything now -- rename every existing
plan file, update `docs/plans/.checksums` for the frozen `done/` ones, and
sweep every citation across the whole repo (not just `docs/plans/`) to
match.

### D2 -- how should `plan-tick` handle an ID that lands on a continuation line instead of the checkbox line?
**ANSWERED 2026-08-28:** block-aware match -- treat a bullet as the
checkbox line plus any lazy-continuation lines up to the next
bullet/blank-line/heading, and search the ID anywhere in that block. No
`--line` override added.

### D3 -- how should `plan-new` avoid awkward mid-word slug truncation?
**ANSWERED 2026-08-28:** raise the cap (70 chars, up from 50) and truncate
at the last word boundary within it, rather than cutting mid-word.

## Gotchas (G)
### G1 -- two frozen `done/` plans needed a content edit as part of the D1 migration
`2026-08-27-git-reset-checkout-do-not-revert-a-path-with-no-he.md` and
`2026-08-27-hardcode-pull-before-branching-as-a-hook.md` both cite
`2026-08-27-establish-the-workflow-and-plan-file-system.md` (and one also
cites a since-renamed corrupted-file path) by the old filename. Freezing
exists to stop *unnoticed* drift, not to make the repo unable to survive a
deliberate, user-approved renaming migration -- so both were edited
(citation text only, nothing else) and `docs/plans/.checksums` was
updated to match the new content hash for each, keeping
`.githooks/pre-commit`'s frozen-file check honest rather than bypassing it.

### G2 -- `nix flake check`'s `checks.x86_64-linux.zrepl-replication` failed during verify-ladder, unrelated to this change
Failure was `error: path '...-source' is not valid` while evaluating a
NixOS VM test's node environment -- a substituter/store-availability issue
in nixpkgs' test driver, not something this diff touched (no `.nix` file's
logic changed, only a handful of comment-only citation-string fixes).
`nixfmt --check`, `statix`, `deadnix`, and all five `nixos-rebuild build`
targets (vps, isoimage, thinkpad, homelab, torrent) passed clean.

## Findings (F)
*(populated by security/docs-updater when invoked)*
