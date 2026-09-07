# `workflow` skill reference

## Trust hierarchy

When verifying a claim or a fix, evidence is not all equally trustworthy.
Least to most trusted:

**documentation → source code → local build (output actually inspected,
not just "it built") → VM testing → an actual switch on a real host.**

Each rung supersedes the ones below it when they disagree — a doc saying a
service is hardened doesn't outrank actually reading the unit's
`serviceConfig`; a clean build doesn't outrank a VM boot showing the unit
failing to start. Climb the ladder as far as the task actually warrants
(see `docs/procedures/testing-changes.md` for the concrete commands at
each rung) rather than stopping at the cheapest rung that happens to agree
with what you expected to find. The rationale — including why this
generalizes beyond security work — is in `docs/agents.md`.

**Corollary: a fix that is not declarative and reproducible is no fix at
all.** A change made by hand on a live host (an ad hoc `systemctl edit`, a
manually-run command, a value patched in `/run/secrets` or the running
config) is not a fix until it's expressed in this repo's Nix and actually
deployed from it — otherwise the next rebuild silently reverts it, and the
next person has no way to know the fix ever existed.

The step sequence's close-out step applies this standard when deciding
whether a plan's work is actually done, or still belongs in
`in-progress/`. The rung reached is declared in the plan's `## State`,
and `plan-move ... done`/`plan-freeze` refuse without it — see
`docs/procedures/testing-changes.md`, "Declaring the rung".

## Subagent selection

Which agents a change obliges is decided **mechanically, from the diff**
-- never by judging whether one is "relevant".
`docs/skills/workflow/scripts/required-agents` prints the set for the
current working tree and is the authority; this table only explains it.

| Agent | Fires when | Built? | Stamped? |
|---|---|---|---|
| `/simplify` | any code change (see below) | yes | **no** |
| `docs-updater` | any of the above **or** any `.md` changed | yes | yes |
| `security` | any code change | yes | yes |
| `spec-check` | the active plan has any `### D<N>` | not yet | not yet |

Listed in run order; `required-agents` prints them in that order too.

**"Stamped?" is the honest column.** `plan-gate` can only refuse a merge
for an agent that leaves a completion stamp, and `/simplify` is a slash
command -- no `SubagentStop`, so nothing records that it ran. It is
obliged on every code change and enforced by nobody, which is the one
remaining honour-system leg of this loop.

