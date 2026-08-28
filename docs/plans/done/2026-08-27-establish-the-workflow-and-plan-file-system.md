---
slug: establish-the-workflow-and-plan-file-system
created: 2026-08-27
status: done
frozen: true
---

# Establish the workflow and plan-file system

## Original plan

The user asked for a fundamental restructuring of how agents and humans
work in this repo: premade subagents and skills, a hard-gated step-by-step
workflow any agentic task goes through, and — the biggest change — repo
work tracked by citeable plan files replacing TODO.md/docs/DONE.md, living
under docs/plans/ in status-based subfolders, append-only, with a
citation scheme like the 2026-08-26 security audit's. Roster requested:
`plan`, `security` (adversarial), `docs-updater`, `vm-testing`, "etc.". A
trust hierarchy (documentation → source → local build → VM test → real
switch) and "a fix that isn't declarative and reproducible is no fix at
all" were specified directly. Designed through extensive back-and-forth
(many AskUserQuestion rounds) plus external research (official Claude Code
docs, a live GitHub issue, evidenced practitioner patterns), then built
and verified phase by phase, live, in this same session.

## Progress

- [x] Phase 1: `plan` skill + scripts + symlink drift-checker, built and
      verified with a throwaway slug (happy path + every refusal path).
- [x] Phase 2: TODO.md (11 entries) + docs/DONE.md (21 entries) migrated
      to 31 plan files (5 todo/, 5 in-progress/, 21 done/), 19 code-comment
      citations retargeted, both source files deleted, cross-links fixed.
- [x] Phase 3: `workflow` skill + all hooks (plan-touch-guard, footer-guard,
      subagent-stamp, verify-ladder, two git-level pre-commit extensions),
      all verified live through the real harness, not just standalone.
- [x] Phase 4: `docs-updater` and `security` subagents built, frontmatter
      validated against the confirmed schema with a real YAML parser.
- [x] Live-invoke `security` and `docs-updater` (see G7) at least once
      each to confirm actual tool restrictions and end-to-end plan-file
      writes — blocked on a session restart. Do this next session before
      calling the roster fully proven, not just built.
- [x] Phase 5: CLAUDE.md, AGENTS.md, trust-hierarchy section + rationale,
      GIT_WORKFLOW.md footer/Plan-trailer note, style-guide.md carve-out.
- [x] `rejected/` category (see D14) retrofitted after Phase 4 was already
      underway — re-skim docs/skills/workflow/{SKILL.md,reference.md} once
      more for any remaining "todo/in-progress/done" (missing "rejected")
      phrasing this session's own edits might have missed.

## Decisions (D)

### D1 — plan-file granularity: does every task get a plan file?

**ANSWERED 2026-08-27:** Tiered by size: genuinely trivial one-off changes skip the plan-file system entirely; anything else gets a full plan file.

### D2 — how should the hard gate actually be enforced?

**ANSWERED 2026-08-27:** Hybrid: the workflow skill carries step-by-step judgment; narrow, purely mechanical hooks (plan-touch-guard, subagent-stamp) backstop the one or two facts a script can actually check. Never relies on the skill's own sequencing to enforce anything by itself.

### D3 — what happens to TODO.md/docs/DONE.md once the new system exists?

**ANSWERED 2026-08-27:** Fully retire and migrate: every TODO.md/docs/DONE.md entry becomes its own plan file, then both source files are deleted.

### D4 — how much authority should the adversarial security subagent have?

**ANSWERED 2026-08-27:** Read-only, report-only: security never edits code or config, only appends Findings to the active plan file.

### D5 — citation ID scheme inside a plan file

**ANSWERED 2026-08-27:** Generalize the 2026-08-26 audit's typed-prefix convention: D<N> decisions, G<N> gotchas, F<N> findings, sequential per type per file.

### D6 — how do citations survive a plan file moving between folders?

