---
slug: build-and-test-a-full-restore-suite-scripts-proced
created: 2026-08-25
status: in-progress
frozen: false
kind: task
priority: normal
blocked_by:
---

# build and test a full restore suite (scripts + procedures) against real data — out of scope of the zrepl migration itself

## State

**2026-09-09.** `scripts/restore-drill` built and all five restore paths
(file / dataset / stream / rollback / restic) exercised against real
backup data, including a real-mode file recovery (per-run scratch, glob,
real dest); `docs/procedures/backup-restore.md` rewritten as the
script's runbook, D2's staleness marker declared in homelab's config
(built, not deployed). Reviews done: /simplify 4-way pass applied (G6),
docs-updater (F1 fixed), security (F2 HIGH + F3-F5 MEDIUM + F6 INFO,
all fixed -- every remote splice now printf-%q-quoted, mux socket out
of /tmp, arithmetic input validated, cross-host recv recipe hardened).
Remaining: the real-scale restore-timing check (873G
`zdata/storage/storage` restore into `zbackup/restore-drill/big-recv`
in flight on homelab at ~23MB/s, ~8h to go -- result to be recorded
here), one full composite `drill` re-run after that finishes (also
creates the success marker; note the marker sits in unpersisted /var/lib
until homelab deploys the new persistence entry, so the first
post-deploy reboot will page "marker missing" once -- re-run the drill
to clear it), and deploying homelab when the user says so.

## Original plan

- [ ] **2026-08-25: build and test a full restore suite (scripts +
      procedures) against real data — out of scope of the zrepl
      migration itself.** The zrepl migration (branch
      `worktree-zrepl-migration-plan`) documents restore *paths* in
      `docs/procedures/backup-restore.md`, but per its handoff notes
      these remain unexercised against real data: the VM test
      (`docs/procedures/vm-testing.md`) only covers clone-based file
      recovery, and rollback / full-dataset restore have never been
      run for real. Needs: actual restore drills (clone-based file
      recovery, full-dataset rollback, disaster-recovery-from-scratch)
      for each host's `zbackup/backup/<host>/...` data, ideally scripted
      and repeatable rather than one-off manual runs, plus writing up
      the verified procedure in `docs/procedures/backup-restore.md` in
      place of the current unexercised steps. Supersedes the 2026-08-20
      "`docs/procedures/backup-restore.md` needs real content" entry,
      moved to `docs/DONE.md` 2026-08-25 once confirmed the doc already
      has real (if unexercised) content — this item is what's left.

**2026-09-04 addendum:** workshopped into a tiered backup-testing design.
This plan is now specifically **Tier 3** of that design — the rare,
manual, full-scale drill (full-dataset restore, disaster-recovery-from-
scratch, against real data) — rather than the whole testing effort. A
cheap, fully automated **Tier 1** (canary-file restore-and-verify, daily
for `zbackup`/weekly for restic, wired into the existing Discord alert
pipeline) now runs independently and is tracked in
`2026-09-04-automated-canary-based-backup-restore-and-verify-tier-1.md` —
that plan does not replace this one, since a canary file restoring
correctly says nothing about whether a multi-hundred-GB real restore
completes in a sane time or preserves real-world file metadata
(permissions, xattrs, symlinks, unusual filenames). A previously-considered
middle tier (an automated monthly real-dataset spot check) was dropped as
its own cadence — not necessary to satisfy "tested regularly, fails
loudly," which Tier 1 already covers — and its value (real data, at real
scale) folded into this plan's scope instead: the drill(s) built here
should include a real-data restore-timing/fidelity check, not just the
mechanics already covered by Tier 1's canary.

