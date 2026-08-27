# P7 — the deploy control plane

Part 7 of the 2026-08-26 fleet-wide security audit. Scope: the
machinery that causes code to run as root across the fleet —
`auto-update.nix`, `pull-deploy.nix`, `push-deploy.nix`,
`iso-autobuild.nix`, `health-alerts.nix`, `deploy-guards.nix`,
`scripts/bootstrap-host.sh`, and `.githooks/`.

Severity, reachability and confidence follow
[`00-threat-model.md`](00-threat-model.md) §5 and §6. The finding
schema is [`P0-findings.md`](P0-findings.md)'s.

**Headline:** the threat model's open question §8.4 — *can `lilijoy`
reach root via the pull-deploy checkout?* — is **settled: yes**, by
four independent mechanisms, one of which needs no trick at all. See
F-P7-01. Two further root paths not in the threat model are also
confirmed: a compromised `vps` can execute code as root on `homelab`
through the deploy guards (F-P7-03), and the live zrepl puller private
key is sitting in `/tmp` on `torrent` right now (F-P7-02).

**Written against threat model §4.7 (the repository is public).** Three
things follow for this part specifically, and they are applied
throughout rather than noted once:

- **No obscurity is claimed anywhere below.** The deploy mechanism, the
  guard source, every timer window (`Wed 03:00`, `Thu 03:00`,
  `Thu 03:15`, `*:0/15`), the 604800-second min-switch interval and the
  `protectedUnits` list are all published. Every TOCTOU and
  guard-bypass finding here is rated as **fully discoverable by
  reading the repo** — no adversary needs to be on the machine to learn
  the timing, and "they would have to know X" is never a mitigating
  factor.
- **CI: there is none, and there never has been.** A definitive
  negative result, established below and written up as F-P7-17.
- **`secrets/secrets.yaml` is public ciphertext, permanently, and
  rotation is not retroactive.** This directly re-rates F-P7-08 (a host
  age key written onto a snapshotted, replicated, offsite-backed-up
  filesystem) from MEDIUM to **HIGH**: such a key is not merely exposed
  to backup readers, it is a permanent skeleton key for a file the
  whole internet already holds a copy of.

---

## 1. Scope and method

### Files read in full

| File | Lines |
|---|---|
| `modules/nixos/auto-update.nix` | 231 |
| `modules/nixos/pull-deploy.nix` | 156 |
| `modules/nixos/push-deploy.nix` | 163 |
| `modules/nixos/iso-autobuild.nix` | 166 |
| `modules/nixos/health-alerts.nix` | 283 |
| `modules/flake/deploy-guards.nix` | 80 |
| `scripts/bootstrap-host.sh` | 195 |
| `.githooks/pre-commit`, `pre-push`, `commit-msg` | 49 / 57 / 23 |

Supporting reads: `modules/flake/hosts.nix`, `modules/flake/vars.nix`,
`modules/flake/devshell.nix`, `modules/profiles/server.nix`,
`modules/profiles/default.nix` (smartd block), `.sops.yaml`,
`.gitignore`, the `myAutoUpdate`/`myPushDeploy`/`myHealthAlerts`/
`myPullDeploy`/`myIsoAutobuild` blocks and the persistence block of
each host's `configuration.nix`, `hosts/vps/configuration.nix:13-98`
(the dispatcher, as the receiving half of push-deploy),
`hosts/isoimage/configuration.nix`, `docs/hardening.md`,
`docs/procedures/workflow.md`, `docs/procedures/testing-changes.md`,
`docs/architecture.md` (deploy section).

### Verified against the pinned nixpkgs / rendered units

`nix eval` is blocked in this session's harness, so effective units
were obtained by **building the unit derivations** instead, which is
equivalent and arguably better (it is the literal file systemd loads):

```
nix build --no-link --print-out-paths \
  '.#nixosConfigurations.homelab.config.systemd.units."<unit>".unit'
```

Rendered and read in full:

- homelab: `auto-switch.service` (+ its `unit-script-auto-switch-start`),
  `auto-switch-now.service`, `flake-update-test.service`,
  `push-deploy-vps.service` (+ its start script), `health-check.service`,
  `auto-switch.timer`, `push-deploy-vps.timer`
- vps: `health-check.service`
- torrent: read live from the running system (`systemctl cat
  pull-deploy.service`), which is the strongest form available

Also verified against pinned sources: `lib.types.path` / `pathWith` in
the 26.11 nixpkgs tree (`lib/types.nix:655-706`); the transient unit
name `nixos-rebuild-switch-to-configuration` in
`nixos-rebuild-ng-26.11/.../nix.py:52`; `git` 2.54.0/2.55.0 contain no
hardcoded store path to `ssh` (so it is resolved via `PATH`).

### Confirmed live on `torrent` (read-only)

Everything here was observed on the machine this audit ran on. No unit
was started, stopped or triggered; no file outside this report was
modified; no host was SSH'd to; no secret was decrypted.

- `hostname` = `torrent`; `pull-deploy.timer` active, `NEXT Thu
  2026-08-27 03:00`, last run `Thu 2026-08-20`.
- `systemctl cat pull-deploy.service` → `User=root`,
  `NoNewPrivileges=true`, nothing else.
- `journalctl -u pull-deploy.service` → a real root run on 2026-08-25
  13:41 that fast-forwarded `/home/lilijoy/dotfiles`, then printed
  `Last switch activated 16 seconds ago (minimum 604800), skipping this
  scheduled run.` and was recorded by systemd as **`Deactivated
  successfully` / `Finished`**.
- `ls -ld /home/lilijoy/dotfiles` → `drwxr-xr-x lilijoy users`;
  `.git/config` → `-rwxr-xr-x lilijoy users`.
- `cat /home/lilijoy/dotfiles/.git/config` → `core.hooksPath =
  /home/lilijoy/dotfiles/.githooks` (a user-writable directory inside
  the worktree), `remote.origin.url = git@github.com:…`.
- `/etc/ssh/ssh_known_hosts` on torrent is **empty**; `/` is
  `zroot/local/root` with no impermanence.
- `/tmp` is on `zroot/local/root` (no separate mount); tmpfiles ages it
  at 10d. `ls -la /tmp` → `-rw------- lilijoy users 411 Aug 23
  /tmp/homelab_zrepl_key` plus its `.pub`.
- `/var/lib/iso-autobuild/result` → dangling symlink to a GC'd store
  path; `~/Downloads/nixos-recovery-*.iso` is mode `0444`, dated Aug 16.
- `ls /etc/systemd/system` → a **`pull-deploy.service.service`** unit
  exists alongside `pull-deploy.service`; only the former carries
  `OnSuccess=iso-build.service`.

### Behaviour verified by experiment

Run in throwaway directories under `/tmp`, cleaned up afterwards. Used
to turn "git can execute config-named commands" from an assertion into
a demonstration, with the exact git version the units use (2.55.0):

1. **Repo-local `core.fsmonitor`, `core.hooksPath` → command
   execution.** `git status --porcelain` executed the `core.fsmonitor`
   program; `git fetch origin` executed the `reference-transaction`
   hook; `git merge --ff-only origin/master` executed the `post-merge`
   hook. All three named only in the repo-local `.git/config`.
2. **`safe.directory` is the whole gate.** Using a user namespace to
   make the repo appear owned by a different uid: without
   `safe.directory` git aborts with `fatal: detected dubious
   ownership` and executes nothing; after running the exact line at
   `deploy-guards.nix:24` (`git config --global --add safe.directory
   "$(pwd)"`), the same commands succeed **and execute the
   `core.fsmonitor` / `post-merge` / `reference-transaction` programs
   named in the unprivileged owner's config**.
3. **`git merge --ff-only origin/master` is a silent no-op when HEAD is
   ahead of `origin/master`** — prints `Already up to date.`, exits 0,
   leaves the local commits in place.
4. **`nix build .#x` in a git flake reads the working tree, not the
   index.** Modifying a tracked file without committing produced a
   different out-path from the committed content.
5. **Bash arithmetic injection.** With bash 5.3p9 (the interpreter the
   rendered unit scripts use), `x='a[$(touch /tmp/probe)]'; echo $((
   now - x ))` executes the command substitution.

### What could not be verified

- **Anything requiring reading `homelab`, `thinkpad` or `vps`.** No SSH
  was permitted. Claims about homelab's `/root/.ssh/known_hosts`,
  `/root/.gitconfig`, `/etc/nixos`'s `remote.origin.url`, and whether
  `flake-update-test`/`auto-switch` have ever completed are marked
  PLAUSIBLE and say what would settle them.
- **Secret contents.** Never decrypted. The `/tmp/homelab_zrepl_key`
  identification in F-P7-02 was made by comparing its **public** half
  to `modules/flake/vars.nix:14` and reading only the PEM header line.
- **Whether `disk`-group write to a raw device actually yields root on
  these specific hosts.** Not attempted (destructive). Rated on the
  well-established property of the group, marked accordingly.

---

### Additional checks run after the public-repository correction

- `ls .github` → does not exist. `find` for any `*.yml`/`*.yaml` at
  depth ≤3 → only `.sops.yaml` and `secrets/secrets.yaml`.
- `git log --all --diff-filter=A --name-only` over the **entire
  history** (every file ever added, all branches) filtered for
  `.github/`, `workflow`, `.gitlab-ci`, `.circleci`,
  `azure-pipelines`, `Jenkinsfile`, `.woodpecker`, `.drone`,
  `.travis`, `.builds/`, `garnix` → **zero matches.**
- The complete set of root-level dotfiles ever added in history is
  `.envrc`, `.githooks/{commit-msg,pre-commit,pre-push}`, `.gitignore`,
  `.sops.yaml`. Nothing else.
- Grepped `flake.nix` and `modules/flake/` for `garnix`, `hercules`,
  `cachix`, `magic-nix-cache`, `DeterminateSystems` → the only hit is
  `github:hercules-ci/flake-parts`, which is the GitHub org that owns
  `flake-parts`, not a CI integration.
- Read the 31 secret **key names** in `secrets/secrets.yaml` (names
  only — no decryption) to ground F-P7-18's assessment of what the
  pre-commit scanner would actually need to catch.

## 2. Findings

Ordered by severity. F-P7-17 and F-P7-18 were added after the
public-repository correction and are placed in their severity slots, so
the ids are not sequential in reading order.

### F-P7-01 — `lilijoy` gets root on torrent and thinkpad through the pull-deploy checkout, four ways

- **File:** `modules/flake/deploy-guards.nix:18-35,37-54`,
  `modules/nixos/pull-deploy.nix:102-124`,
  `hosts/torrent/configuration.nix:15-26`,
  `hosts/thinkpad/configuration.nix:16-27`
- **Severity:** HIGH
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A7 — anything already executing as `lilijoy` on
  either laptop: a browser exploit, a malicious npm/cargo/pip
  dependency, an agent tool call. Threat model §5 rates A7 the most
  likely initial foothold. No user interaction, no timing skill, and
  the payload can be planted days before the weekly timer fires.
  Per threat model §4.7 this is **fully discoverable without touching a
  host**: `pull-deploy.nix`, `deploy-guards.nix` and
  `hosts/torrent/configuration.nix` are public, so the exact `Thu
  03:00` window, the 604800-second interval, the `flakeDir` path and
  the fact that the guards check only cleanliness and branch name are
  all readable in advance. Malware targeting this fleet does not need
  to discover the escalation; it can be written from the repo.
