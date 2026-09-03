---
name: human-style-writing
description: Manual checklist for editing text to remove the telltale wording, structure, and formatting tics of LLM-generated prose, distilled from Wikipedia's "Signs of AI writing" essay. This is a tool the user reaches for by hand when polishing a specific piece of writing -- it is not part of the workflow/plan/review gate and should not be self-invoked while writing code, commits, docs, or plans; only use it when the user explicitly asks to check or clean up writing style.
---

Source: [Wikipedia:Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing).
That essay is about detecting undisclosed LLM edits to encyclopedia
articles; most of its signal generalizes to any prose someone wants to
read as human-written, so the checklist below keeps the general-purpose
categories and leaves out Wikipedia-only mechanics (DOIs, edit
summaries, wikitext bugs).

If a category below doesn't resolve a case, or you need the actual
example phrases, the era-by-era vocabulary lists, or the Wikipedia-
specific tells, read `reference.md` in this skill's directory -- it's
the single place those examples live, kept there rather than
duplicated here so there's one list to update as vocabulary shifts, not
two that can drift apart.

## How to use this

Given a piece of text, scan it against the categories below. For each
hit, either cut the phrase, replace it with the plain claim it's
dressing up, or -- if the underlying fact is genuinely uncertain or
unsourced -- flag it rather than launder it into confident-sounding
filler. Not every hit is worth fixing; a single stray instance isn't a
tell, a cluster is. Judge density, not presence.

## Quick checklist

- **Inflated significance** -- attaching importance to a fact ("plays a
  crucial role," "stands as a testament to") instead of just stating
  the fact. Cut the frame, keep the fact.
- **Empty analysis tacked onto a fact**, usually via a trailing "-ing"
  clause ("..., highlighting its significance"). If the clause would
  still sound true glued onto an unrelated sentence, it's filler.
- **Promotional / travel-guide tone** -- selling the subject
  ("boasts a...", "nestled in the heart of...") instead of describing
  it. State what it is; let specifics carry the weight.
- **Vague attribution and hedge-inflation** -- "experts argue,"
  "industry reports suggest," or "such as" in front of a list that's
  actually exhaustive. If you can't name the source, name it or cut
  the claim.
- **Avoiding plain "is"/"are"** in favor of "serves as," "functions
  as," "represents," where a flat copula would do.
- **Negative parallelism** -- "not just X, but Y" used as a rhetorical
  reframe rather than because a real misconception needs correcting.
  Occasional use is fine; a tell when it recurs.
- **Rule-of-three padding** -- reflexive triplets of near-synonyms
  where one well-chosen word would do.
- **Formulaic "despite challenges" closers** -- a "Despite \[praise\],
  X faces challenges..." template followed by generic, unsourced
  speculation, instead of specific sourced obstacles.
- **Overused vocabulary, in clusters.** One instance of a word like
  "crucial" or "meticulous" is nothing; three or four in one paragraph
  is the actual signal. The specific word list shifts with model
  releases -- see `reference.md` for the current era-tagged version
  rather than treating any fixed list as permanent.
- **Formatting tells** -- excessive em dashes standing in for commas/
  periods, bold "header:" lead-ins on every bullet, unnecessary Title
  Case, skipped heading levels, a heading containing only more
  headings, emoji used as bullets or dividers.
- **Structural tells** -- a lead sentence that restates the title as a
  formal subject ("**X** refers to..."), or an "in conclusion" style
  closer in prose that isn't a formal essay.

## What this isn't

Not every instance of these patterns is AI-written, and avoiding them
doesn't by itself make text "sound human" -- these are correlational
tells from one essay's editors' experience with specific model eras,
not a certification test. Use judgment: the goal is plainer, more
specific, more checkable prose, not phrase-substitution to dodge a
detector.
