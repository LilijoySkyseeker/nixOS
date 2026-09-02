---
slug: add-human-style-writing-skill-manual-not-auto-invoked
created: 2026-09-02
status: done
frozen: true
---

# Add human-style-writing skill (manual, not auto-invoked)

## Original plan

User request: use the `workflow` skill, then use
https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing to build a
"human style writing" skill and add it to this repo like the existing
skills (`plan`, `workflow`, `security-audit`). Explicitly: not
automatically called, not integrated into any other skill/gate -- just
a manual tool the user reaches for by hand.

## State

**2026-09-02, done.** Added `docs/skills/human-style-writing/`
(`SKILL.md` + `reference.md`), symlinked to
`.claude/skills/human-style-writing` per the existing convention, and a
docs-map row in `AGENTS.md` right after the `security-audit` row.
`SKILL.md` is a short, general-purpose checklist (inflated significance,
empty "-ing" analysis, promotional tone, vague attribution, avoided
copulas, negative parallelism, rule-of-three padding, formulaic
"despite challenges" closers, clustered overused vocabulary, formatting
tells, structural tells). `reference.md` holds the full catalogue
extracted from the Wikipedia essay: era-tagged vocabulary lists (GPT-4 /
GPT-4o / GPT-5 eras), every phrase pattern with its actual example
quotes, and the Wikipedia-specific mechanics (citations, edit summaries,
markup-bug fingerprints per assistant, "signs of human writing",
historical/now-unreliable markers) kept separate since they don't
generalize past Wikipedia editing.

Ran `/simplify` (4 parallel review agents: reuse, simplification,
efficiency, altitude) per the `workflow` skill's mandatory step.
Applied fixes: SKILL.md's checklist trimmed to bare category + one-line
description (was duplicating reference.md's phrase-example lists,
which had already drifted -- see G1); the "read reference.md" framing
reworded from an unconditional instruction to a conditional one, since
most of reference.md (citations/edit-summaries/markup bugs) is
Wikipedia-only and not needed for a typical general-prose pass.

`nix flake check --no-build` fails in this environment on an unrelated
pre-existing issue (see G2) -- confirmed present with this diff
stashed out, so not caused by this change; this diff touches zero
`.nix` files so `nixfmt`/`statix`/`deadnix`/targeted-build all
correctly no-op.

## Progress

- [x] Fetched and distilled the Wikipedia "Signs of AI writing" essay
- [x] Wrote `docs/skills/human-style-writing/SKILL.md` and
      `reference.md`
- [x] Symlinked `.claude/skills/human-style-writing` -> the docs/skills
      source, matching the `plan`/`workflow`/`security-audit` pattern
- [x] Added the `AGENTS.md` docs-map row
- [x] Ran `verify-ladder` -- pre-existing unrelated `nix flake check`
      failure noted (G2), no `.nix` files touched by this diff
- [x] Ran `/simplify` (reuse/simplification/efficiency/altitude, 4
      parallel agents) and applied its fixes (see State)
- [x] Committed and pushed

## Decisions (D)


## Gotchas (G)

### G1 -- SKILL.md's own duplicated phrase-example list drifted from reference.md within the same session
First draft had SKILL.md restate a shortened phrase-example list per
category, mirroring reference.md's fuller version. It immediately
drifted: SKILL.md listed "delve" as a live overused-vocabulary example
with no caveat while reference.md (correctly) notes it dropped off
sharply in 2025 and is no longer distinctive; SKILL.md also listed "a
summary paragraph that recaps a section" as a current structural tell
while reference.md files the same pattern under "historical / now-
unreliable markers." Caught by the `/simplify` simplification-angle
review, not written correctly the first time. Fixed by making
reference.md the single place phrase examples and era-tagged vocabulary
live -- SKILL.md now only names categories and points to it. Worth
remembering for any future skill with a similar short-checklist/full-
reference split: don't hand-copy examples into the short file, just
reference the categories.

### G2 -- `nix flake check --no-build` fails in this environment independent of this change
Fails on evaluating `checks.x86_64-linux.zrepl-replication`
(`driverConfiguration.vms.puller...` -> "path
'09g0q2nr523x5inkal66127xmq2z8gw0-...' is not valid") -- looks like a
local Nix store issue (a fetched source path no longer present),
unrelated to this diff. Confirmed by stashing this diff's changes
entirely and re-running: identical failure, same store path. This diff
touches zero `.nix` files, so not investigated further here; worth a
look before trusting `nix flake check` results on this machine for an
unrelated task.

### G3 -- the "manual, not auto-invoked" property is enforced only as description prose, with no hard gate
Confirmed via the `/simplify` altitude-angle review: this repo's only
`Skill`-tool-adjacent mechanism is three `PreToolUse` git hooks
(`plan-touch-guard`, `footer-guard`, `fresh-branch-guard`), none of
which match on skill invocation, and no skill in this repo (including
`workflow`'s own triviality carve-out) has anything stronger than
description-field prose gating when it gets picked. So this skill's
"don't self-invoke, not part of the workflow gate" framing (`SKILL.md`
frontmatter + the `AGENTS.md` row) is a request a future session could
still ignore, not a guarantee -- there's no post-hoc check for it the
way `plan-touch-guard` backstops `workflow`'s trivial path. Matches
existing repo convention exactly (not a shortcut specific to this
skill), so left as-is; a `PreToolUse` hook matching the `Skill` tool
would be the real fix if the user ever wants this enforced rather than
requested, but wasn't built here as it wasn't asked for and no
precedent for it exists yet.

## Findings (F)
*(populated by security/docs-updater when invoked)*