- **Rule:** new-rule candidate — "a root unit must not operate on a
  path any unprivileged principal can write."
- **Finding:** this settles threat-model open question §8.4 and
  upgrades F-P0-03 from PLAUSIBLE to CONFIRMED. `pull-deploy.service`
  runs as `root`, `cd`s into `/home/lilijoy/dotfiles` (owned by
  `lilijoy`, mode 0755, confirmed live), and runs git against it. Four
  independent escalations, in increasing order of how little the
  attacker needs to do:

  1. **Commit locally on `master`. Nothing else.** `require_clean_master`
     only checks that the tree is clean and the branch is `master`;
     `fetch_and_merge_master` then runs `git merge --ff-only
     origin/master`, which is a **no-op that exits 0 when HEAD is ahead
     of `origin/master`** (verified). So `lilijoy` commits a malicious
     `.nix` change on `master`, and at the next timer root runs
     `nixos-rebuild build` and then `nixos-rebuild boot` on it. No
     git-config trickery, no race, no root-owned file touched, and it
     is completely invisible to every guard. This is the whole exploit.
  2. **`.git/config` names a command git executes.** `.git/config` is
     owned by `lilijoy` (confirmed live, `-rwxr-xr-x lilijoy users`).
     Setting `core.fsmonitor`, `core.hooksPath`, `include.path`,
     `diff.external`, `filter.*.clean/smudge` or a `merge.*.driver`
     makes git itself run an attacker binary as root.
     `core.fsmonitor` fires on the *first* guard command
     (`git status --porcelain`), before any check has passed;
     `reference-transaction` fires on `git fetch`; `post-merge` fires
     on the `--ff-only` merge. All three verified executing under a
     privileged uid against an unprivileged-owned repo (method §1).
     `core.sshCommand` is the one that does *not* work — `GIT_SSH_COMMAND`
     (`deploy-guards.nix:51`) takes precedence over it.
  3. **`deploy-guards.nix:24` is what makes (2) possible.** `git config
     --global --add safe.directory "$(pwd)"` disables git's ownership
     check — the check that exists specifically to stop a privileged
     user from executing config out of another user's repository
     (CVE-2022-24765). Verified both directions: without the line git
     refuses and executes nothing; with it, git proceeds and runs the
     owner-specified programs. The line is not a workaround for a
     cosmetic warning; it is the removal of the only control.
  4. **TOCTOU, independent of git entirely.** `nix build`/`nixos-rebuild
     build` on a git flake reads the **working tree** of tracked files,
     not the committed content (verified). The window between
     `require_clean_master`'s `git status` and `nixos-rebuild build`
     reading the tree is seconds to minutes, is trivially observable
     (watch `.git/FETCH_HEAD`, or just the known Thu 03:00 slot), and
     needs no privileged write. So even a perfectly clean `.git`
     directory does not close this.

  Additionally, `remote.origin.url` and `sshKeyPath`'s target
  (`/home/lilijoy/.ssh/id_ed25519`, owned by `lilijoy`) are both
  user-controlled, so root can be pointed at an attacker's repository
  authenticating with an attacker's key.

  `operation = "boot"` on both laptops does not blunt this:
  `switch-to-configuration boot` still runs the new closure's
  bootloader-installation script as root immediately, and guarantees
  the malicious system at next boot.

  It chains exactly as F-P0-03 predicted: `lilijoy` → root on the
  laptop → the admin SSH key in `flake.vars.publicSshKeys` and the
  GitHub push key → F-P0-01 → root on all four hosts.
- **Proposed fix:** the only structural fix is to stop root operating
  on a user-writable path. Options, best first:
  (a) **Drop unattended pull-deploy on the laptops.** They are
  interactive machines with a person present; the unattended-patching
  argument that justifies it on homelab is much weaker here, and this
  removes the whole class rather than one instance.
  (b) **Root-owned checkout**, `/etc/nixos` as homelab already uses,
  cloned and fast-forwarded by root only, with `lilijoy`'s working
  clone kept entirely separate. Requires solving the `sshKeyPath`
  problem properly (see F-P7-11) rather than moving it.
  (c) If neither is acceptable, at minimum: run every git invocation
  with `-c core.fsmonitor= -c core.hooksPath=/var/empty -c
  include.path=` and `GIT_CONFIG_GLOBAL=/dev/null`, drop the
  `safe.directory` line in favour of `GIT_CEILING_DIRECTORIES` +
  explicit `--git-dir`, and verify `git rev-parse HEAD` equals
  `git rev-parse origin/master` after the merge. This is a mitigation
  list, not a boundary — mechanism (4) survives all of it, so treat (c)
  as a stopgap only.
- **Fix risk:** (a) and (b) both change the day-to-day edit-and-test
  loop on the daily driver; (b) doubles disk use for the checkout and
  needs the deploy identity solved first. Whatever lands must be VM
  tested for the *failure* path (fetch fails, merge fails) as well as
  the success path.
- **Owner:** P7 (this finding, mechanism) and P5 (host impact), per
  F-P0-03. **Verdict for F-P0-03: CONFIRMED.**

### F-P7-02 — the live zrepl puller private key is sitting in `/tmp` on torrent

- **File:** `/tmp/homelab_zrepl_key` (live artefact, not in the repo);
  `modules/flake/vars.nix:14`
- **Severity:** HIGH
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A7 — any code running as `lilijoy` reads it
  directly (mode 0600, owner `lilijoy`). Also A9/backup-holder: `/tmp`
  is on `zroot/local/root`, which `myZrepl` snapshots every 5 minutes
  and replicates to `zbackup` on homelab. **Corrected 2026-08-27:** this
  line previously ended "which restic pushes to Backblaze". It does not.
  restic mounts only `zroot/local/state` and `zdata/storage/storage`
  under `/tmp/restic` and backs up that path alone, so `zbackup/*` — and
  therefore every laptop replica — is outside the offsite copy.
- **Rule:** violates `docs/procedures/secrets.md`'s "secrets live in
  sops, never on disk in the clear"; new-rule candidate for key-generation
  hygiene.
- **Finding:** `/tmp/homelab_zrepl_key` is an OpenSSH ed25519 private
  key, 411 bytes, dated 2026-08-23, mode 0600 `lilijoy:users`. Its
  public half is byte-identical to `vars.zreplPullerKey`
  (`modules/flake/vars.nix:14`) — i.e. this is the **live** credential
  homelab uses to pull backups from torrent and thinkpad, authorized in
  their `authorized_keys` behind the `zrepl stdinserver` forced command.
  It was generated on torrent during a deploy and never removed. Only
  the PEM header line and the `.pub` were read to make this
  identification.

  Consequences: (i) `lilijoy` — the A7 foothold — holds a fleet backup
  credential it was never meant to hold, granting `zrepl` source-side
  access to torrent's and thinkpad's snapshotted datasets (both home
  directories); (ii) the key is now in roughly 32 days of local ZFS
  snapshots and in the offsite backup, so deleting the file does not
  retract it; (iii) `systemd-tmpfiles-clean` will remove the `/tmp`
  copy around 2026-09-02, which will look like remediation while the
  snapshot copies persist.

  No repo procedure instructs generating this key into `/tmp` — `grep
  -rn ssh-keygen docs/` finds nothing relevant — so this is an ad-hoc
  admin action, which is precisely why it needs a written procedure.
- **Proposed fix:** rotate `vars.zreplPullerKey` and its sops
  counterpart, then delete `/tmp/homelab_zrepl_key*`. Accept that the
  old key remains recoverable from snapshots until they age out — which
  is the argument for rotating rather than just deleting. Add to
  `docs/procedures/secrets.md`: generate key material only under a
  `mktemp -d` on a **tmpfs** path (`TMPDIR=/run/user/$UID` or
  `/dev/shm`), never on a ZFS-snapshotted dataset, and `sops` it in the
  same shell.
- **Fix risk:** rotating the puller key breaks replication from both
  laptops until the new public half lands in `vars.nix` and both hosts
  have switched — sequence it as: add the new key alongside the old,
  switch both sources, cut homelab over, then remove the old.
- **Owner:** P7 found it; **P6 (zrepl) should own the rotation**, and
  P5 should check both laptops' `/tmp` and `~` for the same class of
  leftover.

### F-P7-03 — a compromised `vps` gets root on `homelab` via arithmetic injection in `check_min_switch_interval`

- **File:** `modules/flake/deploy-guards.nix:58-66` (esp. `:61`),
  `modules/nixos/push-deploy.nix:116-117`
- **Severity:** HIGH
- **Confidence:** CONFIRMED (injection primitive verified against the
  exact interpreter the rendered unit uses; the precondition is root on
  vps)
- **Reachability:** A1/A2/A3 having achieved root on `vps` — the one
  host deliberately exposed to the internet, running caddy, anubis,
  crowdsec and forwarding two game-server ports. This is the
  **reverse** of threat-model §4.2, which grants homelab → vps but says
  nothing about vps → homelab, and vps holds no credential to homelab
  (it runs no `myZrepl`, and homelab's `authorized_keys` are the three
  admin keys plus the zrepl peers).
- **Rule:** new-rule candidate — never feed remote-supplied strings
  into `$(( ))`.
- **Finding:** `push-deploy-vps.service` (root on homelab) runs:

  ```sh
  last_switch=$(ssh $NIX_SSHOPTS vps-deploy@vps stat -c %Y /nix/var/nix/profiles/system)
  check_min_switch_interval 604800 "$last_switch"
  ```

  and `check_min_switch_interval` does `elapsed=$(( now -
  last_switch_epoch ))`. Bash arithmetic evaluation recursively
  evaluates the *contents* of a named variable, and an array subscript
  inside that expression is expanded — so a value of the form
  `a[$(command)]` executes `command`. Verified with bash 5.3p9, the
  interpreter in the rendered `push-deploy-vps-start` script.

  The value is whatever `vps` writes to stdout. Today the dispatcher
  (`hosts/vps/configuration.nix:87-92`) exact-matches the command and
  execs a fixed `stat`, so a healthy vps cannot trigger this — but a vps
  whose root is compromised controls that output completely, and
  `push-deploy-vps` connects to it on a `Persistent=true` weekly timer
  plus every homelab switch. The result is arbitrary code as root on
  homelab, which per threat model §1 is the host holding the only
  consolidated copy of every host's data.

  The same primitive exists in `health-alerts.nix:183` (`(now -
  newest)`, fed from `zfs list`) and `:230` (fed from `date -d`), but
  neither source is attacker-controlled short of already owning the
  host, so those are hardening-by-consistency rather than live issues.
- **Proposed fix:** validate before arithmetic. In
  `check_min_switch_interval`:

  ```sh
  case "$last_switch_epoch" in
    ''|*[!0-9]*) echo "non-numeric last-switch timestamp: refusing" >&2; exit 1 ;;
  esac
  ```

  and separately clamp the read at the call site
  (`last_switch=$(ssh … | head -c 32 | tr -dc '0-9')`). Failing closed
  here is correct: a vps that cannot report a plausible timestamp is a
  vps that should not be deployed to unattended.
- **Fix risk:** none functionally — the legitimate value is always a
  bare integer. Worth a VM test of the reject path so the new `exit 1`
  is confirmed to surface as a failed unit rather than a silent skip.
- **Owner:** P7. **P2 should note this in the vps write-up**: it means
  "homelab is trusted with root on vps" (F-P0-02) is currently
  *symmetric*, which the threat model does not say and probably does
  not intend.

