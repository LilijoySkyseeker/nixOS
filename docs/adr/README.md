# Architecture decision records

Sequentially numbered, permanent records of decisions that shaped the
fleet's architecture: `NNNN-slug.md`, numbered by scanning for the highest
existing number and incrementing.

## ADRs vs plan files

They answer different questions and neither replaces the other.

- A **plan file** (`docs/plans/`, see the `plan` skill) tracks *a piece of
  work*: what is being done, what is still open, what was found along the
  way. It moves `todo` → `in-progress` → `done` and freezes.
- An **ADR** records *a decision that outlives the work that produced it*.
  It stays where a reader looking at the architecture will find it, rather
  than being buried in a completed plan nobody re-reads.

When a plan produces a durable architectural decision, the ADR states the
decision and the plan cites it. Do not restate an ADR's content in the
plan — cite it, the same way plan files are cited by bare filename.

## When to write one

All three must be true, or skip it:

1. **Hard to reverse** — changing your mind later costs something real.
2. **Surprising without context** — a future reader will look at the
   config and wonder why on earth it was done this way.
3. **A real trade-off** — there were genuine alternatives and one was
   picked for specific reasons.

An easily reversed decision will just be reversed. An unsurprising one
raises no questions. One with no alternative records nothing beyond "we
did the obvious thing."

## Format

A title and a paragraph is a legitimate ADR. `Status` frontmatter,
`Considered alternatives` and `Consequences` are optional — include them
only where they carry weight. Most will not need all three.

Existing architectural decisions predate this practice and are being
migrated in
`2026-09-05-migrate-existing-architectural-decisions-into-docs-adr.md`;
until that lands, `docs/architecture.md` remains the primary home for
anything not yet given an ADR.
