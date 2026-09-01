---
slug: sval-main-renumber-layers-2-3-13-to-12-13-14
created: 2026-08-31
status: in-progress
frozen: false
---

# sval_main: renumber layers 2/3/13 to 12/13/14

## Original plan

User request, verbatim intent: in `files/sval_main.vil` (a Vial/VIA
keymap JSON for a Svalboard), relocate three layers by index:
- layer 13 -> layer 14
- layer 2 -> layer 12
- layer 3 -> layer 13
...in that exact order (13->14 must happen before 3->13, otherwise
layer 3's content would clobber layer 13's content before it has a
chance to move out). Then fix every other place in the file that
pointed at the old layer numbers so behavior is preserved, not just
the raw layer contents relocated.

## State

Done. `files/sval_main.vil` was rewritten via a one-off Python script
(not committed to the repo -- ran from the job's scratch dir) that
loaded the JSON, relocated the three layer arrays, rewrote every
`MO(2)`/`MO(3)` reference to `MO(12)`/`MO(13)`, and updated one
`key_override` layer bitmask. Verified with a full recursive diff
against the pre-edit file: only the intended cells changed, nothing
else in the 21KB file moved. File committed in worktree
`sval-main-layer-remap` (branch `worktree-sval-main-layer-remap`),
not yet merged to master.

## Progress

- [x] G1 -- confirm actual layer indices with `jq`/python before editing (see G1)
- [x] Relocate layer 13's content -> layer 14 (no internal refs to fix)
- [x] Relocate layer 2's content -> layer 12, rewriting its own internal
      `MO(2)`->`MO(12)` and `MO(3)`->`MO(13)` self/sibling references
- [x] Relocate layer 3's content -> layer 13 (no internal refs to fix)
- [x] Blank layers 2 and 3 (vacated, nothing moves into them)
- [x] Fix base layer (layer 0)'s `MO(2)`->`MO(12)`, `MO(3)`->`MO(13)`
      access keys; `MO(15)` on layer 0 and layer 15 left untouched
      (layer 15 did not move)
- [x] Fix `key_override[6]` layer bitmask: `5` (layers {0,2}) ->
      `4097` (layers {0,12})
- [x] Grep entire file for every `MO/TO/TG/TT/OSL/LT/DF/LM(<n>)` and
      confirm no other layer references exist (combos, tap-dance, and
      macro arrays in this file are all empty/layer-independent --
      nothing else to fix)
- [x] Full recursive JSON diff of old vs new to confirm no unintended
      changes

## Decisions (D)


## Gotchas (G)

### G1 -- manual eyeballing of layer index by counting JSON array
brackets is unreliable and was wrong on a first pass; used
`python3 -c "json.load(...)"` + index enumeration to get ground-truth
layer indices before touching anything. Layer 13 in this file is the
`0xff`/`USER*` placeholder layer, layer 2 is the numpad/nav layer,
layer 3 is the F-key/media/RGB layer -- these do not necessarily match
what a quick visual scan of the raw one-line JSON suggests.

## Findings (F)
*(populated by security/docs-updater when invoked)*
