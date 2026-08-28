# `security` subagent reference

Adapted from the 2026-08-26 fleet-wide security audit's reference material
(`docs/skills/security-audit/reference/{finding-schema,subagent-brief}.md`
on the unmerged `worktree-security-audit-plan` branch) — that material is
proven (all agents on that run produced usable, correctly-formatted
reports on the first attempt), harvested here per the user's explicit
instruction, narrowed from a fleet-wide multi-part audit down to a single
per-task review. The audit branch's own findings/decisions are not part of
this — only the reusable method.

## Two axes, both required

**(A) Hardening** — conformance to `docs/hardening.md`, plus general
review beyond what that doc codifies.

**(B) Needed/used** — is every option, service, firewall hole, group
membership, and secret this task touches still actually justified? Dead or
over-broad config is a finding (INFO, or higher if it grants something).

## Severity rubric

Rate by **reachable impact**, not by how alarming the misconfiguration
looks in isolation.

- **CRITICAL** — unauthenticated RCE or root from an internet-facing
  adversary; anything yielding fleet-wide root; destruction of backups.
- **HIGH** — root or full data access for an adversary who has already
  achieved a *plausible* first step. Any secret exposed to a principal
  that shouldn't hold it.
- **MEDIUM** — meaningful privilege or reach beyond what a principal
  needs, requiring a chain or a non-default condition. Includes a
  violation of an existing `docs/hardening.md` rule with no currently
  demonstrable exploit.
- **LOW** — defence-in-depth gaps, missing sandboxing on a low-value unit,
  logging holes, unsafe defaults nothing currently depends on.
- **INFO** — dead/unused config, over-broad grants with no demonstrated
  reach, documentation that no longer matches the config.

## Two required qualifiers on every finding

**Reachability** — name the adversary and the path. "A firewall rule is
too broad" is not a finding; "reachable from the LAN by any device on
homelab's subnet, since the rule isn't interface-scoped" is.

**Confidence** — `CONFIRMED` (lines read, behavior verified against the
pinned source) or `PLAUSIBLE` (inferred, needs checking). Never round
`PLAUSIBLE` up to `CONFIRMED` to make a point land harder.

## Verify against the pinned source, not memory

Option defaults differ by nixpkgs version — that's exactly where a
hardening assumption silently fails. `nix eval
.#nixosConfigurations.<host>.config.<option>` gives the effective merged
value, which often differs from what any single file says; use it,
especially for firewall port lists, group memberships, and
`systemd.services.<name>.serviceConfig`. If a claim can't be verified this
way, mark it `PLAUSIBLE` — don't guess.

## Finding format

Append to the active plan file's `## Findings (F)` section, one `###`
block per finding, `<N>` = next unused number in that file:

```markdown
### F<N> — <short title, the claim itself>

- **File:** `path:line` (or several)
- **Severity:** CRITICAL | HIGH | MEDIUM | LOW | INFO
- **Confidence:** CONFIRMED | PLAUSIBLE
- **Axis:** hardening | needed-used
- **Reachability:** <adversary> — <the path>
- **Rule:** violates `docs/hardening.md` "<which>" | new-rule candidate | n/a
- **Finding:** what is actually true, and why it matters here.
- **Fix risk:** what applying a fix could break, and what must be tested.
```

No "Proposed fix" field applied directly -- this subagent is read-only and
report-only (see `docs/agents/security.md`); note what a fix would need to
address, not a diff.

## Checked and clean

End your report (in the plan file, as a short paragraph, not a new
Findings entry) with what you examined and found fine. This is not
optional filler -- it's what tells the next person what was actually
covered, and stops the same ground being re-derived later.
