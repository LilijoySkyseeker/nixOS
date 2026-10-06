---
name: first-principles-review
description: Use when reviewing, designing or questioning a plan, architecture, process, ruleset or set of requirements, especially one that has grown complex, collected safeguards or process, or costs more effort than it returns. Also use when the user asks to go back to first principles, simplify, or question why something exists.
---

# First-principles review

## Overview

This review asks whether each part should exist *before* improving it. Two
rules drive it:

- **The doghouse check.** The thing being built is a means. Judge it by the
  goal one level above it: a doghouse serves being a good dog owner.
- **The five steps** (SpaceX):
  1. make the requirements less dumb by tracing each one to a named source;
  2. delete;
  3. simplify;
  4. speed up;
  5. automate last.

## The review: produce these parts, in this order

1. **The real goal, one level up.** What is this *for*? Not "a secure X", but
   what the person is trying to get done that X serves. If they haven't said,
   state your best guess, label it as an assumption, and make confirming it
   your question.
2. **The facts that decide it.**
   - Say what the person actually does and has, kept separate from
     assumptions.
   - Check real data before judging: read the files, count, measure, survey.
   - Name the facts that, if they were different, would flip your verdict.
3. **Every part, biggest first.** One row per part:
   `part | source | real problem it serves | verdict`.
   - **Source** is a named person or a concrete external constraint.
     "Security", "best practice", a doc, an audit finding or "borrowed from
     tool X" counts as *unknown* until traced. Mark the parts you (Claude)
     introduced.
   - **Start with the central part** (the platform, the VM, the framework
     itself), not the edges.
   - **Verdict** is one of: **keep**; **delete**, with an add-back trigger (the
     concrete pain that would bring it back); or **simplify**.
4. **Risks, rated.** If the design guards against something, rate each threat
   or failure by likelihood × impact *for this person*, with evidence, before
   keeping its control. Ordinary mistakes count as threats.
5. **What's left.**
   - Give the smallest design that serves the goal, and its size (days or
     weeks).
   - The net part count must go down: add a part only if it replaces more than
     it adds.
   - Polish (hardening details, tuning) and automation come last, after
     deletion.
6. **The one question** whose answer would change the design most. Ask one.

Then offer another pass on what's left, and stop when a pass deletes nothing.

## Limits

- **Deleting means proposing.** Never remove code, rules or protections
  yourself. Existing rules and explicit requests still bind.
- **Small explicit edits don't need this.**
- **For someone else's design,** ask what *their* goal is, and give your
  verdicts as questions.

## Common mistakes

| Mistake | Instead |
|---|---|
| Treating the stated thing ("a secure sandbox") as the goal | Go one level up |
| Questioning only peripheral parts | Start with the central part |
| Hardening details before deletions | Delete first, polish last |
| Adding about as many parts as you cut | Net reduction |
| Keeping a part because it's cheap or harmless | Cheap isn't a source. Delete it unless it serves the goal |
| Several open questions | One deciding question |
| "Add it back when needed" | Name the concrete pain |