**ANSWERED 2026-08-27:** Cite by bare filename + anchor only, never a folder path (superseded an earlier path-based design that needed a fixup script -- see G2).

### D7 — should the workflow gate auto-trigger or require explicit invocation?

**ANSWERED 2026-08-27:** Auto-triggered: the workflow skill's description is written so Claude self-invokes on judged-non-trivial work, backstopped by plan-touch-guard for the cases that get missed.

### D8 — should this restructuring absorb the 2026-08-26 audit branch?

**ANSWERED 2026-08-27:** Leave the audit branch's own unfinished run untouched; harvest only its reusable reference material (finding-schema.md, subagent-brief.md) into the new security subagent now.

### D9 — done-plan freeze semantics: how permanent is "frozen"?

**ANSWERED 2026-08-27:** Fully frozen: zero further edits of any kind once a plan reaches done/ (or rejected/, added later -- D14), not even append-only corrections. New learning becomes a new plan file that cites the frozen one.

### D10 — should skills/subagents be project-scoped or home-manager-managed like tcr?

**ANSWERED 2026-08-27:** Project-scoped, git-tracked directly in the repo (docs/skills/<name>/ or docs/agents/<name>.md canonical, symlinked into .claude/) -- not routed through home-manager like tcr, since these are dotfiles-repo-specific, not repo-agnostic.

### D11 — statix/deadnix: informational, or a real blocker?

