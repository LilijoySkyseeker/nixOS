---
slug: measure-whether-the-review-loop-is-converging-or-churning
created: 2026-09-06
status: rejected
frozen: true
kind: task
priority: normal
blocked_by:
---

# measure whether the review loop is converging or churning

## State

Not started. Filed 2026-09-06 at the user's request, from a question
asked while the motivating session's own loop was running: "what is the
best way to track actual progress in the loop, and keep it from looping
forever?"

## Original plan

The review loop in `docs/skills/workflow/reference.md` terminates
mechanically: a pass that changes no code leaves the stamp fingerprint
unmoved, `plan-gate` stops reporting staleness, and the loop is over.
That is a correct exit condition and it is already built.

What it does not do is tell anyone whether the passes are *getting
anywhere*. A session can run four passes, fix twenty findings, and have
no way to answer "are we finding pre-existing defects, or cleaning up
the last pass's fixes?" Both look identical in the plan file: a numbered
`### F<N>` with a `**FIXED**` marker under it.

The motivating session is
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md`,
which ran the loop five times and produced 30 findings. Findings per
`security` pass went 9, then 5, then 3 — which reads as clean
convergence and is misleading. The first nine were genuine pre-existing
defects. A large share of the later ones were consequences of the
session's own fixes: widening `PLAN_CODE_GLOBS` made three docs stale,
fixing those changed code, which gave the next reviewer a surface it had
not seen. Two of the most serious findings all session — an un-passable
gate created by adding `.claude/*` to the code set, and a fail-open
introduced by a `/simplify` fix — were defects the loop *introduced*
and then caught.

That is the loop working. It is also indistinguishable, from the
outside, from the loop spinning.

### Three proposals

**1. Record a fingerprint trail.** Each pass records the code
fingerprint at its start and at its end. A trail of `a1b2 -> c3d4 ->
c3d4` makes convergence a fact on the page rather than a judgment. The
value is already computed by `plan_code_fingerprint` and already written
into every stamp, so this is presentation, not new machinery.

Known limitation, from
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#G9`:
`docs-updater` edits comments inside the code globs, so a
behaviour-neutral pass still moves the fingerprint. This over-reports by
at most one pass, which is the price of not parsing Nix and shell to
tell a comment edit from a logic edit.

**2. Track finding provenance.** For each finding, record whether the
cited line is in code that predates the task (present in
`origin/master...HEAD`) or in code a previous pass of the same task
introduced (present only in the working tree). This is mechanically
determinable, not a judgment call.

The ratio is the signal. A pass that is mostly discovery is progress. A
pass that is mostly cleaning up the previous pass is churn, and churn is
the point at which the right move stops being "fix it" and becomes
"file it".

**3. A severity floor on what restarts the loop.** Correctness and
security findings restart at `/simplify`. Style, wording, altitude and
"this could be structured better" get filed as follow-up plans instead.

Without a floor there is no natural end, because a competent reviewer
can always find something. The motivating session applied this rule by
hand from the third pass onward and it is what actually bounded the
work — six follow-up plans were filed rather than fixed inline, and the
session closed.

A declared pass budget ("three passes, then everything below the floor
is a follow-up") is a cruder backstop for when the floor is ambiguous.

### What to decide

- Whether provenance is recorded per finding by the agents themselves, or
  computed after the fact from the plan file's `- **File:**` lines. The
  second is cheaper and needs no change to the agent briefs.
- Whether the severity floor belongs in `reference.md` as prose, or in
  the agent briefs as an instruction to classify each finding as
  restart-worthy or file-worthy.
- Whether any of this warrants a script, or whether the fingerprint trail
  plus a convention is enough. Prefer the convention until a script has
  something to check.

### Out of scope

Changing the loop's exit condition. Code stability is the correct fixed
point and this plan does not propose replacing it — only making the
approach to it visible.

## Progress

- [ ] decide how provenance is determined, as a `### D1`
- [ ] add the fingerprint trail to the plan-file convention
- [ ] write the severity floor into `reference.md` or the agent briefs
- [ ] re-read the motivating session's 30 findings and classify them, as
      a check that the proposed metric would have said something true

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

**REJECTED 2026-09-09:** superseded: the review loop it would have measured no longer exists -- one pass and park, per 2026-09-09-dismantle-the-blocking-gate-tier-and-keep-the-plan-corpus.md (ADR-0002)