**2026-09-04, second addendum (user):** the drill must be a hybrid of
fire-drill and real recovery tooling, not a separate test harness that
imitates one. The script(s) and runbook this plan produces should *be* the
actual procedure a real disaster recovery would run — the goal is that
running the drill periodically **is** exercising the real deal, so there
is never a gap between "what we tested" and "what we'd actually do,"
which is the classic way DR runbooks silently rot: a test script drifts
from the real procedure and nobody notices until the real recovery hits a
step the drill never covered. Concretely: `docs/procedures/backup-restore.md`
should stop being hand-written prose describing commands to type, and
become (or directly wrap) the same scripted procedure the drill executes
-- one artifact, used for both the periodic drill and a real recovery,
not two that are supposed to stay in sync by discipline.

## Progress
- [x] `scripts/restore-drill` -- one tool for drills and real recovery
      (file / dataset / stream / rollback / restic / cleanup), per the
      second addendum's hybrid directive
- [x] drill: clone-based file recovery from a real zbackup snapshot
- [x] drill: full-dataset send|recv restore + GUID + content verify
- [x] drill: cross-host stream path (zfs send over ssh from the
      operator machine)
- [x] drill: snapshot/mutate/rollback lifecycle
- [x] drill: restic offsite restore from B2
- [ ] real-scale restore-timing check (multi-hundred-GB dataset)
- [x] rewrite `docs/procedures/backup-restore.md` to wrap the script
- [x] G1
- [x] G2
- [x] G3
- [x] G4
- [x] G5

## Decisions (D)