"Code" is `PLAN_CODE_GLOBS` in `docs/skills/plan/scripts/lib.sh`, which
is the authority. It is deliberately wider than Nix: the skill and repo
scripts (`*/scripts/*`, `scripts/*`), the git hooks (`.githooks/*`), the
hook wiring (`.claude/settings.json`), the agent and skill entries under
`.claude/`, the agent definitions, `.sops.yaml` and `secrets/`, the CI
workflows, `flake.lock`, `.gitignore` (which, through
`--exclude-standard`, decides the fingerprint's own input set) and
`.gitattributes` (`*.pem -diff` switches off the `pre-commit` secret
scan) are all things a change to which weakens other gates more
thoroughly than any module edit could. It is an allowlist, and it has
three times been found to be missing something that met its own rule --
the standing proposal to invert it is
2026-09-06-invert-the-reviewable-code-set-from-an-allowlist-to-a-denylist.md.

**What that does and does not buy.** Obliging review and moving the
fingerprint is enforcement for anything the *repo's own* gates check --
a `.claude/settings.json` edit that disables the stamp hook still faces
a server-side missing-stamp block. It is **not** enforcement for the CI
workflow itself: GitHub resolves a `pull_request` workflow from the PR's
own ref, so a PR editing `.github/workflows/plan-gate.yml` runs its own
version, and the required status context is satisfied by whatever job
carries that name. Listing the workflow here means such a PR is reviewed
and stamped, not that it is mechanically prevented. See
2026-09-06-stop-a-pr-from-weakening-the-ci-gate-it-is-judged-by.md.

Why mechanical: "invoke where relevant" ran on 12 of 89 plans while
"`/simplify`, always" ran every time -- same skill, same agent, one
sentence apart. A trigger that has to be judged is a trigger that gets
skipped. `docs-updater` deliberately fires on code, not just `.md`,
because a code change can invalidate a doc without touching it, which is
the drift that matters most.
`plan: 2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#D7`

### Order, and the loop

Run them strictly one after another -- never two in the same parallel
batch, even though the review agents are read-only and would seem safe to
overlap:

```
loop { /simplify -> docs-updater -> security -> spec-check -> fix }
      until security and spec-check found nothing to fix,
      or the user signed off
```

**Every agent that writes runs before every agent whose stamp must stay
valid.** `/simplify` and `docs-updater` edit; `security` and `spec-check`
are read-only. Ordering them the other way is not merely untidy, it is
unsatisfiable: `docs-updater` rewrites inline comments in `.nix` files and
skill scripts, all of which the stamp fingerprint covers, so a
`docs-updater` pass after `security` leaves `security`'s stamp stale by
construction and `plan-gate` blocks on a task where nothing is actually
wrong. A gate that goes red on the first honest attempt every time is the
one people learn to route around.

Each also needs to see the code *after* the previous one's fixes landed,
which is why none of them run in parallel. A real session had `/simplify`
land a refactor that was later reverted for an eval-time infinite
recursion, while `docs-updater` ran concurrently and had already written
the reverted design into the plan's Findings as settled fact -- leaving
plan and code contradicting each other until hand-reconciled. That
incident constrains `docs-updater` to follow `/simplify`; it says nothing
about the read-only reviewers, so putting them last costs nothing it
protects.

The two read-only reviewers stay serialized too, for a different reason:
both append `### F<N>` findings to the same plan file, numbering from the
next unused id. Run them concurrently and both pick the same number --
duplicate headings `plan-lint` then rejects, on exactly the runs that
matter, the ones with findings. If parallel tail reviewers are ever
wanted, that is a design constraint on `spec-check`'s finding-append
contract, to settle when `spec-check` is built
(2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#D7),
not a scheduling flag to flip.

**The fix stage is the pass's last step, not a detour.** Findings from
`security` or `spec-check` are applied *after* both have reported, so a
verdict always lands on a settled tree and a fix is never churned on
unreviewed. A non-empty fix stage is what sends the loop back to
`/simplify`; an empty one is the exit. It appears once, at the tail,
because `/simplify` and `docs-updater` apply their own findings as part
of running; the read-only reviewers cannot, and an unnamed handoff is one
that gets skipped.

Any actionable finding from `security` or `spec-check` **restarts the loop
at `/simplify`** -- as does any other manual change the main agent makes
after `/simplify` last ran to code or to anything functionally
load-bearing: a skill script, a git hook, an agent definition (`.md` or
not). Either way the behavior has moved past what
the earlier agents saw, including `docs-updater`, whose description of the
settled state is stale the moment the code moves again. `docs-updater`'s
*own* doc and comment fixes never restart the loop by themselves: they
change no behavior, so there is nothing new for `/simplify` or the
reviewers to judge (decided with the user 2026-09-06, see
2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#D7).
The exception is mechanical rather than a judgment call: if `docs-updater`
edits something inside `PLAN_CODE_GLOBS` -- an agent definition, a script
comment -- the fingerprint moves and the reviewers must run again anyway,
which is the same rule, not a second one.

Termination needs no new machinery. Every finding resolves `fixed`,
`accepted` or `moot`, and `plan-freeze` already refuses while any is
unresolved -- the loop's exit condition is the gate that already exists.
If the same finding recurs across passes, seek the user's sign-off rather
than looping again.

### What a completion stamp proves

`subagent-stamp` appends a stamp to the active plan when a stampable
agent finishes, and `plan-gate` refuses a merge if an obliged agent left
none. The stamp carries a **fingerprint of the code the agent read** --
a content hash over the same `PLAN_CODE_GLOBS` set the trigger table
above names -- and `plan-gate` blocks when it no longer matches. That is
what separates "this agent ran" from "this agent ran against *this*
code": a fix applied after the agent finished leaves a stale stamp and
is caught.

The line the set draws is **behavior, not file extension**. Plan files
and explanatory docs stay out: every stamp appends to a plan file and
`docs-updater` edits docs, so folding prose in would make each stamp
invalidate itself and every stamp before it. Agent definitions are in
even though they are `.md`, because an agent definition is what a
reviewer does, not a description of it.

**What a stamp is not.** It is a record, not proof. `SubagentStop` fires
for any subagent of that type whatever it actually did, so a no-op prompt
produces an identical valid stamp; and the line is plaintext in a file the
author controls, so one `printf` forges one. That is fine against the
adversary this system has -- an agent that forgets a step -- and worth
nothing against one that lies. Real attestation would need a signature
from something the author does not control, which a local hook cannot be.

Consequence for the loop: re-running an agent after a code change is not
etiquette, it is how the merge passes.

**Worktree sessions stamp with the main checkout's scripts.** Hooks
appear to resolve through the session's original project directory (the
effect is confirmed, the mechanism inferred), so a PR that changes
`subagent-stamp` (or any hook script) is never exercised by the sessions
developing it -- its stamps carry whatever format the main checkout's
copy writes, and older formats read as `legacy` NOTEs to the gate. That
is expected, not a failure. After merging a hook-script PR, pull the
main checkout before trusting the new hook behavior (see
2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F12).

### The agents themselves

- **`security`** — reviews firewall rules (`networking.firewall.*`,
  `openFirewall`), secrets wiring (`sops.secrets.*`), newly exposed
  services, systemd hardening flags, and authentication. Read-only,
  report-only — see `docs/agents/security.md`.
- **`docs-updater`** — rewrites any doc or comment the diff touched, or
  that a touched config surface invalidates. Runs after `/simplify` and
  before the read-only reviewers, per the loop above. See
  `docs/agents/docs-updater.md`.
- **`/simplify`** — fires per the table above, no judgment call. Reviews
  for reuse, simplification, efficiency, and condensing into shared
  modules, then applies its own fixes. This is a deliberately cheap
  stand-in for a dedicated repo-aware cleanliness subagent (matching
  `security`/`docs-updater`'s shape — auto-invoked, appending findings
  into the plan) that may be worth building later; see
  `2026-08-27-design-a-diff-scoped-linting-skill-or-subagent.md`. Unlike
  `security`/`docs-updater`, `/simplify` doesn't yet append anything into
  the plan file itself — it just edits the working tree directly.

## Trivial vs. not: worked examples

Line count is not the test. A textually tiny change can still be
substantively risky:

- **Trivial**: fixing a typo in a comment; correcting a doc's wording
  where the underlying fact doesn't change; a one-line formatting fix
  `nixfmt` would have made anyway.
- **Not trivial, despite being one line**: `openFirewall = true` added to
  a service block (security-relevant); a single sops secret reference
  added or removed; a one-line change to a systemd hardening flag; a
  one-character change to a firewall port range.
- **Not trivial, despite being "just a comment"**: a comment describing
  *why* a security-relevant decision was made — that's exactly the kind
  of thing that should be cited to a plan file (see
  `docs/skills/plan/SKILL.md`), which means a plan file needs to exist.

If genuinely unsure, don't skip the gate — `plan-new` is cheap.

## Resuming an in-progress plan across sessions

A new session picking up unfinished work should check
`docs/plans/in-progress/` first, before starting anything: if a plan
already exists for the task, `plan-tick`/`plan-decide` into the *same*
file rather than creating a duplicate. `plan-new` already refuses an exact
duplicate slug, but a near-duplicate title won't be caught mechanically —
grep first.

## Why a hook at all

A skill that just tells the agent "invoke the subagent, then wait for it"
is not a hard gate — confirmed Claude Code behavior (and a live GitHub
issue, closed "not planned") is that a subagent invocation does not
reliably block the calling context by default; skill auto-invocation
itself is documented as unreliable. So this system does not rely on the
`workflow` skill's own sequencing to actually enforce anything. Instead:

- `plan-touch-guard` (`PreToolUse`, blocks `git commit`) checks one
  mechanical fact: did this session touch a plan file, or explicitly
  record a trivial-change acknowledgment? It cannot and does not judge
  whether the *right* subagents ran, or whether the plan content is any
  good — that's out of reach for shell logic, and is not its job.
- `subagent-stamp` (`SubagentStop`) fires whenever `security` or
  `docs-updater` actually *finishes* — regardless of whether the calling
  context waited for it — and appends a timestamped stamp to the active
  plan file. This is what makes "the subagent ran" a checkable fact
  instead of an assumption.
- `footer-guard` (`PreToolUse`) hard-blocks AI-attribution footers in
  commit messages and PR bodies, rather than relying on this file being
  remembered.
- `fresh-branch-guard` (`PreToolUse`) blocks creating a new branch
  (`git checkout -b`/`git switch -c`/`git branch <name>`) when local
  `master` is behind `origin/master` — added after a real incident where
  an entire session's work was branched off stale local `master`, causing
  a large, avoidable rebase against 57 commits of drift once it was time
  to land. `docs/procedures/workflow.md` already said to pull first; this
  is that rule, hardcoded, not just documented.
- The git-level `pre-commit` extensions (frozen-file check, symlink-drift
  check) apply the same logic outside Claude Code entirely — a human
  editing a frozen plan by hand, or forgetting to symlink a new skill, is
  caught the same way.

None of this is exhaustive judgment enforcement — it's a narrow,
mechanical backstop for the handful of facts a script can actually check.
The judgment itself (which subagents apply, whether a change is trivial,
whether the plan content is honest) is still the agent's job.

## What this system does not cover yet

**VM-testing is deliberately not part of this roster.** The scriptable
floor (`verify-ladder`: the gates' own failure-mode tests, format, lint,
eval, targeted build) is hard-gated; booting a VM or running a
`runNixOSTest` is not. A single
`vm-testing` subagent may be the wrong shape for this — it might need to
be several subagents (split by boot-check vs. `runNixOSTest`), or folded
into a broader verification agent. This needs its own research/design
pass before building it — see
`docs/procedures/vm-testing.md` for the manual procedure in the meantime,
and `2026-08-27-design-the-vm-testing-subagent-s.md` for the tracked plan.

**A dedicated linting/lint-scoping skill or subagent may also be worth
building.** `verify-ladder`'s diff-scoped statix/deadnix logic (only
failing on genuinely new issues, never pre-existing debt in a touched
file) came out of a real false-positive hit during this system's own
construction — the same diff-scoping problem could recur anywhere lint
tooling gets added to a gate, and a dedicated skill encoding "how to scope
a linter to a diff, not a whole file" might be worth generalizing beyond
this one script. Not built now — see
`2026-08-27-design-a-diff-scoped-linting-skill-or-subagent.md`.

**A dedicated code-cleanliness subagent (reuse/simplification/module
condensation), matching `security`/`docs-updater`'s auto-invoked,
plan-appending shape, was considered and deliberately deferred** —
`workflow` mandates the existing `/simplify` skill instead for now (see
the subagent-selection table above). Revisit if `/simplify` proves
insufficient for this repo's own module conventions (it isn't repo-aware
the way `security`/`docs-updater` are), or fold it into the diff-scoped
linting skill above if that gets built first.
