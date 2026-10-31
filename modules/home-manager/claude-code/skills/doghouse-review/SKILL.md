---
name: doghouse-review
description: Use when reviewing or questioning a plan, design, process, system, habit, ruleset or set of requirements; before proposing a plan that adds a part (a service, job, check, hook, rule or process); and when the user asks for a doghouse review, to step back, to simplify, or why something exists.
---

# Doghouse review

Apply the six rules from your global instructions to the thing, as someone who
didn't build it and whose job is to subtract. Scale the review to the thing: a
quick question gets a few sentences, a plan or design gets the parts table
below. The definitions of the rules, and the reasons behind them, are in
`/home/agent/research/Projects/Golden Engineering Rules.md`; read it when a
rule is in doubt, not every time.

## What a review produces

**0. The goal.** State it one level above the thing itself. If the person
hasn't said, give your guess, labelled as one, grounded in what they actually
do and have, with real data where you can check it, and name the facts that
would change your mind. "Nothing" is a valid answer. The request is not the
goal: "a secure X", "a faster Y" are means.

**1. Each requirement, traced.** Every "must" lands on a person who can be
asked why, or on physics. A requirement with no owner isn't one. Trace
"security" to a threat with a likelihood and a cost. Trace your own
requirements first, and the parts you want to add in answer to a risk you
noticed; the risk is worth naming, the part deserves suspicion.

**2. The parts table.** Question the central part before the edges: who is
it for, what does it solve? Then one row per part, including the parts the
plan adds: what it serves, who asked for it (a name), the pain its absence
would cause (one you've seen or can point to, not one you can imagine), and
your proposal: keep, delete, or reduce to its least form. Every part is
deleted by default; it keeps its place only with a name behind it and a pain
you've seen or can point to. "In case", "cheap", "small" and "harmless"
aren't reasons. A part that only
serves a deleted part goes with it. Deletions are proposals; you never delete
anything yourself. Name losses that would be silent or unrecoverable (keys,
data, the way back in) instead of proposing them. "Nothing to delete" needs
each part's reason, not a default.

**3. The smallest test.** Where the review turns on something unknown, say
what real use or measurement would answer it, and the smallest, soonest
version of that. Propose the test rather than arguing the point.

**4. Optimisations, against a measure.** Anything the plan makes faster
(latency, throughput, build or deploy time), cheaper (compute, storage,
tokens, upkeep), lighter (dependencies, image or binary size, memory) or
more robust (failure modes handled, time to recover): which measure, and
does it trace to the goal? Flag anything made cleverer rather than simpler
(an abstraction, a cache, a second code path, a config knob), and any
optimisation of a part whose place isn't settled.

**5. What becomes permanent.** Anything the plan freezes (a hook, a job, a
check, a schedule, a rule): has it run by hand and proven useful first? Is
the fix declarative and reproducible, or does it live in someone's head? A
check added for a problem that's gone goes in the table as a deletion.

**End with the one question** whose answer would change the review most, if
there is one.

## Edges agents get wrong

- Running all six as a checklist where one sentence would do. The rules scale.
- Treating the stated thing as the goal, and trimming the edges while leaving
  the central part alone.
- Cutting or adding to fit the answer you expect the person wants.
- Asking five questions instead of one.
- Acting on the review. The review is the deliverable; the person decides.

## Source

Adapted 2026-10-29 for agents from the owner's reference above, which is the
master text; this copy may diverge where agents need different wording.
