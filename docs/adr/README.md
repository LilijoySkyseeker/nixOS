# Architecture decision records

Sequentially numbered, permanent records of decisions that shaped the
fleet's architecture: `NNNN-slug.md`, numbered by scanning for the highest
existing number and incrementing.

## ADRs vs commit messages

A **commit message** (and its PR) records why *a change* was made. An
**ADR** records *a decision that outlives the work that produced it*, where
a reader looking at the architecture will find it rather than having to
dig through history. When a PR makes a durable architectural decision,
write the ADR in the same PR.

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

A title and a paragraph is a legitimate ADR, and a short one is not a
lesser one. But `Status` frontmatter, `Considered alternatives` and
`Consequences` are optional only in principle: a decision that clears
all three bars above usually earns them, because the rejected
alternatives and the downstream costs are *what made it* hard to reverse
and surprising in the first place.

`0001` is the worked example — the decision stated in a paragraph, then
the constraint that forces it, then alternatives and consequences.
Follow it rather than the minimum, and cut sections that would be empty
rather than padding them.

Existing architectural decisions predate this practice; each gets an ADR
when the thing it describes is next changed, tracked in
`2026-09-05-migrate-existing-architectural-decisions-into-docs-adr.md`.
That is a trigger, not a holding pattern: `docs/architecture.md` keeps
describing **how the system is built now**, permanently, and cites an ADR
for **why a shape was chosen**. Neither restates the other.