### F-P7-04 — homelab re-TOFUs GitHub and vps on every boot, because `/root` is not persisted

- **File:** `modules/flake/deploy-guards.nix:43`,
  `modules/nixos/push-deploy.nix:114`,
  `hosts/homelab/configuration.nix:469-492` (persistence list),
  `:216-224` (the knownHosts entries that exist)
- **Severity:** HIGH
- **Confidence:** CONFIRMED for the configuration; PLAUSIBLE for the
  runtime consequence (needs one `ls /root/.ssh` on homelab to settle)
- **Axis:** hardening
- **Reachability:** A4 or A2 — an on-path attacker between homelab and
  github.com / vps. A4 (a guest device, an IoT thing, a compromised
  phone on the home LAN) is rated plausible and "mostly unmodelled" by
  the threat model, and ARP/NDP spoofing homelab's gateway puts such a
  device on-path for every outbound connection homelab makes.
- **Rule:** n/a (this is F-P0-07, re-sized)
- **Finding:** F-P0-07 rated this LOW on the reading that
  `StrictHostKeyChecking=accept-new` only matters "on a freshly
  provisioned host's first fetch". On homelab that reading does not
  hold, for a reason F-P0-07 could not have seen without the
  persistence list:

  - homelab is an impermanence host: `/` is rolled back to
    `zroot/local/root@blank` at boot, and the persistence list at
    `hosts/homelab/configuration.nix:473-492` does **not** include
    `/root`. So `/root/.ssh/known_hosts` is empty at every boot.
  - `programs.ssh.knownHosts` on homelab (`:216-224`) pins only
    `torrent` and `thinkpad` — for zrepl. **Neither `github.com` nor
    `vps` is pinned anywhere**, and the global
    `/etc/ssh/ssh_known_hosts` is the only persisted store.
  - Both SSH consumers use `accept-new`: `fetch_and_merge_master`
    (`deploy-guards.nix:43`, GitHub) and `push-deploy-vps`'s
    `NIX_SSHOPTS` (`push-deploy.nix:114`, vps).
  - `push-deploy-vps.timer` is `Persistent=true` (rendered unit read)
    and `/var/lib/systemd/timers` **is** persisted, so a boot after a
    missed Thursday fires the job within seconds of boot — the moment
    `known_hosts` is guaranteed empty.

  So the exposure is not one first contact ever; it is **every boot,
  for two destinations, one of which (GitHub) is the fleet's root
  authority per §4.1 and the other of which receives a root-activating
  closure.** A successful MITM of the GitHub fetch yields root on
  homelab: the attacker's SSH session serves a pack containing a single
  commit parented on homelab's current HEAD with an entirely
  attacker-authored tree, `--ff-only` accepts it, and
  `nixos-rebuild switch` activates it.

  The comment at `deploy-guards.nix:38-42` justifies `accept-new` by
  "root's own known_hosts may never have trusted the origin remote's
  host before" — accurate, but the fix for that is a declarative pin,
  and the repo **already uses exactly that pattern** three lines of
  config away, with a comment (`:205-215`) explaining why it is
  preferable to `accept-new`.

  On torrent and thinkpad the original LOW rating stands: `/` is a
  plain ZFS dataset with no impermanence (confirmed live on torrent),
  so root's `known_hosts` persists and the TOFU already happened.
- **Proposed fix:** pin declaratively and let `accept-new` go. In the
  shared profile (`modules/profiles/default.nix`), following the
  existing pattern:

  ```nix
  programs.ssh.knownHosts."github.com" = {
    hostNames = [ "github.com" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };
  ```

  (verify the key against GitHub's published fingerprints before
  landing — do not copy it from this document). Pin `vps` the same way
  on homelab. Then change both `accept-new` occurrences to `yes`. As a
  belt-and-braces measure, add `/root/.ssh` to homelab's persistence
  list — but the pin is the real fix, because it makes the property
  independent of persistence.
- **Fix risk:** a stale pinned key fails all unattended updates closed
  until corrected — the correct direction, but it needs F-P7-09's
  alerting gap fixed first, or the laptops fail silently. GitHub
  rotated its RSA host key in 2023; pin the ed25519 key, and record in
  `docs/hardening.md` that this pin exists so a future rotation has an
  obvious place to be applied.
- **Owner:** P7, with P1 if the pin lands in the shared profile
  (F-P0-07 anticipated this).

### F-P7-05 — the `health-check` user is in `disk`, which is write access to every raw block device — and on vps it has no use at all

- **File:** `modules/nixos/health-alerts.nix:272-280` (esp. `:278`),
  `:250-251`, `hosts/vps/configuration.nix:733-738`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the grant and its unconditional
  application; PLAUSIBLE for "yields root" (not attempted — destructive)
- **Axis:** hardening + needed-used
- **Reachability:** no direct adversary today — `health-check` parses
  only local `zpool`/`smartctl`/`systemctl` output and discards
  Discord's response. This is a blast-radius and least-privilege
  finding: it means the "dedicated non-root user" is not actually a
  privilege reduction on homelab.
- **Rule:** violates `docs/hardening.md` "Dedicated service users" —
  "grant only the specific group memberships/capabilities … actually
  needed"; and §7.4 for the vps half.
- **Finding:** two problems in the same three lines.

  1. **`disk` is not read access.** The comment at `:272-274` says the
     group "gives read access to the raw block devices smartctl needs".
     Block device nodes are `root:disk 0660` — group members have
     **write**. On homelab that is write access to the vdevs backing
     `zbackup`, threat-model asset #1, and to the boot disk. A
     compromise of this unit is therefore a compromise of the backup
     pool and of the host, not a bounded read. The dedicated user and
     the careful `CapabilityBoundingSet = [ "CAP_SYS_RAWIO" ]` next to
     it give the impression of a tight sandbox that the group
     membership silently undoes — failure mode §7.5, inside a single
     module.
  2. **On vps the grant is entirely dead.** `users.users.health-check.
     extraGroups = [ "disk" ]` and `AmbientCapabilities = [
     "CAP_SYS_RAWIO" ]` are set unconditionally, with no `lib.mkIf
     cfg.checkSmart`. vps sets `checkSmart = false` and `checkZfs =
     false` (`hosts/vps/configuration.nix:736-737`) — confirmed in the
     rendered vps unit, which still carries
     `AmbientCapabilities=CAP_SYS_RAWIO`. So the internet-facing host
     carries a raw-I/O capability and a raw-disk group for a code path
     that is compiled out. Textbook §7.4.
- **Proposed fix:** gate both on `cfg.checkSmart`:

  ```nix
  users.users.health-check.extraGroups = lib.optionals cfg.checkSmart [ "disk" ];
  # and in serviceConfig:
  AmbientCapabilities = lib.optionals cfg.checkSmart [ "CAP_SYS_RAWIO" ];
  CapabilityBoundingSet = lib.optionals cfg.checkSmart [ "CAP_SYS_RAWIO" ];
  ```

  and on the hosts that do need it, constrain the access to read with
  systemd's device cgroup rather than relying on the file mode:

  ```nix
  DevicePolicy = "closed";
  DeviceAllow = [ "block-blkext r" "block-sd r" "block-nvme r" ];
  ```

  which blocks writes to the device nodes regardless of group
  membership. Also fix the comment to say "read/write". Worth
  considering whether the SMART check is needed here at all —
  `services.smartd` is already enabled fleet-wide as root
  (`modules/profiles/default.nix:104-112`); what health-alerts uniquely
  adds is the Discord delivery, since smartd's configured notifiers are
  wall/x11/systembus and reach nobody on a headless box.
- **Fix risk:** `DeviceAllow … r` may break `smartctl`'s SG_IO ioctls
  if it opens the device O_RDWR. VM-test `smartctl -H` under the new
  unit before landing; if it breaks, fall back to gating the group on
  `checkSmart` alone, which already fixes vps.
- **Owner:** P7; P3 should confirm the homelab impact on the zbackup
  vdevs, P2 the vps half.

### F-P7-06 — `push-deploy-vps` takes only `NoNewPrivileges` despite doing no local activation, and its comment claims a `ReadOnlyPaths` that is not set

- **File:** `modules/nixos/push-deploy.nix:141-151`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (rendered unit read)
- **Axis:** hardening + documentation
- **Reachability:** no adversary reaches this today; it is a
  blast-radius gap on a root unit that handles remote input (see
  F-P7-03, which lands *in* this unit).
- **Rule:** **violates `docs/hardening.md`'s "Custom `systemd.services`
  sandboxing"** — the carve-out is for units performing real system
  activation, and this unit performs none locally.
