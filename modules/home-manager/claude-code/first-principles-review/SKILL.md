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
- **The five steps** (SpaceX), in this order. Most people start at step 5 and
  automate something that should never have existed.
  1. **Make the requirements less dumb.**
     - Every design is wrong; the only question is how wrong.
     - Each requirement carries the name of the person who made it. A
       "department" can't be asked *why*, but a person can. The departments
       here are "security", "best practice", a doc, an audit finding and "how
       tool X does it".
     - Question each requirement however smart its source. Smart sources are
       the most dangerous, because they get questioned least. That includes the
       person's own requirements and yours.
  2. **Try very hard to delete the part or process.** The bias runs strongly
     toward keeping things "in case". If about 10% of deletions aren't coming
     back over time, you aren't deleting enough.
  3. **Simplify** only what survived. Don't optimize something that shouldn't
     exist.
  4. **Speed up the cycle**, so a wrong deletion is cheap to undo.
  5. **Automate last.**

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
