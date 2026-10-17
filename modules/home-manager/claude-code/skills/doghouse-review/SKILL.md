---
name: doghouse-review
description: Use when reviewing, designing or questioning a plan, architecture, process, system, habit, ruleset or set of requirements, especially one that has grown complex, collected safeguards or process, or costs more effort than it returns. Also use when the user asks for a doghouse review, to simplify, or why something exists.
---

# Doghouse review

Run **the six steps** from CLAUDE.md ("How to work with me") on the thing:
step 0, the doghouse, then SpaceX's five. Hold to the spirit, not the form:
before improving anything, ask what it's really *for* and whether each part
should exist at all.

Scale the review to the thing. A quick question gets a few sentences that do
this thinking. A big design gets a parts table. The form serves the review.

## What each step looks like in a review

0. **The goal.** Trace the goal up, a level at a time, until you reach what the
   person cares about. If they haven't said, give your guess, labelled as one.
   Ground it in facts: what they actually do and have, and real data where you
   can check it. Say which facts would change your mind.
1. **Requirements.** For each part, start with the central one: who asked for
   it, and what real problem it solves for the goal from step 0. Name the
   departments ("security", "best practice", "how tool X does it") and ask who
   is behind them. For anything the design guards against, rate likelihood ×
   impact *for this person*. Ordinary mistakes count.
2. **Deletions.** Propose deleting parts, each with the concrete pain that would
   bring it back. A part that exists only to serve another part falls with it.
   Being cheap is not a reason to keep a part. The net part count goes down.
3. **Simplify, 4. speed up, 5. automate**, briefly and only for what survived.
   Drop checks once the problem they guarded is solved.

End with **the one question** that would change the answer most, and offer
another pass until nothing more comes out.

## Signs you've lost the spirit

- You treated the stated thing ("a secure X") as the goal.
- You trimmed the edges but never questioned the central part.
- You added about as much as you cut.
- You asked five questions instead of one.
- You ran this as a checklist where one sentence would have done.
- You deleted something yourself. Deletions are proposals; existing rules and
  explicit requests still bind.
