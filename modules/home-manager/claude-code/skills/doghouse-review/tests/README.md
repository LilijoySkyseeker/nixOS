# Testing the doghouse-review skill

Re-run this whenever SKILL.md changes. It follows superpowers:writing-skills:
a baseline without the skill, then a run with it.

**How.** Dispatch fresh subagents that read only one scenario. There are three, so the
skill is tested across domains and sizes:
- `scenario.md`: an over-built agent-sandbox design, v1 of a real one;
- `scenario-process.md`: an over-built personal planning system;
- `scenario-small.md`: a one-line question, where the right answer is short.

The subagents are asked: "Review this design." Run at least 2 without the
skill and 2 with it, where the skill is read first. Score each run against
the rubric.

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
- **2026-10-06, after re-checking against the original texts (1 run):** all 7
  criteria met. The restored points came through in use:
  - the goal was traced up several levels;
  - the chain rule was used 4 times ("falls with its sources");
  - it landed on the known-good destination, 1–3 days.

  Restored points: "even if the requirement came from me", "remove in-process
  testing once diagnosed", "additions beget additions", "refocus during work",
  and the user's framing that "the real goal wasn't solid".
- **2026-10-06, spirit-first rewrite** (user: "the spirit of it is more
  important than an exact process. the goal is for this to generalize").
  - **Probes of the old six-part version:** the process case had excellent
    substance but heavy form (six sections, three tables). The small question
    got a full six-part essay with a table, where a few sentences were right.
  - **The rewrite:** the doghouse rule applied to the skill itself. The *moves*
    are kept as "what a good review does", scaled to the thing; the mandated
    order and table are gone. It is roughly 20% shorter.
  - **After the rewrite (1 run per scenario):**
    - **Design:** no regression. It questioned the central part and landed on
      the known-good destination.
    - **Process:** prose plus one table, 11 parts → 3, and it reached the
      dog-owner level ("take on less, not plan better").
    - **Small:** about 200 words of prose, "build nothing", one question.
- **2026-10-06, SpaceX section re-checked against the original text** (user: is
  the simplified form still serving the original, more general purpose?).
  - **Restored:**
    - why requirements need a name (a department can't be asked why);
    - smart sources are the most dangerous;
    - what counts as a "department" here (security, best practice, a doc, an
      audit, how tool X does it);
    - the bias toward keeping things "in case";
    - the ~10% add-back calibration;
    - why speed is step 4 (it makes a wrong deletion cheap);
    - "most people start at step 5".
  - **Regression (design + small):** all criteria met. The design run used the
    restored framing directly ("it came from 'how a multi-agent tool does
    it'"). The small question stayed short (~250 words of prose).
- **2026-10-08, renamed to doghouse-review, doghouse rule marked as the more
  important** (user: the doghouse rule comes first; the name collided with
  ordinary talk about first principles). The body changed only in the title
  and "most important first".
  - **Small (Sonnet):** short prose, "don't add it", an add-back trigger, one
    question.
  - **Design (Sonnet):** missed item 3. It kept a trimmed VM and never
    questioned the VM itself.
  - **Design (default model):** all 7 criteria met. It questioned the VM pool
    first ("very secure" is a department) and landed on the known-good
    destination, 4 parts, days of work. The Sonnet miss looks like the model,
    not the change; earlier runs used the default model.