- **Finding:** the module's own comment (`:144-149`) reads: "no local
  system activation happens here, so unlike pull-deploy/auto-switch
  this genuinely could be sandboxed further, but `ReadOnlyPaths` on
  `${cfg.flakeDir}` plus `NoNewPrivileges` is enough for now". The
  rendered unit contains **only** `NoNewPrivileges=true` — there is no
  `ReadOnlyPaths`, and there could not be one, since the unit's first
  action is `fetch_and_merge_master`, which *writes* to `flakeDir`. So
  the comment describes a control that does not exist and could not
  exist as described. That is §7.5 at module scope: a future reader
  budgets for a protection that was never applied.

  The unit's actual job — `git fetch`/`merge` in `/etc/nixos`, `nix
  build` (delegated to nix-daemon), closure copy over SSH, remote
  activation — is exactly the "build-only job" the hardening rule says
  can take the full stack. Compare `flake-update-test` in
  `auto-update.nix:174-192`, which is the same shape and does take most
  of it.
- **Proposed fix:** bring it to `flake-update-test`'s level and then
  some:

  ```nix
  NoNewPrivileges = true;
  ProtectSystem = "strict";
  ReadWritePaths = [ cfg.flakeDir "/root/.ssh" "/root/.gitconfig" ];
  ProtectKernelModules = true;
  ProtectKernelTunables = true;
  ProtectKernelLogs = true;
  ProtectControlGroups = true;
  RestrictNamespaces = true;
  PrivateTmp = true;
  ```

  and replace the misleading comment with what is actually true. Note
  `ProtectHome` must stay off (git/ssh read `/root`), and `/root/.ssh`
  must be writable while `accept-new` remains — fixing F-P7-04 removes
  that need.
- **Fix risk:** `nixos-rebuild --target-host` shells out to `ssh` and
  `nix-copy-closure`; `PrivateTmp` and `ProtectSystem=strict` can break
  the SSH control-master socket path and nix's fetcher cache under
  `/root/.cache`. This must be VM-tested with a real remote target, not
  build-tested — a broken push-deploy is a silent vps-stops-updating
  failure.
- **Owner:** P7.

### F-P7-07 — `flake-update-test` auto-merges upstream input updates to `origin/master` with build success as the only gate

- **File:** `modules/nixos/auto-update.nix:132-207`, esp. `:150-172`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the mechanism
- **Axis:** hardening
- **Reachability:** A6 — a malicious or compromised flake input.
- **Rule:** new-rule candidate; amplifies F-P0-01.
- **Finding:** weekly, as root on homelab, this unit runs `nix flake
  update`, builds, and if the build succeeds does `git merge --ff-only
  auto-update; git push origin master`. So the *only* thing standing
  between an upstream input change and `origin/master` — which §4.1
  establishes is a root credential for the whole fleet — is "it
  compiles". No human sees the lock diff, and once it is on master
  every other host's guard happily fast-forwards to it.

  F-P0-01 frames the fleet's root authority as "a GitHub account". This
  unit widens it to "a GitHub account, plus every flake input's
  upstream, unattended". Both severity qualifiers in F-P0-01 should be
  read with that in mind.

  Note also `:169` — on build failure the branch is pushed with `--force`.
  Bounded (it is a scratch branch), but it means a failing input update
  silently overwrites whatever was last left there for review.
- **Proposed fix:** decision required, and it belongs with F-P0-01's
  decision rather than separately. Options: (a) push the `auto-update`
  branch always and never auto-merge, so the merge is a human action —
  this preserves the build-test value and costs one click a week;
  (b) keep auto-merge but restrict `nix flake update` to the inputs
  where it is genuinely wanted (`nix flake update nixpkgs-stable
  nixpkgs-unstable`) rather than every input including the small
  community ones; (c) accept and record it in `docs/hardening.md`
  alongside F-P0-01's decision.
- **Fix risk:** (a) means unattended patching stops happening if nobody
  clicks, which has its own security cost — that is the same trade
  F-P0-01 is about, so decide them together.
- **Owner:** user decision; P7 for the mechanism.

### F-P7-08 — `bootstrap-host.sh` writes a secrets-master private key onto a snapshotted, replicated, offsite-backed-up filesystem, and enrols it before asking

- **File:** `scripts/bootstrap-host.sh:120-140`, `:157-184`; `.sops.yaml`
- **Severity:** **HIGH** (re-rated from MEDIUM after threat model §4.7
  — see the "permanent and retroactive" paragraph below)
- **Confidence:** CONFIRMED for the code and the filesystem facts;
  PLAUSIBLE for "a copy is currently in a snapshot" (would need
  `zfs diff` against the snapshots to prove)
- **Axis:** hardening
- **Reachability:** A7 for the failure-path leftover (mode 0700 dir, so
  only the invoking user and root — but that is `lilijoy`, the A7
  foothold); A9/backup-holder for the snapshot copies.
- **Rule:** violates `docs/procedures/secrets.md` in spirit;
  new-rule candidate for key-generation location.
- **Finding:** three related issues, in a script whose whole purpose is
  handling key material.

  1. **`mktemp -d` lands on a snapshotted dataset.** `work_dir=$(mktemp
     -d)` → `/tmp`, which on torrent is part of `zroot/local/root` (no
     separate mount, confirmed live) — the dataset `myZrepl` snapshots
     **every 5 minutes** and replicates to `zbackup`, from which restic
     pushes to Backblaze. A real install takes many minutes, so several
     snapshots capture the freshly generated host private key even on
     the *success* path, where the script's `rm -rf` gives a false
     sense of cleanup. This is not a small key: `.sops.yaml` has a
     single `creation_rule` covering `secrets/[^/]+\.(yaml|json|env|ini)$`
     with all seven recipients, so the age key derived from that host
     key decrypts **the entire `secrets.yaml`** — tailscale auth keys,
     the wireguard private key and PSK, the vps-deploy key, the zrepl
     keys, both Discord webhooks, the restic/Backblaze credentials.
  2. **The failure path deliberately preserves it.**
     `cleanup()` (`:121-128`) prints "preserving $work_dir (has the
     generated host key) for recovery" on any non-zero exit. Reasonable
     intent, but it leaves that key on disk indefinitely (until
     tmpfiles' 10-day sweep) with no reminder, in the same
     snapshotted location.
  3. **Secrets are re-encrypted to the new recipient *before* the
     confirmation prompt.** `sops updatekeys` runs at `:172`; the
     "This will WIPE …" prompt is at `:175-184`. Answering `N` exits 1
     — which takes the preserve-on-failure branch. So an aborted run
     leaves `secrets/secrets.yaml` enrolled for a key whose private
     half is sitting in `/tmp`. The script's own abort message
     acknowledges the repo mutation but not that consequence.

  Concretely non-hypothetical: `.sops.yaml`'s `&vps` anchor comment
  says it was "Rotated 2026-08-25 for the post-brick reinstall", i.e.
  this script ran yesterday.

  **Why this is HIGH and not MEDIUM, given threat model §4.7.** My
  first rating assumed the ciphertext was reachable only by someone who
  already held backup access. On a public repo that is wrong in two
  compounding ways. `secrets/secrets.yaml` and all 72 of its historical
  revisions are downloadable by anyone, so the age key is the *entire*
  protection — there is no network boundary, no rate limit, and no
  detection in front of an attacker who has one. And **rotation is not
  retroactive**: anyone who archives today's ciphertext and later
  obtains any one of the seven recipient keys decrypts every secret
  that file has ever held, including ones rotated years earlier. A key
  written into 32 days of ZFS snapshots plus an offsite backup is
  therefore not a bounded exposure that ages out; it is a durable,
  permanently-valuable artefact against a permanently-available
  ciphertext. The recipient set is itself public in `.sops.yaml`, so an
  attacker knows exactly which seven keys are worth hunting.
- **Proposed fix:**
  - Force the work dir onto tmpfs: `work_dir=$(TMPDIR="${TMPDIR:-/run/user/$(id -u)}" mktemp -d)`,
    with a guard that refuses to proceed if `findmnt -no FSTYPE
    "$work_dir"` is not `tmpfs`. `/run/user/$UID` is tmpfs and 0700 on
    all these hosts.
  - Move the confirmation prompt **above** the `.sops.yaml` edit and
    `sops updatekeys`, so an abort mutates nothing.
  - On the preserve-on-failure branch, print the exact `shred`/`rm`
    command and a warning that the key is a full `secrets.yaml`
    recipient until `.sops.yaml` is rotated.
- **Fix risk:** `/run/user/$UID` is small (typically 10% of RAM) — fine
  for two key files, but the script also passes `work_dir` to
  `nixos-anywhere --extra-files`, so anything larger added later would
  hit the limit. Note that in a comment. Reordering the prompt changes
  the script's observable flow; re-read `docs/procedures/new-host.md`
  for any step that depends on the current ordering.
- **Owner:** P7; the `docs/procedures/secrets.md` addition is a Phase 4
  doc change.

### F-P7-18 — the secret scan runs at `pre-commit`, not at `pre-push`, and the hooks only exist if you entered the devshell

- **File:** `.githooks/pre-commit:1-49`, `.githooks/pre-push:1-57`,
  `modules/flake/devshell.nix:38-47`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** not an adversary path — this is the preventive
  control F-P0-08 proposes, assessed against the fact that a plaintext
  commit to a public repo is permanent and cannot be withdrawn.
- **Rule:** new-rule candidate.
- **Finding:** assessment of F-P0-08, in three parts.

  **(a) A secret scan already exists, and it is better than nothing.**
  `.githooks/pre-commit` is not just a `sops:` check. Against staged
  *index* content (`git show ":$file"` — correctly, not the worktree)
  it already blocks: a `secrets.yaml` lacking a `^sops:` metadata
  block; PEM private-key headers (`RSA`/`EC`/`OPENSSH`/`DSA`/bare);
  `AGE-SECRET-KEY-1[A-Z0-9]+`; and `AKIA[0-9A-Z]{16}`,
  `xox[baprs]-…`, `ghp_[0-9A-Za-z]{36}`. It skips binaries, quotes
  every expansion, and tells the user how to override. So the answer to
  "does it do any secret scanning today" is **yes** — F-P0-08 should be
  scoped as *strengthening* an existing control, not adding a missing
  one.

  **(b) It is at the wrong gate for a public repo.** `pre-commit` is
  the *recoverable* boundary — a bad commit can be amended or
  rebased away before it leaves the machine. `pre-push` is the
  *irreversible* one, and `.githooks/pre-push` does no secret scanning
  at all: it only builds affected hosts. Anything that reaches a commit
  without passing `pre-commit` therefore reaches GitHub unchecked, and
  there are ordinary ways for that to happen — `git commit --no-verify`,
  a rebase or `git am` (hooks do not run per replayed commit), a
  cherry-pick, a tool or editor integration that bypasses hooks, or a
  commit made in a clone where the hooks were never installed (see (c)).
  On a public repo that gap is exactly backwards: the cheap check is
  guarding the recoverable step and the permanent step is unguarded.

  **(c) The hooks are opt-in by side effect.** They are wired only by
  `modules/flake/devshell.nix:41` — `git config --local
  core.hooksPath .githooks` inside the devshell's `shellHook`. That is
  repo-local config, so a fresh clone has **no hooks at all** until
  somebody enters the nix devshell in it. Confirmed live on torrent:
  `.git/config` does carry `hooksPath`, but that is a property of this
  particular checkout, not of the repository.

  **(d) The current patterns miss most of what this fleet actually
  holds.** Cross-referencing the 31 key names in `secrets/secrets.yaml`
  against the regex list, the unmatched classes are:
  tailscale auth keys (`tskey-auth-…`, `tskey-client-…` — five of
  them); Discord webhook URLs (`https://discord.com/api/webhooks/…` —
  two); WireGuard private keys and PSKs (three, 44-char base64);
  Backblaze/restic credentials and the rclone config block; the
  Cloudflare octoDNS token (40 chars, and `modules/services/octodns.nix`
  already has a `CLOUDFLARE_TOKEN` string right where a real one could
  get pasted); and every GitHub token form other than `ghp_` — `gho_`,
  `ghu_`, `ghs_`, `ghr_`, and fine-grained `github_pat_[A-Za-z0-9_]{82}`.
  The age-key regex is also case-sensitive and would miss a
  lowercase-emitted key.
- **Proposed fix:** practical, and small.
  1. **Move the scan to `pre-push` as well** — the higher-value change.
     `pre-push` already computes `$range` per ref; reuse it:
     `git diff --name-only "$range"` → for each file,
     `git show "$local_sha:$file"` → the same regex battery, then block.
     Keep `pre-commit` too: catching it early is still nicer.
  2. **Extend the patterns** to the classes in (d). All are
     low-false-positive except the WireGuard/base64 one, which should
     be anchored on a nearby `wireguard`/`PrivateKey`/`PresharedKey`
     keyword rather than matching bare base64.
  3. **Consider `gitleaks`** (packaged in nixpkgs; verify the attribute
     on the pin before landing) instead of hand-maintaining the list:
     `gitleaks protect --staged --no-banner` in `pre-commit` and
     `gitleaks detect --log-opts="$range"` in `pre-push`. A maintained
     ruleset is worth more than a hand-rolled one for exactly the
     classes nobody thought of. Cost: one more devshell dependency and
     some allowlist tuning for `env/CLOUDFLARE_TOKEN` and the sops
     ciphertext itself.
  4. **Make hook installation not depend on entering the devshell** —
     at minimum document it in `AGENTS.md`/`README.md` as a required
     first step in a fresh clone, ideally as a one-line `git config
     core.hooksPath .githooks` in the clone instructions.
- **Fix risk:** a `pre-push` scan runs over whole commit ranges, so a
  large first push (or a `--force` after a rebase) scans a lot; keep it
  to files changed in the range, not the full tree. Any new pattern
  risks blocking a legitimate push at the worst moment — keep the
  existing `--no-verify` escape hatch documented, and make the failure
  message name the matching pattern so a false positive is obvious.
  Note also that neither hook can help with anything already pushed:
  §4.7 records the history as clean, and the hook's job is only to keep
  it that way.
- **Owner:** P7 for the assessment; F-P0-08 owns the decision.

