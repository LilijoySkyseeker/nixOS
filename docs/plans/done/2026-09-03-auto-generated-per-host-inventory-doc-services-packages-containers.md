---
slug: auto-generated-per-host-inventory-doc-services-packages-containers
created: 2026-09-03
status: done
frozen: true
---

# Auto-generated per-host inventory doc (services, packages, containers, storage, firewall, timers, users, secrets)

## Original plan
Add a `nix run .#doc-host <hostname>` flake app that evaluates
`nixosConfigurations.<host>.config` and writes a machine-generated
`<!-- inventory:start -->…<!-- inventory:end -->` block into
`hosts/<host>/README.md`, covering: enabled `services.*`, `environment.
systemPackages`, `virtualisation.oci-containers` containers, ZFS/other
`fileSystems`, per-interface firewall ports, `systemd.timers`, users
(`isNormalUser`/`isSystemUser`), and `sops.secrets` names in use. Goal is
a comprehensive at-a-glance "what does this host actually run" doc for
easier review, per the user's request. Run it for every host and commit
the populated READMEs. Also propose (not necessarily build yet) options
for keeping the block from going stale between manual runs.

## State
**2026-09-03, done.** Implemented as `scripts/doc-host.sh <host>|--all`,
invoked directly (bash, like `scripts/bootstrap-host.sh`) -- no
`modules/flake/doc-host.nix` flake-app wrapper after all, since nothing
else in this repo's `scripts/` uses that pattern and a plain script
matches existing convention better. Ran `--all`; every `hosts/*/
README.md` now has a populated `<!-- inventory:start/end -->` block.
`/simplify` (4 parallel angles: reuse/simplification/efficiency/
altitude), `security`, and `docs-updater` all ran and their findings
were applied or resolved (F1-F4, all fixed). D1 answered: staleness
prevention is now the `docs-updater` subagent's job (see
`docs/agents/docs-updater.md`'s "Host Inventory freshness" section) --
no separate pre-commit hook or `nix flake check` derivation. All
Progress items and Decisions/Findings are closed; ready to commit.

## Progress
- [x] `scripts/doc-host.sh` extraction + marker-block rewrite
- [x] Generated block for all 5 hosts
- [x] verify-ladder
- [x] `/simplify`
- [x] `security` subagent
- [x] `docs-updater` subagent
- [x] D1

## Decisions (D)
### D1 -- how should the inventory block avoid going stale between manual runs?
Options on the table: (a) a diff-scoped pre-commit hook, matching this
repo's existing `verify-ladder`/frozen-file/symlink-drift hooks, that
re-runs `doc-host` for any host whose `hosts/`/`modules/` files changed
in the commit and blocks if the working tree's README doesn't match the
regenerated output; (b) a `nix flake check` integration (a
`checks.<system>.doc-host-<host>` derivation that fails the check if the
committed README block is stale) — runs in CI/`nix flake check` but not
on every commit; (c) leave it manual (`nix run .#doc-host <host>`,
documented in `docs/procedures/`) and accept drift risk. Not yet decided
-- awaiting user's choice.


**ANSWERED 2026-09-03:** user: fold this into the docs-updater subagent's own job instead of a separate pre-commit hook or nix flake check derivation. Implemented: docs/agents/docs-updater.md now has a 'Host Inventory freshness' section directing it to re-run scripts/doc-host.sh <host> for any host whose config changed in the diff it's reviewing, and it's listed in the pass's Rubric. docs/procedures/updating-documentation.md updated to point at this as the enforcement mechanism inside the workflow gate (still discipline-only for changes made outside that gate).

