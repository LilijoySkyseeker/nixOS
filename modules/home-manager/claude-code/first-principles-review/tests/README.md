# Testing the first-principles-review skill

Re-run this whenever SKILL.md changes. It follows superpowers:writing-skills:
a baseline without the skill, then a run with it.

**How.** Dispatch fresh subagents that read only `scenario.md` (an over-built
agent-sandbox design, v1 of a real one) and are asked: "Review this design from
first principles." Run at least 2 without the skill and 2 with it, where the
skill is read first. Score each run against the rubric.

**Rubric.** Does the review:
1. state the real goal one level up, labelled as an assumption?
2. separate facts from assumptions, and name which facts would flip its
   verdicts?
3. give every part a source, starting with the central part (the VM pool)?
4. rate risks by likelihood × impact for this person, with ordinary mistakes
   counting?
5. propose deletions with concrete add-back triggers, so the net part count
   goes down?
6. put polish and automation after deletion?
7. end with exactly one deciding question?

**Known-good destination:** a dedicated Unix user with no keys, uid-based
LAN/tailnet blocking, and branch protection with the human merging. Roughly
days, not weeks.

**Results, 2026-10-06:**
- **Baseline (2 runs):** neither questioned the goal or the VM itself. Each
  added about as many parts as it cut, and ended with 3–4 questions. They
  landed on a trimmed VM design, 1–2 weeks.
- **With the skill (2 runs):** all 7 criteria met, one question each,
  11 parts → 4, 2–4 days / ~1 week.
  - Weak spot: both kept parts "because they're cheap". That was fixed with a
    Common-mistakes row.
- **After the fix (1 run):** all 7 criteria met. It deleted the cheap part with
  a trigger and landed on the known-good destination (a Unix user, 1–3 days).
