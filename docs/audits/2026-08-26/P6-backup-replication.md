# P6 — backups, snapshots and replication

Part 6 of the 2026-08-26 fleet-wide security audit. Scope: `zrepl`,
`zfs-space-guard`, the NFS client mounts, and the two VM tests that
cover them — plus, by reference, homelab's restic→Backblaze job and the
three hosts' `myZrepl` call sites.

Severity, adversary ids and confidence labels follow
[`00-threat-model.md`](00-threat-model.md) §5–§6. Finding schema follows
[`P0-findings.md`](P0-findings.md).

**Rated under §4.7: this repository is public.** No control in this part
is discounted on discoverability grounds. The replication topology, the
dataset layout, the retention grids, the forced-command identity scheme,
the exact zrepl version (0.7.0), the bucket name and schedule of the
offsite job, and every line of `zrepl.nix` are published — so an attacker
studies the identity pin against zrepl's own source offline, at leisure,
with no rate limit and nothing to detect. Most consequentially for this
part, `secrets/secrets.yaml` is public ciphertext in all 72 revisions,
and it holds all three of this subsystem's secrets (F-P6-01).

This subsystem protects threat-model asset #1 and runs as root on every
host that has data worth keeping. §3 below answers the question the
whole subsystem exists to answer, and the answer is **no**.

---

## 1. Scope and method

### Files read in full

- `modules/nixos/zrepl.nix` (all 1094 lines)
- `modules/nixos/zfs-space-guard.nix`
- `modules/nixos/nfs-homelab-mounts.nix`
- `tests/zrepl-replication.nix`
- `tests/zfs-space-guard.nix`
- `docs/backups.md`, `docs/procedures/backup-restore.md`,
  `docs/hardening.md`
- By reference: `hosts/homelab/configuration.nix:80-270` (restic block,
  `boot.zfs.extraPools`, knownHosts, `myZrepl`),
  `hosts/homelab/disko.nix:55-175`, `hosts/torrent/configuration.nix:60-120`,
  `hosts/thinkpad/configuration.nix:90-145`, `modules/services/nfs.nix`,
  `modules/nixos/health-alerts.nix:57-100,167-192`,
  `modules/flake/hosts.nix`, `modules/flake/vars.nix`, `.sops.yaml`

### Pinned artefacts located and read

| Artefact | Store path | How located |
|---|---|---|
| nixpkgs (homelab, stable) | `/nix/store/xk3y420fsdc1hm9il55vyz4b0gxsk6dg-…-source` | `nix eval .#nixosConfigurations.homelab.pkgs.path` |
| zrepl package | `/nix/store/a8fcpgwsmcr0gag7lf61r9r7rc51cj0c-zrepl-0.7.0` | `nix eval …config.services.zrepl.package` |
| **zrepl 0.7.0 source** | `/nix/store/g51c0xy3sjd0mk27m8czwy8s0wlillm1-source` | `nix build …package.src` |
| go-netssh (vendored dep) | `/nix/store/xznh8y9jr8mi45i3pzrv61w0zjqdfx7z-zrepl-0.7.0-go-modules` | `nix build …package.goModules` |
| OpenSSH 10.4p1 man pages | `/nix/store/8a3sasxrpl5892sj9f5qxp8qxqd9vvwq-openssh-10.4p1-man` | `programs.ssh.package.version` on torrent, then store lookup |
| OpenZFS 2.4.3 man pages | `/nix/store/5lnhjgj5cgfgvhs023g7j46a36jbgn44-zfs-user-2.4.3-man` | store lookup; matches the `zfs-user-2.4.3` on both units' `PATH` |

Both nixpkgs pins (stable for homelab, unstable for the laptops) build
zrepl 0.7.0 from the **identical** `src` store path, so a single source
read covers all three hosts.

Effective merged values were read with `nix eval --json` for
`config.services.zrepl.settings`,
`config.users.users.root.openssh.authorizedKeys.keys`,
`config.systemd.units."zrepl.service".text` and
`config.systemd.units."zfs-emergency-prune.service".text` on homelab,
torrent and thinkpad. The rendered forced-command line on both source
hosts is exactly:

```
command="/nix/store/wy1v…-zrepl-0.7.0/bin/zrepl --config /etc/zrepl/zrepl.yml stdinserver homelab",restrict ssh-ed25519 AAAA…Uzgi homelab-zrepl-pull
```

and it is the **only** entry in root's declarative `authorized_keys` on
either laptop.

### Claims verified against pinned source

| Claim under test | Verdict | Evidence |
|---|---|---|
| `restrict` disables pty, port/agent/X11 forwarding, `~/.ssh/rc`, and is forward-compatible | **true** | `sshd.8` (10.4p1), `.It Cm restrict` |
| `command=` overrides the client's command, incl. subsystem requests | **true** | `sshd.8`, `.It Cm command` |
| a client cannot claim a different zrepl identity | **true** | `internal/client/stdinserver.go` takes the identity from `args[0]` only (never stdin, never `SSH_ORIGINAL_COMMAND`); the daemon derives the identity from *which unix socket* the connection arrived on — `transport.NewAuthConn(c, l.clientIdentity)`, `internal/transport/ssh/serve_stdinserver.go` |
| stdinserver socket has no chmod applied | **true** | `go-netssh/serve.go:234` `Listen()` = bare `net.Listen("unix", …)`; `nethelpers.PreparePrivateSockpath` only *asserts* the directory is not world-accessible (`p&0007 != 0`), it does not chmod anything |
| the runtime dir is 0700 | **true** | zrepl's own unit, `$out/lib/systemd/system/zrepl.service`: `RuntimeDirectory=zrepl zrepl/stdinserver` + `RuntimeDirectoryMode=0700` |
| the zrepl **daemon** must be root | **true** | `zfs-allow.8` (2.4.3): "Delegations are supported under Linux with the exception of `mount`…"; and `destroy`, `snapshot`, `receive`, `rollback` all "Must also have the `mount` ability". `zfs allow` therefore cannot produce a working non-root zrepl on Linux |
| the **SSH user** must be root | **false as stated** — see F-P6-08 |
| a receiving endpoint exposes `DestroySnapshots` | **true** | `internal/endpoint/endpoint.go:1058` |
| a *sending* endpoint also exposes `DestroySnapshots` | **true, and undocumented here** | `internal/endpoint/endpoint.go:417`; bounded only by `filterCheckFS` — see F-P6-04 |
| a `source` job has no pruning/keep rules of its own | **true** | `config.SourceJob` (`internal/config/config.go:208-213`) has no `Pruning` field |
| zrepl only releases holds it owns | **true** | `stepHoldTagRE = ^zrepl_STEP_J_(.+)`; a foreign `zfs hold` tag is invisible to zrepl — this is the basis of the F-P6-04 mitigation |
| whether properties travel in a send is the **sender's** choice alone | **true** | `Sender.sendMakeArgs` sets `Properties: s.config.SendProperties` from the *source host's own* config (`endpoint.go:173-202`) |
| zrepl's receive passes no `-x`/`-o`/`-u` unless configured | **true** | `zfs.RecvOptions.buildRecvFlags()` (`internal/zfs/zfs.go:1186-1205`) emits `-x`/`-o` only from config; `ZFSRecv` builds `["recv"] + flags + target` — never `-u` |
| filesystem filters without a trailing `<` are exact-match | **true** | `filters/fsmapfilter.go:45-54` |
| dataset names cannot path-traverse | **true** | ZFS dataset paths are not resolved like filesystem paths, and `ComponentNamecheck` rejects `.`/`..` |
| `AllowTcpForwarding` defaults to `no` (claimed in `docs/hardening.md`) | **false** | `sshd_config.5` (10.4p1): "`yes` (the default)" — see F-P6-10 |