### D1 -- real `zfs rollback` stays a bare command, not a script mode
The drill proves the snapshot -> mutate -> rollback mechanics on a
scratch dataset, but `restore-drill` deliberately has no "roll back this
live dataset" mode: a real rollback is a single `zfs rollback -r
<ds>@<snap>` whose whole risk is deciding to run it, and wrapping it in
tooling would only make the destructive step easier to reach than the
safe ones. Runbook documents the bare command instead.

### D2 -- drill cadence is enforced by a staleness marker, not left as prose
An all-PASS `restore-drill drill` touches
`/var/lib/restore-drill/last-drill-success` on homelab, watched by
`myHealthAlerts.staleMarkerFiles` at 2160h (90 days, i.e. a quarterly
drill cadence) and persisted through impermanence like restic's marker.
Chosen over a "run the drill periodically" sentence in the runbook
because a hand-written last-verified date rots invisibly -- this converts
"we haven't drilled lately" into the same dead-man's-switch alert the
rest of the backup stack already uses. Named `last-drill-success` (not
`last-success`) because `staleMarkerFiles` asserts unique basenames
across entries. The 90-day threshold is a first guess -- tune to taste.

## Gotchas (G)

### G1 -- the doc's cross-host restore recipe was impossible as written
`docs/procedures/backup-restore.md` said to restore a dataset to torrent
via `zfs send ... | ssh root@torrent zfs recv ...` from homelab. torrent
and thinkpad set `PermitRootLogin = "forced-commands-only"` with zrepl's
stdinserver as the only root key (`hosts/torrent/configuration.nix`,
`docs/backups.md`) -- homelab cannot open an interactive root session or
run an arbitrary `zfs recv` there, by design. The workable direction is
the reverse: from the target host (or the operator machine), pull the
stream out of homelab -- `restore-drill stream --src <ds> | run0 zfs
recv -u <local-ds>` -- since operator machines do have root SSH *to*
homelab. Doc corrected to match.

### G2 -- a bare `zfs clone` of a backup snapshot is unusable: everything under zbackup is mountpoint=none
The doc's file-recovery recipe (`zfs clone <snap> zbackup/restore-scratch`)
produces a clone that inherits `mountpoint=none` from the zbackup
container (deliberate, see `docs/backups.md`), so there is nothing to
copy files out of. A working clone needs explicit properties:
`zfs clone -o readonly=on -o mountpoint=<scratch-mnt> <snap> <clone-ds>`.
`readonly=on` is cheap hygiene on top -- the Tier 1 module's G3 covers
why forcing clone properties instead of inheriting is also
defense-in-depth. Doc corrected; `restore-drill file` does exactly this.

### G3 -- GNU find's `-size -1M` matches only empty files, and an unmatchable find walks the whole dataset
find rounds sizes *up* to the unit before comparing, so every non-empty
file under 1MiB rounds to "1M" and fails `-size -1M`; combined with
`-size +0` nothing can ever match, and the drill's sample-file pick hung
walking torrent's entire 3.14T home clone with `head -zn 3` never
filling. `-size -1024k` (k-unit rounding) is the correct "under 1MiB".
Caught live on the first drill run.

### G4 -- `diff -rq` cannot compare sockets, so a byte-identical restore still exits 1
thinkpad's root dataset carries live sockets under /tmp (X11, sddm,
ICE); for each, diff reports "X is a socket while Y is a socket" and
exits nonzero even though both sides match in type and the restore is
byte-perfect everywhere else. Any full-tree verify of a restored real
dataset must treat same-type special-file pairs as equal
(`restore-drill` filters them) or it will fail on every dataset that was
snapshotted while software was running. Snapshot GUID equality is the
authoritative integrity check anyway -- the tree diff is a
belt-and-suspenders readback test.

### G5 -- restic archive paths live under /run/restic-backups-backblazeWeekly, not /tmp/restic
The doc said restored paths reflect `/tmp/restic/<dataset>@<snapshot>/...`;
the actual layout (verified via `restic-backblazeWeekly ls` against the
2026-09-04 snapshot) is `/run/restic-backups-backblazeWeekly/<dataset
path>@<zrepl snapshot>/...` -- e.g. top level `{includes,zdata,zroot}` --
matching `backupPrepareCommand`'s `$RUNTIME_DIRECTORY` mounts (the Tier 1
plan's G2 documents the same shape). Doc corrected.

### G6 -- /simplify's 4-way review pass (reuse/simplification/efficiency/altitude): applied and parked
**Applied:** one explicit drill-vs-real mode decision made at arg parsing
(real modes now *require* their full argument set instead of silently
inheriting drill defaults -- previously `file --dest X` without `--glob`
would have restored three arbitrary sample files to a real destination
and reported PASS); `set -uo pipefail` (a failed `zfs send` was masked
by the exit status of the `zfs recv`/`wc` after the pipe); ssh
`ConnectTimeout=8` + `ControlMaster=auto`/`ControlPersist` multiplexing
in `rh()` (a full drill makes ~20 remote calls, each previously paying a
full handshake); EXIT-trap scratch teardown (an interrupted drill
previously left scratch that hard-blocked the next run until a manual
`cleanup`); real file recoveries use a per-run `-$$` scratch name so
leftover drill scratch can never block an actual emergency recovery;
`rsync -naHAXx --checksum` dry-run replaces `diff -rq` for the readback
verify (compares perms/owners/xattrs/ACLs/hardlinks -- the "real-world
file metadata" this tier exists to check -- and handles sockets/fifos,
deleting G4's filter instead of maintaining it); `-o canmount=on` forced
on verification clones alongside readonly/mountpoint (matches the tier1
branch's F-P6-03-motivated never-trust-received-properties recipe); the
restic drill derives the archived root path from the snapshot's own
`paths[0]` instead of hardcoding `/run/restic-backups-backblazeWeekly`;
restic's ls filter+head run remotely with `jq --unbuffered` so restic
stops reading B2 at the first match (local jq's block buffering was
letting restic walk far past it); guid/used property reads and
restore+stat batched into single remote calls; `RESTORE_DRILL_HOST`
override for DR against a rebuilt/IP-only sink; drill find bounded with
`-maxdepth 4`; script header cut to a pointer at the runbook (three
copies of the option list had already drifted); D2's staleness marker.

**Parked, with reasoning:** (1) remote-side `wc -c` for the stream drill
-- pulling the stream across the wire is the point (it *is* the
cross-host restore transfer, and it measured the 100MB/s LAN baseline);
(2) parallelizing the restic leg of the composite drill against the ZFS
legs -- drills are rare and minutes-long, not worth cross-process
result plumbing; (3) deriving the drill's dataset list from
`myHealthAlerts.backupStaleness` via `nix eval` for coverage
completeness -- right idea, sizable machinery; revisit if the replicated
set grows past what two representative defaults cover (constants are
comment-linked to their Nix sources meanwhile); (4) a shellcheck flake
check over `scripts/*` -- worth doing as its own housekeeping change,
`modules/flake/gate-checks.nix` is the precedent; (5) pointing the file
drill at the Tier 1 canary path once that branch lands, making the
sample deterministic; (6) unifying scratch naming with the unmerged
tier1 module's `zbackup/restore-test-scratch` -- different subsystems
with different lifecycles (self-healing automated canary vs
tagged+refuse manual drill); the clone-property recipe *was* aligned
(see Applied) which is the half with the security rationale.

## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 -- workflow.md's mistake-recovery pointer described the pre-rewrite "Recovering a few files" recipe
`docs/procedures/workflow.md` ("If you already made a destructive local
mistake") said to recover "with the same recipe as 'Recovering a few
files' in docs/procedures/backup-restore.md" and then described the
local `.zfs/snapshot/` copy-out. After this plan's rewrite that
section's primary recipe is `restore-drill file` (clone-based, against
zbackup on homelab); the local `.zfs/snapshot/` route survives there
only as a parenthetical note. Reworded workflow.md to point at that
note specifically and to say why the script route is the wrong tool for
an on-box mistake (the host's own mounted datasets already carry the
snapshots); its self-contained local recipe is unchanged.

_docs-updater finished 2026-09-10T00:47:24Z (code 4b55147a8325f699) -- see Findings above._


**FIXED 2026-09-09:** workflow.md's mistake-recovery section now points at the local .zfs/snapshot route specifically and explains why restore-drill is the wrong tool for an on-box mistake (docs-updater pass)

### F2 -- restic archive paths are interpolated unescaped into remote root shell commands; a hostile filename in a backed-up dataset becomes root command execution on homelab

- **File:** `scripts/restore-drill:298-304` (drill pick -> `--include '$include'` and `stat -c %s '$dest$include'`), `scripts/restore-drill:277` (real-restore `--include`), `scripts/restore-drill:136-156` (`--glob`/`--dest` expanded locally into an unquoted `<<REMOTE` heredoc run by remote root bash), `scripts/restore-drill:42-46` (`rh()` -- every remote call is one string handed to the remote root shell)
- **Severity:** HIGH
- **Confidence:** CONFIRMED (code read; write-access reachability confirmed at `hosts/homelab/configuration.nix:185` -- `A /storage - - - - group:multimedia:rwx` -- and `zroot/local/state` is service-writable state; these are exactly the two datasets restic archives, `hosts/homelab/configuration.nix:225`)
- **Axis:** hardening
- **Reachability:** any principal able to choose a filename inside a restic-backed dataset -- the multimedia-group media stack writing internet-derived names into `/storage` (`zdata/storage/storage`), or any service writing attacker-influenced names under `/var/lib` (`zroot/local/state`) -- with execution as **root on homelab** when an operator runs the tool. Two paths: (1) drill mode automatically picks a file via `jq -r .path` from `restic ls --json` and splices that path into `rh "$restic_wrapper restore '$id' --target '$dest' --include '$include' && stat -c %s '$dest$include'"`; a filename containing a single quote terminates the quoting and the rest runs as root (the pick is `head -n1` under `$proot/zroot`, i.e. the lexicographically first small file in the state subtree -- an adversary who can create an early-sorting path gets executed by every quarterly drill, which D2's staleness alert guarantees will keep running); (2) real-restore mode, where the runbook instructs browsing with `restic-backblazeWeekly ls` and passing the shown path as `--include` -- pasting a hostile archived filename injects the same way. ZFS snapshot/dataset names cannot carry quote/metacharacters (namecheck charset), so `--src`/`--snap`-derived values are not injectable by a source host, but restic archive paths are arbitrary bytes. The `--glob`/`--dest` heredoc expansion (`$(...)`, backticks and double quotes in an operator-typed glob execute remotely as root) is the same root cause with a trusted-operator adversary -- a footgun rather than a boundary break, but fixed by the same mechanism.
- **Rule:** new-rule candidate -- "remote commands built from data must not be assembled by string interpolation; quote with `printf %q` or pass values out-of-band (stdin/env) to a fixed remote script"
- **Finding:** every remote invocation is a locally-interpolated string executed by the root shell on homelab; the restic legs splice repo-content-derived paths (attacker-nameable files) into those strings guarded only by single quotes the data itself can close. This turns "can name a file in a backed-up dataset" (e.g. a compromised container in the multimedia group, or anything that downloads user-named media into `/storage`) into root on homelab, triggered either automatically by the periodic drill or by an operator following the documented real-restore flow.
- **Fix risk:** low -- `printf %q`-escaping (or shipping values via stdin to a fixed remote script, as the `<<REMOTE` blocks already almost do) preserves behavior for all legitimate names; re-run a full drill afterwards to confirm globs/paths with spaces still resolve, since ZFS names may legitimately contain spaces.


**FIXED 2026-09-09:** every data value spliced into a remote command now goes through printf %q (q() helper) -- restic paths, --to/--dest/--glob/--include, and remote-derived snap names; heredoc expansions use pre-quoted values

### F3 -- the runbook's cross-host restore `zfs recv` applies whatever properties the stream carries: no `-o`/`-x` overrides, unlike the script's own receive

- **File:** `docs/procedures/backup-restore.md:136-137` (`restore-drill stream --src ... | run0 zfs recv -u zroot/local/home-restored`), contrast `scripts/restore-drill:181` (`zfs recv -u -o mountpoint=none -o readonly=on`)
- **Severity:** MEDIUM
- **Confidence:** PLAUSIBLE (mechanics are the same as the accepted, still-open F-P6-03 reasoning on the tier1 branch -- a send stream can embed `mountpoint`/`canmount`/`setuid`/`exec` and the receive side applies them absent overrides; not re-verified against the pinned OpenZFS here)
- **Axis:** hardening
- **Reachability:** a compromised homelab (the backup sink -- internet-adjacent via forwarded game ports) feeding a crafted stream to the one place this procedure pipes its output into root `zfs recv` on a *target* host (torrent/thinkpad). The bytes of the stream are entirely attacker-chosen, so "plain `zfs send` does not include properties" is no defense -- a crafted stream can carry a poisoned `mountpoint` (shadowing `/etc`, a PATH dir, ...) with `setuid=on`/`exec=on`. `-u` only defers the mount; the next boot's `zfs mount -a` mounts it where the poisoned property says. Result: lateral movement from backup-sink root to target-host root, i.e. the restore procedure widens homelab's blast radius to every host that restores from it.
- **Rule:** consistent-with-repo-precedent -- the script's own comment ("never trusts properties that arrived in a send stream", `scripts/restore-drill:130-133`) and the tier1 branch's G3/F-P6-03 both state this recipe; the runbook's cross-host one-liner is the one receive in the whole change that omits it.
- **Finding:** `do_dataset`'s receive forces `mountpoint=none -o readonly=on`, and every verification clone forces `readonly`/`canmount`/`mountpoint` -- but the documented cross-host restore (the only path that receives onto a *different* host, where the stakes are highest) is a bare `zfs recv -u`. Adding `-o mountpoint=none -o readonly=on -o canmount=off` (cleared deliberately after inspection, exactly as the "Onto homelab" section already tells the operator to do) closes it at zero usability cost.
- **Fix risk:** none beyond doc accuracy -- the extra `zfs set`/`zfs inherit` steps after inspection must be added to the same runbook section or the restored dataset stays unmountable.


**FIXED 2026-09-09:** runbook cross-host recipe now recv's with -o mountpoint=none -o readonly=on -o canmount=off and documents the deliberate post-inspection zfs set steps

### F4 -- remote-derived `zfs send` size estimate is evaluated in bash arithmetic on the operator machine: a compromised homelab gets code execution as the operator

- **File:** `scripts/restore-drill:230` (`expect=$(rh "zfs send -c -nvP '$snap' 2>&1" | awk ...)`), `scripts/restore-drill:238` (`$((expect * 9 / 10))`)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (bash arithmetic expansion evaluates command substitutions inside array subscripts -- `expect='a[$(payload)]'` executes `payload` locally; `expect` is a verbatim remote output field)
- **Axis:** hardening
- **Reachability:** root on homelab (or anything that can answer the SSH session, cf. F5) -- already a serious position, but this crosses the remaining boundary that matters: homelab -> operator machine. The operator's account holds root SSH to the whole fleet, so arbitrary code as the operator user is fleet-wide reach. Trigger is any `restore-drill drill`/`stream` drill run -- quarterly at minimum, by design.
- **Rule:** new-rule candidate -- "never place remote-derived strings in bash arithmetic contexts; validate as integers first"
- **Finding:** `expect` is field 2 of homelab's `zfs send -nvP` output and flows unvalidated into `$((expect * 9 / 10))`. A hostile sink returns `size a[$(cmd)]` and `cmd` runs on the operator machine. Everything else remote-derived is only displayed or re-sent to the same remote (no boundary crossed); this is the single local evaluation sink. A `[[ $expect =~ ^[0-9]+$ ]]` guard (already half-implied by the `[ -n "$expect" ]` check) removes it.
- **Fix risk:** none -- non-numeric estimates already fall through to FAIL; the guard just makes that path safe as well as correct.


**FIXED 2026-09-09:** expect is regex-validated as an unsigned integer before entering bash arithmetic; non-numeric falls through to the existing FAIL path

### F5 -- SSH ControlMaster socket at a predictable path in world-writable /tmp

- **File:** `scripts/restore-drill:44` (`-o ControlPath=/tmp/restore-drill-%C -o ControlPersist=60`)
- **Severity:** MEDIUM
- **Confidence:** PLAUSIBLE (mux-hijack feasibility not verified against the pinned OpenSSH; the live socket itself is created 0600 by OpenSSH's `umask 0177`, so direct connection by another uid is blocked -- the exposure is squatting/pre-planting, not the socket's perms)
- **Axis:** hardening
- **Reachability:** any *other* uid on the operator machine (a compromised low-privilege service account is the plausible first step) -- /tmp is world-writable and `%C` is a deterministic hash of local host/remote host/port/user, so the path is computable in advance. Pre-planting a listening socket there means the operator's next `rh()` call, with `ControlMaster=auto`, connects to the attacker's fake mux master instead of homelab: at minimum the fire drill's PASS/FAIL is attacker-controlled (defeating exactly the guarantee D2's marker exists to provide -- it would happily touch the success marker), and in `stream` real mode there is an escalation chain -- `resolve_snap` runs through the (hijacked) mux and its output `$snap` is then spliced single-quoted into a *fresh, non-mux* `exec ssh "$host" "zfs send -c '$snap'"` (`scripts/restore-drill:225`) against the real homelab, so an attacker-returned string containing a single quote is root command injection on the real sink (overlaps F2's root cause). Pre-planting a symlink or plain file instead is a cheap drill-DoS.
- **Rule:** consistent-with-repo-precedent -- the restic unit's own comment (`hosts/homelab/configuration.nix:219-224`) moved a /tmp working dir to `RuntimeDirectory` for precisely this pre-planted-path-in-/tmp class (audit L-02); `ssh_config(5)` itself recommends ControlPath live in a directory "not writable by other users".
- **Fix risk:** none -- `${XDG_RUNTIME_DIR:-$HOME/.ssh}/restore-drill-%C` (or `~/.ssh/`) is a one-line change; only caveat is the directory must exist on whatever operator machine runs the tool.


**FIXED 2026-09-09:** ControlPath moved to XDG_RUNTIME_DIR (0700, fallback ~/.ssh) -- no predictable path in world-writable /tmp; the snap-into-fresh-ssh splice in stream real mode is also now %q-quoted (F2), closing the escalation chain

### F6 -- the already-touched success marker predates its persistence entry, and `dataset --src` alone contradicts the "partial real arguments are an error" invariant

- **File:** `hosts/homelab/configuration.nix:564` (marker watched at 2160h), `hosts/homelab/configuration.nix:745` (persistence entry, not yet deployed), `scripts/restore-drill:14-18` (header invariant) vs `scripts/restore-drill:164-169` (`src=${opt_src:-$drill_dataset_src}` -- `--src` without `--to` silently runs as a drill)
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** n/a (operational/doc accuracy)
- **Rule:** n/a
- **Finding:** two small mismatches. (1) The 2026-09-09 drill touched `/var/lib/restore-drill/last-drill-success` on homelab's impermanence-rolled-back root *before* the persistence entry exists in any deployed generation -- on the first reboot after deploying this change, the persisted dir starts empty and `myHealthAlerts` pages "Marker file missing" until a drill re-runs. Fail-loud and self-healing (re-run the drill post-deploy), but worth expecting rather than debugging. (2) The header and runbook state "partial real arguments are an error", and `file`/`restic` enforce it, but `dataset --src X` without `--to` silently runs as a drill against `X` (harmless direction -- it writes only to tagged scratch, and plausibly deliberate for the pending real-scale timing check, but it is undocumented behavior that contradicts the stated invariant either way; document it or reject it).
- **Fix risk:** none.

---

**Security review (cold read, 2026-09-09) -- checked and clean.** Reviewed `scripts/restore-drill` in full, the homelab `staleMarkerFiles`/persistence additions, the rewritten `docs/procedures/backup-restore.md`, and the `docs/backups.md`/`workflow.md` edits, against `docs/hardening.md` and the tier1 branch's F-P6-03 reasoning. Found sound: the `org.dotfiles:restore-drill` tag guard on all destroy paths is name-prefix-bounded *first* (`zbackup/restore-drill*` only) and tag-checked second, so `zfs destroy -r`/`rm -rf` blast radius is confined to script-created scratch (verification clones are `readonly=on`, so even the blanket `rm -rf /mnt/restore-drill*` cannot eat through a still-mounted clone; only the rollback scratch child is writable and it holds urandom test data); plain `zfs send -c` (no `-p`/`-R`) cannot leak the drill tag into or out of received datasets, and received/cloned datasets inside the script are consistently forced `readonly`/`mountpoint`/`canmount` (F-P6-03-aligned) -- the one omission is the runbook's cross-host recv (F3). The ZFS name charset (no quotes/metacharacters) means snapshot-name-derived values from `resolve_snap` are not an injection vector even from a hostile source host. The tool refuses to overwrite existing datasets, real modes require full argument sets (except the F6 wrinkle), real backups are only ever read, D1's decision not to wrap live `zfs rollback` is correct risk placement, and the marker/staleness wiring matches the restic `last-success` precedent (missing file alerts immediately, unique-basename assertion satisfied, the non-dereferencing-`stat` concern is n/a for a real file). No secrets are read, embedded, or newly exposed; no firewall/port changes; no new services or privilege grants -- root-over-SSH is the pre-existing operator capability, not a new one. `RESTORE_DRILL_HOST` is an env override on the operator's own invocation, not a trust boundary. Docs edits match actual script behavior except as noted in F6.

_security finished 2026-09-10T03:18:57Z (code 4b55147a8325f699) -- see Findings above._

**FIXED 2026-09-09:** invariant restated everywhere as: a destination argument (--dest/--to) selects real mode and requires the full set, --src/--snap/--id alone repoint the drill (file now accepts --src-only drills like dataset); the marker-predates-persistence page after the first post-deploy reboot is expected and noted in State -- re-run the drill post-deploy to clear it
