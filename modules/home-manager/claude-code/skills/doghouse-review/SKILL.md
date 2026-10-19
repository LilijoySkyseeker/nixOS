---
name: doghouse-review
description: Use when reviewing or questioning a plan, architecture, process, system, habit, ruleset or set of requirements, especially one that has grown complex, collected safeguards or process, or costs more effort than it returns. Also use when the user asks for a doghouse review, to simplify, or why something exists.
---

# Doghouse review

Run the six steps from CLAUDE.md on the thing. Hold to the spirit, not the
form, and scale the review to the thing: a quick question gets a few
sentences, a big design gets a parts table.

What a review adds to the steps:

- **The goal.** If the person hasn't said, give your guess, labelled as one.
  Ground it in what they actually do and have, with real data where you can
  check it, and say which facts would change your mind.
- **The central part first.** Ask who it's for and what it solves before
  trimming anything at the edges.
- **Risks.** For anything the design guards against, rate likelihood × impact
  for this person. Ordinary mistakes count.
- **The result** is usually fewer parts. Keeping everything, or adding a
  missing part, is a valid answer.
- End with the question that would change the answer most, if there is one.

## Signs you've lost the spirit

- You treated the stated thing ("a secure X") as the goal.
- You trimmed the edges but never questioned the central part.
- You cut or added to fit the expected answer, not the goal.
- You asked five questions instead of one.
- You ran this as a checklist where one sentence would have done.
- You deleted something yourself. Deletions are proposals.

## The meaning behind the steps

CLAUDE.md carries the steps in short form, to steer everyday work. This is the
context behind them, for when a review needs it. It explains; it doesn't add
rules.

**Why they exist.** My previous agent-safety process (plan-file gates, review
stamps, a 40-rule orchestrator) was step 5 done first. My dotfiles repo went
from up to 69 commits a day to 2 in three weeks. I said on 2026-10-05: "I have
created too much friction, and the work has suffered greatly because of it."
In the 2026-10-05/06 agent-sandbox design, Claude kept proposing controls
before establishing the problem. Each time, my questions "what is the real
goal / what are the real threats / what am I actually doing" deleted most of
them. Most people start at step 5 and automate something that shouldn't
exist. Musk did it on the Model 3 line ("I automated, accelerated, simplified
and then deleted"), and so did I.

**0. The doghouse.** I ask for a doghouse, go to work, and come back to a
moonbase with the dog still waiting outside. Someone asked "should it have a
light?", which is a fair question. Then the light needed power, the power
needed a generator, and the generator needed fuel. Each step was locally
defensible from where the builder stood. Zoomed out, they add up to something
nobody wanted. This happens when the real goal isn't solid and the means
quietly becomes the goal. Process grows the same way: a mistake gets a check,
the check gets skipped, so a check that it ran is added. Checks need
evidence, and evidence needs checking, until finishing the process is the
goal: "the rules became more important than the things they were supposed to
serve." The trace runs a level at a time: a usable doghouse → the dog
comfortable outdoors → being a good dog owner.

**1. Requirements.** "Your requirements are definitely dumb; it does not
matter who gave them to you", "even if the requirement came from me". Musk:
"the only rules are the ones dictated by the laws of physics; everything else
is a recommendation." A department (his examples are legal and safety) can't
be asked why; a person can. Smart sources are the most dangerous, because
they get questioned least, and Claude's own requirements most of all, because
they sound reasoned. Here, though, the person behind "security" is usually me,
so the move is to trace it to a threat, not to dismiss it.

**2. Delete.** "You can make 'in case' arguments for so many things." Musk's
calibration: if you're not adding back at least 10% of what you deleted, you
didn't delete enough. That's a long-run heuristic for someone tracking it, not
a per-task check. It assumes the pain of a wrong deletion shows up, as it does
in testing on a factory line. For keys, data and remote access it often shows
up only once it's permanent, which is why those get named, not deleted.

**3. Simplify.** "Possibly the most common error of a smart engineer is to
optimize a thing that should not exist."

**4. Speed up.** It comes after direction, because it makes a wrong deletion
cheap to undo: "if you're digging your grave, don't dig faster."

**5. Automate last.** Musk removed in-process tests once the output was
reliably good, while the final test still ran. When the work is done, stop
proving it's done, but keep what still catches the failure.

**Sources:** the doghouse is from OpenRig, "I Run an AI Civilization in Herdr"
(youtu.be/AL-PQuB2wy0, 13:05–19:50), refined in chat on 2026-10-06. Steps 1–5
are from Musk's 2021 Starbase tour with Everyday Astronaut and "the algorithm"
in Isaacson's *Elon Musk* (2023). Quotes are theirs. Adopted 2026-10-06,
combined 2026-10-16, split into short rule and this background 2026-10-19.