### What I could not verify

- **The Backblaze bucket's server-side state.** Whether the B2
  application key in `homelab_backblaze_rclone_config` is scoped, and
  whether Object Lock is enabled on `restic21029709384`, is console
  state, not repo state. I reason from what the job *does* (below) and
  mark the conclusion accordingly.
- **The end-to-end property-injection escalation in F-P6-03.** Every
  config fact is CONFIRMED from the pinned sources; whether an
  *incremental* `zfs send -p` stream actually rewrites `mountpoint` on
  an existing received dataset is not stated in `zfs-receive.8` and I
  did not run it (static audit, no VM tests). Rated PLAUSIBLE.
- **Live state**: no host was contacted, no `zfs`/`zrepl` command was
  run anywhere, no VM test was executed, no secret was decrypted.
- **Whether `@blank` currently exists on torrent.** `TODO.md`'s
  "migrate torrent and thinkpad to impermanence" item is still open, so
  torrent may have no `@blank` at all; `docs/backups.md` states thinkpad
  has one on both served datasets.

---

## 2. Findings

### F-P6-01 — every host's key decrypts homelab's zrepl pull key *and* the Backblaze credentials

- **File:** `.sops.yaml:14-24`, `modules/profiles/default.nix:156`,
  `secrets/secrets.yaml` (recipient block, lines 34-97),
  `hosts/homelab/configuration.nix:87-88,222,237,242`
- **Severity:** CRITICAL
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A2 — root on `vps`, the only internet-facing host,
  reaches the offsite backup credentials without ever touching homelab.
  Also A7→A5 (root on either laptop), and A6. **And A8**, because of
  §4.7: the ciphertext is public, so a stolen thinkpad (no FDE today,
  §8.7) is not "a laptop with some secrets on it" — it is one of seven
  keys to a file anyone already has a copy of, decrypted offline at
  leisure.
- **Rule:** new-rule candidate — `docs/hardening.md` says nothing about
  per-host secret scoping.
- **Finding:** there is one `creation_rules` entry, matching
  `secrets/*.yaml`, with all seven age recipients: thinkpad (×3),
  torrent (×2), homelab, **and vps**. `modules/profiles/default.nix:156`
  sets `sops.defaultSopsFile = secrets/secrets.yaml` for every host, so
  the whole encrypted file is in every host's nix store and every host
  holds a key that decrypts all of it. Three secrets in this part's
  scope are affected:
  - `homelab_zrepl_key` — the private half of the pull key. Its holder
    gets `Sender.DestroySnapshots` and `Sender.Send` against
    `zroot/local/{home,root}` on **both** laptops (see F-P6-04): total
    read of both machines' home and root datasets, and destruction of
    all their snapshot history including `@blank`.
  - `homelab_backblaze_restic_password` and
    `homelab_backblaze_rclone_config` — the *only* offsite copy. The job
    itself proves the credential's power: `restic forget --prune`
    requires delete, and `ExecStartPre` runs `rclone backend lifecycle …
    -o daysFromHidingToDeleting=1`, which requires B2 `writeBuckets`,
    i.e. the ability to change (or remove) the bucket's own retention
    settings.

  So the blast radius of a root compromise on *any* fleet host includes
  the offsite backup, and the isolation the offsite copy is supposed to
  provide is undone by the key distribution. vps is the sharpest case:
  it holds no backup data, participates in no replication, and needs
  none of these three secrets, but can decrypt all of them.

  **§4.7 sharpens this in a way that is specific to backups.** The
  ciphertext is not merely on seven machines — it is on GitHub, in 72
  revisions, permanently, for anyone. There is no network boundary, no
  rate limit and no detection in front of an offline attack on it; the
  seven age keys are the entire control. The threat model's
  rotation-is-not-retroactive point applies with one qualification worth
  stating precisely: these three secrets *are* revocable at their far
  end — a new zrepl keypair invalidates the old public key in
  `authorized_keys`, and a B2 application key can be deleted at
  Backblaze — so prompt rotation does bound the damage in a way it does
  not for, say, a leaked archive of personal data. But nothing here has
  been rotated, so the *current* offsite backup credentials and the
  *current* pull key are protected, right now, by seven age keys, one of
  which sits unencrypted on a laptop with no full-disk encryption that
  leaves the house. That is the real shape of this finding.
