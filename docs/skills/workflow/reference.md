# `workflow` skill reference

## Subagent selection

Not every task needs every subagent. Invoke:

- **`security`** — anything touching firewall rules (`networking.firewall.*`,
  `openFirewall`), secrets wiring (`sops.secrets.*`), a newly exposed
  service, systemd hardening flags, or authentication. Read-only,
  report-only — see `docs/agents/security.md`.
- **`docs-updater`** — once the code-level work is otherwise done, for
  anything that touched a doc, a comment, or a config surface a doc
  describes. See `docs/agents/docs-updater.md`.

Neither is required for a purely mechanical change (a version bump, a
rename with no behavior change) — use judgment, and if genuinely unsure,
invoke the one in question rather than skip it silently.

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
- The git-level `pre-commit` extensions (frozen-file check, symlink-drift
  check) apply the same logic outside Claude Code entirely — a human
  editing a frozen plan by hand, or forgetting to symlink a new skill, is
  caught the same way.

None of this is exhaustive judgment enforcement — it's a narrow,
mechanical backstop for the handful of facts a script can actually check.
The judgment itself (which subagents apply, whether a change is trivial,
whether the plan content is honest) is still the agent's job.

## What this system does not cover yet

**VM-testing is deliberately not part of this roster.** The cheap ladder
(`verify-ladder`: format, eval, targeted build) is hard-gated; booting a
VM or running a `runNixOSTest` is not. A single `vm-testing` subagent may
be the wrong shape for this — it might need to be several subagents (split
by boot-check vs. `runNixOSTest`), or folded into a broader verification
agent. This needs its own research/design pass before building it — see
`docs/procedures/vm-testing.md` for the manual procedure in the meantime,
and `design-the-vm-testing-subagent-s-2026-08-27.md` for the tracked plan.

**A dedicated linting/lint-scoping skill or subagent may also be worth
building.** `verify-ladder`'s diff-scoped statix/deadnix logic (only
failing on genuinely new issues, never pre-existing debt in a touched
file) came out of a real false-positive hit during this system's own
construction — the same diff-scoping problem could recur anywhere lint
tooling gets added to a gate, and a dedicated skill encoding "how to scope
a linter to a diff, not a whole file" might be worth generalizing beyond
this one script. Not built now — see
`design-a-diff-scoped-linting-skill-or-subagent-2026-08-27.md`.
