---
name: first-principles-review
description: Use when reviewing, designing or questioning a plan, architecture, process, system, habit, ruleset or set of requirements, especially one that has grown complex, collected safeguards or process, or costs more effort than it returns. Also use when the user asks to go back to first principles, simplify, or question why something exists.
---

# First-principles review

## The spirit

Before improving anything, ask what it's really *for* and whether each part
should exist at all. Two rules carry this:

- **The doghouse.** Projects grow from a doghouse into a moonbase when **the
  real goal isn't solid**. The doghouse builder forgot that the fundamental
  goal was to be a good dog owner. Each addition is locally defensible, and
  additions beget additions: the light needs power, power needs a generator,
  the generator needs fuel. Meanwhile the dog is still waiting outside. So
  make the goal solid first, and judge every part by whether it serves that
  goal or only the thing being built. Sometimes the answer is to build nothing.
- **The five steps** (SpaceX), in order:
  1. Make the requirements less dumb.
  2. Delete the part or process.
  3. Simplify what survived.
  4. Speed up the cycle.
  5. Automate last.

  Every design is wrong; the only question is how wrong. Every requirement has
  a named source (a person or a real constraint, never "best practice"), and it
  gets questioned however smart that source is, the person's own requirements
  and yours included.

## What a good review does

Scale it to the thing. A quick question gets a few sentences that do this
thinking. A big design gets a parts table. The form serves the review.

- **It makes the goal solid.** Trace the goal upward, a level at a time, until
  you reach what the person actually cares about. If they haven't said, give
  your guess and ask.
- **It grounds itself in facts.** Find out what they actually do and have.
  Check real data where you can. Say which facts would change your mind.
- **It questions every part, central part first.** For each part: who asked
  for it, and what real problem it solves. A part that exists only to serve
  another part falls with it. Being cheap or harmless isn't a reason to keep
  something.
- **It rates real risks.** For anything the design guards against, weigh
  likelihood × impact *for this person*. Ordinary mistakes count.
- **It deletes boldly.**
  - Propose deletions, each with the concrete pain that would bring the part
    back. The net part count goes down.
  - Polish and automation come last.
  - Drop checks once the problem they guarded is solved.
- **It ends with the one question** that would change the answer most, and
  offers another pass until nothing more comes out.

## Signs you've lost the spirit

- You treated the stated thing ("a secure X") as the goal.
- You trimmed the edges but never questioned the central part.
- You added about as much as you cut.
- You asked five questions instead of one.
- You ran this as a checklist where one sentence would have done.
- You deleted something yourself. Deletions are proposals; existing rules and
  explicit requests still bind.