### F-P7-09 — every guard fails *open as success*, so skips are indistinguishable from deploys and nothing on the laptops ever alerts

- **File:** `modules/flake/deploy-guards.nix:27,33,64,74`;
  `modules/nixos/health-alerts.nix` (absent on torrent/thinkpad, see
  `modules/flake/hosts.nix:11-46`); `hosts/homelab/configuration.nix:312`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (observed live in torrent's journal)
- **Axis:** hardening
- **Reachability:** n/a directly — this is the observability hole that
  makes every other finding harder to detect, and it is the specific
  blocker on F-P0-01's option (b).
- **Rule:** new-rule candidate — "a security check must fail loudly."
- **Finding:** all four guards end in `exit 0`. Observed live on
  torrent: a run that skipped with `Last switch activated 16 seconds
  ago …` was recorded by systemd as `Deactivated successfully` /
  `Finished`. Three consequences:

  1. **`OnSuccess=` fires on a skip.** On homelab,
     `systemd.services.auto-switch.onSuccess = [ "push-deploy-vps.service" ]`
     (`hosts/homelab/configuration.nix:312`), so a switch skipped by the
     `protectedUnits` guard — the guard that exists to avoid killing a
     multi-day restic run — still kicks off a build and a closure push
     to vps, which is exactly the boot-time/CPU contention the guard is
     about. Same for a skip caused by a dirty tree.
  2. **Nothing distinguishes "deployed" from "did not deploy."** The
     only signal is a journal line. `myHealthAlerts` reports `systemctl
     --failed`, which a skip never enters.
  3. **On torrent and thinkpad there is no alerting at all.**
     `modules/flake/hosts.nix` imports `health-alerts` only for homelab
     and vps. So a `pull-deploy` that *fails* — build error, fetch
     failure, and, if F-P0-01 option (b) lands, a signature-verification
     failure — is completely silent on both laptops. This directly
     answers F-P0-01's stated fix risk ("needs the health alerting to
     actually page on it"): **today, nothing would.**

  This also has a straightforward safety reading. `check_min_switch_interval`
  and `check_protected_units_inactive` are TOCTOU-shaped: the protected
  unit is checked once, then a build runs for minutes to hours before
  the switch. A `restic-backups-backblazeWeekly` run that starts inside
  that window is killed by the switch anyway. Not exploitable, but the
  guard is weaker than the docs imply.
- **Proposed fix:** distinguish the two cases. Either (a) keep `exit 0`
  for the *deliberate* skips but emit a machine-readable marker
  (`systemd-notify --status=…`, or touch a state file that
  `staleMarkerFiles` watches — the module already has that mechanism,
  and a "last successful deploy" marker per host is the natural fit),
  or (b) use a distinct exit code plus `SuccessExitStatus=` so systemd
  still reports success while `OnSuccess=` can be replaced by an
  explicit `ExecStartPost` that only runs after a real switch. Either
  way: **enable `myHealthAlerts` on torrent and thinkpad**, at minimum
  with `checkZfs`/`checkSmart` as appropriate and a
  `staleMarkerFiles` entry for the deploy marker, before landing any
  fail-closed check.
- **Fix risk:** enabling health-alerts on the laptops adds a second
  Discord webhook consumer and needs a per-host sops secret; a laptop
  legitimately offline for weeks will produce staleness noise unless
  thresholds are set as generously as homelab's 336h entries already are.
- **Owner:** P7, with P5 for the laptop-side enablement.

### F-P7-10 — homelab's auto-update units have no `ssh` on their `PATH`

- **File:** `modules/nixos/auto-update.nix:34-39`, `:135-139`;
  `modules/flake/deploy-guards.nix:51`
- **Severity:** LOW (security), but operationally urgent
- **Confidence:** CONFIRMED that `openssh` is absent from the rendered
  `PATH`; PLAUSIBLE that this breaks the fetch (depends on whether
  `/etc/nixos`'s `origin` is an SSH or HTTPS URL, which needs one
  command on homelab)
- **Axis:** needed-used
- **Reachability:** n/a — this fails closed, which is the safe
  direction. It is here because it blocks F-P0-01's remediation.
- **Rule:** n/a
- **Finding:** `fetch_and_merge_master` exports
  `GIT_SSH_COMMAND="ssh …"` and git resolves `ssh` via `PATH` (verified:
  neither git 2.54.0 nor 2.55.0 contains a hardcoded store path to it).
  `pull-deploy.nix:95-101` and `push-deploy.nix:98-104` both list
  `openssh` in `path`. **`auto-update.nix` does not** — the rendered
  `auto-switch.service` `PATH` is git, nixos-rebuild-ng, nix, coreutils,
  findutils, gnugrep, gnused, systemd, and nothing else. So
  `auto-switch`, `auto-switch-now` and `flake-update-test` cannot run
  `git fetch`/`git push` over SSH.

  Corroborating: `deploy-guards.nix` was created 2026-08-25 (one day
  ago) and `auto-update.nix` was rewritten in the same commit, so
  `auto-switch`'s next run is Thu 2026-08-27 03:00 — it has not run in
  this shape yet. Separately, `flake-update-test` has existed since
  2026-08-15 (`d16733f`) with two `Wed 03:00` windows since, and there
  is **not one `chore: automated flake.lock update` commit in the
  repository's 1371-commit history** — consistent with it never having
  completed. Its sandbox is a second candidate cause:
  `ProtectSystem = "strict"` with `ReadWritePaths = [ "/etc/nixos" ]`
  makes `/root` read-only, and `nix flake update` needs to write
  `~/.cache/nix/fetcher-cache-*.sqlite` — the exact problem
  `iso-autobuild.nix:108-114` documents and solves for its own build
  user, and which is not solved here.
- **Proposed fix:** add `openssh` to `auto-update.nix`'s `path` (both
  the shared `mkSwitchService` list and `flake-update-test`'s), and add
  `"/root/.cache/nix"` to `flake-update-test`'s `ReadWritePaths`. Note
  that `openssh` is also a **prerequisite for F-P0-01 option (b)**:
  `git verify-commit` with `gpg.format = ssh` shells out to
  `ssh-keygen`, from the same package.
- **Fix risk:** none; strictly additive. Confirm afterwards by watching
  `journalctl -u flake-update-test` for a completed run rather than
  assuming.
- **Owner:** P7; **P3 should verify on homelab** — `git -C /etc/nixos
  remote -v` and `journalctl -u flake-update-test -u auto-switch` will
  settle it in one command.

### F-P7-11 — the laptops' unattended deploys authenticate with the interactive user's push-capable GitHub key

- **File:** `modules/nixos/pull-deploy.nix:78-89`,
  `hosts/torrent/configuration.nix:25`,
  `hosts/thinkpad/configuration.nix:26`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A7/A8 — `lilijoy` owns the file (0600, confirmed
  live) and can replace it; and physical loss of the thinkpad (§8.7, no
  FDE) hands over a key with push access, hence fleet root per §4.1.
- **Rule:** new-rule candidate.
- **Finding:** `sshKeyPath = "/home/lilijoy/.ssh/id_ed25519"` on both
  laptops points root's unattended fetch at the human's day-to-day
  GitHub key. Two distinct problems:

  1. **Wrong privilege for the job.** A *pull* deploy needs read-only
     access to one repository. This key has push access to it — which
     §4.1 makes equivalent to root on all four hosts. A GitHub
     **deploy key** with read-only scope, or a dedicated
     `sops.secrets.<host>_pull_key`, would be strictly less powerful
     and would also let root stop depending on a path in `/home`.
  2. **The file is attacker-writable.** `lilijoy` can substitute a key
     of their own choosing; combined with a rewritten
     `remote.origin.url` (also user-writable), root fetches from an
     attacker's repository. This is a sub-case of F-P7-01, listed here
     because the fix is separate and independently worthwhile.

  The option's own documentation states the underlying constraint
  honestly ("root has no home-manager profile at all"), and
  `docs/architecture.md` repeats it as a settled design. It is not
  settled: the constraint argues for root *having its own identity*,
  which sops already provides everywhere else in this repo.
- **Proposed fix:** issue a read-only GitHub deploy key per laptop,
  store it in `secrets/secrets.yaml`, and set `sshKeyPath =
  config.sops.secrets.<host>_pull_key.path`. That is root-owned 0400
  under `/run/secrets`, needs no home-manager profile, and drops the
  push capability from the unattended path entirely. Do this whether or
  not F-P7-01's fix moves `flakeDir`.
- **Fix risk:** GitHub deploy keys are per-repository and cannot be
  reused across the two laptops (a key may be attached to only one
  repo, but also each key must be unique across the account) — generate
  two. Adding a secret means a `.sops.yaml`/`updatekeys` cycle, which
  F-P7-08 shows needs care.
- **Owner:** P7, with P5.

### F-P7-12 — `myIsoAutobuild.triggeredBy` renders a phantom `pull-deploy.service.service` unit and never fires

- **File:** `modules/nixos/iso-autobuild.nix:69-74`, `:84-87`;
  `hosts/torrent/configuration.nix:30-35`
- **Severity:** LOW
- **Confidence:** CONFIRMED (observed live)
- **Axis:** needed-used
- **Reachability:** n/a — recovery-readiness, not attack surface.
- **Rule:** n/a; textbook failure mode §7.2 ("config that renders but
  never takes effect").
- **Finding:** `lib.genAttrs cfg.triggeredBy (_: { unitConfig.OnSuccess
  = [ "iso-build.service" ]; })` uses the values of `triggeredBy`
  verbatim as `systemd.services` **attribute names**, and torrent passes
  `[ "pull-deploy.service" ]`. NixOS appends `.service` itself, so this
  generates a unit literally named `pull-deploy.service.service`.
  Confirmed live: `/etc/systemd/system/pull-deploy.service.service`
  exists, contains `OnSuccess=iso-build.service` and nothing else, and
  the real `pull-deploy.service` has no `OnSuccess` at all. The recovery
  ISO has therefore never been rebuilt by this mechanism — corroborated
  by `~/Downloads/nixos-recovery-*.iso` being dated 2026-08-16 while
  `pull-deploy` has run since, and by
  `/var/lib/iso-autobuild/result` now being a **dangling symlink** to a
  garbage-collected store path (so even a manual `iso-copy-to-downloads`
  would find nothing and exit 0 with "No iso has been built yet").
- **Proposed fix:** strip the suffix in the module —
  `lib.genAttrs (map (lib.removeSuffix ".service") cfg.triggeredBy) …` —
  and change the option's `example`/description to say plain unit names
  without the suffix. Then delete the phantom unit from the live system
  (it disappears on the next switch once the module is fixed). Consider
  an assertion rejecting names containing a `.` so the next instance
  fails at eval instead of silently.
- **Fix risk:** once fixed, every successful *or skipped* `pull-deploy`
  run triggers a full ISO build (see F-P7-09 — `OnSuccess` fires on
  skips too), which is a multi-gigabyte build on the daily driver. Wire
  it after F-P7-09, or trigger from a real-switch marker instead.
- **Owner:** P7; P5 for the torrent-side behaviour once it starts firing.

### F-P7-13 — health-alerts records an alert as sent before it is sent, and aborts the rest of the run when delivery fails

- **File:** `modules/nixos/health-alerts.nix:122-134` (esp. `:131-133`)
- **Severity:** LOW
- **Confidence:** CONFIRMED (rendered script read; `set -e` is emitted
  by NixOS's job-script wrapper and is *not* cleared by the script's
  own `set -uo pipefail`)
- **Axis:** hardening
- **Reachability:** n/a — reliability of the only outward alerting
  channel, which several other findings depend on.
- **Rule:** new-rule candidate.
- **Finding:** `notify()` writes the cooldown stamp (`echo "$now" >
  "$stamp"`) *before* the `curl` that actually posts. If the POST
  fails — network down, Discord 5xx, an expired webhook — the alert is
  lost **and** suppressed for `cooldownHours` (6 by default) as though
  it had been delivered. Worse, `curl`'s non-zero exit under the
  inherited `set -e` aborts the whole script, so every check after the
  first failing notification is skipped for that run: the `failed
  systemd units` and `stuck nixos-rebuild switch` checks are last in
  the script and are the first to be lost.

  Related, cosmetic but user-facing: the payload at `:132` embeds `\n`
  as a literal backslash-`n` (Nix indented strings do not process `\n`,
  and `jq --arg` JSON-escapes the backslash). Verified: the emitted
  JSON is `"**[h] T**\\n\`\`\`\\nB\\n\`\`\`"`, so Discord renders one
  run-on line containing literal `\n` sequences rather than a formatted
  code block. Since the entire value of this module is that a human
  reads the message, that is worth fixing.
- **Proposed fix:** stamp only on success —
  `if echo "$payload" | curl -sS --fail -K … --data-binary @-; then echo "$now" > "$stamp"; fi`
  — and wrap the whole `notify` body so a delivery failure logs and
  returns rather than aborting the run (`|| { echo "alert delivery
  failed for $key" >&2; return 1; }` with the call sites tolerant of
  it). For the newlines, build the payload with real newlines
  (`printf '%b'`, or a Nix `''\n''`-free heredoc) so jq encodes them as
  `\n` in JSON.
- **Fix risk:** removing the abort means a run continues after a failed
  delivery and may attempt several more POSTs against a dead endpoint —
  add `--max-time 10`. Changing the stamp semantics means a persistently
  unreachable webhook retries every 15 minutes instead of every 6 hours;
  that is the correct behaviour but is a change in outbound volume.
- **Owner:** P7.

### F-P7-17 — there is no CI, and there never has been; the PR path into fleet root rests entirely on settings only the user can see

- **File:** absence of `.github/` (and of every other CI config) in the
  working tree and in the full history
- **Severity:** LOW as it stands — but the rating is **conditional on
  branch protection**, which cannot be read from the repo. If PRs can
  be merged without review, the correct rating is HIGH.
- **Confidence:** CONFIRMED for the negative result (no CI, ever);
  **UNKNOWN** for branch protection and merge settings
- **Axis:** hardening
- **Reachability:** A6 / "anyone on the internet" — threat model §4.7
  establishes that a public repo means anyone may open a PR against
  `origin/master`, and §4.1 establishes that `origin/master` is root on
  all four hosts.
- **Rule:** n/a; threat model open question §8.8.
- **Finding:** **the valuable part of this finding is the negative
  result, so it is stated first and precisely.**

  **There is no CI in this repository and there never has been.**
  `.github/` does not exist. Searching every file ever added on every
  branch in the full history for `.github/`, `workflow`, `.gitlab-ci`,
  `.circleci`, `azure-pipelines`, `Jenkinsfile`, `.woodpecker`,
  `.drone`, `.travis`, `.builds/` and `garnix` returns zero matches;
  the complete set of root dotfiles ever added is `.envrc`,
  `.githooks/*`, `.gitignore`, `.sops.yaml`. There is no
  Nix-CI-as-a-service integration either — the only `hercules` string
  in the flake is `github:hercules-ci/flake-parts`, the upstream owner
  of `flake-parts`.

  So the two worst PR-shaped paths **do not exist here**: no workflow
  triggers on `pull_request` from a fork, and no CI holds a credential
  of any kind. An untrusted PR causes nothing to execute anywhere. That
  is a genuinely good posture and should be preserved deliberately —
  the moment any workflow is added to this repo it becomes an
  unauthenticated inbound path toward a `master` that is fleet root,
  and `pull_request_target` in particular would be catastrophic here.

  What remains is entirely off-repo, and **cannot be settled by
  reading the config** — flag for the user:

  1. **Branch protection / rulesets on `master`.** Specifically:
     is a pull request required (no direct pushes)? Is at least one
     approving review required? Is force-push to `master` blocked? Are
     deletions blocked? Do the rules apply to administrators
     (`enforce_admins`) — because if not, the single admin's key is the
     whole control and the rules are decorative.
  2. **Who can merge.** Collaborators, outside collaborators, and any
     organisation/team access. On a single-admin repo this should be
     exactly one account.
  3. **Auto-merge and Dependabot.** If auto-merge is enabled on the
     repo, or Dependabot/Renovate is configured with automerge, a bot
     can move `master` — i.e. move fleet root — without a human. Note
     `flake-update-test` (F-P7-07) is this repo's own equivalent and is
     already doing exactly that from homelab.
  4. **Deploy keys and PATs with write scope**, and the account's 2FA
     posture and recovery email. F-P0-01 already lists these as in
     scope.
  5. **Whether the repo needs to be public at all.** Not P7's call, but
     it is the one setting that changes several ratings at once (§4.7,
     F-P7-08, F-P7-18). If it is public for portfolio/sharing reasons
     that is a legitimate answer; it should be a recorded decision
     rather than a default.

  One further consequence within P7's scope, from §4.7's no-obscurity
  rule: because PRs are a normal thing to receive on a public repo,
  **checking one out locally is itself a hazard here**, and two of this
  part's mechanisms make it worse. `core.hooksPath` points into the
  worktree (`.githooks/`, F-P7-18(c)), so a PR branch that edits
  `.githooks/pre-commit` executes the contributor's code as `lilijoy`
  on the next commit in that checkout. And `nix flake check` /
  `nixos-rebuild build` on a PR branch evaluates the contributor's Nix,
  where import-from-derivation and `builtins.fetchurl` give a
  motivated author reach. Mitigating: `require_clean_master` refuses to
  run on a non-`master` branch (`deploy-guards.nix:30-34`), so a
  checked-out PR branch is **not** auto-deployed — a real and
  worthwhile property, verified in the guard source.
- **Proposed fix:** (i) the user verifies items 1–5 above in the GitHub
  UI and records the answers in `docs/hardening.md` next to F-P0-01's
  decision; (ii) add a written rule that **no GitHub Actions workflow
  is to be added to this repository** while `master` is fleet root, or
  if one ever is, that it must be `pull_request` (never
  `pull_request_target`), hold no secrets, and have
  `permissions: contents: read`; (iii) review PR branches by reading
  the diff on GitHub, and if a local checkout is needed, do it in a
  clone with `core.hooksPath` unset.
- **Fix risk:** none — settings verification and documentation.
- **Owner:** user for items 1–5 (threat model §8.8); P7 for the CI
  negative result and the no-workflows rule.

### F-P7-14 — what health-alerts hands to Discord

- **File:** `modules/nixos/health-alerts.nix:132-133`, `:142-241`;
  `hosts/homelab/configuration.nix:89-92`,
  `hosts/vps/configuration.nix:729-732`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening + documentation
- **Reachability:** anyone who can read the Discord channel, plus
  Discord itself. Not an adversary in §5; recorded because it is a
  standing outbound data flow to a consumer chat service that nothing
  in the docs describes.
- **Finding:** the credential handling is **good** and should be kept:
  the webhook URL is passed via `curl -K <file>` rather than argv
  (`:22-23` documents exactly why), the file is a sops secret owned by
  `health-check` on both hosts (`hosts/homelab/configuration.nix:89-92`,
  `hosts/vps/configuration.nix:729-732`), and `jq --arg` correctly
  JSON-escapes every interpolated body, so none of the message
  construction is injectable.

  What leaves the fleet, per alert: the hostname; `zpool status -x`
  output (pool names, vdev device paths, error counters, resilver
  state); the device paths of any SMART-failing drive; ZFS dataset
  paths and snapshot ages from `backupStaleness`, which on homelab
  spells out the full backup topology including both laptops' dataset
  names; marker-file paths; and `systemctl --failed --no-legend
  --plain`, which is unit names *and their descriptions* — e.g. "Build
  locally and push+activate vps on vps-deploy@vps", naming the deploy
  user and the target. No secret values, no journal text, no command
  stderr beyond `zpool status`.

  So: no credential leaks, but a periodic, retained, plaintext-at-rest
  inventory of the fleet's hosts, storage layout and service topology
  in a third-party consumer service. For a personal homelab that is
  probably an acceptable trade — but it is currently an undocumented
  one, which is the finding.
- **Proposed fix:** documentation. Add a line to `docs/hardening.md` or
  the module's option description recording what is sent, that it is
  retained by Discord indefinitely, and that the channel should not be
  in a shared server. If that is judged too much, the cheap mitigation
  is to send unit *names* only (`systemctl --failed --no-legend --plain
  | awk '{print $1}'`), dropping the descriptions, which are the most
  revealing part.
- **Fix risk:** none for the doc; dropping descriptions slightly
  reduces alert usefulness.
- **Owner:** P7 for the finding, Phase 4 for the doc.

### F-P7-15 — `sshKeyPath`, `identityFile` and `webhookUrlFile` use `types.path`, which accepts a real path and would copy the secret into the world-readable store

- **File:** `modules/nixos/pull-deploy.nix:79`,
  `modules/nixos/push-deploy.nix:36`,
  `modules/nixos/health-alerts.nix:18`
- **Severity:** LOW (latent)
- **Confidence:** CONFIRMED against the pinned nixpkgs
  (`lib/types.nix:655-706`)
- **Axis:** hardening
- **Reachability:** none today — all three call sites pass strings
  (`"/home/lilijoy/.ssh/id_ed25519"`, `config.sops.secrets.*.path`), and
  `types.path`'s `check` accepts a string without copying anything.
- **Rule:** new-rule candidate.
- **Finding:** in the pinned 26.11 tree, `types.path = pathWith { }`
  with both `inStore` and `absolute` unconstrained; its `check` is
  `isStringLike x`, which accepts **both** strings and genuine Nix path
  values. A future edit writing `sshKeyPath = /home/lilijoy/.ssh/id_ed25519;`
  (no quotes — a one-character difference) would type-check, and Nix
  would copy the **private key into `/nix/store`**, world-readable, on
  every host that builds the config, permanently. The same applies to
  the vps deploy key and the Discord webhook.

  nixpkgs already ships the right type for this and even documents the
  hazard in a comment on the very line: `types.externalPath`
  (`= pathWith { absolute = true; inStore = false; }`), whose check
  requires `isString` — "Do not allow a true path, which could be
  copied to the store later on."
- **Proposed fix:** change all three to `lib.types.externalPath`
  (`nullOr lib.types.externalPath` for `sshKeyPath`). One-line each,
  no behaviour change for the current call sites, and it makes the
  dangerous spelling a build error.
- **Fix risk:** `externalPath` also rejects values that *are* store
  paths, so if any future caller legitimately wants a store-resident
  file (a public key, say) it would need a different option. Not the
  case for any of these three. Confirm `externalPath` exists on the
  stable pin homelab uses as well as unstable before landing.
- **Owner:** P7.

### F-P7-16 — smaller items in the deploy path

- **File:** as listed
- **Severity:** INFO
- **Confidence:** CONFIRMED unless noted
- **Axis:** needed-used / documentation
- **Reachability:** n/a
- **Finding:** grouped because none justifies its own remediation
  decision.

  1. **`push-deploy-vps.timer` is `Persistent = true`
     (`push-deploy.nix:158`), contradicting the documented reasoning
     that governs its siblings.** `auto-update.nix:199-205` explains at
     length why `flake-update-test` and `auto-switch` are
     `Persistent = false` — a missed run firing at boot piles I/O onto
     zrepl's post-boot catch-up. `docs/architecture.md:347-359` repeats
     it for "these three". But `push-deploy-vps` is the fourth, is
     `Persistent = true`, triggers a build plus a closure copy, and
     homelab persists `/var/lib/systemd/timers` so the catch-up
     actually happens. Either make it `false` for consistency or
     document why the remote deploy is the exception. (This also
     interacts with F-P7-04: it is the unit most likely to run seconds
     after boot with an empty `known_hosts`.)
  2. **`.githooks/pre-push:23` filters on pathspecs that do not exist.**
     `-- hosts/ profiles/ modules/ services/ …` — there is no top-level
     `profiles/` or `services/` in this repo (they are
     `modules/profiles/`, `modules/services/`), and the `grep` at `:37`
     carries the same dead alternatives. Harmless because `modules/`
     covers them, but the filter genuinely misses `files/`, which
     *is* build-relevant: `modules/profiles/PC.nix:242` reads
     `../../files/gruvbox-dark-rainbow.png`. So a `files/` change can
     land unbuilt. Add `files/` and drop the two dead pathspecs.
  3. **`deploy-guards.nix:24` appends a duplicate `safe.directory` line
     to root's global gitconfig on every run** (`--add`, same value,
     never checked). Unbounded on torrent and thinkpad, where `/root`
     persists; self-limiting on homelab, where it does not. Use
     `git config --global --get-all safe.directory | grep -qxF "$(pwd)" ||
     git config --global --add …` — or, better, remove the line
     entirely as part of F-P7-01.
  4. **`myPushDeploy.elevate = "none"` has no consumer.** homelab is
     the only caller and takes the `"sudo"` default. §7.4 — a branch in
     root-running deploy code with no user. Either exercise it or drop
     the option.
  5. **`ssh $NIX_SSHOPTS …` (`push-deploy.nix:116,133,134,137`) relies
     on unquoted word-splitting**, so the identity path is also
     glob-expanded. Fine for `/run/secrets/homelab_vps_deploy_key`, and
     the pattern is idiomatic for `NIX_SSHOPTS`, but a `NIX_SSHOPTS`
     array (`ssh "${ssh_opts[@]}"`) for the direct `ssh` calls would be
     robust without affecting what `nixos-rebuild` reads.
  6. **`git merge --ff-only` cannot be *defeated* in the direction that
     matters.** A force-push to a non-descendant makes the merge exit
     non-zero, which under `set -e` fails the unit — correct, and worth
     recording as a checked-and-clean property. Its weakness is the
     opposite direction, covered in F-P7-01 mechanism (1).
  7. **The git hooks are `core.hooksPath`-into-the-worktree
     (`modules/flake/devshell.nix:38-47` sets it, `.git/config`
     confirms it live).** This means a commit landing in `.githooks/`
     executes as `lilijoy` on the next commit or push on every
     developer machine that pulls it — a second, lower-privilege
     consequence of F-P0-01 on top of the root one, and, on a public
     repo, also the PR-checkout hazard in F-P7-17. Inherent to the
     pattern, listed so it is a recorded acceptance rather than an
     oversight. The hooks' own code is clean: `pre-commit` uses
     `git show ":$file"` (index content, not worktree) and quotes
     consistently, and `commit-msg` is a pure regex check. Where they
     run and what they scan for is F-P7-18.
- **Proposed fix:** as described inline; all are small and independent.
- **Fix risk:** (1) changes when vps gets deployed after an outage —
  intended. (2) makes the pre-push hook build more often.
- **Owner:** P7.

---

## 3. Root-execution paths

Every way code ends up running as root on each host through this
machinery, and what authenticates each one. This is the deliverable
other parts most need; **"authenticated by" means what actually gates
it today, not what is intended.**

### homelab

| # | Path | Trigger | Runs as | Authenticated by | Findings |
|---|---|---|---|---|---|
| H1 | `flake-update-test.service` → `nix flake update` → build → `git push origin master` | `Wed 03:00` timer, `Persistent=false` | root | nothing — the upstream inputs' own integrity, plus "it builds" | F-P7-07, F-P7-10 |
| H2 | `auto-switch.service` → `git fetch origin` + `merge --ff-only` → `nixos-rebuild switch` | `Thu 03:00` timer, `Persistent=false` | root | **nothing.** No signature check. Transport is SSH to GitHub with `accept-new` against a `known_hosts` wiped every boot | F-P0-01, F-P7-04, F-P7-10 |
| H3 | `auto-switch-now.service` — same, minus the interval/protected-unit guards | manual `systemctl start` | root | root already, by definition | — |
| H4 | `push-deploy-vps.service` → `fetch_and_merge_master` → build → remote activate | `auto-switch`'s `OnSuccess`, **and** a `Thu 03:15` `Persistent=true` timer that fires at boot after a miss | root | same as H2 for the fetch half | F-P0-01, F-P7-04, F-P7-06 |
| H5 | **inbound:** `vps`'s reply to `ssh … stat -c %Y …` reaches `$(( ))` in `check_min_switch_interval` | every H4 run | root | the vps-deploy SSH key and the dispatcher — i.e. **the integrity of vps itself** | F-P7-03 |
| H6 | `ExecStartPost` reboot-if-kernel-changed (`auto-update.nix:73-79`) | after any H2/H3 switch | root | whatever produced the closure in H2 | — |
| H7 | `health-check.service` | `*:0/15` | `health-check`, but in group `disk` with `CAP_SYS_RAWIO` — raw read **and write** to every block device including the zbackup vdevs | the unit's own fixed script | F-P7-05 |

Net: **the only authentication anywhere on homelab's root path is
"whoever can push to `origin/master`", plus — through H5 — "whoever
owns vps".** Both are unsigned.

### Upstream of all of it: `origin/master`

Not a host, but it is the root of every path in the three tables below
and belongs in the enumeration.

| # | Path | Trigger | Becomes root on | Authenticated by |
|---|---|---|---|---|
| M1 | direct push to `master` | admin action | all four hosts, within a cycle | possession of a key with push access — both laptops' `id_ed25519`, plus any PAT; **and** whatever branch protection is configured, which is not visible from the repo (F-P7-17) |
| M2 | merged pull request | anyone may open one; a human must merge unless auto-merge is on | same | review discipline plus the same unverified branch-protection settings |
| M3 | `flake-update-test`'s own auto-merge and push | homelab, `Wed 03:00` | same | "it builds" — no human, no signature (F-P7-07) |
| M4 | any workflow run | **does not exist** — no CI has ever been in this repo (F-P7-17) | — | n/a |

Nothing on this path checks a signature. M4 being empty is the one
piece of good news, and is worth protecting as such.

### torrent and thinkpad

| # | Path | Trigger | Runs as | Authenticated by | Findings |
|---|---|---|---|---|---|
| T1 | `pull-deploy.service` → `git status`/`fetch`/`merge --ff-only` in `/home/lilijoy/dotfiles` → `nixos-rebuild build` → `nixos-rebuild boot` | `Thu 03:00` timer, `Persistent=true` | root | **nothing, and less than nothing** — the repo, its `.git/config`, its `origin` URL, its working tree and the SSH key are all writable by `lilijoy` | **F-P7-01**, F-P0-01, F-P7-11 |
| T2 | any command git itself runs out of that repo's config: `core.fsmonitor` (on `git status`), `reference-transaction` (on `git fetch`), `post-merge` (on the merge), `include.path`, `diff.external`, `filter.*`, `merge.*.driver` | same | root | `deploy-guards.nix:24` explicitly *removes* the only check (git's ownership refusal) | **F-P7-01** |
| T3 | the new closure's bootloader-installation script, via `switch-to-configuration boot` | same | root | whatever T1 built | F-P7-01 |
| T4 | the same closure's full activation | next reboot | root | as T3 | F-P7-01 |
| T5 | `iso-build` / `iso-copy-to-downloads` | *would* be T1's `OnSuccess`; **currently never fires** | `lilijoy`, fully sandboxed | n/a — not a root path | F-P7-12 |

