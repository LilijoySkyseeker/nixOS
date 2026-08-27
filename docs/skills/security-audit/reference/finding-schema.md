# Finding schema and severity rubric

Every finding, from every part, uses this. Consistency here is what
makes consolidation possible — the 2026-08-26 run parsed all 158
findings mechanically out of nine reports because the format held.

## Schema

One `###` block per finding. Id is `F-<part>-NN` (`F-P3-07`,
`F-P0-02`).

```markdown
### F-<part>-NN — <short title, the claim itself>

- **File:** `path:line` (or several)
- **Severity:** CRITICAL | HIGH | MEDIUM | LOW | INFO
- **Confidence:** CONFIRMED | PLAUSIBLE
- **Axis:** hardening | needed-used | documentation
- **Reachability:** <adversary id from threat model §5> — <the path>
- **Rule:** violates `docs/hardening.md` "<which>" | new-rule candidate | n/a
- **Finding:** what is actually true, and why it matters here.
- **Proposed fix:** concrete, or "decision required" with the options.
- **Fix risk:** what applying it could break, and what must be tested.
- **Owner:** <part> — only when another part must confirm or act.
```

Report structure around the findings:

1. **Scope and method** — files read, which claims were verified
   against pinned sources and how, what could not be verified and why.
2. **Findings**, most severe first.
3. **Checked and clean** — what was examined and found fine. This
   matters: a later reader needs to know what was *covered*, not only
   what was wrong. It is also what stops the next audit re-deriving it.

## Severity rubric

Rate by **reachable impact**, not by how alarming the misconfiguration
looks in isolation. A scary-looking setting only a supply-chain
adversary can reach is not critical; a boring one the desktop user can
reach may be.

- **CRITICAL** — unauthenticated RCE or root from an internet-facing
  adversary; anything yielding fleet-wide root; or destruction of the
  backups. Fix out of band from the audit's own schedule.
- **HIGH** — root or full data access for an adversary who has already
  achieved a *plausible* first step. Also any secret exposed to a
  principal that should not hold it.
- **MEDIUM** — meaningful privilege or reach beyond what a principal
  needs, requiring a chain or a non-default condition. Includes
  violations of an existing `docs/hardening.md` rule with no currently
  demonstrable exploit — the rule exists because the class is real.
- **LOW** — defence-in-depth gaps, missing sandboxing on a low-value
  unit, logging holes, unsafe defaults nothing currently depends on.
- **INFO** — dead or unused config, over-broad grants with no
  demonstrated reach, documentation that no longer matches the config.
  Still report these; the needed/used axis lives here.

### Two required qualifiers

These change what gets fixed first far more than the label does.

**Reachability** — name the adversary and the path. "A7 via the docker
socket" is a finding; "an attacker could" is not.

**Confidence** — CONFIRMED (lines read, behaviour verified against the
pinned source) or PLAUSIBLE (inferred, needs checking). **Never round
PLAUSIBLE up to CONFIRMED to make a point land harder.** A
consolidation pass that cannot trust the labels is worthless, and the
distinction is what let the last run correctly rate one finding HIGH
while flagging that its escalation half still needed demonstrating.

### Promotion at consolidation

A cluster can be worth more than its parts. The 2026-08-26 run promoted
three, always with the reasoning stated:

> **C2 — promoted from HIGH to CRITICAL.** Every contributing finding
> was HIGH alone. But the rubric makes anything yielding fleet-wide
> root CRITICAL, the threat model rates this adversary the *most
> likely* foothold, and the paths require no exploit at all.
> Most-likely adversary plus total impact plus zero difficulty is not a
> HIGH.

A promotion that hides its logic is just an assertion. Write the
sentence.
