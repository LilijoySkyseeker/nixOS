---
slug: docs-updater-rewrite-inline-comments-for-concision-not-just-check-them
created: 2026-09-04
status: in-progress
frozen: false
---

# docs-updater: rewrite inline comments for concision, not just check them

## Original plan

User: "use workflow. i want to change docs updator to also include updating
and rewriting inline comments. the goal is to make the inline comments
short, concise, minimal, and human readable. preferably 1 line of what the
thing is, then the plan/plan links for the why."

Today the `docs-updater` subagent (`docs/agents/docs-updater.md`;
`.claude/agents/docs-updater.md` is a symlink to it, not a second copy)
only *checks* touched comments
for accuracy, brevity/register, and citation form, and only rewrites when
it finds a policy *violation* (why-prose that should have moved to the
plan, or a stale description). It does not have a mandate to actively
tighten a comment that's accurate and policy-compliant but still wordier
than the style guide's own examples. Extend its mandate to actively
rewrite every touched inline comment into the style guide's shape: one
terse line naming what the code is/does, plus a `# plan: <file>#<id>`
citation if there's non-obvious why-content, per `docs/style-guide.md`'s
existing "Inline comments" and "Why context" sections (that shape is
already documented there, just not actively enforced by the subagent).

## State

`docs/agents/docs-updater.md` edited and landed:
- Merged the new concision mandate into the existing `Brevity/register`
  check (now `Brevity/register/concision`) rather than adding it as a
  separate bullet -- `/simplify`'s reuse and simplification passes both
  flagged the rule being spelled out three times (check bullet, rewrite
  instruction, rubric line); altitude flagged Concision as a second axis
  bolted on next to Brevity/register rather than a generalization of it.
  Merging fixed both: one full statement, two short back-references.
- Renamed "What to do about a violation" -> "What to do about what you
  find" since it now also covers a non-violation style-tightening case
  (wordy-but-accurate comments, rewritten directly, no plan finding).
- Broadened the frontmatter `description` to say "verify and tighten"
  instead of only "verify".
`.claude/agents/docs-updater.md` picked up the change automatically --
it's a symlink to the same file, not a second copy.

verify-ladder passed both before and after the `/simplify` pass.
Considered and rejected altitude's alternative suggestion (narrow
Concision to only why-prose-adjacent padding, dropping pure formatting
nits) -- that would cut against the user's explicit ask for general
comment concision, not just the why-leakage subset.

## Progress

- [x] Update `docs/agents/docs-updater.md`: merged concision into
      Brevity/register, added direct-rewrite instruction and rubric line.
- [x] Update frontmatter `description` to reflect the broadened mandate.
- [x] Run verify-ladder.
- [x] Invoke `/simplify` (4 parallel reviews: reuse + simplification
      found triplicated rule text, fixed by merging; efficiency clean;
      altitude's narrowing suggestion considered and rejected).
- [ ] Commit.

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