Net: on both laptops, **root activation is authenticated by nothing
stronger than `lilijoy`'s own privileges.** Anything running as the
desktop user is, on a one-week delay at worst, root.

### vps

| # | Path | Trigger | Runs as | Authenticated by | Findings |
|---|---|---|---|---|---|
| V1 | the `vps-deploy` ForceCommand dispatcher → `nix-store --serve --write`, then `sudo`(run0) `nix-env --set` and `sudo switch-to-configuration switch` | homelab's H4 | root, via run0 | possession of `homelab_vps_deploy_key` (root-only sops secret on homelab) + the dispatcher allowlist, which constrains the store path's **name** only | F-P0-02 (P2 owns) |
| V2 | `health-check.service` | `*:0/15` | `health-check`, holding `CAP_SYS_RAWIO` and group `disk` **for a code path compiled out on this host** | the unit's own script | F-P7-05 |

Net: unchanged from F-P0-02 — homelab is vps's deployer and therefore
holds root there by design. What is new is that F-P7-03 makes the
relationship symmetric.

### isoimage

Not a running host. Built by torrent's `iso-build` as `lilijoy` under
the full sandbox stack. The ISO embeds `vars.publicSshKeys` — **public**
keys only (`hosts/isoimage/configuration.nix:98`); no private material
is baked in, and the ISO's own host key is generated at boot. The
briefing's premise that the ISO "contains admin credentials" does not
hold. The real exposure is `services.getty.autologinUser = "root"`
(`:88`) — anyone who boots the media has a root console, which is
inherent to recovery media and is P4's to weigh. File modes are fine:
`~/Downloads/nixos-recovery-*.iso` is `0444` inside a `0700` home
directory. (Aside for P4: `extraConfig` at `:105-113` writes
`PermitRootLogin = prohibit-password` with an `=`, and is subject to
failure mode §7.2 in any case.)