## Gotchas (G)
### G1 -- ZFS pool/mirror topology isn't visible in evaluated `config`
`disko.nix`'s pool layout (which pools are mirrors, USB enclosure
details) doesn't surface in `nixosConfigurations.<host>.config` the way
runtime NixOS options do. The Storage section instead lists
`config.fileSystems` (mountpoint -> device/fsType, filtered to `zfs`/
`nfs*`), which captures dataset-to-mountpoint mapping but not pool
redundancy. Full pool topology would need hand-maintained prose (as
today's READMEs already have) or bespoke per-file `disko.nix` parsing --
not attempted here.

### G2 -- NFS export/Samba share detail is coarse
`services.nfs.server.exports` is a single freeform multiline string and
`services.samba.settings` mixes global config with per-share sections
with no reliable discriminator. The generator shows whether these
services are enabled (flat Services list) but doesn't parse export
paths/share names out of either.

### G3 -- some nixpkgs option-compat shims throw `abort`, not `throw`, on read
Confirmed live: probing every `services.<name>.enable` (to find what's
enabled) crashes outright on a handful of names whose
`mkRenamedOptionModule`/`mkRemovedOptionModule` shim is itself broken
upstream (`services.frp.enable` -> a `services.frp.instances."".enable`
that doesn't exist; also hit on `redis`, `vmalert`). `builtins.tryEval`
catches `throw` but **not** `abort` -- nothing in-language can catch
`abort`. `fetch_services()` in `scripts/doc-host.sh` works around this by
retrying the batch probe, parsing the offending top-level service name
out of nix's own error trace, and excluding it, rather than hardcoding a
list that would rot as nixpkgs adds more of these. Whole-submodule
serialization has the same class of problem for non-`services` fields
too (e.g. `systemd.timers.fstrim.startLimitBurst` has no default and was
never set) -- fixed there by only pulling the specific leaf fields
actually rendered instead of returning whole submodules to `--json`.

`/simplify`'s altitude pass flagged that this retry/exclude mechanism is
scoped only to `services` (the empirically-hit namespace) rather than
generalized into a shared helper the other `apply_rest` namespaces
(`users.users`, `fileSystems`) could also use if they ever hit the same
class of upstream `abort`. Deliberately not generalized now -- no
evidence those namespaces actually hit it, and speculative
generalization for a hypothetical is exactly the kind of premature
abstraction this repo avoids. Revisit if a future host/nixpkgs bump
trips the same failure outside `services`.

### G4 -- `users.users` with `isSystemUser`/`isNormalUser` is noisy
Every host's Nix build-user pool (`nixbld1`..`nixbld32`) and `nobody`
have `isSystemUser = true` and show up identically to genuinely
meaningful dedicated service users (`health-check`, `android-smb`,
`octodns`). There's no mechanical NixOS-config-level property that
distinguishes "this repo hand-declared this account" from "some enabled
service module auto-created this account" -- that provenance only exists
in the repo's own `.nix` source text, not in evaluated config. Landed
compromise: drop `nixbld[0-9]+`/`nobody` (unambiguous, permanent-pattern
boilerplate) and split the rest into "Human" (`isNormalUser`) and
"System" (`isSystemUser`, everything else) with an explicit caveat in
the rendered doc that "System" still isn't purely this-repo's-own
accounts.

## Findings (F)
### F1 -- hand-rolled per-branch `rm -f` cleanup had gaps under `set -e`
`scripts/doc-host.sh`'s per-host temp-file cleanup used to be hand-rolled
per-branch `rm -f` calls rather than a single `trap ... EXIT`. That had
gaps: a mid-loop failure under `set -e` (e.g. one host's `nix eval`
failing) could exit the script before that branch's `rm -f` ran, leaking
the current host's temp files. Fixed by collecting every mktemp'd path
across every host into one array and removing them all in a single
`trap 'rm -f "${tmpfiles[@]}"' EXIT`, matching
`scripts/bootstrap-host.sh`'s existing trap-cleanup convention instead of
re-deriving a weaker version of it.
- **File:** `scripts/doc-host.sh:178-179`


**FIXED 2026-09-03:** trap-based cleanup applied in scripts/doc-host.sh (tmpfiles array + single trap ... EXIT), replacing the hand-rolled per-branch rm -f calls

### F2 -- docs-updater pass, 2026-09-03
Verified `scripts/doc-host.sh`'s header/inline comments against its actual
behavior (usage, marker-block idempotency, jq/nix requirement) -- all
accurate, no changes needed there. Found and fixed two citation-form
violations: the header comment cited this plan as a folder path
(`docs/plans/.../2026-09-03-...md`) instead of the bare-filename+anchor
form, and one inline comment cited "this task's plan file G3" with no
filename at all -- both now `# plan:
2026-09-03-auto-generated-per-host-inventory-doc-services-packages-containers.md#G3`.
Also found two comments duplicating multi-sentence "why"/incident prose
that was already captured (near-verbatim) in G3 and not yet captured
anywhere for the trap-cleanup rationale (F1 above) -- shortened both to a
one-line technical note plus a `# plan:` citation, per
`docs/style-guide.md`'s "Why context" section. No stale/inaccurate prose
found in `docs/procedures/new-host.md` or elsewhere claiming host READMEs
are purely hand-written; added a pointer to `scripts/doc-host.sh`
instead (see below) since none existed before this task.

_docs-updater finished 2026-09-03T21:28:09Z -- see Findings above._


**FIXED 2026-09-03:** docs-updater's own pass summary -- citation-form fixes and comment trims it made are already reflected in scripts/doc-host.sh; nothing further to action

### F3 -- `fetch_services()` splices nix's own error-derived option name into evaluated Nix source unescaped
- **File:** `scripts/doc-host.sh:134,140` (`fetch_services()`)
- **Severity:** LOW
- **Confidence:** CONFIRMED (mechanism) / theoretical under the current pin (exploitability)
- **Axis:** hardening
- **Reachability:** No adversary reachable today. `exclude_nix="[ $(printf '"%s" ' "${excluded[@]}")]"` builds a Nix
  list literal by directly interpolating `$bad` -- an option name parsed out of nix's own stderr via
  `grep -oP "while evaluating the option \`services\.\K[^.']+"` -- with no quoting/escaping, and that value is then
  spliced a second time into the `--apply` Nix source string passed to `nix eval` (`let excluded = $exclude_nix; ...`).
  If `$bad` ever contained an embedded `"` it would break out of the Nix string literal and let arbitrary trailing
  Nix source run with the ambient authority of the invoking `nix eval` (filesystem-reading builtins etc., which could
  then be echoed into the generated README). Verified live against the pinned nixpkgs
  (`nix eval --json '.#nixosConfigurations.homelab.config.services' --apply <probe>`) that the actual `abort`-triggering
  compat-shim names hit today (`frp`, and per the plan's G3, `redis`/`vmalert`) are plain lowercase identifiers with no
  quote/backslash chars -- nixpkgs' own module system uses ordinary Nix identifiers for `services.<name>` almost
  universally, so producing an injecting name would require either a nixpkgs revision that deliberately declares
  `services."foo\""` (not present in the pinned lock) or a supply-chain compromise of the pinned nixpkgs input --
  which already grants far larger code-execution reach via normal `nixos-rebuild switch` than this eval path does.
  $host itself (interpolated into the `.#nixosConfigurations.$host...` installable argument, a separate mechanism
  from this one -- CLI attrpath syntax, not Nix source text) is not part of this finding: it's parsed by nix's own
  installable grammar, which has no way to reach arbitrary expression evaluation through dotted-attr selection alone,
  and its value is always operator-supplied (direct CLI arg) or drawn from `hosts/*/` directory names already
  version-controlled in this repo -- never externally/adversary supplied.
- **Rule:** n/a (no existing `docs/hardening.md` rule covers shell-to-Nix-source interpolation)
- **Fix risk:** Escaping `$bad`/list members (e.g. building the list via `jq -Rn` into JSON and feeding it through
  `builtins.fromJSON` instead of hand-building a Nix string literal) is a small, low-risk change confined to
  `fetch_services()`; would need re-testing against the same `frp`/`redis`/`vmalert`-style abort cases to confirm the
  retry loop still terminates.


**FIXED 2026-09-03:** validated $bad against ^[A-Za-z0-9_-]+$ before splicing into evaluated Nix source (scripts/doc-host.sh); anything else aborts the retry loop instead of being interpolated

### F4 -- marker-block rewrite silently discards trailing README content if the start marker is ever unpaired
- **File:** `scripts/doc-host.sh:207-221` (the `awk` block-replace)
- **Severity:** LOW
- **Confidence:** CONFIRMED (reproduced standalone: an input file with `<!-- inventory:start -->` present but no
  matching `<!-- inventory:end -->` before EOF has every line after the start marker dropped, including any
  hand-written prose that followed a stray/duplicated marker, with zero error/warning output, and the script exits 0)
- **Axis:** hardening (general review -- contradicts the script's own documented invariant)
- **Reachability:** No external adversary; the actor is a future editor of this repo (or a bad merge-conflict
  resolution that leaves an orphaned `inventory:start` line, e.g. git conflict markers interleaved with the
  inventory block) running `scripts/doc-host.sh` afterward. The header comment states "Idempotent: only the
  `<!-- inventory:start/end -->` block is touched, everything else in the README is left alone" -- that invariant is
  false once the markers are ever unpaired, and the failure mode compounds: the rewritten output also lacks a
  closing `inventory:end` marker (the `awk` script only emits `end` when it saw one in the original input), so every
  subsequent run repeats the truncation with no self-healing. This matters more than it otherwise would because the
  plan's still-open D1 decision is whether to run this unattended from a pre-commit hook or `nix flake check` --
  either would remove the "someone reviews the diff before committing" safety net that currently catches this kind
  of silent truncation.
- **Rule:** n/a
- **Fix risk:** Have the `awk` script (or a pre-check in the bash wrapper) fail loudly instead of silently truncating
  when a start marker is seen without a subsequent end marker before EOF. Low risk, self-contained to the
  block-replace logic; test with a deliberately malformed README fixture (start marker, no end marker) and confirm
  the script now errors instead of writing.


**FIXED 2026-09-03:** awk marker-replace now exits 1 on an unpaired start marker (no matching end before EOF) instead of silently truncating; verified against paired/unpaired/no-marker fixtures

## Checked and clean

Reviewed `scripts/doc-host.sh` in full (all `nix eval`/`--apply` call sites, the `fetch_services` retry loop, jq
rendering, and the `awk` marker-replace), the generated diffs for all five `hosts/*/README.md` files, the three
docs-updater changes (`docs/architecture.md`, `docs/procedures/new-host.md`,
`docs/procedures/updating-documentation.md`), and confirmed no `.nix` module, firewall rule, secrets wiring, or
systemd unit was touched by this change (`git diff HEAD --stat` / `git diff --cached --stat` combined show only the
new script, the plan file, and README/docs prose).

Specifically checked the two things flagged as worth extra scrutiny:

- **`$host` interpolation into `.#nixosConfigurations.$host...` installable strings** (both the direct
  `nix eval ... --apply "$apply_rest"` call and `fetch_services`'s use) is safe: it's consumed by nix's own
  installable/attrpath parser as a dotted attribute path, not fed through the Nix language evaluator as source text,
  so it cannot reach arbitrary-expression evaluation regardless of content, and its value is always either a direct
  CLI argument from whoever runs the script locally or a `hosts/*/` directory name already committed to this
  version-controlled repo -- never data from an untrusted/remote source. (The separate, real string-interpolation
  concern in `fetch_services` is `$exclude_nix`/`$bad`, written up as F3 above.)
- **Secret *names* (never values) written into committed READMEs**: cross-checked every name that appears in the
  five generated "Secrets in use" sections (e.g. `homelab_backblaze_restic_password`, `vps_wireguard_private_key`,
  `tailscale_authkey_*`) against `git grep` over the tracked `.nix` files and confirmed each already appears
  verbatim in an already-committed, already-public `sops.secrets.<name>` reference in that host's
  `configuration.nix` -- this repo's `secrets/secrets.yaml` itself is already public per
  `docs/procedures/secrets.md`, and secret *names* were already fully enumerable from the tracked `.nix` source
  before this change existed. The new READMEs are a reformatting of already-public information, not a new
  disclosure. (Did not decrypt or inspect any secret value, per this task's own rules.)

Also checked: firewall/storage/user/timer data rendered into the READMEs is likewise all sourced from already-public
`.nix` config in this repository (itself public, per `docs/procedures/secrets.md`), so the aggregation doesn't
create reconnaissance value beyond what full repo read access (which any reader of this public repo already has)
already provides. No new `flake.nix`/`modules/flake/*` wiring was added (the plan explicitly dropped the flake-app
approach in favor of a plain script, consistent with `scripts/bootstrap-host.sh`'s existing convention) and nothing
invokes `scripts/doc-host.sh` automatically yet (D1 is still open, undecided, correctly not yet built). `jq` and
`nix` are both already present in the devshell (`modules/flake/debug-tools.nix`), matching the script's documented
requirement. Did not find any dedicated-user/systemd-hardening/firewall-scoping/privilege issue introduced by this
change, since it adds no systemd unit, no firewall rule, and no privilege grant -- it's a read-only reporting script
over already-evaluated config, run manually, writing only to committed markdown.

_security finished 2026-09-03T21:29:52Z -- see Findings above._
