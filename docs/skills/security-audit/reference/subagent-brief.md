# Subagent brief template

The prompt used for each Phase 1 part agent. All eight agents on the
2026-08-26 run produced usable, correctly-formatted reports on the
first attempt with this structure, so change it deliberately rather
than casually.

Agents start **cold** — they inherit nothing. Everything they need must
be in the prompt or in a file the prompt names.

---

## Template

> You are the **P<n>** security auditor in a fleet-wide security audit
> of this NixOS flake dotfiles repo.
>
> **WORKING DIRECTORY** (absolute — use it for every path):
> `<absolute worktree path>`
>
> **READ THESE FIRST, IN FULL, BEFORE ANYTHING ELSE:**
> 1. `docs/audits/<date>/00-threat-model.md` — adversaries (§5), trust
>    boundaries (§4), the severity rubric you MUST apply (§6), and the
>    recurring failure modes you must actively probe for (§7).
> 2. `docs/audits/<date>/P0-findings.md` — the exact output schema, with
>    worked examples. Copy the format precisely.
> 3. `docs/hardening.md` — the repo's standing rules. Conformance to
>    these is half your job.
> 4. `<any part-specific context doc>`
>
> **YOUR SCOPE** — audit all of these, completely:
> `<explicit file list — not a directory glob>`
>
> **NOT yours** (other agents own them, do not duplicate):
> `<explicit list>`. You DO own this part's own call-site settings for
> those modules.
>
> **FOCUS.** `<why this part matters, in threat-model terms — its blast
> radius, its adversary, its trust role>`
>
> Priority areas: `<3-8 specific things, each with a file:line seed
> where one is known, and what question to answer about it>`
>
> **TWO AXES, both required:**
> (A) **Hardening** — conformance to `docs/hardening.md`, plus general
> review beyond what that doc codifies.
> (B) **Needed/used** — is every option, service, package, firewall
> hole, group membership and secret still actually used and justified?
> Dead config is a finding (INFO, or higher if it grants something).
>
> **RULES:**
> - READ-ONLY with respect to configuration. Do not edit any `.nix`
>   file. Do not run `nixos-rebuild` against a live host. Never
>   `switch`. Never decrypt or read the contents of `secrets/*`.
> - The ONE file you write is your report.
> - **Verify against the PINNED nixpkgs, not from memory.** Option
>   defaults differ by version and that is exactly where a hardening
>   assumption silently fails. Locate the pinned source
>   (`nix eval --raw .#nixosConfigurations.<host>.pkgs.path`) and read
>   the real module under `nixos/modules/`. If you cannot verify a
>   claim, mark it PLAUSIBLE. Do not guess.
> - `nix eval .#nixosConfigurations.<host>.config.<option>` gives the
>   **EFFECTIVE merged value**, which often differs from what any single
>   file says. Use it — especially for firewall port lists, group
>   memberships, and `systemd.services.<name>.serviceConfig`. Slow is
>   fine.
> - Never round PLAUSIBLE up to CONFIRMED.
> - Rate by reachable impact per §6, naming a specific adversary from
>   §5. "An attacker could" is not a reachability statement.
> - Do not re-derive P0's cross-cutting findings; if your part is named
>   as owner of one, confirm or refute it with evidence and reference
>   the `F-P0-NN` id.
>
> **OUTPUT** — write `docs/audits/<date>/P<n>-<slug>.md` containing:
> 1. "Scope and method" — files read, claims verified and how, what you
>    could not verify and why.
> 2. Findings, most severe first, in the schema, ids `F-P<n>-01`...
> 3. `<any part-specific deliverable — e.g. a table>`
> 4. "Checked and clean" — what you examined and found fine.
>
> Then return a summary: counts by severity, your top 3 findings one
> line each, and anything another part needs to know.

---

## Notes on making this work

**Give seeds, not just scope.** Every part brief named 3–8 concrete
things with `file:line` where known. This costs little and dramatically
raises the floor of what comes back. It does not cap the ceiling —
agents consistently found more than they were pointed at.

**Say what they do *not* own.** Without this you get the same finding
eight times. With it, agents cross-reference each other's ids instead.

**Ask for a part-specific deliverable** where one is obviously useful —
a firewall-scoping table, a secrets table, a comparison matrix. Several
of these turned out more valuable than the findings.

**Live access, when it exists, is worth spelling out precisely.** Three
agents ran on the machine being audited. The brief told them exactly
what read-only commands were acceptable and forbade escalation, and
that produced the audit's most decisive evidence. Say which host the
agent is on, and that it must not SSH elsewhere.

**Correct them mid-flight.** Agents run 20–40 minutes. When a material
fact changes, message every running agent. On the last run, learning
the repo was public on GitHub changed severity across all eight parts;
one message per agent fixed it without restarting anything.