---

## 4. Checked and clean

Things examined that are fine, recorded so they are not re-derived and
not regressed.

- **Module wiring is tight.** `modules/flake/hosts.nix:11-98` imports
  each of the five modules only into the hosts that use them:
  `auto-update` and `push-deploy` on homelab only, `pull-deploy` on the
  two laptops only, `iso-autobuild` on torrent only, `health-alerts` on
  homelab and vps. No module is imported anywhere it is not enabled.
  Every option is consumed except `myPushDeploy.elevate = "none"`
  (F-P7-16.4).
- **The webhook credential is handled correctly.** `curl -K <file>`
  keeps the URL out of argv and out of `/proc/*/cmdline`
  (`health-alerts.nix:22-23,133`); the file is a sops secret owned by
  `health-check` on both hosts. `jq --arg` is used for every
  interpolation, so no alert body is injectable regardless of what
  `zpool`/`smartctl`/`systemctl` emits.
- **The vps-deploy identity file is not exposed by push-deploy.** Only
  the *path* appears in `NIX_SSHOPTS` and the unit's environment; the
  key itself is a default-mode sops secret (root, 0400) and is never
  read, echoed or logged by the sender. Nothing in the unit writes the
  key material anywhere.
- **`git merge --ff-only` fails closed against history rewriting.** A
  force-push to a non-descendant makes the merge exit non-zero, which
  under `set -e` fails the unit. The `--ff-only` choice is also what
  makes tip-only signature verification sound, if F-P0-01 option (b) is
  taken.
