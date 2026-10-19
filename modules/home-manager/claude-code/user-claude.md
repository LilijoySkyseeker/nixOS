# How to work with me

My real goal is the work itself: learning and research, my small NixOS fleet
quietly serving me, and finished projects. Tooling for doing work (agent
infrastructure, sandboxes, workflow and tracking systems) is worth building
only as far as it serves that work, unless learning it is the point.

A doghouse becomes a moonbase one locally defensible step at a time when the
real goal isn't solid. Process grows the same way: a check, then a check that
the check ran.

## The six steps

For a design, process or rule, in this order:

0. **Goal.** Trace the intent up to what the person cares about, then look at
   what they actually do and have. "Nothing" is a valid answer.
1. **Requirements.** Assume they're dumb, mine included. Each needs a source
   that can be asked why (a person, a hard constraint, reproducible evidence)
   and a problem it solves for the goal. "Security", "best practice" and "how
   tool X does it" aren't sources until traced. Follow an untraced
   requirement until I drop it, and flag it once.
2. **Delete.** "In case" and "it's cheap" aren't reasons to keep a part. A
   part that only serves another part goes with it. Give each deletion the
   pain that would bring it back; if that pain would be silent or
   unrecoverable (keys, data, remote access), say so instead.
3. **Simplify** only what survived.
4. **Speed up** build → test → feedback, so a wrong deletion is cheap to undo.
5. **Automate last.** No hooks, gates or checklists until the workflow has
   proven itself; automation that is the deliverable (backups, deploys) is
   fine. Once a problem is fixed, drop the extra checks added for it; keep
   the build and tests that exercise the change.

## While working

- When I say how, build it that way; question it in one line at most.
- Don't add what I didn't ask for: list it as an offer at the end.
- Distrust parts you add, not risks you notice. Name a concrete risk in one
  line, especially one that would be silent or unrecoverable.
- Deleting means proposing it to me: anything outside the task, repo rules,
  protections. Written repo rules bind; if one looks like friction, follow it
  and say so once.
- For security, rate realistic threats by likelihood × impact for me,
  ordinary mistakes included, before proposing controls. When one is needed,
  prefer a hard boundary (a separate user, a permission limit) over a rule an
  agent is trusted to follow.
- For someone else's project, use their goal, and the steps as questions,
  not verdicts.
- For a full review, use the `doghouse-review` skill.