- **Proposed fix:** split `secrets/secrets.yaml` by consumer. A second
  `creation_rules` entry — e.g. `secrets/homelab.yaml` encrypted only to
  `homelab3` — for `homelab_zrepl_key`,
  `homelab_backblaze_restic_password`, `homelab_backblaze_rclone_config`
  and `homelab_vps_deploy_key`. Per `docs/procedures/secrets.md` the
  re-encryption is a manual, user-performed step; agents must not do it.
  Separately, scope the B2 application key to the one bucket, and
  consider a *second* key with append-only capability for the backup job
  with the delete-capable key held offline (see F-P6-02).
  Because of §4.7, narrowing the recipient set is only half the job —
  the old ciphertext stays public forever. The three secrets named here
  should therefore also be **rotated at their far end** once the split
  lands: a new zrepl keypair (which invalidates the old public key in
  both laptops' `authorized_keys`), and a fresh B2 application key with
  the old one deleted at Backblaze. Narrowing protects future values;
  rotation is what retires the ones already published under seven keys.
- **Fix risk:** re-keying is the classic way to lock yourself out of
  your own secrets. Do it one file at a time, keep the old file until
  each host has demonstrably decrypted the new one, and remember that a
  host cannot decrypt a secret it is no longer a recipient of — a
  mistake here is a boot-time service failure on the affected host, not
  a build error.
- **Owner:** P7 owns secrets plumbing generally; this finding is the
  backup-specific instance and should be consolidated with whatever P7
  finds.

### F-P6-02 — no copy of the fleet's data is out of reach of a single root, and the offsite window is ~2 runs

- **File:** `hosts/homelab/configuration.nix:96-170,247-256`,
  `hosts/homelab/disko.nix:128-175`
- **Severity:** HIGH
- **Confidence:** CONFIRMED for the config; PLAUSIBLE for the absence of
  B2 Object Lock (console state, not in the repo)
- **Axis:** hardening
- **Reachability:** A9 — ransomware or a destructive actor with root on
  homelab. Reached from A2 (homelab's public IPv6, §2.1), A3 (the DNAT'd
  game servers), A5, or A6. Per §4.7, A9 does not have to *discover* any
  of this: the pool names, the dataset tree, the retention grids, the
  repository string `rclone:backblazeDaily:restic21029709384`, the
  `--keep-daily 2` window, the `daysFromHidingToDeleting=1` lifecycle
  call and the Fri 03:00 schedule are all published. A destructive
  payload can be written against this exact layout before it ever
  lands, and can be timed against the offsite job's own calendar.
- **Rule:** new-rule candidate — `docs/hardening.md` has no rule about
  backup immutability or air gaps.
- **Finding:** the three "independent paths" in `docs/backups.md` are
  independent of each other's *failure modes*, not of each other's
  *authority*. All three terminate at root on homelab:
  1. live data — `zdata`, on homelab;
  2. `zbackup` — different disks, same machine, same root, imported and
     writable at all times (`boot.zfs.extraPools`), no
     `readonly=on`, no `zfs allow` delegation anywhere in the repo,
     no dataset-level protection of any kind;
  3. Backblaze — credentials decrypted to `/run/secrets` on homelab, and
     per F-P6-01 decryptable on every other host too.

  The offsite copy's depth is also thin. `pruneOpts = --keep-daily 2` on
  a weekly timer is two runs, i.e. ~14 days of history — and the comment
  at `:141` acknowledges this. `b2-hard-delete = "false"` would normally
  leave deleted files as *hidden* B2 versions, a genuine recovery net,
  but `ExecStartPre` explicitly sets `daysFromHidingToDeleting=1`, which
  purges hidden versions after one day. That is a deliberate cost
  decision, and it removes the one immutability-ish property the design
  had. Net: a silent corruption or an encrypt-in-place event that is not
  noticed within ~2 weeks has no clean copy left offsite, and one that
  *is* noticed still has no copy an attacker with root on homelab
  couldn't have destroyed first.

  `zbackup`'s 13-month `archive` grid is the real depth here — which is
  exactly why F-P6-01 and F-P6-07 matter: it is depth with no
  independence and no alarm.
- **Proposed fix:** decision required. Options, roughly in cost order:
  (a) enable B2 Object Lock / a bucket lifecycle floor and give the
  backup job an **append-only** application key, keeping the
  delete-capable key offline for manual prunes — this alone converts the
  offsite copy into a real last line of defence and is the highest-value
  single change in this report; (b) raise `--keep-daily` / add
  `--keep-weekly`/`--keep-monthly` so the offsite window exceeds a
  realistic detection time; (c) drop the `daysFromHidingToDeleting=1`
  lifecycle call, or raise it to something like 30, accepting the
  storage cost; (d) a periodic `zfs send` to detachable media as a true
  air gap. (a)+(b) together are probably the right answer.
- **Fix risk:** an append-only key makes `restic forget --prune` fail —
  the job must then either stop pruning (unbounded growth) or prune
  out-of-band with the privileged key, and the failure has to be
  something `myHealthAlerts` actually pages on rather than a silent
  weekly error. Object Lock also makes storage cost monotonic until the
  lock expires; size it before enabling.
- **Owner:** P3 owns the restic block; this is the cross-cutting
  statement of why it matters. User decision on the trade.

### F-P6-03 — a compromised source host can steer homelab's `zfs recv` through stream properties

- **File:** `modules/nixos/zrepl.nix:201-203` (`mkRecv`),
  `modules/nixos/zrepl.nix:9-21` and
  `hosts/homelab/configuration.nix:186-192` (the claim this refutes)
- **Severity:** HIGH
- **Confidence:** PLAUSIBLE — every config fact below is CONFIRMED
  against pinned source; the end-to-end escalation is inferred and needs
  a VM test to confirm
- **Axis:** hardening
- **Reachability:** A7 or A8 → root on thinkpad (the roaming laptop,
  and per F-P0-03 the most likely place `lilijoy` becomes root) → root
  on homelab → §4.2 → vps, §4.1 → the fleet. Fully discoverable per
  §4.7: `mkRecv`'s single line is public, so that homelab receives with
  no `-x`, no `-o` and no `-u` is a published fact, not something an
  attacker has to probe for.
- **Rule:** new-rule candidate.
- **Finding:** the module's headline security argument — "a compromised
  source host has no RPC handle on this machine at all" — is true about
  *RPC* and incomplete about *data*. Under pull, homelab still feeds an
  entirely source-controlled `zfs send` stream into a root `zfs recv`,
  and three facts combine badly:
  1. **The sender decides whether properties travel.** `Properties:
     s.config.SendProperties` in `Sender.sendMakeArgs`
     (`endpoint.go:190`) reads the *source host's own* config. A source
     host whose root is compromised sets `send.properties: true` in its
     own `/etc/zrepl/zrepl.yml`; the puller has no say and no way to
     detect it.
  2. **The receiver applies whatever arrives.** `mkRecv` sets only
     `placeholder.encryption`. `recv.properties.inherit` and
     `recv.properties.override` are never set, so
     `buildRecvFlags()` emits no `-x` and no `-o`
     (`internal/zfs/zfs.go:1186-1205`).
  3. **Nothing stops a mount.** `ZFSRecv` never passes `-u`
     (`zfs.go:1262-1264`), and `zfs-receive.8` documents `-u` as the
     flag whose absence means the received filesystem *is* mounted. The
     `zbackup` containers get `mountpoint=none` by *inheritance* from
     the pool root (`disko.nix:130-136`), and in ZFS a **received**
     property outranks an inherited one.

  So a hostile `mountpoint=/etc` (or `/root/.ssh`) plus `canmount=on`
  arriving in the stream plausibly lands as a root-owned mount over a
  live path on the backup server. `sharenfs`/`sharesmb` are the same
  shape with a different payoff. `docs/backups.md` already flags the
  weaker version of this ("a container that has drifted to a real
  mountpoint will silently give every dataset received under it a
  mountpoint too") without noticing that the sender can force it.
- **Proposed fix:** cheap and low-risk regardless of whether the full
  escalation reproduces — extend `mkRecv` to pin the dangerous
  properties on the receiving side:
  ```
  properties.override = { mountpoint = "none"; canmount = "off"; };
  properties.inherit  = [ "sharenfs" "sharesmb" "exec" "setuid" "devices" ];
  ```
  (`-o` and `-x` for the same property are mutually exclusive, so pick
  one per property.) Then correct the two comments so they say "no RPC
  handle" rather than implying no attack surface at all.
- **Fix risk:** `-o mountpoint=none` sets a *local* property on received
  datasets, which changes what a future restore inherits, and `-o` on a
  resumed receive has historically been fussy. This must be exercised in
  `tests/zrepl-replication.nix` — including a resumed receive — before
  it goes near homelab. The test should also add the hostile case: a
  source with `send.properties: true` and a poisoned `mountpoint`,
  asserting the receiver ignores it.
- **Owner:** P6 (this part) for the module change; wants a VM test
  before deploy.

### F-P6-04 — the pull direction hands homelab destroy-and-read authority over both laptops, with no sender-side veto

- **File:** `modules/nixos/zrepl.nix:9-21`,
  `hosts/homelab/configuration.nix:186-192,230-245`,
  `hosts/torrent/configuration.nix:70-92`,
  `hosts/thinkpad/configuration.nix:91-118`
- **Severity:** HIGH
- **Confidence:** CONFIRMED
- **Axis:** hardening / documentation
- **Reachability:** A9 via homelab; also anybody who decrypts
  `homelab_zrepl_key` (F-P6-01), which today is root on any fleet host —
  and, per §4.7, anybody who ever obtains one of the seven age keys,
  since the ciphertext is already in their possession.
- **Rule:** new-rule candidate; addresses threat model §4.5's explicit
  "the inverse question, which the existing comment does not answer".
- **Finding:** the repo reasons carefully about push-vs-pull in one
  direction and not at all in the other. In the pull direction:
  - `Sender.DestroySnapshots` exists (`endpoint.go:417`) and is what
    `keep_sender` pruning is built on. It calls `filterCheckFS` and then
    `doDestroySnapshots`, which simply runs `zfs destroy` for every
    snapshot the client names. **It evaluates no keep rules.** The
    source's own `protectRegexes`/`^blank$` and its `snap` job's ceiling
    are local pruning policy only; they do not gate an incoming destroy.
  - `config.SourceJob` has no `Pruning` field at all
    (`internal/config/config.go:208-213`), so zrepl 0.7.0 offers a source
    host *no* mechanism to veto what its puller asks it to destroy.
  - `Sender.Send` gives the same client a full read of every served
    dataset — `zroot/local/home` and `zroot/local/root` on both laptops,
    i.e. essentially everything personal on those machines.

  Concretely: a compromised homelab can, without any vulnerability and
  without ever getting a shell, read both laptops entirely and destroy
  every snapshot on their home and root datasets — **including
  `@blank`**, which `zrepl.nix:527-540` correctly describes as
  unregenerable without reinstalling. The same outcome arrives from a
  plain configuration mistake: drop `protectRegexes` on homelab and the
  next `keep_sender` prune destroys `@blank` on two other hosts.

  This does *not* extend to the live filesystems — the source endpoint
  destroys snapshots only, and `restrict` + `command=` deny a shell — so
  the pull choice remains the right one. The finding is that the
  asymmetry is real, one-sided, and written down nowhere.
- **Proposed fix:** two parts.
  1. **A sender-side backstop that zrepl cannot override.** zrepl only
     recognises and releases holds tagged `zrepl_STEP_J_*` /
     `zrepl_last_received_J_*` (`endpoint_zfs_abstraction_step_hold.go:13`),
     so a foreign `zfs hold` is invisible to it and cannot be released
     over any RPC, while `doDestroySnapshots` tolerates the resulting
     failure. A small oneshot unit on torrent/thinkpad that ensures
     `zfs hold protect <dataset>@blank` exists gives `@blank` genuine
     local immutability against the puller, declaratively, at
     essentially zero cost. This is the highest-value fix in this
     finding.
  2. **Document the direction.** Add the inverse paragraph to
     `docs/backups.md`'s "Why pull, not push" and to the module header:
     pull moves destroy authority *onto* homelab, which means homelab is
     trusted with the snapshot history and full contents of both
     laptops. Same shape as F-P0-02's homelab→vps conclusion.
- **Fix risk:** a `zfs hold` on a snapshot makes `zfs destroy` of it
  fail forever until released — that is the point, but it also means
  `zfs-emergency-prune` and any future retention change will log
  failures on it. Hold only `@blank`, never a `zrepl_`-prefixed
  snapshot, or you will pin the pool.

### F-P6-05 — NFS client mounts carry no `nosuid`, `nodev` or `noexec`

- **File:** `modules/nixos/nfs-homelab-mounts.nix:24-46`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A9/A2 with root on homelab, chaining to root on
  torrent and thinkpad — a boundary the threat model does not currently
  model (§4 has homelab→vps but not homelab→laptops). Then A7 completes
  the chain locally.
- **Rule:** new-rule candidate.
- **Finding:** `mountOpts` covers availability behaviour thoroughly
  (`noauto`, `x-systemd.automount`, `soft`, `timeo`, `retry=0`) and
  security behaviour not at all. Both laptops automount
  `homelab:/storage` and `homelab:/storage-bulk` with `dev` and `suid`
  in force. The server's `root_squash` (`modules/services/nfs.nix:12-13`)
  correctly stops a compromised *client* from writing root-owned files;
  it does nothing about files the *server* already owns. So root on
  homelab can place a setuid-root binary, or a `mknod`'d device node
  with permissive modes, under `/storage`, and on the client that node
  is a direct route to the client's raw disks for any local user. The
  `multimedia` gid mapping at `:8-15` means `lilijoy` on both laptops has
  group read/write on the whole share, so nothing else stands in the way.
  NFS `sec=sys` also means the client extends full trust to homelab's
  claims about ownership — noted in the module comment, correctly, but
  without drawing this conclusion.
- **Proposed fix:** add `"nosuid"` and `"nodev"` to `mountOpts`.
  `noexec` is the aggressive option and probably wrong here — this is a
  media/file share and someone will eventually want to run something off
  it — so add the first two and record `noexec` as considered and
  declined, in the same comment.
- **Fix risk:** essentially none for `nodev`. `nosuid` breaks any setuid
  binary stored on the share, which nothing in this repo puts there.
  Verify the automount still mounts after the change (`systemctl status
  home-lilijoy-storage.automount`) since option typos surface only at
  first access, not at build.

### F-P6-06 — `zfs-emergency-prune.service` is the only custom service in `modules/nixos/` with no sandboxing

- **File:** `modules/nixos/zfs-space-guard.nix:71-89`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** n/a for direct exploitation — the unit is root-only
  to start. Rated on the rubric's "violations of an existing
  `docs/hardening.md` rule with no currently demonstrable exploit".
- **Rule:** **violates `docs/hardening.md` "Custom `systemd.services`
  sandboxing"**.
- **Finding:** the rendered unit on torrent has `Type=oneshot`, a
  `PATH`, an `ExecStart`, and nothing else — no `NoNewPrivileges`, no
  `ProtectSystem`, no `ProtectHome`, no `RestrictNamespaces`, no
  `PrivateTmp`. Every other custom module in `modules/nixos/` applies
  the stack (`health-alerts.nix:252-260`, `iso-autobuild.nix:115-123` and
  `:148-156`, `auto-update.nix:184-191`), and the deliberately-partial
  ones (`pull-deploy.nix:135`, `push-deploy.nix:148-150`) say in a
  comment why. This one is a plain omission, and a textbook §7.6: the
  hardening pass reached the modules that prompted it and not this one.
  `health-alerts.nix` is the direct precedent that the full stack is
  compatible with running `zfs`/`zpool` commands — it does exactly that
  under `ProtectSystem = "strict"`.
- **Proposed fix:** mirror `health-alerts.nix:252-260`:
  `NoNewPrivileges`, `ProtectSystem = "strict"`, `ProtectHome`,
  `ProtectKernelModules`, `ProtectKernelTunables`, `ProtectKernelLogs`,
  `ProtectControlGroups`, `RestrictNamespaces`, `PrivateTmp`. Do **not**
  add `PrivateDevices` — the unit needs `/dev/zfs`.
- **Fix risk:** low, but the failure mode is "the break-glass service
  doesn't work when you need it at 2am", which is the worst time to find
  out. `tests/zfs-space-guard.nix` already starts the unit for real in a
  VM, so extend that test rather than trusting the build.

### F-P6-07 — nothing detects backup *destruction*, and the detector runs on the host it would have to accuse

- **File:** `modules/nixos/health-alerts.nix:57-82,167-192`,
  `hosts/homelab/configuration.nix:320-349`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A9 — the whole point of asset #1's threat is an
  actor who destroys quietly.
- **Rule:** new-rule candidate.
- **Finding:** `backupStaleness` measures exactly two things per
  dataset: does it exist, and how old is its *newest* snapshot. Wholesale
  dataset destruction does alert ("no snapshots found"). But destroying
  ~13 months of `archive` history while leaving the most recent snapshot
  in place is completely invisible — no snapshot-count check, no
  used-space check, no delta check. That is precisely the shape of a
  competent destructive actor: keep the backup looking fresh.

  Compounding it, the detector and the asset share a fate. `health-check`
  runs on homelab, reads `homelab_discord_webhook` from homelab, and
  alerts about `zbackup` which is on homelab. Root on homelab silences
  the alarm in the same motion that destroys the data. `vps` runs its own
  `myHealthAlerts` but watches nothing about the backups.
- **Proposed fix:** two cheap additions. (1) A snapshot-count or
  `usedbysnapshots` floor per `zbackup` dataset — a run that sees the
  count drop by more than some fraction since the last run alerts. (2)
  Give vps (or any host that is not homelab) a check that the backup is
  advancing, so at least one detector survives homelab. A one-line
  marker file that homelab writes and vps checks over the tailnet would
  do; the existing `staleMarkerFiles` mechanism is most of it already.
- **Fix risk:** a count-delta check is a false-positive generator during
  legitimate retention transitions and after a deliberate prune. Give it
  a generous threshold and the same `cooldownHours` treatment the
  existing checks get, or it gets muted and becomes worthless.
- **Owner:** P6 for the requirement; whoever owns `health-alerts.nix`
  for the implementation.

### F-P6-08 — the root SSH user is avoidable, and `docs/hardening.md` states it as a hard requirement

- **File:** `docs/hardening.md` ("Dedicated service users", the zrepl
  paragraph), `docs/backups.md` ("`ssh+stdinserver` requires the SSH user
  to be root"), `modules/nixos/zrepl.nix:399-419`
- **Severity:** LOW
- **Confidence:** CONFIRMED for the mechanism; the fix is untested
- **Axis:** documentation / hardening
- **Reachability:** none directly — with `PermitRootLogin
  forced-commands-only` and exactly one `restrict`ed key on each laptop,
  the current arrangement is sound. The cost is that a false constraint
  is recorded as fact and will be reasoned from later.
- **Rule:** §7.5 — documentation asserting a boundary the config does not
  actually require.
- **Finding:** both halves of the standing justification were checked.
  - **The daemon must be root: true.** `zfs-allow.8` (2.4.3):
    delegations "are supported under Linux with the exception of
    `mount`… because the Linux `mount(8)` command restricts
    modifications of the global namespace to the root user", and
    `destroy`, `snapshot`, `receive` and `rollback` each "Must also have
    the `mount` ability". No `zfs allow` can produce a working non-root
    zrepl on Linux. This half is correct and should stay.
  - **The SSH user must be root: not forced.** The stated reasoning is
    accurate as far as it goes — `RuntimeDirectoryMode=0700` in zrepl's
    packaged unit, and `go-netssh`'s `Listen()` is a bare
    `net.Listen("unix", …)` with no chmod, so the socket's own mode
    (0777&~umask, i.e. 0755 under systemd's default `UMask=0022`) is not
    the barrier; the directory is. And `PreparePrivateSockpath` only
    requires the directory to be non-world-accessible (`p&0007 != 0`), so
    **0750 already passes**. The conclusion that follows —
    "`RuntimeDirectoryMode` also exposes the control socket" — holds only
    because both directories are covered by the unit's single
    `RuntimeDirectoryMode`. Move the stdinserver sockets out from under
    `/run/zrepl` (`global.serve.stdinserver.sockdir`, default
    `/var/run/zrepl/stdinserver`, is configurable) into a directory
    created `0750 root:zrepl-ssh` by `systemd.tmpfiles`, and the control
    socket at `/run/zrepl/control` stays 0700 root-only while a
    dedicated non-root SSH user can proxy. That would let both laptops
    drop root SSH entirely (`PermitRootLogin = "no"`).
- **Proposed fix:** at minimum, correct both docs to say the root SSH
  user is the *current* choice and why (simplicity; the forced command
  is the boundary either way), not a requirement of the transport.
  Optionally implement the dedicated user as described — it is a
  genuine defence-in-depth win on the one host that roams.
- **Fix risk:** the implementation is more delicate than it looks. The
  daemon must be started *after* tmpfiles creates the directory, the
  proxy process runs as the new user but must still reach a
  root-owned socket, and getting it wrong is a silent backup outage
  rather than a build failure. Exercise it in
  `tests/zrepl-replication.nix` first. The doc fix carries no risk and
  should land regardless.

### F-P6-09 — `zrepl.service` runs as root with no systemd sandboxing at all

- **File:** `modules/nixos/zrepl.nix:1067-1071`, upstream
  `nixos/modules/services/backup/zrepl.nix`, zrepl's packaged unit
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A5/A7 with the pull key, or a compromised peer, as a
  containment gap rather than an entry — zrepl's exposed parsers are Go
  gRPC/protobuf, so this is defence in depth, not a live hole.
- **Rule:** `docs/hardening.md` "Custom `systemd.services` sandboxing" —
  arguably out of scope as written, since zrepl.service comes from
  upstream nixpkgs plus the package's own unit. But this repo *does*
  edit that unit, and the rule's own zrepl paragraph tells you to grant
  "only the specific group memberships/capabilities/`zfs allow`
  delegations actually needed". Rated LOW rather than MEDIUM because of
  that scope ambiguity; a reading that the rule covers repo-modified
  units would make it MEDIUM.
- **Finding:** the rendered override on homelab contains `After`,
  `Wants`, `X-Restart-Triggers`, `Environment`, `Restart=on-failure` and
  nothing else. Combined with the packaged unit, `zrepl.service` is a
  long-running root daemon with the full ambient namespace: no
  `NoNewPrivileges`, no `ProtectHome`, no `ProtectKernelTunables`, no
  `RestrictNamespaces`, no `PrivateTmp`, no `RestrictAddressFamilies`.
  It genuinely needs `/dev/zfs` and root, so the full stack is not
  available — but a useful subset is.
- **Proposed fix:** add `NoNewPrivileges = true`, `ProtectHome = true`,
  `ProtectKernelModules`, `ProtectKernelTunables`, `ProtectKernelLogs`,
  `ProtectControlGroups`, `RestrictNamespaces = true`, `RestrictSUIDSGID
  = true`, `PrivateTmp = true` in the existing
  `systemd.services.zrepl` block. Do **not** add `PrivateDevices`
  (needs `/dev/zfs`) or `ProtectSystem = "strict"` without confirming
  the receive path never mounts anything.
- **Fix risk:** on homelab this daemon is the backup, and a sandboxing
  flag that blocks a `zfs` subprocess fails at *runtime*, not at build.
  `tests/zrepl-replication.nix` exercises a real send/recv and is the
  right gate. Note also that the source-side `zrepl stdinserver` proxy is
  spawned by sshd, not by this unit, so none of this constrains it.
- **Also checked here:** `requires = lib.mkForce [ ]`
  (`zrepl.nix:1068`). It drops upstream's `Requires=local-fs.target` and
  nothing else — the rendered unit has no `Requires=` line at all, and
  no security-relevant dependency (secrets, network, firewall) was ever
  expressed there. sops-nix supplies `/run/secrets/homelab_zrepl_key`
  via activation ordering, not via this unit's `Requires`. The override
  weakens nothing.

### F-P6-10 — the source hosts' sshd misses several `docs/hardening.md` SSH rules, and the doc states one OpenSSH default incorrectly

- **File:** `hosts/torrent/configuration.nix:100-108`,
  `hosts/thinkpad/configuration.nix:122-131`, `docs/hardening.md`
  ("SSH" bullet), `docs/backups.md` ("SSH on the source hosts")
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening / documentation
- **Reachability:** none today — root's only key on either host is the
  `restrict`ed forced command, and `restrict` independently kills
  forwarding, pty and `~/.ssh/rc` for that key. This is a latent gap
  that becomes real the moment a second key or a non-root login exists.
- **Rule:** partially violates `docs/hardening.md` "SSH".
- **Finding:** the rendered `sshd_config` on torrent sets
  `PasswordAuthentication no`, `KbdInteractiveAuthentication no`,
  `PermitRootLogin forced-commands-only`, `X11Forwarding no`. It does
  **not** set `AuthenticationMethods publickey`,
  `AllowAgentForwarding no`, `AllowStreamLocalForwarding no`,
  `PermitTunnel no`, `ClientAliveInterval`/`ClientAliveCountMax`, and it
  ships the sftp subsystem (`allowSFTP` not disabled) on a host whose
  sshd exists solely to carry zrepl. `docs/backups.md` says these hosts
  are "Locked down in both host configs… See `docs/hardening.md`", which
  over-reads what is there (§7.5).

  Separately and more importantly, `docs/hardening.md` asserts
  "`AllowTcpForwarding` defaults to `no` — only flip to `yes` for a
  specific confirmed need." The pinned `sshd_config.5` (OpenSSH 10.4p1)
  says the opposite: "The available options are `yes` (**the default**)".
  So every host in this fleet that relies on that sentence has TCP
  forwarding enabled while believing it is off. On torrent and thinkpad
  it does not matter (one `restrict`ed key); elsewhere it might, which
  makes this P5's and P3's problem too.
- **Proposed fix:** correct the `AllowTcpForwarding` sentence in
  `docs/hardening.md` and set it explicitly to `no` wherever the doc
  implied it already was. On torrent and thinkpad add the missing
  directives via `services.openssh.settings` (never `extraConfig` —
  §7.2) and set `allowSFTP = false`. Soften the `docs/backups.md`
  sentence to list what is actually set.
- **Fix risk:** `allowSFTP = false` breaks any `scp`/`sftp` to these
  hosts; confirm nothing does that first. `ClientAlive*` interacts with
  long-running replication — 60s/5 is the documented baseline and is
  comfortably above zrepl's traffic pattern, but a stricter value would
  cut transfers.
- **Owner:** P5 owns the two laptops' sshd; the doc correction is
  fleet-wide and should be consolidated.

### F-P6-11 — the `tcp` transport is wired, unauthenticated, unencrypted, and one enum value away from fleet-wide

- **File:** `modules/nixos/zrepl.nix:65-68,88-93,476-492,738-746,771-776`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening / needed-used
- **Reachability:** none today — nothing sets it. A5 if it were ever
  enabled, since the tailnet is flat (F-P0-04).
- **Rule:** new-rule candidate.
- **Finding:** `myZrepl.defaultTransport` is a single enum consumed as
  the default by every role's `type`. Setting it to `"tcp"` moves the
  whole fleet onto a transport whose only authentication is a
  client-IP→identity map (`mkServe`'s `clients = lib.mapAttrs (_: c:
  c.address)`), with no cryptography of any kind on the wire — a
  `zfs send` of every home directory in plaintext, authenticated by
  source IP. That may be defensible over WireGuard; it is not
  self-evidently so, and neither the option description
  ("Transport every role defaults to, so a repo-wide change is a
  one-line edit here") nor the `tcp` field descriptions say a word about
  it. `tls` is the safe sibling and is equally undocumented as such.
- **Proposed fix:** either delete the `tcp` transport (see F-P6-13) or
  add a warning to `defaultTransport` and to `serve.listen` stating that
  `tcp` provides neither encryption nor real authentication and must
  only ever be used inside an already-encrypted tunnel — with `tls` named
  as the alternative.
- **Fix risk:** none; documentation, or deletion of unused code.

### F-P6-12 — `zfs-emergency-prune` is an unguarded "destroy all history" primitive

- **File:** `modules/nixos/zfs-space-guard.nix:71-89`,
  `hosts/torrent/configuration.nix:112-119`,
  `hosts/thinkpad/configuration.nix:134-141`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A7 *only after* becoming root-equivalent — which on
  these hosts is one `docker` group membership away (§4.3,
  `PC.nix:313`). Once there, this is a single `systemctl start` that
  destroys every snapshot on `zroot/local/{home,root}`.
- **Rule:** new-rule candidate.
- **Finding:** the module is honest about what it does and the VM test
  covers it well. Three residual sharp edges:
  - It destroys snapshots that have **not** been replicated. The option
    docs say the replication cursor preserves the incremental base, which
    is true, but a laptop that has been offline for a month loses that
    month's recoverable history entirely — and thinkpad is exactly that
    host.
  - On a dataset with no `@blank` it destroys *everything*. The comment
    calls this documented behaviour rather than a bug, and the VM test
    asserts it. Fair — but `TODO.md`'s impermanence migration for torrent
    is still open, so torrent is plausibly in that state right now.
  - There is no `--dry-run`, no confirmation, and no journal record of
    what the pre-state was; recovery from a mistaken invocation depends
    entirely on `zbackup` having a current copy.
- **Proposed fix:** add a dry-run mode (an `Environment=DRY_RUN=1`
  variant, or a second unit) and have the script log the snapshot list
  and count before destroying, so the journal records what was lost.
  Consider refusing to run on a dataset with no `@blank` unless an
  explicit override is set — that turns the documented-but-surprising
  fallback into a deliberate choice.
- **Fix risk:** none material; extend `tests/zfs-space-guard.nix`, which
  already covers the no-`@blank` case and would catch a regression in it.

### F-P6-13 — roughly 40% of a 1094-line root-running module has no consumer

- **File:** `modules/nixos/zrepl.nix` — `push` (`:840-874`), `sink`
  (`:878-946`), the `tls` transport
  (`:69-75,94-100,430-455,778-792,900-925`), the `tcp` transport
  (`:65-68,88-93`), `preserveLegacySnapshots`/`legacySnapshotPrefix`
  (`:546-565`)
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** none — enabling any of it requires a commit, which
  is already fleet root (F-P0-01). This is §7.4 accounting, not an
  exploit.
- **Rule:** threat model §7.4.
- **Finding:** the evaluated `services.zrepl.settings` on all three
  hosts uses exactly four job types (`snap`, `source`, `pull`, plus the
  `local` source/pull pair) and one transport (`ssh+stdinserver`, plus
  `local`). Unused:
  - **`push.targets`** and **`sink`** — `docs/backups.md`'s own table
    says "nobody currently" for both. `sink` is the more notable one: it
    is the *only* code path that would write a forced-command key
    accepting **incoming** replication, i.e. the exact topology
    `zrepl.nix:9-21` argues against at length. Live code implementing the
    rejected design.
  - **`tls`** — six options (`ca`/`cert`/`key`/`serverCn`/`listen`/
    `client_cns`) across four submodules, never set.
  - **`tcp`** — see F-P6-11.
  - **`preserveLegacySnapshots` / `legacySnapshotPrefix`** — defaults to
    `true`, but all three hosts set it `false`
    (`homelab:262`, `torrent:84`, `thinkpad:109`) and the evaluated keep
    rules on every host contain no `^autosnap_` entry. The sanoid cutover
    is complete; the machinery is dead and its `true` default is now a
    trap for a future fourth host.
  - **`sshOptions`** — used only by the VM test, never in production.
- **Proposed fix:** decision required, and reasonable people differ. My
  recommendation: delete `sink`, `push`, `tcp` and `tls` (git remembers
  them, and `docs/backups.md`'s role table can note they were removed as
  unused); flip `preserveLegacySnapshots`'s default to `false` and delete
  `legacySnapshotPrefix`. That takes the module to roughly 650 lines of
  code that three hosts actually execute. The counter-argument — that
  `push` exists for a documented future case (a laptop a puller would
  miss) — is real but is answered by the fact that thinkpad, the host
  that case was written for, is explicitly kept on pull
  (`thinkpad:101-106`).
- **Fix risk:** none at runtime, since nothing evaluates these paths.
  The risk is purely "we delete it and want it back in six months",
  which git handles. Removing `sink`/`push` does change `myZrepl`'s
  option surface, so re-run the per-host builds.

### F-P6-14 — the VM tests cover the happy path and the forced command, but not the properties that matter most

- **File:** `tests/zrepl-replication.nix:98-107,146-172`,
  `tests/zfs-space-guard.nix`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** documentation / hardening
- **Reachability:** n/a — a test gap, not an exposure.
- **Rule:** n/a.
- **Finding:** `tests/zrepl-replication.nix` is better than most: it
  asserts the forced command is present with the right identity, that
  `restrict` is present, and that the key cannot get a shell (bounded
  with `timeout` and `-n`, which is the right way to test a command that
  blocks on stdin). What it does not cover:
  - **The identity pin is never negatively tested.** There is one
    identity, so "cannot claim to be a different host" — the load-bearing
    claim at `zrepl.nix:1073-1076` and threat model §4.5 — is asserted by
    the comment and not by the test. A second `clients.<other>` entry
    plus an attempt to reach it with the first key would close this. (The
    pin does hold; I verified it in the source. The point is that nothing
    would catch a regression.)
  - **The `local` transport is not tested at all** — and it is the path
    homelab uses for its *own* data, i.e. the majority of the fleet's
    bytes. `local-source`/`local-pull`, the `rootFs`+`clientIdentity`
    composition at `zrepl.nix:882-886`, and the `1x15m(keep=all)` leading
    bucket that `docs/backups.md` says was tuned specifically on
    `local-pull` are all uncovered.
  - **No hostile-source case** — nothing feeds the receiver a stream from
    a sender configured against it (F-P6-03).
  - **A stale comment.** `tests/zrepl-replication.nix:100-102` says
    "Production pins nothing either -- the forced command on the far side
    is the real boundary." Production *does* pin, deliberately and with a
    long comment explaining why:
    `hosts/homelab/configuration.nix:206-224`,
    `programs.ssh.knownHosts.{torrent,thinkpad}`. A future reader
    trusting the test comment could remove that pinning — which, given
    F-P6-03, is the difference between a hostile stream needing root on a
    source host and needing only a tailnet MITM position.
- **Proposed fix:** correct the comment; add a second client identity and
  a negative assertion; add a third VM node (or a second `myZrepl` block)
  exercising the `local` source/pull pair; add the hostile-property case
  alongside the F-P6-03 fix.
- **Fix risk:** none — tests only. Note `pkgs.testers.runNixOSTest` with
  two ZFS nodes is already slow; adding a third node has a real wall-clock
  cost on CI.

### F-P6-15 — the restore paths are still unexercised, so "we have backups" is unverified

- **File:** `docs/procedures/backup-restore.md:7-12`, `TODO.md:280-296`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** documentation
- **Reachability:** n/a — this is an availability/recoverability risk,
  not an access-control one.
- **Rule:** n/a.
- **Finding:** the doc is honest about its own status and `TODO.md`
  tracks the work, so this is a known gap rather than a discovery. It is
  recorded here because it changes how every other finding in this report
  should be weighted: the fleet's most valuable asset is a pool nobody
  has ever successfully restored from. `tests/zrepl-replication.nix`
  gives the clone-based file-recovery path its only real exercise; full
  dataset restore and disaster-recovery-from-scratch have never run.
  Nothing at all exercises the Backblaze path — and that is the copy
  F-P6-02 says is the last line of defence.
- **Proposed fix:** as `TODO.md` already says. If only one drill gets
  done, make it `restic-backblazeWeekly restore` of a single file from
  the offsite repo — it is the cheapest, and it is the path that would be
  used on the worst day.
- **Fix risk:** a restore drill that writes to a live dataset can destroy
  data. Follow the doc's own advice and restore alongside
  (`-restored`), never over.

---

## 3. Can we survive root on homelab?

**No — and the margin is wider than the design implies.**

An adversary with root on homelab reaches, in one session, with no
further vulnerability:

| Copy | Reachable? | How |
|---|---|---|
| live `zdata` (`/storage`, `/storage-bulk`, `zroot/local/state`) | **yes** | local root |
| `zbackup` — the 13-month consolidated copy of all three hosts | **yes** | same machine, pool imported and writable at all times, no delegation boundary, no `readonly`, no holds beyond zrepl's own |
| Backblaze offsite | **yes** | `/run/secrets/homelab_backblaze_{restic_password,rclone_config}`; the job's own `rclone backend lifecycle` call proves the key can rewrite bucket retention |
| torrent + thinkpad **snapshot history** | **yes** | `Sender.DestroySnapshots` over the pull key, incl. `@blank` (F-P6-04) |
| torrent + thinkpad **live data** | no (read-only) | the source endpoint destroys snapshots only; `restrict`+`command=` deny a shell. But `Sender.Send` reads both machines entirely |
| torrent + thinkpad **root** | **plausibly** | setuid/device node on the NFS share, which both laptops automount with `suid,dev` (F-P6-05) |
| vps | **yes** | threat model §4.2 — already established, no boundary |
| the alarm | **yes** | `health-check` and the Discord webhook both live on homelab (F-P6-07) |

The two backup copies homelab holds are independent of *disk failure*
(separate mirrors, separate pool) and of *each other's software bugs*
(zrepl vs restic, ZFS vs B2). They are not independent of *authority*.
Every one of them answers to the same uid 0 on the same box, and nothing
anywhere in the fleet — no `zfs allow` delegation, no `readonly=on`, no
`zfs hold` other than zrepl's own transient ones, no B2 Object Lock, no
append-only credential, no offline medium — imposes a cost on destroying
all of it.

Worse, per F-P6-01 you do not even need homelab. Root on **vps** — the
one host that is deliberately internet-facing, and the one whose
compromise the threat model treats as A1/A2's most likely landing spot —
decrypts `homelab_backblaze_*` straight out of its own nix store and can
empty the offsite repository without ever touching the machine the
backups are on. Nor do you strictly need a *host*: §4.7 means the
ciphertext is already public, so any one of the seven age keys —
including the one on a laptop with no FDE that leaves the house — is
sufficient, offline, at leisure.

And the attacker plans with the same map we do. §4.7 removes the one
thing that has historically bought defenders time against A9: the period
where ransomware has landed but has not yet worked out where the backups
are. Here it never has to. `docs/backups.md` states the topology, the
pool names, the retention windows, the offsite bucket and the schedule.
An adversary who reaches root on homelab knows, before running a single
command, that there are exactly three copies, that two of them are on
the machine it already owns, that the third is ~14 days deep, and that
the third's credentials are in `/run/secrets` beside it. Any answer to
this section that relied on an attacker having to look around is wrong;
this one does not rely on it, which is why the answer is "no".

What *does* survive root on homelab today: the live filesystems on
torrent and thinkpad, and only because the pull direction happens not to
expose a filesystem-destroy verb. That is a real and deliberate design
win — the push-vs-pull reasoning in `zrepl.nix:9-21` is correct and
should not be regressed — but it is the whole of the surviving set.

**The single change that most alters this answer** is an append-only B2
application key plus Object Lock (F-P6-02(a)), with the delete-capable
key held outside the fleet. That is the difference between "three copies,
one authority" and an actual last line of defence. Second is the
`zfs hold` on `@blank` (F-P6-04), which is nearly free. Third is
splitting the sops recipients (F-P6-01), which stops the offsite copy
from being reachable from four machines that have no business reaching
it.

---

## 4. Checked and clean

Examined and found sound — recorded so a future pass does not re-derive
it, and so a regression is visible as a change from a stated baseline.

**The ForceCommand identity pin (threat model §4.5's load-bearing
control) holds.** All three of the comment's claims at
`zrepl.nix:1073-1076` are true against the pinned OpenSSH 10.4p1 and
zrepl 0.7.0:
- *"cannot ask for a shell"* — `command=` overrides the client's command
  including subsystem requests (`sshd.8`), and `restrict` removes pty,
  port/agent/X11 forwarding and `~/.ssh/rc`, and is forward-compatible
  with restrictions OpenSSH adds later.
- *"cannot claim to be a different host"* — the identity reaches zrepl
  only as `argv[1]`, fixed server-side in `authorized_keys`.
  `runStdinserver` reads nothing from stdin except the proxied byte
  stream, and ignores `SSH_ORIGINAL_COMMAND` entirely. On the daemon
  side the identity is stamped by *which* per-identity unix socket the
  connection arrived on (`transport.NewAuthConn(c, l.clientIdentity)`),
  not by anything on the wire — so there is no field for a client to lie
  in. The rendered `authorized_keys` on both laptops confirms one key,
  one identity, one job.
- The sshd side supports it: `PermitRootLogin forced-commands-only`,
  `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, no
  `PermitUserEnvironment`, no `AcceptEnv`, and the zrepl key is the only
  entry in root's declarative keys on either host.

This one deserves emphasis under §4.7. The pin is published, the zrepl
version it depends on is published, and zrepl's source is open — so an
attacker evaluates it exactly as I did, offline, with no rate limit and
nothing to detect. That is fine, because the pin does not depend on
secrecy: the identity is not a value the client supplies and can lie
about, it is a property of *which socket the daemon accepted the
connection on*, chosen server-side. A control that survives being read
is the right kind of control, and this is one. It is also the reason
F-P6-14's missing negative test matters more than it would in a private
repo — a regression here would be found by someone reading the diff.

**No `zfs allow` delegation exists anywhere in the repo** — grepped
across `modules/` and `hosts/`. Everything ZFS runs as root, which
matches the (correct) daemon-must-be-root finding above. There is no
principal with partial ZFS authority to audit.

**No path traversal in the receive path.** A malicious source controls
the filesystem names homelab's `Receiver` maps through
`subroot.MapToLocal`, and `NewDatasetPath` does not reject `..`. It does
not matter: ZFS dataset names are not resolved like filesystem paths, so
a `..` component would be a literal child name, not an escape — and
`ComponentNamecheck` rejects `.`/`..` at the layers that do validate.

**`requires = lib.mkForce [ ]`** (`zrepl.nix:1068`) weakens nothing
security-relevant. The rendered unit has no `Requires=` at all
afterwards; the only thing dropped is upstream's
`Requires=local-fs.target`, and no secret, network or firewall
dependency was ever expressed there.

**Retention and pruning are correctly reasoned and correctly rendered.**
The three grid presets evaluate exactly as documented on all three
hosts. The two genuinely dangerous zrepl pruning behaviours —
`KeepGrid` *condemning* rather than ignoring non-matching snapshots, and
a leading bucket without `keep=all` targeting its own newest occupant —
are both understood in the module comments and both handled: every keep
rule set carries the `^blank$` regex protect rule, and `retention.archive`
leads with `1x15m(keep=all)` against a 15m pull interval. `not_replicated`
is present on every `keep_sender` and correctly omitted from the `snap`
job (where `alwaysUpToDateReplicationCursorHistory` makes it inert) with
that reasoning written down. The `ceiling`-slacker-than-`source` ordering
is right and does what the comment says.

**`recv.placeholder.encryption`** is set on every receiving job on
homelab (`off`, matching an unencrypted `zbackup`) — the failure
`configcheck` cannot catch, caught instead by the VM test.

**Host key pinning is done properly.** `programs.ssh.knownHosts.torrent`
and `.thinkpad` on homelab, declarative, with an accurate comment about
why `StrictHostKeyChecking=accept-new` was rejected. Contrast
F-P0-07's TOFU in the deploy path; this subsystem got it right.

**`zfs-space-guard`'s script logic** is sound: `-r` plus a `^dataset@`
grep correctly scopes to the named dataset and excludes children;
`grep -v '@blank$'` is anchored; `|| true` on the destroy tolerates
zrepl's holds without failing the unit (and the VM test asserts exactly
that, including `ExecMainStatus == 0`). The `lib.escapeShellArg`-inside-
a-grep-pattern construction at `:76-78` is unusual but correct as shell,
and only mildly loose as a regex (an unescaped `.` in a dataset name
would match one character); no dataset in this fleet contains a regex
metacharacter.

**`tests/zfs-space-guard.nix`** is a genuinely good test — it proves the
premise (deleting a file frees nothing while a snapshot holds it), the
behaviour, the held-snapshot tolerance, the no-`@blank` fallback, and the
non-obvious claim that a cursor *bookmark* does not pin the space. It
even handles ZFS's deferred free with a sync-and-poll rather than a
sleep.

**`nfs-homelab-mounts` availability behaviour** is well thought through:
`noauto` + `x-systemd.automount` + `soft` + `retry=0` +
`mount-timeout=10` means a laptop off the tailnet never blocks on boot
and never hangs a process, which is the right call for two roaming
machines. Only the security options are missing (F-P6-05).

**Build-time config validation** (`myZrepl.validateConfig` running
`zrepl configcheck` via `system.extraDependencies`) is a good pattern and
correctly scoped — the module comments are explicit about the several
gotchas it *cannot* catch, which is the useful half of documenting a
control.

**`zbackup` import** is handled (`boot.zfs.extraPools`), with the ~23h
outage that motivated it recorded. Not security, but it is the kind of
silent-failure fix that makes the rest trustworthy.

---

## 5. Notes for other parts

- **P3 (homelab):** F-P6-01 and F-P6-02 land on your restic block. Two
  smaller observations I did not raise as findings:
  `backupPrepareCommand` picks the snapshot to back up with
  `zfs list -s name … | tail -n 1` — sorting by *name*, not creation.
  That is correct only while every snapshot carries the `zrepl_` prefix
  and a lexicographically-sortable timestamp; a prefix change would
  silently start backing up an old snapshot offsite. And
  `backupCleanupCommand` runs `umount` against *every* snapshot on the
  host, not just the ones it mounted.
- **P5 (laptops):** F-P6-05 (NFS mount options) and F-P6-10 (sshd
  directives) are yours to apply; F-P6-12 depends on your finding about
  the `docker` group.
- **P7 (secrets/deploy):** F-P6-01 is the backup-specific instance of
  what is almost certainly a fleet-wide secret-scoping finding. The
  `.sops.yaml` has exactly one `creation_rules` entry for all secrets and
  all hosts. Under §4.7 the recipient breadth is the whole control, so
  this is likely the highest-severity secrets finding in the audit; note
  also that a *split* alone does not retire the already-published
  ciphertext, so P7's recommendation should pair narrowing with
  far-end rotation of anything that can be rotated.
- **Everyone:** `docs/hardening.md` states that `AllowTcpForwarding`
  defaults to `no`. It defaults to `yes` (OpenSSH 10.4p1
  `sshd_config.5`). Any finding that assumed the doc was right needs
  re-checking.
- **Threat model:** §4 gains an edge it does not currently have —
  homelab → root on torrent and thinkpad, via the NFS mounts (F-P6-05),
  in addition to the snapshot-destroy and full-read authority the pull
  direction already grants (F-P6-04).
