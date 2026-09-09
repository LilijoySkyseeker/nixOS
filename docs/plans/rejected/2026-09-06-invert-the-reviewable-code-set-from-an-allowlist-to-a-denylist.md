---
slug: invert-the-reviewable-code-set-from-an-allowlist-to-a-denylist
created: 2026-09-06
status: rejected
frozen: true
kind: task
priority: normal
blocked_by:
---

# invert the reviewable code set from an allowlist to a denylist

## State

Not started. Filed 2026-09-06 from a `/simplify` altitude finding, after
the allowlist was widened twice in one session and found incomplete a
third time. Deliberately not done inline: it is a design change to the
set that four separate mechanisms read, and the branch that raised it was
already closing.

## Original plan

`PLAN_CODE_GLOBS` in `docs/skills/plan/scripts/lib.sh` decides four
things at once: which review agents a change obliges, what the stamp
fingerprint hashes, what `plan-citations` scans, and what the docs
describe. It is an allowlist, and it has been widened twice in one day:

- **3 entries** originally -- `*.nix`, `docs/skills/*/scripts/*`,
  `.githooks/*`.
- **7** after
  `2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#G11`
  added CI workflows, `.claude/`, `scripts/`, and the agent definitions.
- **11** after that plan's F26 added `.sops.yaml`, `secrets/*`,
  `flake.lock` and `.gitignore`.

Both widenings came from a review agent pointing out that a file which
met the set's own stated rule was not in it. The rule is "behavior, not
prose: what a change to this file set can alter is what the machine
does."

A third round found it is *still* incomplete. All of these meet the rule
and match no glob:

- `modules/home-manager/claude-code/tcr-skill/tests/run-fixture-tests.sh`
  -- an executable script whose sibling `tcr-skill/scripts/*` **is**
  covered, one directory name apart.
- `.envrc` -- `use flake`, runs on `cd` for anyone with direnv.
- `docs/agents.md` -- the general agent-invocation policy, while every
  per-agent file beneath `docs/agents/` is covered.
- `docs/tailscale-acl.json` (weaker -- a reference copy of the tailnet
  access policy).

### The change

Invert. The complement is two entries where the allowlist is eleven:

```sh
PLAN_NONCODE_GLOBS=("*.md" "docs/plans/*")
plan_is_code_path() { ! plan_path_matches "$1" "${PLAN_NONCODE_GLOBS[@]}"; }
```

`docs/plans/*` is needed for `.checksums` and the `.gitkeep` files, which
churn whenever a plan freezes. `docs/agents/*.md` would need re-adding as
an explicit exception, since agent definitions are behavior despite being
`.md` -- so the real shape is a denylist with one carve-out, not a pure
inversion.

### Why the inversion is the right altitude

The two failure modes are not symmetric. An allowlist that misses a file
fails **silently**: the file changes, `required-agents` emits nothing,
the fingerprint does not move, an existing stamp stays valid, and
`plan-gate` prints "all obliged reviews stamped" over an unreviewed
change. A denylist that over-matches fails **loudly and cheaply**: one
extra agent re-run.

The price is real and should be stated plainly: `files/*` holds 14 binary
assets, so a wallpaper swap would move the fingerprint and oblige a
security review. That is the cost of never missing a script again.

### Do this behind the fingerprint work

Changing the set changes the emitted fingerprint for an unchanged tree,
which is the trap
`2026-09-06-make-plan-gate-survive-a-pr-that-changes-the-fingerprint-algorithm-or.md`
is filed against. Sequence this after that plan, or accept the same
one-off staleness the widenings already took.

## Progress

- [ ] confirm the four uncovered files above, and re-scan for others
- [ ] decide the carve-out shape for `docs/agents/*.md`, as a `### D1`
- [ ] invert, keeping `PLAN_DOC_GLOBS` as the primitive both predicates
      share
- [ ] measure the new file count and the fingerprint cost
- [ ] check `plan-citations`' scan set is still sane once it covers
      everything that is not prose

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

**REJECTED 2026-09-09:** superseded: PLAN_CODE_GLOBS now only selects advisory reviewers, so an allowlist gap no longer weakens any enforcement -- 2026-09-09-dismantle-the-blocking-gate-tier-and-keep-the-plan-corpus.md (ADR-0002)