- **The activation carve-out in `docs/hardening.md` is applied
  correctly where it applies.** `auto-switch`, `auto-switch-now`
  (`auto-update.nix:62-81`) and `pull-deploy`
  (`pull-deploy.nix:128-144`) each take `NoNewPrivileges` only, and each
  carries an accurate comment saying why. It is **not** used as a
  blanket excuse: `flake-update-test` and both iso units take the full
  stack. The one unit that claims the carve-out without qualifying for
  it is `push-deploy-vps` — F-P7-06.
- **`iso-autobuild`'s sandboxing is the best in this part.** Both units
  take `ProtectSystem=strict`, `ProtectHome=read-only`,
  `PrivateTmp`, `RestrictNamespaces`, `LockPersonality`,
  `RestrictRealtime`, `MemoryDenyWriteExecute` and all four
  `ProtectKernel*`/`ProtectControlGroups`, run as an unprivileged user,
  and the `ReadWritePaths` are minimal and individually justified in
  comments — including the `~/.cache/nix` entry that
  `flake-update-test` is missing. The "not a `DynamicUser`" reasoning at
  `:100-106` and `:131-137` is correct.
- **The copy-to-Downloads script is safe.** Quoted throughout,
  `set -euo pipefail`, atomic `cp` to `.tmp` then `mv -f`, and the
  `find … -delete` is anchored with `-maxdepth 1` and a specific
  `-name 'nixos-recovery-*.iso'` pattern plus `-not -name "$name"`.
  Its failure mode on a missing build is a clean `exit 0`.
- **The health-check stuck-switch detector matches reality.** Its
  `grep -E '^nixos-rebuild-switch-to-configuration'` matches the
  transient unit name nixos-rebuild-ng actually uses
  (`nixos-rebuild-ng-26.11/.../nix.py:52`). It does cover a stuck
  switch — the F-P7-09 gap is that it only exists on homelab and vps.
- **`.githooks/commit-msg` and `.githooks/pre-commit` are sound as
  code.** `pre-commit` inspects staged index content via
  `git show ":$file"` rather than the worktree, quotes every expansion,
  skips binaries, and its `secrets.yaml`-must-contain-`sops:` check is
  the right shape. `commit-msg` is a pure regex check. Their *placement*
  and *coverage* are F-P7-18.
- **No CI has ever existed in this repository**, so despite the repo
  being public there is no `pull_request`-triggered workflow and no
  CI-held credential — the two worst PR-shaped paths toward fleet root
  simply are not present. Verified over the full history, not just the
  working tree. F-P7-17 records what to keep that way.
- **A checked-out pull-request branch is not auto-deployed.**
  `require_clean_master` (`deploy-guards.nix:30-34`) exits before
  fetching if `HEAD` is not on `master`, so leaving a contributor's
  branch checked out on a laptop does not hand it a root switch. Worth
  recording explicitly now that the repo is known to be public.
- **`bootstrap-host.sh`'s key generation itself is correct** —
  `ssh-keygen -t ed25519 -N ""` into a `mktemp -d` (0700), explicit
  `chmod 600`/`644`, `.gitignore` carries `ssh_host_*_key` and
  `*-extra-files/` as a backstop, and the script never writes key
  material into the repo. The problems are *where* the temp dir lives
  and *when* the prompt happens (F-P7-08), not the crypto.
- **The `--vm-test` path touches nothing real** — it short-circuits
  before any `.sops.yaml`/`secrets.yaml` mutation and before the
  confirmation prompt, and says so.
- **`myPullDeploy.protectedUnits` defaulting to `[ ]` is harmless** —
  `check_protected_units_inactive ""` iterates zero times.

---

## 5. The F-P0-01 mechanism assessment

P7 owns the mechanism half of F-P0-01. The decision is the user's; what
follows is what option (b), "verify signatures in
`fetch_and_merge_master`", would concretely cost and actually buy.

**Read this section against the corrected F-P0-01.** The repo is
public, so "private repo" is not among the compensating controls for
option (a), and the inbound side of `origin/master` includes pull
requests from anyone. Two adjustments follow. Option (a) — accept and
document — now has to account for the PR path explicitly, and its
compensating controls reduce to: single admin, GitHub 2FA, and branch
protection whose actual state nobody has yet checked (F-P7-17). Option
(b) becomes correspondingly more attractive, because a signature check
in the deploy path is the one control that is enforced by *this* repo's
code rather than by a GitHub setting, and therefore the one that keeps
working if a branch-protection rule is misconfigured, bypassed by an
admin push, or silently changed. That is a real argument for (b) that
did not exist when the repo was believed to be private — and it does
not depend on trusting GitHub at all.

### The chain, confirmed

- homelab `myAutoUpdate` (`hosts/homelab/configuration.nix:281-290`) →
  `auto-switch.service` → `require_clean_master`,
  `fetch_and_merge_master` (`deploy-guards.nix:18-54`) →
  `nixos-rebuild build` → `nixos-rebuild switch`
  (`auto-update.nix:55-60`) — rendered unit script read in full.
- `systemd.services.auto-switch.onSuccess = [ "push-deploy-vps.service" ]`
  (`hosts/homelab/configuration.nix:312`) → build vps's closure locally
  → `nixos-rebuild switch --target-host vps-deploy@vps --sudo`
  (`push-deploy.nix:119-122`) → the dispatcher activates it as root
  (`hosts/vps/configuration.nix:62-68`).
- torrent and thinkpad `myPullDeploy` → the same two guard functions →
  `nixos-rebuild build` → `nixos-rebuild boot`
  (`pull-deploy.nix:111-123`). Confirmed live on torrent, including a
  real root run in the journal.
- **No signature verification exists anywhere in that path.** Grepped
  the whole repo: no `verify-commit`, no `verify-tag`, no
  `allowedSigners`, no `gpg.format`. Confirmed by reading all five
  rendered scripts end to end. And `git log --format=%G?` shows every
  authored commit in recent history as `N` (unsigned).

### What `git verify-commit` would look like here

Inserted in `fetch_and_merge_master` between the fetch and the merge:

```sh
git fetch origin
tip=$(git rev-parse origin/master)
if ! git -c gpg.format=ssh \
         -c gpg.ssh.allowedSignersFile=/etc/ssh/git-allowed-signers \
         verify-commit "$tip"; then
  echo "origin/master ($tip) is not signed by an allowed signer; refusing." >&2
  exit 1
fi
git merge --ff-only origin/master
```

Five things determine whether that is worth anything:

1. **Tip-only verification is sufficient — but only because the merge
   is `--ff-only`.** A signature over the tip commits to the whole
   ancestry through the parent hashes, and `--ff-only` guarantees the
   current HEAD is an ancestor. If the merge strategy ever loosens, this
   silently stops being true. Write that dependency down next to the
   check.

2. **The allowed-signers file must come from the running system, never
   from the checkout.** `environment.etc."ssh/git-allowed-signers".text`
   generated from a new `flake.vars.commitSigners` (mirroring
   `publicSshKeys`) puts it at `/etc/ssh/git-allowed-signers`, root-owned
   0444, in the store. The bootstrap is sound: the running system was
   itself built from a verified commit, so an attacker who wanted to add
   their key to `commitSigners` would need a valid signature to land
   that change. Putting the file anywhere under `flakeDir` would make
   the check self-certifying and worthless — and on the laptops it would
   be `lilijoy`-writable.

3. **`ssh-keygen` must be on the unit's `PATH`.** `gpg.format = ssh`
   makes git shell out to `ssh-keygen -Y verify`. `pull-deploy` and
   `push-deploy` list `openssh`; **`auto-update.nix` does not**
   (F-P7-10). Landing (b) without fixing that fails homelab closed on
   the first run, in a way that looks like a signature problem and is
   not.

4. **It fails closed, and on two of four hosts nothing would notice.**
   `exit 1` puts the unit in `failed`, which on homelab and vps
   `health-check` reports to Discord within 15 minutes — subject to
   F-P7-13's stamp-before-send bug. On torrent and thinkpad there is no
   `myHealthAlerts` at all (F-P7-09), so both laptops would simply stop
   updating, silently, indefinitely. **Enable alerting on the laptops
   before landing (b), not after.** This is the concrete answer to the
   "Fix risk" note in F-P0-01.

5. **Two things in the current workflow would break immediately, and
   the second one is the real problem.**
   - `flake-update-test` creates its own commit (`chore: automated
     flake.lock update`, `auto-update.nix:159`) and pushes it to master.
     Under (b) that commit must be signed, so homelab's root would need
     a signing key in `commitSigners` — which makes homelab root a
     fleet-root signer and gives back a good part of what (b) bought.
     The clean resolution is F-P7-07 option (a): stop auto-merging, and
     let the human sign the merge.
   - **The tip of `origin/master` is frequently a GitHub web-flow merge
     commit.** Verified in this repo's history: `676bf31`, `26614c3`,
     `b877074` all have committer `GitHub` and `%G?` = `E` (signature
     present, key not available locally). If PR merges through the
     GitHub UI continue, `commitSigners` must include GitHub's
     `web-flow` key — at which point anyone who can merge a PR on
     GitHub produces a valid signature, and the control degrades to
     "GitHub account security", which is exactly what F-P0-01 is
     worried about. **(b) only delivers its stated benefit ("meaningfully
     raises the cost of losing a laptop") if merges are made locally and
     signed with a key GitHub never holds** — ideally the FIDO2 YubiKey
     already in `publicSshKeys`, since a hardware-backed
     `sk-ssh-ed25519` signing key is the one credential a laptop
     compromise does not yield.

     On a **public** repo this second point sharpens rather than
     softens. Anyone can open a PR; if `web-flow` is an allowed signer,
     then whatever merges a PR on GitHub — a maintainer, a
     misconfigured auto-merge, a compromised GitHub session — mints a
     signature the fleet accepts as root. Local signing with the
     YubiKey is not a nicety here, it is the difference between (b)
     being a real control and being a restatement of "we trust GitHub".

**Summary judgement on the mechanism.** Option (b) is implementable in
about fifteen lines and fails closed correctly. Its value is contingent
on three prerequisites that are not currently in place: alerting on the
laptops (F-P7-09), `openssh` on homelab's auto-update `PATH`
(F-P7-10), and a merge workflow that signs locally rather than relying
on GitHub-web-signed merge commits. Landing (b) without the third would
produce a check that looks strong and enforces almost nothing.

With those three in place, (b) is worth doing, and the public-repo
correction strengthens that conclusion: it is the only control on this
path that lives in code this repo owns, so it survives a
branch-protection rule being absent, bypassed by an admin push, or
changed without anyone noticing — none of which the config can see
(F-P7-17). If the user is unwilling to change the merge workflow, then
option (a) — accept and document — is the honest choice rather than
shipping a check that certifies GitHub's key, and F-P7-07's option (a)
(stop auto-merging lock updates) buys more real risk reduction for less
ceremony.

Independently of that decision, **F-P7-01 must be fixed regardless.**
Signature verification on the fetch does nothing about a `lilijoy` who
commits locally, edits `.git/config`, or wins a two-second race — none
of those go anywhere near `origin`.