**ANSWERED 2026-08-27:** Diff-scoped hard blocking: fail only on statix/deadnix warnings whose line falls inside the actual changed lines (via git diff hunk ranges cross-referenced against each tool's JSON output), never pre-existing debt elsewhere in a touched file.

### D12 — should a SubagentStop hook exist, given subagent calls don't reliably block?

**ANSWERED 2026-08-27:** Yes -- added after research confirmed a skill invoking a subagent doesn't reliably block (G1). subagent-stamp (SubagentStop hook) is the real backbone that makes 'the subagent finished' a checkable fact.

### D13 — should the frozen-file git-level pre-commit check exist?

**ANSWERED 2026-08-27:** Yes -- .githooks/pre-commit gained a frozen-file check (via the checksums manifest) and a symlink-drift check, so both hold for any tool or human, not just a Claude Code session.

### D14 — should there be a fourth "rejected" plan status?

**ANSWERED 2026-08-27:** Yes -- docs/plans/rejected/ added for work started and then abandoned or superseded, distinct from done/'s 'actually completed' semantics.

### D15 — plan-reject's gate: same decision-resolution bar as done/, or reason-only?

**ANSWERED 2026-08-27:** Reason-only, not the full decision-resolution bar: plan-reject requires a mandatory reason but does not require every D-item answered/deferred+carried first, since abandoning the work legitimately moots open questions.

### D16 — should plan-reject have a dedicated revival mechanism?


**ANSWERED 2026-08-27:** No dedicated plan-revive script -- reviving a rejected idea is rare enough that plan-new plus a manual citation to the old rejected file's bare filename is enough.

## Gotchas (G)

### G1 — a skill invoking a subagent does not reliably block by default
Confirmed Claude Code behavior (default/fork-mode interactive sessions run
subagent calls in the background) plus a live GitHub issue closed "not
planned." This is why the gate can't rely on the `workflow` skill's own
step sequence "waiting" — `subagent-stamp` (a `SubagentStop` hook) exists
specifically to make "the subagent finished" a checkable fact instead.

### G2 — path-based citations collide with "frozen forever"
The original design cited plan files by root-relative path
(`docs/plans/done/foo.md#D3`), needing a `plan-cite-fixup` script to
rewrite citations on every move. This created a real deadlock: a frozen
file citing a plan that later moves can never be legally repaired. Fixed
by citing the bare filename instead (`foo-2026-08-27.md#D3`, decision 3,
answered D5/D6 below) — moves stop needing any citation rewrite at all,
and the fixup script became unnecessary.

### G3 — whole-file linting blocks on debt unrelated to the actual edit
`statix check .`/`deadnix .` (and even per-file, un-scoped) surfaced
pre-existing warnings in `modules/home-manager/tmux.nix`,
`modules/services/samba.nix`, `modules/profiles/{PC,default,server}.nix`
that had nothing to do with the one-line citation-comment edits touching
those files. Fixed with true diff-scoped blocking (`verify-ladder`,
line-range-filtered via statix/deadnix's JSON output against `git diff`
hunk ranges) — only genuinely new issues on changed lines block.

### G4 — accidentally deleted the real checksums manifest during test cleanup
While testing `subagent-stamp`, treated `docs/plans/done/.checksums` as
disposable test scaffolding and deleted it — it was actually the real
migration's manifest (21 entries) merged with one test addition. Nothing
was actually lost (the frozen files' content was untouched), but the
manifest had to be regenerated from the actual files' current `sha256sum`.
Lesson: a shared mutable state file (a manifest, a marker) needs the same
care during ad hoc testing as a real content file — clean up *additions*
you made, don't blanket-delete a file you didn't create from scratch.

### G5 — compound shell commands are blocked as a whole unit
`mark-trivial "..." && git commit ...` in a single Bash tool call gets
denied entirely by `plan-touch-guard`, because the `PreToolUse` hook sees
the whole command string and `hook_anchored` correctly matches `git
commit` after the `&&` — the `mark-trivial` half never runs. This is
correct, safe behavior (matches `tcr-guard-hook`'s own anchored-matching
rationale: you can't smuggle a blocked command through a chain), but it
means testing a "do X, then the gated action" sequence needs two separate
tool calls, not one chained command.

### G6 — `${CLAUDE_PROJECT_DIR}` in .claude/settings.json is real, confirmed live
Verified end-to-end through the actual harness (not just by piping JSON
into the hook script by hand): a real `git commit --dry-run` attempt was
genuinely blocked by `plan-touch-guard` via the project-scoped
`.claude/settings.json`, then genuinely allowed after `mark-trivial` ran.
Also empirically captured a real `SubagentStop` payload (via a throwaway
Explore-agent probe) rather than guessing its schema — confirmed
`agent_type`/`cwd` fields exist, which `subagent-stamp` depends on.

### G7 — newly created `.claude/agents/` isn't watched until a session restart
Confirmed via Claude Code's own docs (fetched directly, not from memory):
"the watcher covers only directories that existed when the session
started, so after creating a scope's first agent file in a new `agents`
directory, restart to load it." `.claude/skills/` already existed
(`tcr`... actually no local `.claude/skills/` existed either, but skills
appeared to hot-reload regardless — `.claude/agents/` specifically did
not exist before this session, so `security`/`docs-updater` could not be
live-invoked this session despite both files' frontmatter validating
correctly against the confirmed schema with a real YAML parser. Needs a
fresh session to actually invoke and verify tool restrictions hold.

### G8 — `plan_today` used UTC, producing a wrong date near local midnight
`date -u +%Y-%m-%d` returned 2026-08-28 while local time (and the
session's own stated "today") was still 2026-08-27 (UTC had already
rolled over). Fixed to use local `date +%Y-%m-%d`, matching how the rest
of the repo dates entries.

### G9 — `plan-freeze`'s echoed confirmation broke output chainability
`plan-move ... done` execs `plan-freeze`, whose final line was `"$rel
frozen."` — a human sentence, not a bare path. Anything capturing the
combined script's stdout (as `plan-carry` does when chaining `plan-new`,
and as this session's own test harness did) got the whole sentence
instead of a usable path. Fixed: the confirmation moved to stderr
(`plan_note`), the path alone goes to stdout, matching `plan-new`'s
already-correct convention.

## Findings (F)
*(populated by security/docs-updater when invoked)*

_docs-updater finished 2026-08-28T03:03:01Z -- see Findings above._

### F1 — `environment.persistence` for `/var/lib/samba` is unneeded and needlessly pushes an SMB password hash into offsite/local backups

- **File:** `modules/services/samba.nix:95-143` (samba-user-provision idempotent script) and `modules/services/samba.nix:183-188` (persistence entry + its own comment)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (the idempotent add-or-set logic and the backup dataset list), PLAUSIBLE (the practical exploitability of the resulting hash exposure)
- **Axis:** needed-used (secondary: hardening — needlessly widens what reaches the backup pipeline)
- **Reachability:** Any principal who can read `zbackup/backup/homelab/zroot/local/state` on `homelab` itself (e.g. anyone with root there, or a future bug in zrepl's job scoping across the `torrent`/`thinkpad` backup peers noted in `docs/backups.md`), or — one step further — anyone who obtains both Backblaze bucket access *and* the `homelab_backblaze_restic_password` secret for the weekly offsite copy, gets `android-smb`'s NTLM password hash (`/var/lib/samba/private/passdb.tdb`) and can attempt offline cracking or hash-reuse, entirely avoidably.
- **Rule:** needed-used axis (reference.md "(B) Needed/used"); no direct `docs/hardening.md` line, but it works against the spirit of scoping secret-adjacent material to only where it's needed.
- **Finding:** `samba-user-provision.service`'s own script (lines 135-142) is written to be idempotent on every boot: it runs `pdbedit -L | grep -qx android-smb` and, if the user is *absent* from `passdb.tdb`, runs `smbpasswd -s -a` (add) instead of `-s` (set) — i.e. it already fully reconstructs `android-smb`'s Samba account and password straight from the sops secret when `/var/lib/samba` is empty. That means the `environment.persistence."/nix/state".directories = [ "/var/lib/samba" ]` block's own justification, "Without persisting it, android-smb's SMB password would be wiped by the impermanence rollback and need re-adding after every boot" (lines 183-185), is incorrect: the service *does* re-add it every boot, before `samba-smbd` starts (`before = [ "samba-smbd.service" ]`), with no persistence required. The only practical effect of keeping the persistence entry is that `/var/lib/samba/private/passdb.tdb` — which holds the NT hash of `android-smb`'s SMB password — survives on the `zroot/local/state` dataset, which is (a) locally zrepl-replicated to the unencrypted `zbackup` pool (`myZrepl.placeholderEncryption` defaults off there per `docs/backups.md`) and (b) explicitly one of the two datasets snapshotted and pushed to Backblaze by `restic-backups-backblazeWeekly` (`hosts/homelab/configuration.nix:110`: `datasets="zroot/local/state zdata/storage/storage"`). Dropping the persistence entry would remove this hash from both backup paths at zero functional cost, since the account is already rebuilt from the sops secret (the actual source of truth) on every boot regardless.
- **Fix risk:** Removing the `environment.persistence` entry needs a live-reboot test on `homelab` to confirm `samba-user-provision` really does complete the `smbpasswd -s -a` add-path cleanly against a freshly-created (empty) `/var/lib/samba/private` before `samba-smbd.service` starts — in particular confirm no other file under `/var/lib/samba` (e.g. `secrets.tdb`) is silently relied on elsewhere, and that no ordering race exists between `systemd-tmpfiles-setup.service` (which creates `/var/lib/samba/private`) and `samba-user-provision.service` on a from-scratch boot.

### F2 — smb.conf's `hosts allow`/`hosts deny` pair is IPv4-only, silently inert for tailnet clients reaching homelab over its Tailscale IPv6 address

- **File:** `modules/services/samba.nix:49-53` (settings), `modules/services/samba.nix:181` (firewall rule)
- **Severity:** LOW
- **Confidence:** PLAUSIBLE (Samba's own "hosts allow"/"hosts deny" fallthrough default and Tailscale's dual-stack address assignment are both well-documented behaviors, but not independently re-verified against the pinned samba package's source/docs here, and not tested live)
- **Axis:** hardening
- **Reachability:** Any device on the tailnet that reaches `homelab` via its Tailscale IPv6 (`fd7a:115c:a1e0::/48`-range) address rather than its `100.64.0.0/10` IPv4 address — Tailscale assigns both to every node — connects to smbd on port 445 (opened host-wide on `tailscale0` for both address families by NixOS's interface-scoped firewall rule) without matching either `"hosts allow" = "100.64.0.0/10"` or `"hosts deny" = "0.0.0.0/0"`, both of which are IPv4-only CIDR literals. The comment at line 49-51 calls this pair "defense-in-depth on top of the tailscale0 firewall interface scoping," but for v6 traffic it provides none — the client isn't a new adversary (already tailnet-authorized), but the stated second layer doesn't actually cover the full traffic the interface-scoped rule admits.
- **Rule:** n/a — new-rule candidate ("interface-scoped/CIDR-scoped defense-in-depth restrictions should cover both address families reachable on the scoped interface, or say why not").
- **Finding:** the primary control (tailscale0 interface-only firewall + WireGuard auth) still holds regardless, so this doesn't admit any host that wasn't already tailnet-authorized — but it does mean the documented "belt-and-suspenders" smb.conf-level restriction is only real for IPv4 tailnet traffic, contrary to what the comment implies.
- **Fix risk:** low — adding an IPv6 CGNAT-equivalent entry (Tailscale's ULA range) to both `hosts allow` and `hosts deny` should be safe, but needs confirming the exact current Tailscale IPv6 prefix in use (it's assigned per-tailnet, not a global constant) before hardcoding it.


**Checked and clean (security review of `modules/services/samba.nix`, 2026-08-27):**
Reviewed the whole file plus everything it touches: `users.users.android-smb`
(confirmed via `nix eval` — `shell` resolves into `shadow`'s nologin,
`hashedPassword = null`, `isNormalUser = false`, so no Unix-password/login
path exists, only the tdbsam SMB password), the merged `services.samba`
settings against the pinned NixOS `samba.nix` module source (`invalid users
= [ "root" ]` matches upstream's own default; `openFirewall = false` is
correctly not relied on — port 445 is opened only via
`networking.firewall.interfaces.tailscale0.allowedTCPPorts`, confirmed via
`nix eval .#nixosConfigurations.homelab.config.networking.firewall.interfaces.tailscale0.allowedTCPPorts`
→ `[ 22 445 2049 8096 25565 ]`), the `wide links`/`follow symlinks` share-escape
guards, the printer/RPC surface reduction (`disable spoolss`, `load
printers = false`), the `samba-user-provision`/`samba-smbd` systemd unit
merge (confirmed via `nix eval` on both units' full `serviceConfig` — no
key collisions with the upstream module's `ExecStart`/`Type=notify`/etc,
hardening flags land as written), the root-as-smbd justification (confirmed
against the pinned samba.nix module: no `User=`/group option exists on
`cfg.smbd`, so root is genuinely unavoidable there, matching the file's own
comment), the sops secret wiring (`homelab_samba_android_smb_password`
exists as ciphertext in `secrets/secrets.yaml` with `restartUnits` correctly
pointed at `samba-user-provision.service`; did not decrypt it), the
`multimedia` gid (999, shared consistently with `jellyfin.nix` and
`nfs.nix`'s pre-existing trust model — not a new exposure introduced by this
file), and confirmed no dead `copyparty` config was left behind after
`nfs.nix`'s comment that it replaced a prior copyparty-based share
(`copyparty-iso.nix` is an unrelated ISO-serving module). Two findings
above (F1 needed-used/MEDIUM, F2 hardening/LOW); nothing CRITICAL/HIGH
found. Did not decrypt or inspect `secrets/secrets.yaml`'s contents per
`docs/procedures/secrets.md`.

_security finished 2026-08-28T03:06:53Z -- see Findings above._
